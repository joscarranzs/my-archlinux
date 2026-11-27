import QtQuick
import QtQuick.Layouts
import ".."

// A block's status: a dot for the state and a word for the state, in the
// annotation voice the rest of the desktop uses for labels.
//
// The colour goes into the dot, never into the word: a 12 px red word is the
// cheapest way to fail contrast, and the dot already carries the signal at a
// size where it is legible.
RowLayout {
    id: root

    property Appearance appearance: Appearance {}
    property string text: ""
    property color dotColor: appearance.textMuted
    property bool showDot: true

    spacing: appearance.spacingXs

    Rectangle {
        visible: root.showDot
        Layout.alignment: Qt.AlignVCenter
        width: root.appearance.dotSize
        height: root.appearance.dotSize
        radius: root.appearance.shapeFull
        color: root.dotColor
    }

    Text {
        Layout.alignment: Qt.AlignVCenter
        text: root.text
        color: root.appearance.textMuted
        font.family: root.appearance.uiFont
        font.weight: root.appearance.fontWeightUi
        font.variableAxes: root.appearance.fontVariableAxesUi
        font.pixelSize: root.appearance.fontSizeSmall
        font.letterSpacing: root.appearance.letterSpacingCaption
        font.capitalization: Font.AllUppercase
    }
}
