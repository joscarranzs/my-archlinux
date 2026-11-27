import QtQuick
import ".."

// The category badge: one recipe for the card and the creator.
//
// Two states, one shape. On a card it is a filled chip (accent fill, surface
// ink) that only appears when the task carries a category. In the creator it is
// a keycap that fills when selected, so choosing a category and showing one read
// as the same object in two moods instead of two widgets that happen to be near
// each other. Uncategorised is 0 and draws nothing on a card.
Rectangle {
    id: chip

    property Appearance appearance: Appearance {}
    property int category: 0
    // "C1-URGENT" when the surface has room to say what the number means.
    // Empty keeps the chip to "C1" -- four full labels in one row would be
    // four 75 px bars competing with the fields beside them.
    property string label: ""
    property bool selected: false
    // Only the creator takes clicks; a card badge is a label.
    property bool interactive: false

    signal activated()

    readonly property bool filled: interactive ? selected : category > 0
    readonly property bool hovered: hit.containsMouse && interactive

    objectName: "category-chip-" + category
    // Its own height and a real horizontal padding: the badge is a label, not a
    // key in a legend, and keycapHeight (18) left the numeral cramped.
    implicitWidth: label.implicitWidth + appearance.spacingMedium
    implicitHeight: appearance.badgeHeight
    radius: appearance.shapeSmall
    color: filled ? appearance.accent : "transparent"
    border.color: filled ? appearance.accent
                : (hovered ? appearance.textMuted : appearance.outline)
    border.width: appearance.hairline

    Text {
        id: label

        anchors.centerIn: parent
        text: chip.label !== "" ? chip.label : ("C" + chip.category)
        color: chip.filled ? chip.appearance.surface
             : (chip.hovered ? chip.appearance.text : chip.appearance.textMuted)
        font.family: chip.appearance.uiFont
        font.weight: chip.appearance.fontWeightUi
        font.variableAxes: chip.appearance.fontVariableAxesUi
        font.pixelSize: chip.appearance.fontSizeCaption
        font.letterSpacing: chip.appearance.letterSpacingCaption
    }

    MouseArea {
        id: hit

        anchors.fill: parent
        enabled: chip.interactive
        hoverEnabled: chip.interactive
        cursorShape: chip.interactive ? Qt.PointingHandCursor : Qt.ArrowCursor
        onClicked: chip.activated()
    }
}
