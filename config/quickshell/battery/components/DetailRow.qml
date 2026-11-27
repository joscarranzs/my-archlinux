import QtQuick
import ".."

// One reading: label on the left, value on the right, both on one baseline. A
// plain Item with anchored texts, not a Row: inside a positioner the anchors
// fight the layout and the label lands above the value.
Item {
    id: root

    property Appearance appearance: Appearance {}
    property string label: ""
    property string value: ""
    property color valueColor: appearance.text

    implicitHeight: Math.max(labelText.implicitHeight, valueText.implicitHeight)

    Text {
        id: labelText

        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        text: root.label
        color: root.appearance.textMuted
        font.family: root.appearance.uiFont
        font.weight: root.appearance.fontWeightUi
        font.variableAxes: root.appearance.fontVariableAxesUi
        font.pixelSize: root.appearance.fontSizeCaption
        font.letterSpacing: root.appearance.letterSpacingCaption
        font.capitalization: Font.AllUppercase
    }

    Text {
        id: valueText

        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        text: root.value
        color: root.valueColor
        font.family: root.appearance.uiFont
        font.weight: root.appearance.fontWeightUi
        font.variableAxes: root.appearance.fontVariableAxesUi
        font.pixelSize: root.appearance.fontSizeBody
    }
}
