import QtQuick
import Quickshell
import "@URL@/wifi/components"

// Empty and error, forced: a scan that found nothing, and a connect that failed.
//
// The panel takes its state as an injected object (WifiPanel.state), so this
// hands it a stub shaped like the NetworkState singleton -- a radio that is up,
// a device that exists, and no network in range. Offscreen there is no
// wpa_supplicant, and without a device the panel's empty line is intentionally
// blank, which would let a blank assert as an empty state.
ShellRoot {
    id: root

    property int pass: 0
    property int fail: 0

    function check(name, condition, detail) {
        if (condition) {
            root.pass += 1;
            console.log("PASS " + name);
        } else {
            root.fail += 1;
            console.log("FAIL " + name + " :: " + (detail === undefined ? "" : detail));
        }
    }

    function byText(item, text, found) {
        if (item.text !== undefined && item.text === text)
            found.push(item);
        for (let i = 0; i < item.children.length; i += 1)
            root.byText(item.children[i], text, found);
        return found;
    }

    QtObject {
        id: stubState

        property var networks: []
        property var current: null
        property bool radioOn: true
        readonly property bool available: true
        readonly property bool attempting: false
        property string lastFailedSsid: ""
        property string status: ""
        property string statusKind: ""

        function needsPassword(network) { return false }
        function securityLabel(network) { return "" }
        function signalPercent(network) { return 0 }
        function cancelAttempt() {}
        function rescan() {}
    }

    Window {
        width: 400
        height: 420
        visible: true

        WifiPanel {
            id: panel
            anchors.centerIn: parent
            state: stubState
        }
    }

    Timer {
        interval: 400
        running: true
        onTriggered: {
            const empty = root.byText(panel, "no networks in range", []);
            root.check("an empty scan says so", empty.length === 1, empty.length);
            if (empty.length === 1) {
                root.check("the empty line is visible", empty[0].visible);
                root.check("the empty line is muted ink, not opacity",
                    empty[0].opacity === 1
                    && Qt.colorEqual(empty[0].color, panel.appearance.textMuted),
                    empty[0].color);
                root.check("the empty line keeps the row's height",
                    empty[0].height === panel.appearance.rowHeight, empty[0].height);
            }
        }
    }

    Timer {
        interval: 550
        running: true
        onTriggered: {
            stubState.status = "wrong password for home";
            stubState.statusKind = "error";
        }
    }

    Timer {
        interval: 700
        running: true
        onTriggered: {
            const line = root.byText(panel, "wrong password for home", []);
            root.check("a failed connect is reported", line.length === 1, line.length);
            if (line.length === 1) {
                root.check("a failure takes the alert ink",
                    Qt.colorEqual(line[0].color, panel.appearance.danger), line[0].color);
            }

            console.log("RESULT pass=" + root.pass + " fail=" + root.fail);
            Qt.quit();
        }
    }

    Timer {
        interval: 4000
        running: true
        onTriggered: Qt.quit()
    }
}
