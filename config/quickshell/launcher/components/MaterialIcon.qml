import QtQuick

// Material Symbols Rounded icon. Same metrics and property contract as the lock
// surface icon (wght 700, GRAD 0, opsz 24, FILL 0); the lock surface only adds
// native rendering, which is noted there.
Text {
    id: root

    property string icon: ""
    property color iconColor: "#2a2222"
    property int iconSize: 22

    text: icon
    color: iconColor
    font.family: "Material Symbols Rounded"
    font.weight: 600
    font.pixelSize: iconSize
    font.variableAxes: { "FILL": 0, "wght": 600, "GRAD": 0, "opsz": 24 }

    horizontalAlignment: Text.AlignHCenter
    verticalAlignment: Text.AlignVCenter
}
