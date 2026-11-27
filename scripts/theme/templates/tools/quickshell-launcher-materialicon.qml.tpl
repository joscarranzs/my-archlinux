import QtQuick

// Material Symbols Rounded icon. Same metrics and property contract as the lock
// surface icon (wght 700, GRAD 0, opsz 24, FILL 0); the lock surface only adds
// native rendering, which is noted there.
Text {
    id: root

    property string icon: ""
    property color iconColor: "{{text.ink}}"
    property int iconSize: {{typography.sizes.iconMd}}

    text: icon
    color: iconColor
    font.family: "{{typography.fonts.icons}}"
    font.weight: {{typography.weights.icons}}
    font.pixelSize: iconSize
    font.variableAxes: { "FILL": 0, "wght": {{typography.weights.icons}}, "GRAD": 0, "opsz": 24 }

    horizontalAlignment: Text.AlignHCenter
    verticalAlignment: Text.AlignVCenter
}
