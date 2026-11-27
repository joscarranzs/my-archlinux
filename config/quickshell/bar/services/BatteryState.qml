import QtQuick
import Quickshell
import Quickshell.Services.UPower
import ".."

// The pack, as the bar sees it.
//
// Read straight from upower over D-Bus instead of sysfs: /sys/class/power_supply
// /BAT1 on this host publishes no power_now and no design_capacity, so a sysfs
// reader cannot say how fast the pack is draining. upower already samples it and
// owns the energy, the rate and the health numbers.
//
// DUPLICATED ON PURPOSE from battery/services/BatteryState.qml: Quickshell does not
// register a symlinked component in a directory's synthetic qmldir, and the two
// surfaces import their own Appearance. Change one, copy it over the other, or
// the bar and the plaque will disagree about the same battery.
//
// A component, not a singleton: inside a `pragma Singleton` the UPower service
// was created before the D-Bus side existed and every field stayed at zero for
// the life of the process (measured), while the same reads from an ordinary
// object answer within a second and a half.
QtObject {
    id: root

    // Only for the thresholds, so the glyph and the panel disagree on nothing.
    readonly property Appearance look: Appearance {}

    // The real battery device, not UPower.displayDevice: the composite reports
    // healthPercentage as 0 on this host, while the device behind it reports the
    // measured 65.65 % of design capacity.
    property var pack: null

    readonly property bool available: root.pack !== null && root.pack.ready && root.pack.isPresent

    // upower publishes percentage as a 0..1 fraction.
    readonly property real percent: root.available ? Math.round(root.pack.percentage * 100) : 0

    readonly property int state: root.available ? root.pack.state : 0
    readonly property bool charging: root.state === UPowerDeviceState.Charging
        || root.state === UPowerDeviceState.PendingCharge
    readonly property bool full: root.state === UPowerDeviceState.FullyCharged

    // Seconds, straight from upower: timeToEmpty is 0 whenever the pack is on AC
    // and timeToFull is 0 whenever it is not charging.
    readonly property real secondsToEmpty: root.available ? root.pack.timeToEmpty : 0
    readonly property real secondsToFull: root.available ? root.pack.timeToFull : 0

    // Watt-hours the pack holds now, and what it holds when full, which is the
    // number health is computed from.
    readonly property real energy: root.available ? root.pack.energy : 0
    readonly property real energyCapacity: root.available ? root.pack.energyCapacity : 0

    // Watts, positive while discharging. upower reports 0 on AC with a full pack.
    readonly property real rate: root.available ? root.pack.changeRate : 0

    // Percentage of the design capacity, 0..100.
    readonly property real health: root.available ? root.pack.healthPercentage : 0

    readonly property string model: root.available ? String(root.pack.model || "") : ""

    // upower's own state enum, in the panel's language.
    readonly property string stateLabel: {
        switch (root.state) {
        case UPowerDeviceState.Charging: return "charging";
        case UPowerDeviceState.Discharging: return "discharging";
        case UPowerDeviceState.Empty: return "empty";
        case UPowerDeviceState.FullyCharged: return "full";
        case UPowerDeviceState.PendingCharge: return "pending charge";
        case UPowerDeviceState.PendingDischarge: return "pending discharge";
        default: return root.available ? "unknown" : "no battery";
        }
    }

    readonly property string level: !root.available ? ""
        : (root.percent <= root.look.batteryCriticalThreshold ? "critical"
            : (root.percent <= root.look.batteryAlertThreshold ? "alert" : ""))

    // Gold only where the user has to act, red where the machine is about to
    // decide for him; charging stays muted because it is not a problem to solve.
    readonly property color glyphColor: root.level === "critical" ? root.look.danger
        : (root.level === "alert" ? root.look.accentInk : root.look.textMuted)

    // The glyph carries the level. Charging has its own family, and the bands are
    // the ones the font actually publishes: battery_0_bar .. battery_6_bar,
    // battery_charging_20 .. _90. A pack about to die gets the alert triangle
    // rather than an empty rectangle, which reads as "no data" instead of "hurry".
    readonly property string glyph: {
        if (!root.available)
            return "battery_unknown";
        if (root.percent <= root.look.batteryCriticalThreshold)
            return "battery_alert";
        if (root.charging) {
            if (root.percent <= 25) return "battery_charging_20";
            if (root.percent <= 40) return "battery_charging_30";
            if (root.percent <= 55) return "battery_charging_50";
            if (root.percent <= 70) return "battery_charging_60";
            if (root.percent <= 90) return "battery_charging_80";
            return "battery_charging_90";
        }
        if (root.full || root.percent >= 100)
            return "battery_full";
        const band = Math.round(root.percent * 6 / 100);
        return "battery_" + Math.max(0, Math.min(6, band)) + "_bar";
    }

    function resolve() {
        const devices = UPower.devices.values || [];
        for (let i = 0; i < devices.length; i++) {
            const device = devices[i];
            if (device.type === UPowerDeviceType.Battery && device.isPresent) {
                root.pack = device;
                return;
            }
        }
    }

    Component.onCompleted: root.resolve()

    // upower enumerates a moment after the shell starts, so the first resolve
    // returns nothing. Poll until it lands, then stop. Declared as a property:
    // QtObject has no default property, so a bare Timer child does not compile.
    property Timer poll: Timer {
        interval: 500
        repeat: true
        running: root.pack === null || !root.pack.ready
        onTriggered: root.resolve()
    }
}
