import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import ".."

// One task row: category badge, priority rank and a one-line body preview.
//
// The card never acts on its own: the panel maps drops to backend commands and
// owns the selection. Every gesture is handled by one MouseArea covering the
// whole plaque - not just the label - because a drop target you cannot hit is
// not a drop target:
//
//   hold 180 ms            start a drag (the panel paints the ghost chip)
//   move past 8 px first   let the column scroll instead (no drag)
//   single click           open the preview sheet, which is also the selection
//   right click            ask to archive (the panel shows the confirmation)
//
// There is no editor here. Editing a title in place meant editing it at 13 px
// inside a 46 px plaque with the text elided to two lines, and a card already
// answers the only question it is good for: which task is this. The sheet is
// where the text becomes editable.
//
// Dragging is tracked by hand: the column under the cursor is resolved by the
// panel from real geometry, not by Qt's drag-and-drop, which never started
// here (no drag.target, so no Drag.active).
Rectangle {
    id: card

    property Appearance appearance
    property var task: ({})
    property var panel: null

    objectName: "kanban-card-" + ((task && task.id) ? task.id : "unknown")

    signal deleteRequested(string id)
    // A single left click asks the panel to show this task in full. The sheet
    // belongs to the panel -- it owns selection, drag and the editing fields --
    // so the card reports the gesture and forgets it.
    signal previewRequested(string id)

    property bool dragging: false
    property bool hovered: false
    property bool dimmed: false
    property bool pending: !!panel && panel.pendingId === (task.id || "")

    // A drag started during the current press. `dragging` is already back to
    // false by the time the click arrives -- the release ends the drag before Qt
    // composes the click -- so it cannot answer "did this gesture move the card"
    // and the sheet used to open on every drop. This flag is set when the drag
    // starts and cleared on the next press.
    property bool pressDragged: false

    // Press origin, used to tell a hold from a scroll.
    property real pressX: 0
    property real pressY: 0

    width: parent ? parent.width : card.appearance.columnWidth
    height: Math.max(content.implicitHeight + card.appearance.cardPadding * 2,
                     card.appearance.taskCardHeight)
    color: appearance.surfaceContainerHigh
    radius: appearance.shapeMedium
    border.width: appearance.borderWidth
    border.color: pending || dragging ? appearance.accent
                : hovered ? appearance.outline
                : "transparent"
    // The dragged card stays in place as a placeholder while the ghost moves.
    opacity: dragging ? 0.35 : (pending ? 0.7 : (dimmed ? appearance.opacityDim : 1.0))

    Behavior on opacity {
        NumberAnimation { duration: card.appearance.motionControlDuration }
    }

    ColumnLayout {
        id: content

        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.leftMargin: card.appearance.cardPadding
        anchors.rightMargin: card.appearance.cardPadding
        anchors.topMargin: card.appearance.cardPadding
        spacing: card.appearance.spacingSmall

        // Title first, full width. The badge used to sit to its left and the
        // rank to its right, which put a coloured block before the one thing
        // the eye reads first and squeezed the title into what was left.
        Text {
            id: titleText

            objectName: "card-title"
            Layout.fillWidth: true
            text: card.task.title || ""
            color: card.appearance.text
            font.family: card.appearance.uiFont
            font.weight: card.appearance.fontWeightUi
            font.variableAxes: card.appearance.fontVariableAxesUi
            font.pixelSize: card.appearance.cardFontSize
            elide: Text.ElideRight
            maximumLineCount: 2
            wrapMode: Text.Wrap
            // Ratio, not a pixel value: two wrapped lines at one size sat on
            // top of each other because the font's own leading is tighter than
            // a UI body wants.
            lineHeight: 1.25
            lineHeightMode: Text.ProportionalHeight
        }

        // Meta row: category and rank together, under the title. Both are
        // classification, so they belong on one line as a pair instead of
        // bracketing the title on opposite sides.
        RowLayout {
            objectName: "card-meta"
            Layout.fillWidth: true
            spacing: card.appearance.spacingSmall
            visible: (card.task.category || 0) > 0 || (card.task.priority || 0) > 0

            CategoryChip {
                appearance: card.appearance
                category: card.task.category || 0
                // The card has the width for the full label, so it says what
                // the number means instead of leaving C2 to be memorised.
                label: card.panel ? card.panel.categoryLabel(card.task.category || 0) : ""
                visible: (card.task.category || 0) > 0
                Layout.alignment: Qt.AlignVCenter
            }

            // Priority inside the category: P1 ranks above P9 within the same
            // C. Secondary ink on purpose - the category is the loud axis, the
            // rank is the quiet one.
            Text {
                objectName: "card-priority"
                visible: (card.task.priority || 0) > 0
                text: "P" + card.task.priority
                color: card.appearance.textMuted
                font.family: card.appearance.uiFont
                font.weight: card.appearance.fontWeightUi
                font.variableAxes: card.appearance.fontVariableAxesUi
                font.pixelSize: card.appearance.fontSizeCaption
                Layout.alignment: Qt.AlignVCenter
            }

            Item {
                Layout.fillWidth: true
            }
        }

        // Body preview, one faded line when the task carries notes.
        Text {
            visible: !!card.task.body
            Layout.fillWidth: true
            text: card.task.body || ""
            color: card.appearance.textMuted
            font.family: card.appearance.uiFont
            font.weight: card.appearance.fontWeightUi
            font.variableAxes: card.appearance.fontVariableAxesUi
            font.pixelSize: card.appearance.fontSizeCaption
            elide: Text.ElideRight
            maximumLineCount: 1
            lineHeight: 1.4
            lineHeightMode: Text.ProportionalHeight
        }
    }

    // One hit area for the whole plaque. A drag starts two ways, because
    // nobody holds still to drag: a sideways move past the threshold (the only
    // direction a column change ever takes) or a short hold. A vertical drag
    // is left to the Flickable so the column still scrolls, and stealing is
    // blocked only once the drag is live.
    MouseArea {
        id: hit

        anchors.fill: parent
        hoverEnabled: true
        // Left is the card: preview, drag. Right is the one destructive
        // gesture, and it only ever asks -- the panel owns the confirmation.
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        cursorShape: card.dragging ? Qt.ClosedHandCursor : Qt.OpenHandCursor
        preventStealing: card.dragging

        onEntered: card.hovered = true
        onExited: card.hovered = false
        onPressed: (mouse) => {
            if (mouse.button !== Qt.LeftButton)
                return;
            card.pressX = mouse.x;
            card.pressY = mouse.y;
            card.pressDragged = false;
            holdTimer.restart();
        }
        onPositionChanged: (mouse) => {
            // hoverEnabled delivers moves with no button down: a gesture that
            // was never started must never arm a drag.
            if (!hit.pressed)
                return;
            if (card.dragging) {
                if (card.panel)
                    card.panel.updateDrag(card.mapToItem(card.panel, mouse.x, mouse.y));
                return;
            }
            var dx = Math.abs(mouse.x - card.pressX);
            var dy = Math.abs(mouse.y - card.pressY);
            if (dx > 6 && dx > dy) {
                holdTimer.stop();
                card.pressDragged = true;
                if (card.panel) {
                    card.panel.beginDrag(card);
                    card.panel.updateDrag(card.mapToItem(card.panel, mouse.x, mouse.y));
                }
                return;
            }
            if (dx > 6 || dy > 6)
                holdTimer.stop();
        }
        onReleased: {
            holdTimer.stop();
            if (card.dragging && card.panel)
                card.panel.finishDrag();
        }
        // Right click asks to archive. It never archives by itself: the panel
        // opens the dialog and only its button reaches the feed. A press that
        // dragged asks for nothing: the drop already answered.
        onClicked: (mouse) => {
            if (card.pressDragged) {
                card.pressDragged = false;
                return;
            }
            if (mouse.button === Qt.RightButton && !card.dragging)
                card.deleteRequested(card.task.id || "");
            else if (mouse.button === Qt.LeftButton && !card.dragging)
                card.previewRequested(card.task.id || "");
        }
        onCanceled: {
            holdTimer.stop();
            if (card.dragging && card.panel)
                card.panel.cancelDrag();
        }
    }

    // Qt's own press-and-hold waits ~800 ms and gives nothing back while it
    // waits. This one is short enough to discover and the panel shows the
    // armed state as soon as it fires.
    Timer {
        id: holdTimer

        interval: card.panel ? card.panel.holdDelay : 180
        onTriggered: {
            // A hold that armed a drag must swallow the click that follows the
            // release, exactly like the sideways path does.
            card.pressDragged = true;
            if (card.panel)
                card.panel.beginDrag(card);
        }
    }
}
