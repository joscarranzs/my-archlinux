import QtQuick
import Quickshell
import Quickshell.Io

// Runs scripts/session/kanban-feed.py and exposes the JSON it prints.
//
// One process per refresh, 30 s apart; mutations go through the same helper
// (`act <args...>`) so the hermes binary is resolved in exactly one place.
// The helper always exits 0 and prints valid JSON: a failure is a field inside
// the blob, so the parse decides what we got, not the exit code.
//
// Actions are serialised instead of dropped: a second act while one is in
// flight joins a short queue, so a fast double action can never vanish
// silently. A helper that dies without answering still releases the queue.
Item {
    id: root

    property var tasks: []
    property string error: ""
    property bool busy: false
    property bool parsingFailed: false

    property string verb: ""
    property var queue: []

    signal refreshed()
    signal actionDone(bool ok, string error, string verb)

    function refresh() {
        if (!listProc.running)
            listProc.running = true;
    }

    function act(args) {
        if (actProc.running) {
            if (root.queue.length < 8) {
                var next = root.queue.slice();
                next.push(args);
                root.queue = next;
            }
            return;
        }
        root.launch(args);
    }

    function launch(args) {
        root.busy = true;
        root.verb = (args && args.length > 0) ? args[0] : "";
        actProc.command = ["/usr/bin/python3",
            Quickshell.env("HOME") + "/.scripts/session/kanban-feed.py",
            "act"].concat(args);
        actProc.running = true;
    }

    function next() {
        if (root.queue.length === 0)
            return;
        var pending = root.queue.slice();
        var args = pending.shift();
        root.queue = pending;
        root.launch(args);
    }

    function finishAct(ok, message) {
        if (!root.busy)
            return;
        root.busy = false;
        root.actionDone(ok, message, root.verb);
        if (ok)
            root.refresh();
        root.next();
    }

    function consume(text) {
        try {
            var parsed = JSON.parse(text);
            if (!parsed || typeof parsed !== "object" || !Array.isArray(parsed.tasks))
                throw new Error("no task list");
            root.parsingFailed = false;
            root.tasks = parsed.tasks;
            root.error = parsed.error || "";
            root.refreshed();
        } catch (error) {
            // Keep the previous snapshot on screen: a broken helper must not
            // blank a panel that was showing real tasks a second ago.
            root.parsingFailed = true;
        }
    }

    function consumeAct(text) {
        var ok = false;
        var message = "";
        try {
            var parsed = JSON.parse(text);
            ok = !!parsed.ok;
            message = parsed.error || "";
        } catch (error) {
            message = "unreadable helper response";
        }
        actProc.answered = true;
        root.finishAct(ok, message);
    }

    Component.onCompleted: refresh()

    Timer {
        interval: 30000
        running: true
        repeat: true
        onTriggered: root.refresh()
    }

    Process {
        id: listProc

        command: [
            "/usr/bin/python3",
            Quickshell.env("HOME") + "/.scripts/session/kanban-feed.py"
        ]
        stdout: StdioCollector {
            onStreamFinished: root.consume(text)
        }
    }

    Process {
        id: actProc

        // A mutation that dies before printing still has to free the queue,
        // otherwise every later action is refused and the panel looks dead.
        property bool answered: false

        onStarted: answered = false
        onExited: {
            if (answered)
                return;
            hangTimer.restart();
        }

        stdout: StdioCollector {
            onStreamFinished: root.consumeAct(text)
        }
    }

    // Grace period: StdioCollector can deliver after the process exits.
    Timer {
        id: hangTimer

        interval: 150
        onTriggered: {
            if (!actProc.answered)
                root.finishAct(false, "the helper exited without answering");
        }
    }
}
