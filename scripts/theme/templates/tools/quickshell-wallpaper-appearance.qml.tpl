import QtQuick

// Design tokens for the wallpaper surface. Generated from theme/colors.json +
// theme/look.json. It is the only surface with no widgets: it carries just the
// gold rule painted around the painting.
QtObject {
    readonly property color accent: "{{accent.primary}}"
    readonly property real frameAlpha: {{look.opacity.frameLine}}
    readonly property color frameLine: Qt.rgba(accent.r, accent.g, accent.b, frameAlpha)
    readonly property int hairline: {{look.metrics.hairline}}
}
