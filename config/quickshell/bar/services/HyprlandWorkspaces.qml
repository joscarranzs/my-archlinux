import QtQuick
import Quickshell
import Quickshell.Io

// Workspace state for the bar.
//
// The Quickshell Hyprland module reports nothing on Hyprland 0.57 (0 monitors,
// 0 workspaces, no dispatch), so the state is read from `hyprctl -j`. That poll
// is the source of truth; Hyprland's event stream only says "something changed,
// refresh now", which is what turns a 900 ms poll lag into a few milliseconds
// without spawning hyprctl on every event.
QtObject {
    id: root

    property int active: 1
    property var occupied: []

    // Events that can change which workspace is active or which ones exist.
    readonly property var watched: ["workspace", "createworkspace", "destroyworkspace",
                                    "moveworkspace", "renameworkspace", "focusedmon",
                                    "openwindow", "closewindow", "movewindow"]

    function poll() {
        if (!query.running) {
            query.running = true;
        }
    }

    // `hyprctl dispatch` goes through the Lua parser on this build, so the old
    // "workspace 3" string is a syntax error; the dispatcher object is the form
    // that returns ok.
    function select(id) {
        if (id < 1) {
            return;
        }
        active = id;
        Quickshell.execDetached(["hyprctl", "dispatch", "hl.dsp.focus({workspace=" + id + "})"]);
    }

    function hasWindows(id) {
        for (let i = 0; i < occupied.length; i++) {
            if (occupied[i] === id) {
                return true;
            }
        }
        return false;
    }

    function onEvent(line) {
        const marker = line.indexOf(">>");
        if (marker < 0) {
            return;
        }
        const name = line.slice(0, marker).replace(/v2$/, "");
        const payload = line.slice(marker + 2).trim();

        // The workspace event carries the id: take it straight from the line so
        // the pill moves now, instead of waiting for a hyprctl round trip on the
        // critical path. The poll below still reconciles the whole state.
        if (name === "workspace") {
            const id = parseInt(payload, 10);
            if (!isNaN(id)) {
                active = Math.max(id, 1);
                poll();
                return;
            }
        }

        if (watched.indexOf(name) >= 0) {
            poll();
        }
    }

    function apply(raw) {
        const parts = String(raw || "").split("@@@");
        if (parts.length < 2) {
            return;
        }
        try {
            const current = JSON.parse(parts[0].trim());
            const all = JSON.parse(parts[1].trim());
            // occupied first: assigning `active` emits the change signal, and a
            // consumer reading `occupied` there would still see the old list.
            // Only workspaces holding a window are occupied: switching into an
            // empty workspace creates the row, and a dot for it would lie.
            occupied = all.filter(workspace => workspace.windows > 0).map(workspace => workspace.id);
            active = current.id;
        } catch (error) {
            console.warn("bar: cannot parse hyprctl output:", error);
        }
    }

    property Process query: Process {
        command: ["sh", "-c", "hyprctl -j activeworkspace; echo; echo @@@; hyprctl -j workspaces"]

        stdout: StdioCollector {
            onStreamFinished: root.apply(text)
        }
    }

    property Process events: Process {
        command: [Quickshell.env("HOME") + "/.scripts/session/hypr-event-stream.py"]
        running: true

        stdout: SplitParser {
            onRead: line => root.onEvent(line)
        }
    }

    // Safety net only: a missed event must not leave the bar lying forever.
    property Timer poller: Timer {
        interval: 4000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: root.poll()
    }
}
