import QtQuick
import ".."

// Four bars, filled by strength. Drawn instead of a Material glyph because the
// font only publishes discrete wifi_1/wifi_2/wifi_3 steps: with three glyphs a
// 42 % link and a 64 % link look identical, and the panel is the only place the
// user can see the difference.
Item {
    id: bars

    property Appearance appearance: Appearance {}
    property int percent: 0
    property color barColor: appearance.textMuted

    implicitWidth: appearance.signalBars * appearance.signalBarWidth
        + (appearance.signalBars - 1) * appearance.signalBarGap
    implicitHeight: appearance.signalHeight

    // Which bars are lit. ceil keeps one bar visible for any usable link: a
    // connection at 8 % reading as four empty bars looks like no connection.
    readonly property int lit: percent <= 0 ? 0
        : Math.max(1, Math.ceil(percent / 100 * appearance.signalBars))

    Row {
        anchors.bottom: parent.bottom
        spacing: bars.appearance.signalBarGap

        Repeater {
            model: bars.appearance.signalBars

            Rectangle {
                width: bars.appearance.signalBarWidth
                // A rising staircase: each bar is taller than the previous one.
                height: Math.round(bars.appearance.signalHeight
                    * (0.4 + 0.6 * (index + 1) / bars.appearance.signalBars))
                radius: width / 2
                anchors.bottom: parent.bottom
                color: index < bars.lit ? bars.barColor : bars.appearance.textFaint
            }
        }
    }
}
