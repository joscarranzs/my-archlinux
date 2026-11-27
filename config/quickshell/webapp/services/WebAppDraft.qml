import QtQuick
import Quickshell
import Quickshell.Io

// Session-scoped draft for the web app form.
//
// The panel runs as one short-lived process per open, so the typing state
// cannot live in QML memory: it is written to the runtime directory, which is
// tmpfs and disappears on logout. A draft therefore survives closing the panel
// but never survives a reboot, which is exactly what the panel promises.
Scope {
    id: root

    // The draft file is read asynchronously, so consumers wait for this instead
    // of reading the properties in Component.onCompleted.
    signal draftLoaded()

    readonly property string helper: Quickshell.env("HOME") + "/.scripts/session/webapp.py"
    readonly property string draftPath:
        Quickshell.env("XDG_RUNTIME_DIR") + "/quickshell-webapp-draft.json"

    property string appName: ""
    property string url: ""
    property string iconName: ""

    // True when the current values came from an earlier opening.
    property bool restored: false
    // False until the initial read finished, so an empty form never clobbers
    // a draft written by the previous opening.
    property bool ready: false
    // Blocks the change handlers while values are being set programmatically.
    property bool muted: false
    // Closing while a write is in flight must wait for it: Qt.quit() tears the
    // writer child down with the process, so a dismiss right after typing would
    // otherwise lose the last keystroke. Two phases: let any in-flight write
    // finish, then persist the current fields and wait for that write too.
    property bool quitPending: false
    property bool quitAfterWrite: false

    // The draft is on disk and the panel may close now.
    signal persistDone()

    FileView {
        id: draftFile
        path: root.draftPath
        // The panel writes this very file while the user types; watching it
        // would reload the draft and flip `restored` back on mid-edit.
        watchChanges: false
        blockLoading: true
        preload: true
        onLoaded: root.load(draftFile.text())
        onLoadFailed: {
            root.ready = true;
            root.draftLoaded();
        }
    }

    Process {
        id: writer

        onExited: {
            if (!root.quitPending)
                return;
            root.quitPending = false;
            if (root.quitAfterWrite) {
                root.quitAfterWrite = false;
                root.persistDone();
            } else {
                // The in-flight debounce write finished; the fields may have
                // changed since it started, so persist once more before quitting.
                root.persistAndQuit();
            }
        }
    }

    Timer {
        id: debounce
        interval: 250
        onTriggered: root.persist()
    }

    onAppNameChanged: root.touch()
    onUrlChanged: root.touch()
    onIconNameChanged: root.touch()

    function touch() {
        if (root.ready && !root.muted)
            debounce.restart();
    }

    function payload() {
        return JSON.stringify({ name: root.appName, url: root.url, icon: root.iconName });
    }

    function load(raw) {
        if (root.ready)
            return;
        let data = null;
        try {
            data = JSON.parse(String(raw || ""));
        } catch (error) {
            data = null;
        }
        root.muted = true;
        if (data && typeof data === "object") {
            root.appName = String(data.name || "");
            root.url = String(data.url || "");
            root.iconName = String(data.icon || "");
        }
        root.muted = false;
        root.restored = root.appName !== "" || root.url !== "" || root.iconName !== "";
        root.ready = true;
        root.draftLoaded();
    }

    // Write the draft now. Called by the debounce timer and right before the
    // panel closes, so the last keystroke is never lost.
    function persist() {
        if (!root.ready || root.quitPending || root.quitAfterWrite)
            return;
        debounce.stop();
        if (root.appName === "" && root.url === "" && root.iconName === "") {
            root.clear();
            return;
        }
        writer.running = false;
        writer.command = [root.helper, "save", root.payload()];
        writer.running = true;
    }

    // Persist and ask to close; persistDone fires once the draft is on disk.
    // Never restarts a running writer: killing it mid-write is the race this
    // exists to avoid, so an in-flight write is awaited first.
    function persistAndQuit() {
        if (root.quitPending || root.quitAfterWrite)
            return;
        if (writer.running) {
            root.quitPending = true;
            return;
        }
        root.persist();
        if (writer.running) {
            root.quitPending = true;
            root.quitAfterWrite = true;
        } else {
            root.persistDone();
        }
    }

    function clear() {
        root.muted = true;
        root.appName = "";
        root.url = "";
        root.iconName = "";
        root.restored = false;
        root.muted = false;
        debounce.stop();
        writer.running = false;
        writer.command = [root.helper, "clear"];
        writer.running = true;
    }
}
