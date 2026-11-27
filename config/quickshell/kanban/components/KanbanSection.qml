import QtQuick
import ".."

// One status column: a header band plus a scrolling card list.
//
// The column is a container of its own -- filled surface, one hairline -- and
// its header is a band across the full width with the name on the left and the
// count on the right. Before, the name was a small caption floating over
// nothing and the count was glued to it as "NEW · 3": at a glance you could not
// tell where a column started or ended, and the count shifted whenever a task
// changed status.
//
// Fixed geometry throughout: the parent row sets width and height, the header
// takes what it needs and the Flickable gets the rest. Nothing here measures
// itself from its content, so a long board scrolls inside its column instead of
// pushing the panel off-screen.
//
// The root registers itself with the panel as a drop target and paints three
// states while a card drags: hot (this drop will work), cold (the task cannot
// come here, said in the header) and idle.
Rectangle {
    id: section

    property Appearance appearance: Appearance {}
    property string title: ""
    property int count: 0
    property var tasks: []
    property var panel: null
    property bool danger: false
    property bool dimmed: false
    property string extraTitle: ""
    property int extraCount: 0
    property var extraTasks: []
    property string dest: ""

    objectName: "kanban-section-" + dest

    readonly property bool dropHot: !!panel && panel.dropTarget === dest && dest !== ""
    readonly property bool dropCold: !!panel && panel.dropHover === dest && panel.dropTarget !== dest && !dropSame
    // The card would come back to the lane it is already in: nothing changes, so
    // this reads as a warning (yellow), never as a refusal (red).
    readonly property bool dropSame: !!panel && panel.dropSame === dest && dest !== ""

    Component.onCompleted: {
        if (section.panel)
            section.panel.registerDrop(section, section.dest);
    }

    // The lane's own click-anywhere-else. It lives here because a Flickable
    // never lets a press through to the panel's catcher, so each lane has to
    // hand the gesture up itself; the panel still owns the sheet.
    function dismissPreview() {
        if (section.panel)
            section.panel.closePreview();
    }

    color: appearance.surface
    radius: appearance.shapeLarge
    border.color: dropHot ? appearance.accent
                : (dropCold ? appearance.danger : appearance.outline)
    border.width: appearance.borderWidth

    // Drop feedback, not hover: this is a state the panel reports while a card
    // is in the air, so it stays a wash instead of the gilt-and-lift recipe the
    // hover uses. Three verdicts, three colours: accent when the drop will work,
    // warn when the card is only going home, danger when the backend would
    // refuse the move.
    Rectangle {
        anchors.fill: parent
        radius: section.appearance.shapeLarge
        // The colour and the opacity change in the same frame. A fading opacity
        // over a colour that had already flipped to accent is what flashed mint
        // for a frame after leaving a refused column.
        color: section.dropSame ? section.appearance.warn
            : (section.dropCold ? section.appearance.danger : section.appearance.accent)
        opacity: section.dropHot || section.dropCold || section.dropSame
            ? section.appearance.opacityStateLayer : 0
    }

    // The state layer paints the whole column; the content keeps its distance
    // from that edge on the shared spacing token.
    Column {
        anchors.fill: parent
        anchors.margins: section.appearance.spacingSmall
        spacing: section.appearance.spacingSmall

        // Header band: its own fill, the full column width, name left and count
        // right. The name takes body weight -- a header is a label, not a
        // caption -- and the count keeps the annotation voice.
        Rectangle {
            id: header

            width: parent.width
            height: section.appearance.fieldHeightCompact
            radius: section.appearance.shapeMedium
            color: section.appearance.surfaceContainerHigh
            border.color: section.dropHot ? section.appearance.accent : "transparent"
            border.width: section.appearance.borderWidth

            Text {
                id: headerLabel

                anchors.left: parent.left
                anchors.leftMargin: section.appearance.spacingMedium
                anchors.right: headerCount.left
                anchors.rightMargin: section.appearance.spacingSmall
                anchors.verticalCenter: parent.verticalCenter
                text: section.title
                color: section.dropHot ? section.appearance.accent
                    : (section.danger ? section.appearance.danger : section.appearance.text)
                font.family: section.appearance.uiFont
                font.weight: section.appearance.fontWeightUi
                font.variableAxes: section.appearance.fontVariableAxesUi
                font.pixelSize: section.appearance.fontSizeCaption
                font.letterSpacing: section.appearance.letterSpacingCaption
                font.capitalization: Font.AllUppercase
                elide: Text.ElideRight
            }

            Text {
                id: headerCount

                anchors.right: parent.right
                anchors.rightMargin: section.appearance.spacingMedium
                anchors.verticalCenter: parent.verticalCenter
                text: section.count + ""
                color: section.dropHot ? section.appearance.accent : section.appearance.textMuted
                font.family: section.appearance.uiFont
                font.weight: section.appearance.fontWeightUi
                font.variableAxes: section.appearance.fontVariableAxesUi
                font.pixelSize: section.appearance.fontSizeCaption
            }
        }

        Flickable {
            id: flick

            width: parent.width
            height: parent.height - header.height - parent.spacing - (section.extraTasks.length > 0 ? extraHeader.height + parent.spacing + Math.min(extraList.implicitHeight, section.appearance.extraListMaxHeight) + parent.spacing : 0)
            contentWidth: width
            contentHeight: list.implicitHeight
            clip: true
            interactive: !(section.panel && section.panel.dragCard)

            // A Flickable takes every press inside it, so the panel's own
            // click-anywhere-else catcher never saw the empty space of a column
            // and the sheet only closed from the strip above the board. This
            // sits under the cards (declared first) and closes the preview; it
            // follows the viewport rather than the content, so scrolling never
            // walks the dismiss area out of reach.
            MouseArea {
                objectName: "section-dismiss"

                width: flick.width
                height: flick.height
                y: flick.contentY
                onPressed: section.dismissPreview()
            }

            Column {
                id: list

                width: parent.width
                spacing: section.appearance.rowGap

                // An empty lane is a state, not a gap: with no cards the header
                // floated over nothing and the column read as still loading.
                // Same recipe as the monitor's and the wifi's empty line -- muted
                // ink, no opacity, centred -- so the desktop says "nothing here"
                // the same way on every surface.
                Text {
                    objectName: "section-empty"
                    visible: section.tasks.length === 0
                    width: list.width
                    text: "no tasks"
                    horizontalAlignment: Text.AlignHCenter
                    color: section.appearance.textMuted
                    font.family: section.appearance.uiFont
                    font.weight: section.appearance.fontWeightUi
                    font.variableAxes: section.appearance.fontVariableAxesUi
                    font.pixelSize: section.appearance.fontSizeSmall
                    font.letterSpacing: section.appearance.letterSpacingCaption
                }

                Repeater {
                    model: section.tasks

                    KanbanCard {
                        required property var modelData

                        appearance: section.appearance
                        panel: section.panel
                        task: modelData
                        width: list.width
                        dimmed: section.dimmed

                        onDeleteRequested: (id) => {
                            if (section.panel)
                                section.panel.requestDelete(id);
                        }
                        onPreviewRequested: (id) => {
                            if (section.panel)
                                section.panel.requestPreview(id);
                        }
                    }
                }
            }
        }

        // Blocked work keeps its own band inside the process column: same
        // structure, danger ink, so a stuck card cannot be mistaken for one that
        // is moving.
        Rectangle {
            id: extraHeader

            visible: section.extraTasks.length > 0
            width: parent.width
            height: visible ? section.appearance.chipHeight : 0
            radius: section.appearance.shapeMedium
            color: "transparent"
            border.color: section.appearance.outline
            border.width: section.appearance.borderWidth

            Text {
                anchors.left: parent.left
                anchors.leftMargin: section.appearance.spacingMedium
                anchors.right: extraCount.left
                anchors.rightMargin: section.appearance.spacingSmall
                anchors.verticalCenter: parent.verticalCenter
                text: section.extraTitle
                color: section.appearance.danger
                font.family: section.appearance.uiFont
                font.weight: section.appearance.fontWeightUi
                font.variableAxes: section.appearance.fontVariableAxesUi
                font.pixelSize: section.appearance.fontSizeSmall
                font.letterSpacing: section.appearance.letterSpacingCaption
                font.capitalization: Font.AllUppercase
                elide: Text.ElideRight
            }

            Text {
                id: extraCount

                anchors.right: parent.right
                anchors.rightMargin: section.appearance.spacingMedium
                anchors.verticalCenter: parent.verticalCenter
                text: section.extraCount + ""
                color: section.appearance.textMuted
                font.family: section.appearance.uiFont
                font.weight: section.appearance.fontWeightUi
                font.variableAxes: section.appearance.fontVariableAxesUi
                font.pixelSize: section.appearance.fontSizeSmall
            }
        }

        Flickable {
            id: extraFlick

            visible: section.extraTasks.length > 0
            width: parent.width
            height: visible ? Math.min(extraList.implicitHeight, section.appearance.extraListMaxHeight) : 0
            contentWidth: width
            contentHeight: extraList.implicitHeight
            clip: true
            interactive: !(section.panel && section.panel.dragCard)

            // Same dismiss area as the lane above: the blocked band is a
            // Flickable too, and it used to swallow the click as well.
            MouseArea {
                objectName: "section-extra-dismiss"

                width: extraFlick.width
                height: extraFlick.height
                y: extraFlick.contentY
                onPressed: section.dismissPreview()
            }

            Column {
                id: extraList

                width: parent.width
                spacing: section.appearance.rowGap

                Repeater {
                    model: section.extraTasks

                    KanbanCard {
                        required property var modelData

                        appearance: section.appearance
                        panel: section.panel
                        task: modelData
                        width: extraList.width
                        dimmed: section.dimmed

                        onDeleteRequested: (id) => {
                            if (section.panel)
                                section.panel.requestDelete(id);
                        }
                        onPreviewRequested: (id) => {
                            if (section.panel)
                                section.panel.requestPreview(id);
                        }
                    }
                }
            }
        }
    }
}
