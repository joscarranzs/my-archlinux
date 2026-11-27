import QtQuick

// Design tokens for the kanban panel (MD3 roles mapped to the warm-charcoal palette).
// Generated from theme/colors.json + theme/look.json + theme/typography.json.
// Colour, type and shape roles are shared with the launcher and the lock
// surface so every Quickshell surface stays one family; chrome metrics (padding,
// header height, rule) come from look.launcher on purpose, and only
// the list geometry is the kanban's own block. Names avoid the `on*` prefix
// reserved by QML.
QtObject {
    // Color roles
    readonly property color surface: "#292329"
    readonly property color surfaceContainer: "#332d33"
    readonly property color surfaceContainerHigh: "#3e353e"
    readonly property color outline: "#4a414a"
    readonly property color text: "#dcd6d6"
    readonly property color textFaint: "#877887"
    readonly property color textMuted: "#c9c2c2"
    // accent paints fills and strokes; accentInk is the same hue used as ink.
    readonly property color accent: "#a2d2b9"
    // Gilt: the ornament role (header rule and plaque edge) — the gold accent,
    // not the action accent.
    readonly property color gilt: "#c3b283"
    readonly property color accentInk: "#dff1e8"
    readonly property color danger: "#d9aeab"
    readonly property color warn: "#c3b283"
    readonly property color ok: "#b5dec9"
    readonly property color scrim: "#000000"
    readonly property real scrimOpacity: 0.45

    // Material: hover lights the object instead of tinting it — one rung up the
    // tonal ladder (raisedHigh) plus a gilt hairline; press steps it back down to
    // base. hoverFillHigh is for an object whose resting fill is already
    // raisedHigh and has no rung left below it. Mint stays the action accent.
    readonly property color hoverFill: "#3e353e"
    readonly property color hoverFillHigh: "#453c45"
    readonly property color pressFill: "#292329"

    // Opacity
    readonly property real opacityMuted: 0.8
    readonly property real opacityDim: 0.7
    readonly property real opacityFrame: 0.88
    readonly property real opacityStateLayer: 0.09
    readonly property real opacityPlaceholder: 0.75

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
    readonly property real letterSpacingDisplay: 0

    // Type: one ladder for every surface, read from theme/typography.json.
    // A panel picks a role; it never picks a size.
    readonly property int fontSizeMicro: 10
    readonly property int fontSizeSmall: 11
    readonly property int fontSizeCaption: 12
    readonly property int fontSizeBody: 14
    readonly property int fontSizeTitle: 17
    readonly property int fontSizeDisplay: 26
    readonly property int iconSizeXs: 14
    readonly property int iconSizeSm: 18
    readonly property int iconSizeMd: 22
    readonly property int iconSizeLg: 28
    readonly property int iconSizeXl: 40
    readonly property int iconSizeTile: 48

    // Chrome and controls: one set of heights and steps for every surface,
    // read from theme/look.json. A panel picks a role; it never picks a number.
    readonly property int contentPad: 24
    readonly property int headerHeight: 30
    readonly property int footerHeight: 22
    readonly property int fieldHeight: 36
    readonly property int fieldHeightHero: 52
    readonly property int fieldHeightCompact: 32
    readonly property int buttonHeight: 32
    readonly property int buttonHeightLarge: 48
    readonly property int rowHeight: 46
    readonly property int contentPadTight: 20
    readonly property int footerHeightTall: 28
    readonly property int fieldHeightDense: 34
    readonly property int fieldHeightTall: 56
    readonly property int buttonHeightDense: 34
    readonly property int rowHeightTall: 48
    readonly property int iconButtonSize: 32
    readonly property int chipHeight: 28
    readonly property int cardHeight: 44
    readonly property int spacingTight: 6
    readonly property int headerHeightTall: 32
    readonly property int keycapHeight: 18
    readonly property int dotSize: 6
    readonly property int spacingXs: 4
    readonly property int spacingSmall: 8
    readonly property int spacingMedium: 12
    readonly property int spacingLarge: 16
    readonly property int spacingXl: 24
    readonly property int spacingXxl: 32
    readonly property int ruleWidth: 32
    readonly property int ruleThickness: 1
    readonly property int cursorWidth: 10
    readonly property int cursorHeight: 20
    readonly property int zBadge: 2
    readonly property int zOverlay: 20
    readonly property int zPopover: 99
    readonly property int zModal: 100
    readonly property real letterSpacingPassword: 10

    // Shape
    readonly property int shapeSmall: 4
    readonly property int shapeMedium: 6
    readonly property int shapeLarge: 8
    readonly property int shapeExtraLarge: 12
    readonly property int shapeFull: 9999


    // Metrics
    readonly property int borderWidth: 1
    readonly property int hairline: 1


    // Kanban geometry: a single scrolling column of sections, so the panel
    // width and the row rhythm are the only own numbers here.
    readonly property int kanbanWidth: 1240
    readonly property int columnGap: 16
    readonly property int rowGap: 8
    readonly property int ghostWidth: 300
    readonly property int ghostHeight: 38
    readonly property int dialogMaxWidth: 430
    readonly property int counterWidth: 40
    readonly property int buttonMinWidth: 96
    readonly property int extraListMaxHeight: 160
    readonly property int maxHeight: 640
    // Card and badge geometry. The badge used to borrow keycapHeight (the
    // legend's key) and the card borrowed spacingSmall plus the shared
    // controls.cardHeight, so tuning this panel dragged every other surface's
    // tokens with it; these are the three numbers the board actually owns.
    readonly property int cardPadding: 10
    readonly property int badgeHeight: 22
    readonly property int taskCardHeight: 46
    // Type: the card body sits one step under the shared body size. At 14 px a
    // title in a four-lane column wrapped onto three lines and the card read as
    // a wall; 13 fits the same words in two.
    readonly property int cardFontSize: 13
    // The width a card gets inside the board: the panel minus its padding, cut
    // into as many lanes as the board has. Four, since review became a column of
    // its own. A card rendered on its own (the QTest harness) borrows it.
    readonly property int columns: 4
    readonly property int columnWidth: Math.floor((kanbanWidth - contentPad * 2 - columnGap * (columns - 1)) / columns)

    // Motion: the only animation this panel gets is the hover state layer and
    // the card opacity while it drags, timed like every other control.
    readonly property int motionControlDuration: 110
    readonly property int motionControlEasing: Easing.OutCubic
    readonly property int motionEntranceDuration: 200
    readonly property int motionEntranceEasing: Easing.OutCubic
    readonly property int motionEntranceOffset: 8
}
