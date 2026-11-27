import QtQuick
import Quickshell
import Quickshell.Io

// Runs scripts/session/tokens.py and exposes the JSON it prints.
//
// One process per refresh, 60 s apart. The helper keeps its own 60 s cache under
// XDG_RUNTIME_DIR with a lock, so a second panel (or a second monitor) costs no
// extra request. The helper always exits 0 and prints valid JSON: a failed or
// stale reading is a field inside each block, so the parse decides what we got,
// not the exit code.
Item {
    id: root

    property var data: ({})
    property bool parsingFailed: false
    property real alertThreshold: 90
    property real criticalThreshold: 97

    readonly property var nous: data.nous || ({})
    // Plan allowance: three windows that the panel paints as bars. Exposed as a
    // whole block so a failed read stays readable as fields, not as emptiness.
    readonly property var go: data.go || ({})
    readonly property var tokens: data.tokens || ({})
    readonly property bool hasData: !!data.tokens

    signal refreshed()

    function refresh() {
        if (!proc.running)
            proc.running = true;
    }

    function consume(text) {
        try {
            var parsed = JSON.parse(text);
            if (!parsed || typeof parsed !== "object")
                throw new Error("not an object");
            root.parsingFailed = false;
            root.data = parsed;
            root.refreshed();
        } catch (error) {
            // Keep the previous snapshot on screen: a broken helper must not blank
            // a panel that was showing real numbers a second ago.
            root.parsingFailed = true;
        }
    }

    Component.onCompleted: refresh()

    Timer {
        interval: 60000
        running: true
        repeat: true
        onTriggered: root.refresh()
    }

    Process {
        id: proc

        // The thresholds come from look.json through Appearance; the helper only
        // needs the numbers so its alerts and the bars agree.
        command: [
            "/usr/bin/python3",
            Quickshell.env("HOME") + "/.scripts/session/tokens.py",
            "--alert", String(root.alertThreshold),
            "--critical", String(root.criticalThreshold),
        ]
        stdout: StdioCollector {
            onStreamFinished: root.consume(text)
        }
    }
}
