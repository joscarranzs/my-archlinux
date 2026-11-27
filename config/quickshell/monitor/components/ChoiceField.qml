import QtQuick
import QtQuick.Layouts
import ".."

// One labelled dropdown field. The list itself is NOT drawn here: the panel
// renders it as a floating menu (ChoiceMenu) over the plaque, so opening a
// dropdown never resizes the plaque or pushes the rows below it down.
//
// The root is an Item with an explicit implicit size, NOT a Column: a
// Positioner derives its implicit size from its children's live sizes, and the
// children here bind their width to the parent. In a RowLayout that feedback
// loop let the first field eat the whole row and squeezed the second to 0x0.
//
// The panel owns the keyboard: this component exposes openList/closeList/move/
// commit and the panel's key catcher routes to the focused field. Mouse clicks
// work on their own and report back through opened()/picked()/closed().
Item {
    id: field

    property Appearance appearance: Appearance {}
    property string label: ""
    // Array of { label, rowLabel?, value } rows; value is what picked() hands back.
    property var options: []
    property int currentIndex: 0
    // Focus highlight is panel-driven, not activeFocus: one key catcher owns
    // the whole plaque.
    property bool fieldFocused: false
    property bool open: false
    property int listIndex: 0

    // Review hook: no pointer automation on this host, so a preview can force the
    // pressed state while a capture runs.
    property bool forcePressed: false
    readonly property bool held: forcePressed || boxPress.pressed

    // Box edges relative to this item, for the panel to anchor the menu.
    readonly property real boxTop: box.y
    readonly property real boxBottom: box.y + box.height

    signal opened()
    signal closed()
    signal picked(int index)

    function openList() {
        if (field.options.length === 0)
            return;
        field.listIndex = Math.max(0, Math.min(field.currentIndex, field.options.length - 1));
        field.open = true;
        field.opened();
    }

    function closeList() {
        if (!field.open)
            return;
        field.open = false;
        field.closed();
    }

    function move(delta) {
        if (!field.open || field.options.length === 0)
            return;
        field.listIndex = Math.max(0, Math.min(field.options.length - 1, field.listIndex + delta));
    }

    function commit() {
        if (!field.open)
            return;
        const i = field.listIndex;
        field.open = false;
        field.closed();
        field.picked(i);
    }

    // Minimum width: the label plus padding, never below three field heights,
    // so two fields side by side always share the row evenly. The height never
    // depends on `open`: the plaque must not stretch when a menu appears.
    implicitWidth: Math.max(labelText.implicitWidth + field.appearance.spacingSmall * 2,
                            field.appearance.fieldHeightDense * 3)
    // The label box follows the label, not the other way round: a fixed slot
    // clipped the line it held at rest (12 px box, 16 px of mono) and clipped it
    // worse once the desktop's text scale grew.
    implicitHeight: labelHeightUsed + field.appearance.spacingSmall / 2
        + field.appearance.fieldHeightDense

    readonly property real labelHeightUsed:
        Math.max(field.appearance.labelHeight, labelText.implicitHeight)

    Column {
        anchors.top: parent.top
        width: parent.width
        spacing: field.appearance.spacingSmall / 2

        Text {
            id: labelText

            width: parent.width
            height: field.labelHeightUsed
            verticalAlignment: Text.AlignVCenter
            text: field.label
            color: field.appearance.textMuted
            elide: Text.ElideRight
            font.family: field.appearance.uiFont
            font.weight: field.appearance.fontWeightUi
            font.variableAxes: field.appearance.fontVariableAxesUi
            font.pixelSize: field.appearance.fontSizeCaption
            font.letterSpacing: field.appearance.letterSpacingLabel
        }

        Rectangle {
            id: box

            width: parent.width
            height: field.appearance.fieldHeightDense
            radius: field.appearance.shapeMedium
            // The box already rests at hoverFill, so hover takes the rung above it.
            // Focus and open keep the accent edge: the action and the ornament
            // never share a signal.
            color: field.held
                ? field.appearance.pressFill
                : (boxHover.hovered ? field.appearance.hoverFillHigh : field.appearance.surfaceContainerHigh)
            border.width: field.appearance.borderWidth
            border.color: field.fieldFocused || field.open
                ? field.appearance.accent
                : (boxHover.hovered || field.held ? field.appearance.gilt : field.appearance.outline)

            Behavior on color {
                ColorAnimation {
                    duration: field.held ? field.appearance.motionPressDuration : field.appearance.motionControlDuration
                    easing.type: field.appearance.motionControlEasing
                }
            }

            Behavior on border.color {
                ColorAnimation {
                    duration: field.appearance.motionControlDuration
                    easing.type: field.appearance.motionControlEasing
                }
            }

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: field.appearance.spacingSmall
                anchors.rightMargin: field.appearance.spacingSmall
                spacing: field.appearance.spacingSmall / 2

                Text {
                    Layout.fillWidth: true
                    Layout.alignment: Qt.AlignVCenter
                    text: field.options.length > 0
                        ? field.options[Math.max(0, Math.min(field.currentIndex, field.options.length - 1))].label
                        : "—"
                    color: field.appearance.text
                    elide: Text.ElideRight
                    font.family: field.appearance.uiFont
                    font.weight: field.appearance.fontWeightUi
                    font.variableAxes: field.appearance.fontVariableAxesUi
                    font.pixelSize: field.appearance.fontSizeSmall
                }

                MaterialIcon {
                    Layout.alignment: Qt.AlignVCenter
                    icon: field.open ? "expand_less" : "expand_more"
                    iconColor: field.appearance.textMuted
                    iconSize: field.appearance.iconSizeSm
                }
            }

            HoverHandler { id: boxHover }

            MouseArea {
                id: boxPress
                anchors.fill: parent
                onClicked: field.open ? field.closeList() : field.openList()
            }
        }
    }
}
