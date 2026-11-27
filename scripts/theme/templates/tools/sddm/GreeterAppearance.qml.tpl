import QtQuick

// Design tokens for the SDDM greeter (the same roles the unlock card uses, over
// the {{palette.name}} palette).
// Generated from theme/colors.json + theme/look.json + theme/typography.json.
//
// The greeter is not a Quickshell surface: it runs in SDDM's own QQuickView, as
// the `sddm` user, before any session exists. It therefore carries no Qs*
// import and no env lookup -- only roles, so the template below picks a role
// and never a number.
QtObject {
	// Color roles
	readonly property color surface: "{{surface.base}}"
	readonly property color surfaceContainer: "{{surface.raised}}"
	readonly property color surfaceContainerHigh: "{{surface.raisedHigh}}"
	readonly property color outline: "{{surface.line}}"
	readonly property color text: "{{text.ink}}"
	readonly property color textMuted: "{{text.inkSoft}}"
	readonly property color accent: "{{accent.primary}}"
	// accentInk is the accent used as ink (the caption line above the clock);
	// accentText is what sits on top of an accent fill.
	readonly property color accentInk: "{{accent.primaryInk}}"
	readonly property color accentText: "{{onAccent.primary}}"
	// Gilt: the ornament role -- the plaque rule and the card's edge.
	readonly property color gilt: "{{accent.tertiary}}"
	// Gilt as ink: the ornament tone is a stroke on paper, so gold read as text
	// takes the deeper step that clears 4.5:1 (the monitor's reset label).
	readonly property color giltInk: "{{accent.tertiaryInk}}"
	readonly property color danger: "{{signal.red}}"

	// Material: hover lights the object one rung up the tonal ladder and ignites
	// its edge with gilt; press steps it back down to base. The unlock card's
	// button rests at surfaceContainerHigh, so its hover takes hoverFillHigh --
	// the same recipe, because two login surfaces with two hovers is drift.
	readonly property color hoverFill: "{{surface.raisedHigh}}"
	readonly property color hoverFillHigh: "{{surface.selection}}"
	readonly property color pressFill: "{{surface.base}}"

	// Typography: one UI face. JetBrainsMono Nerd Font is the only family this
	// desktop draws text with -- titles, values and body alike -- and Material
	// Symbols Rounded is the only icon face. The same family owns the terminal
	// and the code; a panel that mixes faces is the drift this replaces.
	readonly property string textFont: "{{typography.fonts.ui}}"
	readonly property string uiFont: "{{typography.fonts.ui}}"
	// Weight: 600 is asked for by name. The family is static, so font.weight is
	// what lands it: fontconfig resolves 600 to the real SemiBold face. The axis
	// map stays empty on purpose -- there is no wght axis here to apply.
	readonly property int fontWeightUi: {{typography.weights.ui}}
	readonly property var fontVariableAxesUi: ({})
	readonly property int fontWeightDisplay: {{typography.weights.display}}
	readonly property var fontVariableAxesDisplay: ({})
	readonly property int fontWeightText: {{typography.weights.text}}
	// Icon glyphs are a variable font too: same weight, plus the axes the
	// component inlines (FILL 0, GRAD 0, opsz 24).
	readonly property int fontWeightIcons: {{typography.weights.icons}}
	readonly property var fontVariableAxesIcons: ({ "FILL": 0, "wght": {{typography.weights.icons}}, "GRAD": 0, "opsz": 24 })
	readonly property string displayFont: "{{typography.fonts.ui}}"
	readonly property string iconFont: "{{typography.fonts.icons}}"
	readonly property real letterSpacingLabel: {{typography.letterSpacing.label}}
	readonly property real letterSpacingCaption: {{typography.letterSpacing.caption}}
	readonly property real letterSpacingPassword: {{typography.letterSpacing.password}}

	// Sizes
	readonly property int fontSizeClock: {{typography.sizes.clock}}
	readonly property int fontSizeTitle: {{typography.sizes.title}}
	readonly property int fontSizeBody: {{typography.sizes.body}}
	readonly property int fontSizeSmall: {{typography.sizes.small}}
	readonly property int fontSizeCaption: {{typography.sizes.caption}}
	readonly property int iconSizeMd: {{typography.sizes.iconMd}}
	readonly property int iconSizeLg: {{typography.sizes.iconLg}}

	// Shape
	readonly property int shapeSmall: {{look.borders.radius.sm}}
	readonly property int shapeMedium: {{look.borders.radius.md}}
	readonly property int shapeExtraLarge: {{look.borders.radius.xl}}
	readonly property int shapeFull: 24

	// Spacing and controls, one set for every surface
	readonly property int spacingXs: {{look.spacing.xs}}
	readonly property int spacingSmall: {{look.spacing.sm}}
	readonly property int spacingMedium: {{look.spacing.md}}
	readonly property int spacingLarge: {{look.spacing.lg}}
	readonly property int spacingXl: {{look.spacing.xl}}
	readonly property int contentPad: {{look.controls.contentPadTight}}
	readonly property int fieldHeightTall: {{look.controls.fieldHeightTall}}
	readonly property int buttonHeightLarge: {{look.controls.buttonHeightLarge}}
	readonly property int ruleWidth: {{look.controls.ruleWidth}}
	readonly property int ruleThickness: {{look.controls.ruleThickness}}
	readonly property int cursorWidth: {{look.controls.cursorWidth}}
	readonly property int cursorHeight: {{look.controls.cursorHeight}}
	readonly property int borderWidth: {{look.borders.width}}

	// Opacity: only the state layer of an accent fill, which has no rung above
	// it. No text on this surface dims with opacity -- the ink steps instead.
	readonly property real opacityStateLayer: {{look.opacity.stateLayer}}

	// Motion: the same durations as every plaque; reduced motion zeroes them in
	// the generator, so nothing here branches on the flag.
	readonly property int motionControlDuration: {{animations.ui.controlDuration}}
	readonly property int motionControlEasing: {{animations.ui.controlEasing}}
	readonly property int motionPressDuration: {{animations.ui.pressDuration}}

	// Card geometry: the greeter's card is the unlock card, so it takes the same
	// width and the same reserved status slot.
	readonly property int cardWidth: {{look.lockscreen.cardWidth}}
	readonly property int statusHeight: {{look.lockscreen.statusHeight}}

	// How long an attempt may sit in VERIFYING before the field is handed back.
	// sddm emits loginFailed on a rejection, but a service that never answers
	// would leave the field disabled with no way out -- the exact hole the lock
	// context had.
	readonly property int failureHintMs: 3000
}
