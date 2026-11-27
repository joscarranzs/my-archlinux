import QtQuick

// Design tokens for the SDDM greeter (the same roles the unlock card uses, over
// the warm-paper palette).
// Generated from theme/colors.json + theme/look.json + theme/typography.json.
//
// The greeter is not a Quickshell surface: it runs in SDDM's own QQuickView, as
// the `sddm` user, before any session exists. It therefore carries no Qs*
// import and no env lookup -- only roles, so the template below picks a role
// and never a number.
QtObject {
	// Color roles
	readonly property color surface: "#efecef"
	readonly property color surfaceContainer: "#e8e5e8"
	readonly property color surfaceContainerHigh: "#dfdadf"
	readonly property color outline: "#cfc9cf"
	readonly property color text: "#2a2222"
	readonly property color textMuted: "#3e3535"
	readonly property color accent: "#007952"
	// accentInk is the accent used as ink (the caption line above the clock);
	// accentText is what sits on top of an accent fill.
	readonly property color accentInk: "#123623"
	readonly property color accentText: "#efecef"
	// Gilt: the ornament role -- the plaque rule and the card's edge.
	readonly property color gilt: "#997900"
	// Gilt as ink: the ornament tone is a stroke on paper, so gold read as text
	// takes the deeper step that clears 4.5:1 (the monitor's reset label).
	readonly property color giltInk: "#826700"
	readonly property color danger: "#d01b31"

	// Material: hover lights the object one rung up the tonal ladder and ignites
	// its edge with gilt; press steps it back down to base. The unlock card's
	// button rests at surfaceContainerHigh, so its hover takes hoverFillHigh --
	// the same recipe, because two login surfaces with two hovers is drift.
	readonly property color hoverFill: "#dfdadf"
	readonly property color hoverFillHigh: "#e0dce0"
	readonly property color pressFill: "#efecef"

	// Typography: one UI face. JetBrainsMono Nerd Font is the only family this
	// desktop draws text with -- titles, values and body alike -- and Material
	// Symbols Rounded is the only icon face. The same family owns the terminal
	// and the code; a panel that mixes faces is the drift this replaces.
	readonly property string textFont: "JetBrainsMono Nerd Font"
	readonly property string uiFont: "JetBrainsMono Nerd Font"
	// Weight: 600 is asked for by name. The family is static, so font.weight is
	// what lands it: fontconfig resolves 600 to the real SemiBold face. The axis
	// map stays empty on purpose -- there is no wght axis here to apply.
	readonly property int fontWeightUi: 600
	readonly property var fontVariableAxesUi: ({})
	readonly property int fontWeightDisplay: 600
	readonly property var fontVariableAxesDisplay: ({})
	readonly property int fontWeightText: 600
	// Icon glyphs are a variable font too: same weight, plus the axes the
	// component inlines (FILL 0, GRAD 0, opsz 24).
	readonly property int fontWeightIcons: 600
	readonly property var fontVariableAxesIcons: ({ "FILL": 0, "wght": 600, "GRAD": 0, "opsz": 24 })
	readonly property string displayFont: "JetBrainsMono Nerd Font"
	readonly property string iconFont: "Material Symbols Rounded"
	readonly property real letterSpacingLabel: 1.4
	readonly property real letterSpacingCaption: 0.6
	readonly property real letterSpacingPassword: 10

	// Sizes
	readonly property int fontSizeClock: 84
	readonly property int fontSizeTitle: 17
	readonly property int fontSizeBody: 14
	readonly property int fontSizeSmall: 11
	readonly property int fontSizeCaption: 12
	readonly property int iconSizeMd: 22
	readonly property int iconSizeLg: 28

	// Shape
	readonly property int shapeSmall: 4
	readonly property int shapeMedium: 6
	readonly property int shapeExtraLarge: 12
	readonly property int shapeFull: 24

	// Spacing and controls, one set for every surface
	readonly property int spacingXs: 4
	readonly property int spacingSmall: 8
	readonly property int spacingMedium: 12
	readonly property int spacingLarge: 16
	readonly property int spacingXl: 24
	readonly property int contentPad: 20
	readonly property int fieldHeightTall: 56
	readonly property int buttonHeightLarge: 48
	readonly property int ruleWidth: 32
	readonly property int ruleThickness: 1
	readonly property int cursorWidth: 10
	readonly property int cursorHeight: 20
	readonly property int borderWidth: 1

	// Opacity: only the state layer of an accent fill, which has no rung above
	// it. No text on this surface dims with opacity -- the ink steps instead.
	readonly property real opacityStateLayer: 0.09

	// Motion: the same durations as every plaque; reduced motion zeroes them in
	// the generator, so nothing here branches on the flag.
	readonly property int motionControlDuration: 110
	readonly property int motionControlEasing: Easing.OutCubic
	readonly property int motionPressDuration: 80

	// Card geometry: the greeter's card is the unlock card, so it takes the same
	// width and the same reserved status slot.
	readonly property int cardWidth: 400
	readonly property int statusHeight: 14

	// How long an attempt may sit in VERIFYING before the field is handed back.
	// sddm emits loginFailed on a rejection, but a service that never answers
	// would leave the field disabled with no way out -- the exact hole the lock
	// context had.
	readonly property int failureHintMs: 3000
}
