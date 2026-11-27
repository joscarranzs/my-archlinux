pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// External-monitor state, read from `hyprctl -j monitors all` on a poll.
//
// The Quickshell.Hyprland module is dead on Hyprland 0.57 (0 monitors, no
// dispatch), and `hyprctl keyword monitor ...` answers "unknown request" on a
// Lua config. The working write path is `hyprctl eval 'hl.monitor({...})'`,
// verified against a fake output name before any real one was touched.
//
// Hard rule: the laptop panel (eDP-*/LVDS-*/DSI-*) changes its SCALE and never
// its mode. apply() refuses an internal output whose width or height differs
// from the live one, so no code path from this panel can rewrite the eDP-1 rule
// in monitors.lua into a mode the screen cannot show.
//
// Changes are hot-only by design: nothing is written to any config file, and a
// session restart falls back to whatever monitors.lua says.
Singleton {
    id: root

    // Parsed outputs. `internal` is the laptop panel, `externals` everything else.
    property var monitors: []
    property var internal: null
    property var externals: []
    property bool ready: false
    // JSON of the last parsed poll. Reassigning the model arrays rebuilds every
    // card (and destroys any open menu / pending pick), so a poll that changed
    // nothing must not notify.
    property string lastSnapshot: ""

    property string status: ""
    property string statusKind: ""

    // Common fractional scales Hyprland accepts. A live scale outside this list
    // is added to the options by scaleOptions(), never silently rounded.
    readonly property var scaleSteps: [1, 1.25, 1.5, 1.75, 2, 2.5, 3]

    // What the last apply asked for, waiting for the read-back to confirm it.
    property var verify: null

    function isInternalName(name) {
        return /^(eDP|LVDS|DSI)/.test(String(name));
    }

    // What monitors.lua asks for. Read from the rule, never remembered: the
    // original is the file's, and a reset that restored "the scale the panel saw
    // when it opened" would restore whatever change was already live.
    property FileView monitorRules: FileView {
        path: Quickshell.env("HOME") + "/.config/hypr/monitors.lua"
        preload: true
        blockLoading: true
        watchChanges: true
        onFileChanged: reload()
    }

    // The scale monitors.lua declares for this output, 0 when it declares none
    // (Hyprland's own "auto" then, which this panel has no business guessing).
    function originalScale(name) {
        const text = String(root.monitorRules.text() || "");
        const blocks = text.match(/hl\.monitor\(\{[^}]*\}\)/g) || [];
        for (let i = 0; i < blocks.length; i++) {
            const output = /output\s*=\s*"([^"]+)"/.exec(blocks[i]);
            if (!output || output[1] !== String(name))
                continue;
            const scale = /scale\s*=\s*([0-9.]+)/.exec(blocks[i]);
            return scale ? parseFloat(scale[1]) : 0;
        }
        return 0;
    }

    function find(name) {
        for (let i = 0; i < root.monitors.length; i++) {
            if (root.monitors[i].name === name)
                return root.monitors[i];
        }
        return null;
    }

    // "1920x1080@60.00Hz" -> { w, h, rate }; null on anything else.
    function parseMode(text) {
        const m = /^(\d+)x(\d+)@([\d.]+)Hz$/.exec(String(text).trim());
        if (!m)
            return null;
        return { w: parseInt(m[1], 10), h: parseInt(m[2], 10), rate: parseFloat(m[3]) };
    }

    function rateLabel(rate) {
        return (Math.round(rate * 100) / 100) + " Hz";
    }

    function scaleLabel(scale) {
        // Hyprland can snap a requested scale to its own value (measured on a
        // headless output: asked 1.75, got 1.6666666). Two decimals keep the
        // field readable without pretending the raw float is a choice.
        return (Math.round(scale * 100) / 100) + "×";
    }

    // Unique resolutions, best refresh rate per resolution, biggest first.
    function resolutions(monitor) {
        const best = {};
        const raw = monitor.availableModes || [];
        for (let i = 0; i < raw.length; i++) {
            const m = root.parseMode(raw[i]);
            if (!m)
                continue;
            const key = m.w + "x" + m.h;
            if (!best[key] || m.rate > best[key].rate)
                best[key] = m;
        }
        const out = Object.values(best);
        const bySize = function (a, b) {
            return (b.w * b.h) - (a.w * a.h) || b.rate - a.rate;
        };
        out.sort(bySize);
        // A live mode outside the advertised list (custom modeline, headless
        // output) must still be visible and selectable, never silently shown
        // as some other resolution. It joins at its sorted position, not at
        // the front: the list order is what the arrow keys navigate.
        const w = monitor.width || 0;
        const h = monitor.height || 0;
        if (w > 0 && h > 0 && !out.some(function (m) { return m.w === w && m.h === h; })) {
            out.push({ w: w, h: h, rate: monitor.refreshRate || 60 });
            out.sort(bySize);
        }
        return out;
    }

    function scaleOptions(monitor) {
        const steps = root.scaleSteps.slice();
        if (monitor && steps.indexOf(monitor.scale) === -1) {
            steps.push(monitor.scale);
            steps.sort(function (a, b) { return a - b; });
        }
        return steps;
    }

    function modeIndexOf(monitor, w, h) {
        for (let i = 0; i < monitor.modes.length; i++) {
            if (monitor.modes[i].w === w && monitor.modes[i].h === h)
                return i;
        }
        return 0;
    }

    function scaleIndexOf(monitor, scale) {
        const opts = root.scaleOptions(monitor);
        const i = opts.indexOf(scale);
        return i >= 0 ? i : 0;
    }

    // ------------------------------------------------------------------ read

    function parse(text) {
        let raw = [];
        try {
            raw = JSON.parse(text);
        } catch (error) {
            return;
        }
        if (!Array.isArray(raw))
            return;
        const out = [];
        for (let i = 0; i < raw.length; i++) {
            const m = raw[i];
            if (!m || !m.name)
                continue;
            out.push({
                name: String(m.name),
                description: String(m.description || ""),
                width: m.width || 0,
                height: m.height || 0,
                refresh: m.refreshRate || 0,
                scale: m.scale || 1,
                x: m.x || 0,
                y: m.y || 0,
                disabled: !!m.disabled,
                internal: root.isInternalName(m.name),
                modes: root.resolutions(m),
            });
        }
        // Build every list fully BEFORE assigning: a var property only notifies
        // on assignment, so assigning [] and then push()ing leaves every binding
        // (and the Repeater) staring at the empty array forever.
        let internal = null;
        const ext = [];
        for (let i = 0; i < out.length; i++) {
            if (out[i].internal) {
                if (!internal)
                    internal = out[i];
            } else {
                ext.push(out[i]);
            }
        }
        const snapshot = JSON.stringify(out);
        if (root.ready && snapshot === root.lastSnapshot) {
            // Nothing moved: keep the cards (and any open menu) alive. A pending
            // verify still gets its answer — unchanged data means the write did
            // not land.
            root.checkVerify();
            return;
        }
        root.lastSnapshot = snapshot;
        root.monitors = out;
        root.internal = internal;
        root.externals = ext;
        root.ready = true;
        root.checkVerify();
    }

    function refresh() {
        poll.running = false;
        poll.running = true;
    }

    Process {
        id: poll
        command: ["hyprctl", "-j", "monitors", "all"]
        running: true
        stdout: StdioCollector {
            onStreamFinished: root.parse(text)
        }
    }

    // Hotplug has no event channel here (socket2 is dead on this build), so a
    // 2 s poll is the reconciliation tick; an apply refreshes immediately.
    Timer {
        interval: 2000
        running: true
        repeat: true
        onTriggered: root.refresh()
    }

    // ----------------------------------------------------------------- write

    function apply(name, w, h, rate, scale) {
        if (!/^[A-Za-z0-9_-]+$/.test(String(name))) {
            root.setStatus("error", "bad output name");
            return;
        }
        const mon = root.find(name);
        if (!mon) {
            root.setStatus("error", "monitor gone · " + name);
            return;
        }
        // The laptop panel takes a SCALE and nothing else. It used to be fully
        // read-only, which left the one panel he looks at with no control at
        // all; the mode stays out of reach on purpose -- it is the mode the user
        // is currently reading, and rewriting it is how you lose the screen.
        if (mon.internal && (w !== mon.width || h !== mon.height)) {
            root.setStatus("error", "internal output changes scale only");
            return;
        }
        // Keep the output where it sits; a disabled one has no position yet.
        const position = mon.disabled ? "auto" : mon.x + "x" + mon.y;
        const mode = w + "x" + h + "@" + rate;
        const lua = 'hl.monitor({ output = "' + name + '", mode = "' + mode
            + '", position = "' + position + '", scale = ' + scale + ' })';
        root.verify = { name: name, w: w, h: h, scale: scale };
        writer.running = false;
        writer.command = ["hyprctl", "eval", lua];
        writer.running = true;
    }

    Process {
        id: writer
        stdout: StdioCollector {
            onStreamFinished: {
                const answer = String(text || "").trim();
                if (answer !== "ok") {
                    root.verify = null;
                    root.setStatus("error", "hyprctl refused the change");
                    return;
                }
                // "ok" only means the Lua ran; the read-back is the proof.
                root.refresh();
            }
        }
        stderr: StdioCollector {}
    }

    function checkVerify() {
        if (!root.verify)
            return;
        const want = root.verify;
        root.verify = null;
        const mon = root.find(want.name);
        if (!mon || mon.width !== want.w || mon.height !== want.h) {
            root.setStatus("error", "no change on " + want.name + " · mode refused?");
            return;
        }
        // The compositor may snap the scale to its own value; report what the
        // read-back says, and say so when it differs from what was asked.
        const asked = Math.abs(mon.scale - want.scale) >= 0.001
            ? " (asked " + root.scaleLabel(want.scale) + ")" : "";
        root.setStatus("ok", "applied · " + want.name + " " + want.w + "×"
            + want.h + " · " + root.scaleLabel(mon.scale) + asked);
    }

    // ---------------------------------------------------------------- status

    function setStatus(kind, message) {
        root.statusKind = kind;
        root.status = message;
        statusClear.interval = kind === "error" ? 12000 : 5000;
        statusClear.restart();
    }

    Timer {
        id: statusClear
        onTriggered: {
            root.status = "";
            root.statusKind = "";
        }
    }
}
