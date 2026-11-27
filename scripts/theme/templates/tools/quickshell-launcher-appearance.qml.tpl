import QtQuick
import Quickshell
import Quickshell.Io

// Design tokens for the launcher (MD3 roles mapped to the {{palette.name}} palette).
// Generated from theme/colors.json + theme/look.json + theme/typography.json.
// Reuses the same roles as LockAppearance.qml so all Quickshell panels
// share one visual language. Names avoid the `on*` prefix reserved by QML.
QtObject {
    id: root
    // Color roles
    readonly property color surface: "{{surface.base}}"
    readonly property color surfaceContainer: "{{surface.raised}}"
    readonly property color surfaceContainerHigh: "{{surface.raisedHigh}}"
    readonly property color outline: "{{surface.line}}"
    readonly property color text: "{{text.ink}}"
    readonly property color textFaint: "{{text.inkFaint}}"
    readonly property color textMuted: "{{text.inkSoft}}"
    // accent paints fills and strokes; accentInk is the same hue used as ink —
    // as text it takes a deeper step, so a label sits above the 4.5:1 floor.
    readonly property color accent: "{{accent.primary}}"
    // Gilt: the ornament role (header rule and plaque edge) — the gold accent,
    // not the action accent.
    readonly property color gilt: "{{accent.tertiary}}"
    // Gilt as ink: the ornament tone is a stroke on paper, so gold read as text
    // takes the deeper step that clears 4.5:1 (the monitor's reset label).
    readonly property color giltInk: "{{accent.tertiaryInk}}"
    readonly property color accentInk: "{{accent.primaryInk}}"
    readonly property color accentText: "{{onAccent.primary}}"
    readonly property color danger: "{{signal.red}}"
    readonly property color scrim: "#000000"

    // Material: hover lights the object instead of tinting it — one rung up the
    // tonal ladder (raisedHigh) plus a gilt hairline; press steps it back down to
    // base. hoverFillHigh is for an object whose resting fill is already
    // raisedHigh and has no rung left below it. Mint stays the action accent.
    readonly property color hoverFill: "{{surface.raisedHigh}}"
    readonly property color hoverFillHigh: "{{surface.selection}}"
    readonly property color pressFill: "{{surface.base}}"

    // Cards: a plaque is a well and every block on it is a raised card, so the
    // grouping is elevation instead of a rule between sections. One fill, radius,
    // inset and gap everywhere; the card's own edge is the system hairline
    // (outline) because the tonal steps sit 1.14:1 apart and do not group alone.
    readonly property color cardFill: "{{surface.raised}}"
    readonly property int cardRadius: {{look.borders.radius.lg}}
    readonly property int cardPad: {{look.spacing.lg}}
    readonly property int cardGap: {{look.spacing.md}}
    // Usage bars: a consumed fraction. One height and one track alpha everywhere,
    // so the bar in the battery panel and the bar in the AI plaque are one object.
    readonly property int usageBarHeight: {{look.spacing.xs}}
    readonly property real usageBarTrack: {{look.opacity.barTrack}}

    // Opacity
    readonly property real opacityMuted: {{look.opacity.muted}}
    readonly property real opacityDisabled: {{look.opacity.disabled}}
    readonly property real opacityStateLayer: {{look.opacity.stateLayer}}
    readonly property real opacityPlaceholder: {{look.opacity.placeholder}}
    readonly property real opacityCursor: {{look.opacity.cursor}}
    readonly property real opacityFrame: {{look.opacity.frame}}

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
    readonly property real letterSpacingDisplay: {{typography.letterSpacing.display}}

    // Shape
    readonly property int shapeSmall: {{look.borders.radius.sm}}
    readonly property int shapeMedium: {{look.borders.radius.md}}
    readonly property int shapeLarge: {{look.borders.radius.lg}}
    readonly property int shapeExtraLarge: {{look.borders.radius.xl}}
    readonly property int shapeFull: {{look.borders.radius.full}}


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

    readonly property int fontSizeMicro: Math.round({{typography.sizes.micro}} * textScale)
    readonly property int fontSizeSmall: Math.round({{typography.sizes.small}} * textScale)
    readonly property int fontSizeCaption: Math.round({{typography.sizes.caption}} * textScale)
    readonly property int fontSizeBody: Math.round({{typography.sizes.body}} * textScale)
    readonly property int fontSizeTitle: Math.round({{typography.sizes.title}} * textScale)
    readonly property int fontSizeDisplay: Math.round({{typography.sizes.display}} * textScale)
    readonly property int iconSizeXs: {{typography.sizes.iconXs}}
    readonly property int iconSizeSm: {{typography.sizes.iconSm}}
    readonly property int iconSizeMd: {{typography.sizes.iconMd}}
    readonly property int iconSizeLg: {{typography.sizes.iconLg}}
    readonly property int iconSizeXl: {{typography.sizes.iconXl}}
    readonly property int iconSizeTile: {{typography.sizes.iconTile}}

    // Chrome and controls: one set of heights and steps for every surface,
    // read from theme/look.json. A panel picks a role; it never picks a number.
    readonly property int contentPad: {{look.controls.contentPad}}
    readonly property int headerHeight: {{look.controls.headerHeight}}
    readonly property int footerHeight: {{look.controls.footerHeightTall}}
    readonly property int fieldHeight: {{look.controls.fieldHeight}}
    readonly property int fieldHeightHero: {{look.controls.fieldHeightHero}}
    readonly property int fieldHeightCompact: {{look.controls.fieldHeightCompact}}
    readonly property int buttonHeight: {{look.controls.buttonHeight}}
    readonly property int buttonHeightLarge: {{look.controls.buttonHeightLarge}}
    readonly property int rowHeight: {{look.controls.rowHeight}}
    readonly property int contentPadTight: {{look.controls.contentPadTight}}
    readonly property int footerHeightTall: {{look.controls.footerHeightTall}}
    readonly property int fieldHeightDense: {{look.controls.fieldHeightDense}}
    readonly property int fieldHeightTall: {{look.controls.fieldHeightTall}}
    readonly property int buttonHeightDense: {{look.controls.buttonHeightDense}}
    readonly property int rowHeightTall: {{look.controls.rowHeightTall}}
    readonly property int iconButtonSize: {{look.controls.iconButtonSize}}
    readonly property int chipHeight: {{look.controls.chipHeight}}
    readonly property int cardHeight: {{look.controls.cardHeight}}
    readonly property int spacingTight: {{look.spacing.tight}}
    readonly property int headerHeightTall: {{look.controls.headerHeightTall}}
    readonly property int keycapHeight: {{look.controls.keycapHeight}}
    readonly property int dotSize: {{look.controls.dotSize}}
    readonly property int spacingXs: {{look.spacing.xs}}
    readonly property int spacingSmall: {{look.spacing.sm}}
    readonly property int spacingMedium: {{look.spacing.md}}
    readonly property int spacingLarge: {{look.spacing.lg}}
    readonly property int spacingXl: {{look.spacing.xl}}
    readonly property int spacingXxl: {{look.spacing.xxl}}
    readonly property int ruleWidth: {{look.controls.ruleWidth}}
    readonly property int ruleThickness: {{look.controls.ruleThickness}}
    readonly property int cursorWidth: {{look.controls.cursorWidth}}
    readonly property int cursorHeight: {{look.controls.cursorHeight}}
    readonly property int zBadge: {{look.controls.zBadge}}
    readonly property int zOverlay: {{look.controls.zOverlay}}
    readonly property int zPopover: {{look.controls.zPopover}}
    readonly property int zModal: {{look.controls.zModal}}
    readonly property real letterSpacingPassword: {{typography.letterSpacing.password}}

    // Metrics
    readonly property int borderWidth: {{look.borders.width}}
    readonly property int hairline: {{look.metrics.hairline}}

    // Panel geometry: every value comes from theme/look.json so the launcher
    // scales with the rest of the desktop instead of pinning its own numbers.
    readonly property int gridCell: {{look.launcher.gridCell}}
    readonly property int gridColumns: {{look.launcher.gridColumns}}
    readonly property int panelMaxHeight: {{look.launcher.maxHeight}}
    // Derived so the grid always lands flush with the content padding.
    // +8px gutter for the thin vertical ScrollBar so it never paints over the 6th column.
    readonly property int panelWidth: gridColumns * gridCell + contentPad * 2 + 8

    // Scrim
    readonly property real scrimOpacity: {{look.opacity.scrim}}

    // Motion: one subtle hover fade plus the plaque entrance, both timed from
    // theme/animations.json at generation time. Same two roles as every other
    // panel: the launcher used to read the JSON at run time and drift.
    readonly property int motionControlDuration: {{animations.ui.controlDuration}}
    readonly property int motionControlEasing: {{animations.ui.controlEasing}}
    // Press steps the fill back down; shorter than hover so the click lands.
    readonly property int motionPressDuration: {{animations.ui.pressDuration}}
    readonly property int motionEntranceDuration: {{animations.ui.entranceDuration}}
    readonly property int motionEntranceEasing: {{animations.ui.entranceEasing}}
    readonly property int motionEntranceOffset: {{animations.ui.entranceOffset}}

    // Backdrop
    readonly property string backdropImage: "file://" + Quickshell.env("HOME") + "/.wallpapers/current/default-background"
}
