import QtQuick
import QtQuick.Layouts
import ".."

// One block of the AI plaque: a raised card on the well.
//
// The plaque used to be a single column with bare headings between sections; it
// was one object claiming to be five. A card is the unit now: identity in the
// header (glyph tile, account name, status chip), everything the account reports
// in the content column below it. Three of them, and the plaque reads as three
// accounts instead of one long receipt.
//
// The content is the default property, so a card declares only its rows and
// never re-states the fill, the radius or the inset.
Rectangle {
    id: root

    property Appearance appearance: Appearance {}
    property string title: ""
    // Identity mark: a Material ligature, or an image for a brand that has a
    // logo of its own. Only one of the two is ever set.
    property string glyph: ""
    property string imageSource: ""
    property string chipText: ""
    property color chipColor: appearance.textMuted
    property bool chipDot: false
    // The edge and the mark are the two things a card may need to say about itself.
    // A block on a plaque wears the system hairline; a toast that arrives over the
    // desktop keeps the plaque's gilt edge, and its mark carries the urgency colour
    // instead of the accent. Defaults are the block's.
    property color edgeColor: appearance.outline
    property int edgeWidth: appearance.hairline
    property color markColor: appearance.accentInk
    // The tile and the title take a rung of the ladder each: a card on a 380 px
    // plaque holds the plank's sizes, a toast in the corner wants the step down.
    property int tileSize: appearance.fieldHeight
    property int titleSize: appearance.fontSizeCaption
    // Optical size of the mark, not a rung to pick at random: a thick-stroked
    // logo carries several times the ink of a line-art one at the same box, so it
    // steps down until the two read as equals. Defaults to the md rung.
    property int markSize: appearance.iconSizeMd
    // A mark that is being resolved right now: the plate is drawn and left empty
    // until the answer arrives, instead of painting the glyph and swapping it a
    // frame later. Cards whose mark is a literal set it to false forever.
    property bool markPending: false

    // A card swallows the clicks that land on its own empty space, and reports
    // them: a toast is dismissed by clicking it, and the body's own controls (a
    // copy button) are above this area and keep their clicks.
    signal clicked()

    default property alias content: body.data

    implicitHeight: column.implicitHeight + appearance.cardPad * 2
    color: appearance.cardFill
    radius: appearance.cardRadius
    // The palette's tonal steps sit 1.14:1 apart (raised on base), which is not
    // enough to group three blocks -- measured, not guessed. The card therefore
    // gets the system's hairline on its own edge: same outline role and same
    // frame opacity as every other hairline on the desktop, so the grouping is
    // one recipe instead of a fourth grey invented for this panel.
    border.color: root.edgeColor
    border.width: root.edgeWidth

    // A card swallows the clicks that land on its own empty space: a plaque that
    // dismisses on click must not close because the pointer landed on a card. It
    // is a sibling of the layout, not a child of it -- `anchors` on a layout child
    // is undefined behaviour, and QML says so.
    MouseArea {
        anchors.fill: parent
        z: -1
        onClicked: root.clicked()
    }

    ColumnLayout {
        id: column

        x: root.appearance.cardPad
        y: root.appearance.cardPad
        width: root.width - root.appearance.cardPad * 2
        spacing: root.appearance.spacingSmall

        RowLayout {
            // No identity, no header: a card whose content is its body (the
            // logo strip) must not reserve a title row that draws nothing.
            visible: root.glyph !== "" || root.title !== "" || root.chipText !== ""
                || root.imageSource !== ""
            Layout.fillWidth: true
            spacing: root.appearance.spacingSmall

            // The tile is the one place a mark sits on its own fill: a glyph on
            // bare card ink and a logo on bare card ink do not read as the same
            // object, and a tile is what the launcher already does.
            Rectangle {
                // No mark, no tile: an empty square reads as a missing image, and a
                // card whose identity is its title (the volume output) has none. A
                // glyph that is only the fallback for an image does not count while
                // the image is on screen.
                //
                // `markPending` is the third case: an image is being resolved right
                // now, so the plate is held empty instead of wearing the glyph for
                // the moment before the image lands. A card that resolves a mark
                // asynchronously (the toast, whose icon comes from a helper process)
                // otherwise shows a glyph at full strength and swaps it ~125 ms
                // later. The plate keeps its size, so nothing shifts when the mark
                // arrives.
                visible: root.markPending || (root.glyph !== "" && !markImage.ready) || markImage.ready
                // 36 is `fieldHeight`, the one square on the ladder that holds a
                // 28 px mark with air around it. The button rung (32) leaves a
                // line-art logo 2 px, which clips its silhouette against the tile.
                Layout.preferredWidth: root.tileSize
                Layout.preferredHeight: root.tileSize
                Layout.alignment: Qt.AlignVCenter
                radius: root.appearance.shapeMedium
                color: root.appearance.surfaceContainerHigh

                // Both the glyph and the brand mark take the md rung of the icon
                // ladder. A logo shrunk to the glyph's xs size stops being a logo:
                // its silhouette survives, its identity does not.
                Text {
                    anchors.centerIn: parent
                    // The fallback: shown only when there is no image to show --
                    // and not while one is still being resolved, or the plate the
                    // card is holding open would draw the very glyph it is holding
                    // it open to avoid.
                    visible: root.glyph !== "" && !markImage.ready && !root.markPending
                    text: root.glyph
                    color: root.markColor
                    font.family: root.appearance.iconFont
                    font.weight: root.appearance.fontWeightIcons
                    font.variableAxes: root.appearance.fontVariableAxesIcons
                    font.pixelSize: root.markSize
                }

                Image {
                    id: markImage

                    // Findable by name: whether the card is wearing a real image or
                    // its glyph fallback is the one thing a harness cannot read off
                    // the outside, and an unresolvable source is a state of its own.
                    objectName: "mark-image"

                    readonly property bool ready: root.imageSource !== "" && status === Image.Ready

                    anchors.centerIn: parent
                    visible: ready
                    source: root.imageSource
                    sourceSize.width: root.markSize
                    sourceSize.height: root.markSize
                    fillMode: Image.PreserveAspectFit
                    smooth: true
                }
            }

            Text {
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignVCenter
                text: root.title
                color: root.appearance.text
                elide: Text.ElideRight
                font.family: root.appearance.uiFont
                font.weight: root.appearance.fontWeightUi
                font.variableAxes: root.appearance.fontVariableAxesUi
                font.pixelSize: root.titleSize
                font.letterSpacing: root.appearance.letterSpacingLabel
                font.capitalization: Font.AllUppercase
            }

            StatusChip {
                // Findable by name: a plaque whose state moved into a chip still has
                // to be assertable, and `text` is the chip's own word.
                objectName: "chip"

                Layout.alignment: Qt.AlignVCenter
                visible: root.chipText !== ""
                appearance: root.appearance
                text: root.chipText
                dotColor: root.chipColor
                showDot: root.chipDot
            }
        }

        ColumnLayout {
            id: body

            Layout.fillWidth: true
            spacing: root.appearance.spacingSmall
        }
    }
}
