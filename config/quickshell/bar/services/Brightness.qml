pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// The panel backlight: read from sysfs, written through logind.
//
// There is no Quickshell brightness module and the sysfs node is root-owned
// (0644), so a panel cannot write /sys/class/backlight/*/brightness. Neither
// `brightnessctl` nor `light` is installed on this host, and adding a setuid
// helper for one slider is not a trade worth making. logind performs the write
// with no polkit prompt from an active local session — measured: 120000 -> 72000
// read back immediately.
//
// The object is /org/freedesktop/login1/session/auto: /session/self does not
// exist here ("Unknown object"). SetBrightness returns nothing, so the sysfs
// read-back is the only proof a write landed; the panel shows what sysfs says,
// never the number it asked for.
//
// The sysfs paths are only bound once the device probe answers, because there is
// no "default backlight" file — the device is whichever directory exists.
//
// DUPLICATED ON PURPOSE from brightness/services/Brightness.qml: Quickshell does
// not register a symlinked singleton in a directory's synthetic qmldir, so the
// link loads as "Brightness is not defined" and the bar silently draws the glyph
// undefined. Change one, copy it over the other, or the bar and the panel will
// disagree.
Singleton {
    id: root

    readonly property string sysfsRoot: "/sys/class/backlight"

    property string deviceId: ""
    property int maxLevel: 0
    property int level: 0

    readonly property bool available: root.deviceId.length > 0 && root.maxLevel > 0
    readonly property real value: root.available
        ? Math.max(0, Math.min(1, root.level / root.maxLevel)) : 0
    readonly property int percent: Math.round(root.value * 100)

    readonly property string deviceName: root.deviceId.length > 0
        ? root.deviceId : "No backlight"

    // Follows the level, the same way the volume glyph does. brightness_1 is the
    // dimmest glyph the font publishes, so a blacked-out panel does not read as
    // "low but fine".
    readonly property string glyph: !root.available ? "brightness_high"
        : (root.value <= 0.001 ? "brightness_1"
            : (root.value < 0.34 ? "brightness_low"
                : (root.value < 0.67 ? "brightness_medium" : "brightness_high")))

    readonly property string maxPath: root.deviceId.length > 0
        ? root.sysfsRoot + "/" + root.deviceId + "/max_brightness" : ""
    readonly property string levelPath: root.deviceId.length > 0
        ? root.sysfsRoot + "/" + root.deviceId + "/brightness" : ""

    // The level the user last asked for, waiting for the throttle to flush it.
    property int pendingLevel: -1

    function setValue(next) {
        if (!root.available)
            return;
        const clamped = Math.max(0, Math.min(1, next));
        root.pendingLevel = Math.round(clamped * root.maxLevel);
        flush.restart();
    }

    function write() {
        if (!root.available || root.pendingLevel < 0)
            return;
        writer.running = false;
        writer.command = [
            "/usr/bin/busctl", "call",
            "org.freedesktop.login1",
            "/org/freedesktop/login1/session/auto",
            "org.freedesktop.login1.Session",
            "SetBrightness", "ssu", "backlight", root.deviceId,
            String(root.pendingLevel),
        ];
        writer.running = true;
        root.pendingLevel = -1;
    }

    // A drag emits one request per mouse event and every write is a process
    // spawn. 60 ms turns ~60 spawns per second into ~16 and is still under the
    // eye's threshold; the panel draws its own visual value, so the fill never
    // waits for this.
    Timer {
        id: flush
        interval: 60
        onTriggered: root.write()
    }

    Process {
        id: writer
        // A missing polkit definition prints "action ... is not registered" here;
        // keep it collected so it lands in the log instead of the panel.
        stderr: StdioCollector {}
    }

    Process {
        id: probe
        command: ["/bin/sh", "-c", "ls -1 " + root.sysfsRoot + " 2>/dev/null | head -1"]
        running: true
        stdout: StdioCollector {
            onStreamFinished: {
                const id = String(text || "").trim();
                if (id.length > 0)
                    root.deviceId = id;
            }
        }
    }

    FileView {
        id: maxFile
        path: root.maxPath
        blockLoading: true
        preload: true
        onLoaded: root.maxLevel = parseInt(maxFile.text(), 10) || 0
    }

    FileView {
        id: levelFile
        path: root.levelPath
        watchChanges: true
        blockLoading: true
        preload: true
        onLoaded: root.level = parseInt(levelFile.text(), 10) || 0
        onFileChanged: levelFile.reload()
    }

    // inotify on sysfs is not guaranteed for every driver, so this is the
    // reconciliation tick: it keeps the panel honest when the write came from the
    // firmware keys or another tool.
    Timer {
        interval: 2000
        running: true
        repeat: true
        onTriggered: {
            if (root.levelPath.length > 0)
                levelFile.reload();
        }
    }
}
