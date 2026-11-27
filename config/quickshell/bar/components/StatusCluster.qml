import QtQuick
import Quickshell
import "../services"
import ".."
import "."

// Right cluster: audio and display, a hairline, connectivity and power, a
// hairline, then notifications and the token readout. Hairlines split the
// groups; every module is icon-only.
Row {
    id: root

    property Appearance appearance: Appearance {}

    // The pack, owned by the bar and handed down: the cluster only reads it.
    property BatteryState battery: null

    height: appearance.contentHeight
    spacing: appearance.iconGap

    StatusItem {
        appearance: root.appearance
        // The glyph follows the level, so the bar cannot claim "volume up" while
        // the mixer sits at 20 % or the output is silent. Red only while muted:
        // that is an anomaly worth seeing from across the room.
        icon: AudioOutput.glyph
        iconColor: AudioOutput.muted ? root.appearance.danger : root.appearance.textMuted
        interactive: true
        // Same script the panel's own toggle uses: a second click closes it.
        onActivated: Quickshell.execDetached([
            Quickshell.env("HOME") + "/.scripts/session/volume.sh"
        ])
    }

    // Backlight. Same contract as the volume glyph above: the glyph follows the
    // level, so the bar cannot claim "full sun" while the panel sits at 5 %, and
    // the click opens the panel (whose script is a toggle, so a second click
    // closes it).
    StatusItem {
        appearance: root.appearance
        icon: Brightness.glyph
        interactive: true
        onActivated: Quickshell.execDetached([
            Quickshell.env("HOME") + "/.scripts/session/brightness.sh"
        ])
    }

    BarSeparator {
        appearance: root.appearance
    }

    // Connectivity. The glyph is the state (off / looking / connected) and the click
    // opens the wifi panel, which is a toggle.
    StatusItem {
        appearance: root.appearance
        icon: NetworkState.glyph
        iconColor: NetworkState.anomaly ? root.appearance.danger : root.appearance.textMuted
        interactive: true
        onActivated: Quickshell.execDetached([
            Quickshell.env("HOME") + "/.scripts/session/wifi.sh"
        ])
    }

    StatusItem {
        appearance: root.appearance
        icon: "bluetooth"
    }

    // External displays. The click opens the monitor panel; the script is a
    // toggle, so a second click closes it. The laptop rule stays locked there.
    StatusItem {
        appearance: root.appearance
        icon: "monitor"
        interactive: true
        onActivated: Quickshell.execDetached([
            Quickshell.env("HOME") + "/.scripts/session/monitor.sh"
        ])
    }

    // The pack. Glyph and colour follow the level, so the bar cannot claim a full
    // battery while the pack is down to its last fifth. The click opens the
    // battery panel; the script is a toggle, so a second click closes it.
    StatusItem {
        appearance: root.appearance
        icon: root.battery ? root.battery.glyph : "battery_unknown"
        iconColor: root.battery ? root.battery.glyphColor : root.appearance.textMuted
        interactive: true
        onActivated: Quickshell.execDetached([
            Quickshell.env("HOME") + "/.scripts/session/battery.sh"
        ])
    }

    BarSeparator {
        appearance: root.appearance
    }

    // Token spend for the session. Opens the token panel; the script is a
    // toggle, so a second click closes the plaque that is already up.
    //
    // The glyph also carries the worst allowance window: muted while there is
    // room, accent at the alert threshold, danger above the critical one. That
    // colour is the only warning this desktop can show.
    StatusItem {
        appearance: root.appearance
        icon: "neurology"
        iconColor: TokenUsage.glyphColor
        interactive: true
        onActivated: Quickshell.execDetached([
            Quickshell.env("HOME") + "/.scripts/session/tokens.sh"
        ])
    }

    // Task board. Opens the kanban panel; the script is a toggle, so a second
    // click closes the plaque that is already up.
    StatusItem {
        appearance: root.appearance
        icon: "task_alt"
        interactive: true
        onActivated: Quickshell.execDetached([
            Quickshell.env("HOME") + "/.scripts/session/kanban.sh"
        ])
    }
}
