import QtQuick

// Material Symbols Rounded icon. Same metrics and property contract as the lock
// surface icon (wght 600, GRAD 0, opsz 24, FILL 0); the lock surface only adds
// native rendering, which is noted there.
//
// Optical sizing. The font gives every glyph the same 1 em advance, but not the
// same ink: measured at wght 600 / opsz 24, the drawn box runs from 0.61 em
// (volume_down) to 0.90 em (brightness_low) tall, and
// from 0.42 em (volume_mute) to 0.95 em (smart_toy) wide. At one pixelSize that
// reads as "some of these are smaller", because some of them are.
//
// `optical` scales each glyph so its ink box lands on inkTarget of the em. Two
// caps keep that from trading one distortion for another: a glyph may reach but
// never pass its own advance (1 em wide is what the row is spaced for), and the
// scale itself is clamped, so a shape with a tiny ink box cannot balloon.
Text {
    id: root

    property string icon: ""
    property color iconColor: "#2a2222"
    property int iconSize: 22

    // Off by default: a caller with a fixed cell (the toast glyph) keeps the
    // font's own draw. The bar's status row opts in.
    property bool optical: false

    readonly property real inkTarget: 0.86
    readonly property real scaleFloor: 0.92
    readonly property real scaleCeiling: 1.35

    // Ink box per glyph, in em units [width, height], measured with fontTools
    // from MaterialSymbolsRounded[FILL,GRAD,opsz,wght].ttf at FILL 0, GRAD 0,
    // opsz 24, wght 600 — the weight the generated file draws with, so the map
    // cannot drift from the render. A glyph that is not listed keeps the font's own size:
    // one icon at its drawn weight beats a guessed scale.
    readonly property var ink: ({
        "volume_off": [0.842, 0.831],
        "volume_mute": [0.415, 0.608],
        "volume_down": [0.611, 0.607],
        "volume_up": [0.798, 0.705],
        "brightness_1": [0.873, 0.873],
        "brightness_low": [0.899, 0.899],
        "brightness_medium": [0.899, 0.899],
        "brightness_high": [0.899, 0.899],
        "wifi_off": [0.941, 0.793],
        "wifi": [0.941, 0.708],
        "wifi_find": [0.916, 0.736],
        "bluetooth": [0.500, 0.784],
        "monitor": [0.873, 0.790],
        "battery_unknown": [0.546, 0.873],
        "battery_alert": [0.465, 0.873],
        "battery_full": [0.465, 0.873],
        "battery_0_bar": [0.465, 0.873],
        "battery_1_bar": [0.465, 0.873],
        "battery_2_bar": [0.465, 0.873],
        "battery_3_bar": [0.465, 0.873],
        "battery_4_bar": [0.465, 0.875],
        "battery_5_bar": [0.465, 0.873],
        "battery_6_bar": [0.465, 0.873],
        "battery_charging_20": [0.557, 0.873],
        "battery_charging_30": [0.557, 0.873],
        "battery_charging_50": [0.557, 0.873],
        "battery_charging_60": [0.557, 0.873],
        "battery_charging_80": [0.557, 0.873],
        "battery_charging_90": [0.557, 0.873],
        "smart_toy": [0.953, 0.828],
        "neurology": [0.823, 0.783],
    })

    readonly property var inkBox: root.ink[root.icon] !== undefined ? root.ink[root.icon] : null

    readonly property real opticalScale: {
        if (!root.optical || root.inkBox === null) {
            return 1;
        }
        const byHeight = root.inkTarget / root.inkBox[1];
        const byWidth = 1 / root.inkBox[0];
        return Math.max(root.scaleFloor,
                        Math.min(root.scaleCeiling, Math.min(byHeight, byWidth)));
    }

    text: icon
    color: iconColor
    font.family: "Material Symbols Rounded"
    font.weight: 600
    font.pixelSize: root.iconSize * root.opticalScale
    font.variableAxes: { "FILL": 0, "wght": 600, "GRAD": 0, "opsz": 24 }

    horizontalAlignment: Text.AlignHCenter
    verticalAlignment: Text.AlignVCenter
}
