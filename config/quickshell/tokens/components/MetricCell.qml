import QtQuick
import ".."

// One metric of the readout: a caption label above, a display-size number
// below. The panel lays these out in equal columns so the numbers line up down
// the plaque; nothing here sizes itself from its own text, or the columns drift
// as the values grow a digit.
Column {
    id: root

    property Appearance appearance: Appearance {}
    property string label: ""
    property string value: ""
    property bool muted: false

    spacing: appearance.spacingSmall / 2

    Text {
        width: parent.width
        text: root.label
        color: root.appearance.textMuted
        elide: Text.ElideRight
        font.family: root.appearance.uiFont
        font.weight: root.appearance.fontWeightUi
        font.variableAxes: root.appearance.fontVariableAxesUi
        font.pixelSize: root.appearance.fontSizeCaption
        font.letterSpacing: root.appearance.letterSpacingCaption
        font.capitalization: Font.AllUppercase
    }

    Text {
        width: parent.width
        text: root.value
        color: root.muted ? root.appearance.textMuted : root.appearance.text
        elide: Text.ElideRight
        font.family: root.appearance.displayFont
        font.weight: root.appearance.fontWeightDisplay
        font.variableAxes: root.appearance.fontVariableAxesDisplay
        font.pixelSize: root.appearance.fontSizeTitle
        font.bold: true
    }
}
