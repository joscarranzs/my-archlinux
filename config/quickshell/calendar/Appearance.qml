import QtQuick
import Quickshell
import Quickshell.Io

// Design tokens for the calendar panel (MD3 roles mapped to the warm-paper palette).
// Generated from theme/colors.json + theme/look.json + theme/typography.json.
// Colour, type and shape roles are shared with the launcher and the lock
// surface so every Quickshell surface stays one family; chrome metrics (padding,
// header height, rule) come from look.launcher on purpose, and only
// the grid geometry is the calendar's own block. Names avoid the `on*` prefix
// reserved by QML.
QtObject {
    id: root
    // Color roles
    readonly property color surface: "#efecef"
    readonly property color surfaceContainer: "#e8e5e8"
    readonly property color surfaceContainerHigh: "#dfdadf"
    readonly property color outline: "#cfc9cf"
    readonly property color text: "#2a2222"
    readonly property color textFaint: "#897689"
    readonly property color textMuted: "#3e3535"
    // accent paints fills and strokes; accentInk is the same hue used as ink —
    // as text it takes a deeper step, so a label sits above the 4.5:1 floor.
    readonly property color accent: "#007952"
    // Gilt: the ornament role (header rule and plaque edge) — the gold accent,
    // not the action accent.
    readonly property color gilt: "#997900"
    // Gilt as ink: the ornament tone is a stroke on paper, so gold read as text
    // takes the deeper step that clears 4.5:1 (the monitor's reset label).
    readonly property color giltInk: "#826700"
    readonly property color accentInk: "#123623"
    readonly property color danger: "#d01b31"
    readonly property color scrim: "#000000"

    // Material: hover lights the object instead of tinting it — one rung up the
    // tonal ladder (raisedHigh) plus a gilt hairline; press steps it back down to
    // base. hoverFillHigh is for an object whose resting fill is already
    // raisedHigh and has no rung left below it. Mint stays the action accent.
    readonly property color hoverFill: "#dfdadf"
    readonly property color hoverFillHigh: "#e0dce0"
    readonly property color pressFill: "#efecef"

    // Cards: a plaque is a well and every block on it is a raised card, so the
    // grouping is elevation instead of a rule between sections. One fill, radius,
    // inset and gap everywhere; the card's own edge is the system hairline
    // (outline) because the tonal steps sit 1.14:1 apart and do not group alone.
    readonly property color cardFill: "#e8e5e8"
    readonly property int cardRadius: 8
    readonly property int cardPad: 16
    readonly property int cardGap: 12
    // Usage bars: a consumed fraction. One height and one track alpha everywhere,
    // so the bar in the battery panel and the bar in the AI plaque are one object.
    readonly property int usageBarHeight: 4
    readonly property real usageBarTrack: 0.14

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
    // Text scale: one multiplier over the type ladder. It is a preference, not a
    // token, so it comes from the state file the monitor panel writes: every
    // surface recomputes its sizes when that file changes, and the theme is never
    // regenerated for it. Icons keep their own sizes -- they pair with control
    // geometry, which does not scale here.
    //
    // `textScaleOverride` is the review hook (0 = follow the file), the same shape
    // as the panels' forceHover: it is how a harness renders this surface at a
    // scale the machine is not wearing, without touching the user's state.
    property real textScaleOverride: 0
    property real fileTextScale: 1
    readonly property real textScale: textScaleOverride > 0 ? textScaleOverride : fileTextScale

    property FileView textScaleReader: FileView {
        path: (Quickshell.env("XDG_STATE_HOME") || (Quickshell.env("HOME") + "/.local/state"))
            + "/dotfiles/text-scale"
        preload: true
        blockLoading: true
        watchChanges: true
        onFileChanged: reload()
        onLoaded: root.syncTextScale()
    }

    function syncTextScale() {
        const value = parseFloat(textScaleReader.text());
        fileTextScale = isFinite(value) && value > 0 ? value : 1;
    }

    // Preload makes the file readable this early, so the first frame already wears
    // the user's scale instead of snapping to it one frame later.
    Component.onCompleted: syncTextScale()

    readonly property int fontSizeMicro: Math.round(10 * textScale)
    readonly property int fontSizeSmall: Math.round(11 * textScale)
    readonly property int fontSizeCaption: Math.round(12 * textScale)
    readonly property int fontSizeBody: Math.round(14 * textScale)
    readonly property int fontSizeTitle: Math.round(17 * textScale)
    readonly property int fontSizeDisplay: Math.round(26 * textScale)
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


    // Calendar geometry: the grid is the panel, so nothing is centred inside a
    // wider box and the first and last cells land flush with the frame.
    readonly property int weekdayHeight: 18
    readonly property int cellSize: 36
    readonly property int cellGap: 2
    readonly property int columns: 7
    readonly property int rows: 6
    readonly property int navSize: 26
    readonly property int todayDot: 5

    // Derived
    readonly property int gridWidth: columns * cellSize + (columns - 1) * cellGap
    readonly property int panelWidth: gridWidth + contentPad * 2
    readonly property real panelHeight: contentPad * 2 + headerHeight + weekdayHeight
        + rows * cellSize + (rows - 1) * cellGap + footerHeight + spacingSmall * 3
    readonly property int cellCount: columns * rows

    // Motion: the hover state layer fades in instead of popping, same duration
    // the launcher uses for its tiles.
    readonly property int motionControlDuration: 110
    readonly property int motionControlEasing: Easing.OutCubic
    // Press steps the fill back down; shorter than hover so the click lands.
    readonly property int motionPressDuration: 80
    readonly property int motionEntranceDuration: 200
    readonly property int motionEntranceEasing: Easing.OutCubic
    readonly property int motionEntranceOffset: 8

    // Scrim
    readonly property real scrimOpacity: 0.45
}
