import QtQuick

// Material Symbols Rounded with the same metrics and property contract as the
// panel icon (wght 600, GRAD 0, opsz 24, FILL 0). This one renders natively:
// on the lock surface the hinted path looked sharper at 24 px than the default
// one, and it is the only deliberate difference from the other surfaces.
Text {
	property string icon: ""
	property color iconColor: "{{text.ink}}"
	property int iconSize: {{typography.sizes.iconMd}}

	text: icon
	color: iconColor
	font.family: "{{typography.fonts.icons}}"
	font.weight: {{typography.weights.icons}}
	font.pixelSize: iconSize
	font.variableAxes: { "FILL": 0, "wght": {{typography.weights.icons}}, "GRAD": 0, "opsz": 24 }
	renderType: Text.NativeRendering
}
