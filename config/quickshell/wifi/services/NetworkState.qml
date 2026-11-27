pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Networking

// The wireless state as the panel needs it, read through Quickshell.Networking
// (a NetworkManager client; this host runs NM with wpa_supplicant as the wifi backend,
// and iwd is retired -- it destroyed the netdev it managed whenever it stopped).
//
// Three hard-won rules live here:
//
// 1. **The model is async.** `Networking.devices` is empty on the first tick, so a
//    `readonly property` that reads it once keeps an empty device forever, and
//    enabling `scannerEnabled` in Component.onCompleted is a no-op (the device does
//    not exist yet, which is why the panel only ever saw NetworkManager's cache).
// 2. **Act on a freshly resolved object, never on a snapshot.** NM destroys and
//    recreates the access-point objects constantly while scanning. A `Network` held
//    for 1.5 s is often already dead, and calling `connectWithPsk` on it does
//    nothing at all: no error, no attempt, no radio activity.
// 3. **Nothing reconnects, disconnects or forgets on its own.** Connect only happens
//    on an explicit user action, and `forget` only touches a profile this panel
//    created during a failed attempt. On a machine whose only uplink is wifi,
//    "forget" is one click from a locked door.
//
// DUPLICATED ON PURPOSE to bar/services/NetworkState.qml: Quickshell does not
// register a symlinked singleton in a directory's synthetic qmldir, so the bar
// keeps its own copy. Change one, copy it over the other.
Singleton {
    id: root

    property var wifiDevice: null

    // What the panel draws. Rebuilt from the live model so sorting and dedup cannot
    // disagree with each other.
    property var networks: []
    property var current: null
    property bool radioOn: Networking.wifiEnabled

    // One attempt at a time. Stores the SSID, not the object: see rule 2.
    property var attempt: null
    property string previousSsid: ""
    // The last network whose attempt failed. `known` can be stale on a recreated
    // access-point object, and a wrong passphrase leaves a profile NetworkManager wrote,
    // so without this the second click skips the prompt and activates a profile that has
    // no secret in it.
    property string lastFailedSsid: ""
    property string status: ""
    property string statusKind: ""

    // The live object the attempt is watching, rebound on every tick so a recreated
    // access point does not silence `connectionFailed`.
    property var watched: null

    readonly property bool attempting: attempt !== null
    readonly property bool available: wifiDevice !== null
    readonly property string deviceName: wifiDevice ? wifiDevice.name : ""

    // The bar draws these; keeping the decision here means the glyph and the panel
    // cannot disagree about what "off", "looking" and "connected" mean.
    readonly property bool anomaly: available && radioOn && current === null
    readonly property string glyph: (!available || !radioOn) ? "wifi_off"
        : (current !== null ? "wifi" : "wifi_find")

    // ---------------------------------------------------------------- device

    function resolveDevice() {
        const list = Networking.devices.values;
        for (let i = 0; i < list.length; i++) {
            if (list[i].type === DeviceType.Wifi) {
                root.wifiDevice = list[i];
                if (root.scanWanted)
                    list[i].scannerEnabled = true;
                root.refresh();
                return;
            }
        }
        root.wifiDevice = null;
        root.networks = [];
        root.current = null;
    }

    function findNetwork(name) {
        if (!root.wifiDevice || !root.wifiDevice.networks)
            return null;
        const list = root.wifiDevice.networks.values;
        for (let i = 0; i < list.length; i++) {
            if (list[i].name === name)
                return list[i];
        }
        return null;
    }

    function refresh() {
        root.radioOn = Networking.wifiEnabled;
        if (!root.wifiDevice || !root.wifiDevice.networks) {
            root.networks = [];
            root.current = null;
            return;
        }
        const raw = root.wifiDevice.networks.values;
        const index = ({});
        const out = [];
        let connected = null;
        for (let i = 0; i < raw.length; i++) {
            const net = raw[i];
            // The connected network is shown by the block above the list; repeating it
            // as a row reads as a duplicate and it cannot be "connected" again.
            if (net.connected) {
                connected = net;
                continue;
            }
            const key = net.name;
            if (index[key] === undefined) {
                index[key] = out.length;
                out.push(net);
            } else if (net.signalStrength > out[index[key]].signalStrength) {
                // The same SSID is advertised once per band; keep the stronger.
                out[index[key]] = net;
            }
        }
        out.sort(function (a, b) {
            if (a.signalStrength !== b.signalStrength)
                return b.signalStrength - a.signalStrength;
            return a.name.localeCompare(b.name);
        });
        root.networks = out;
        root.current = connected;
        root.watchAttempt();
    }

    // ------------------------------------------------------------------ scan

    property bool scanWanted: false

    function startScanning() {
        root.scanWanted = true;
        if (root.wifiDevice)
            root.wifiDevice.scannerEnabled = true;
    }

    function stopScanning() {
        root.scanWanted = false;
        if (root.wifiDevice)
            root.wifiDevice.scannerEnabled = false;
    }

    function rescan() {
        root.startScanning();
    }

    // --------------------------------------------------------------- attempt

    function connectNetwork(network, passphrase) {
        if (!network || root.attempting)
            return;

        // Rule 2: the object the panel passed may be a snapshot from the last tick.
        const fresh = root.findNetwork(network.name);
        if (!fresh) {
            root.statusKind = "error";
            root.status = "out of range · " + network.name;
            clearTimer.interval = 12000;
            clearTimer.restart();
            return;
        }

        root.previousSsid = root.current ? root.current.name : "";
        root.attempt = {
            ssid: fresh.name,
            psk: passphrase !== undefined ? passphrase : "",
            wasKnown: fresh.known,
            pskSent: false,
            seenConnect: false,
        };
        root.watched = fresh;
        root.statusKind = "info";
        root.status = "connecting to " + fresh.name + "…";
        attemptTimer.restart();
        fastPoll.running = true;

        // `connectWithPsk` does attempt the connection, and the backend may reuse the
        // PSK later; `connect()` is the one that asks NM to use what it already knows.
        if (root.attempt.psk !== "")
            fresh.connectWithPsk(root.attempt.psk);
        else
            fresh.connect();
    }

    function onNetworkFailed(reason) {
        if (!root.attempt)
            return;

        // Quickshell.Networking documents this exactly (WifiNetwork.connectWithPsk): a
        // wrong PSK makes the backend emit connectionFailed with NoSecrets. So with a
        // passphrase in hand this is not "the network wants a password", it is "that
        // password is wrong", and it is settled right here. The old code retried at this
        // point, which held the panel in "connecting" until the 12 s timeout and then
        // blamed the backend for refusing a passphrase it had never received.
        if (reason === ConnectionFailReason.NoSecrets) {
            root.failAttempt(root.attempt.psk !== "" ? ConnectionFailReason.NoSecrets : -5);
            return;
        }

        root.failAttempt(reason);
    }

    // Called from every refresh, so a recreated or vanished object cannot strand the
    // attempt the way it did before.
    function watchAttempt() {
        if (!root.attempt)
            return;
        const name = root.attempt.ssid;

        if (root.current !== null && root.current.name === name) {
            root.succeedAttempt();
            return;
        }

        const target = root.findNetwork(name);
        if (target !== root.watched)
            root.watched = target;
        if (!target)
            return;

        if (target.state === ConnectionState.Connecting || target.stateChanging)
            root.attempt.seenConnect = true;

        // Only a network that actually tried and then dropped is a failure; the first
        // Disconnected of an untried access point is not.
        if (root.attempt.seenConnect && target.state === ConnectionState.Disconnected)
            root.failAttempt(ConnectionFailReason.Unknown);
    }

    // The always-available exit: cancel, undo the attempt, keep the panel open. A
    // close blocked while "connecting" is what trapped the panel with no way out.
    function cancelAttempt() {
        if (root.attempt)
            root.failAttempt(-2);
    }

    function succeedAttempt() {
        if (!root.attempt)
            return;
        attemptTimer.stop();
        fastPoll.running = false;
        const name = root.attempt.ssid;
        root.attempt = null;
        root.watched = null;
        root.previousSsid = "";
        root.lastFailedSsid = "";
        root.statusKind = "ok";
        root.status = "connected to " + name;
        clearTimer.interval = 5000;
        clearTimer.restart();
    }

    function failAttempt(reason) {
        if (!root.attempt)
            return;
        attemptTimer.stop();
        fastPoll.running = false;

        const ssid = root.attempt.ssid;
        const wasKnown = root.attempt.wasKnown;
        root.lastFailedSsid = ssid;
        const previousName = root.previousSsid;
        root.attempt = null;
        root.watched = null;
        root.previousSsid = "";

        root.statusKind = "error";
        root.status = root.explain(reason)
            + (previousName !== "" ? " · back on " + previousName : " · offline");
        // Long enough to read, short enough that the key hints come back on their own.
        clearTimer.interval = 12000;
        clearTimer.restart();

        // A network that never came up must not stay saved: NM writes a profile as soon
        // as a passphrase is supplied. Only ever forget what this attempt created.
        if (!wasKnown) {
            const target = root.findNetwork(ssid);
            if (target) {
                try {
                    target.forget();
                } catch (error) {
                    // Nothing was persisted: nothing to remove.
                }
            }
        }

        // Put the link back. An attempt has to disassociate to try another network, so
        // a few seconds of downtime are unavoidable; being left offline is not.
        if (previousName !== "") {
            const back = root.findNetwork(previousName);
            if (back) {
                try {
                    back.connect();
                } catch (error) {}
            }
        }
    }

    function explain(reason) {
        switch (reason) {
        case ConnectionFailReason.NoSecrets:
            return "wrong passphrase";
        case ConnectionFailReason.WifiClientDisconnected:
        case ConnectionFailReason.WifiClientFailed:
            // What a wrong WPA passphrase looks like: the AP drops the four-way
            // handshake and NetworkManager reports the client disconnecting.
            return "wrong passphrase";
        case ConnectionFailReason.WifiAuthTimeout:
            return "auth timed out";
        case ConnectionFailReason.WifiNetworkLost:
            return "out of range";
        case -1:
            return "no answer from the network";
        case -2:
            return "cancelled";
        case -3:
            return "cancelled";
        case -5:
            return "passphrase required";
        default:
            return "connection failed";
        }
    }

    // ---------------------------------------------------------------- labels

    function signalPercent(network) {
        if (!network)
            return 0;
        return Math.max(0, Math.min(100, Math.round(network.signalStrength * 100)));
    }

    function securityLabel(network) {
        if (!network)
            return "";
        switch (network.security) {
        case WifiSecurityType.Open: return "OPEN";
        case WifiSecurityType.Owe: return "OWE";
        case WifiSecurityType.Wpa3SuiteB192: return "WPA3-EAP";
        case WifiSecurityType.Sae: return "WPA3";
        case WifiSecurityType.Wpa2Eap: return "802.1X";
        case WifiSecurityType.Wpa2Psk: return "WPA2";
        case WifiSecurityType.WpaEap: return "802.1X";
        case WifiSecurityType.WpaPsk: return "WPA";
        case WifiSecurityType.StaticWep:
        case WifiSecurityType.DynamicWep: return "WEP";
        case WifiSecurityType.Leap: return "LEAP";
        default: return "UNKNOWN";
        }
    }

    // Open and OWE associations need no passphrase.
    function needsPassword(network) {
        if (!network)
            return false;
        return network.security !== WifiSecurityType.Open
            && network.security !== WifiSecurityType.Owe;
    }

    // ---------------------------------------------------------------- timers

    Timer {
        id: attemptTimer
        interval: 12000
        onTriggered: root.failAttempt(-1)
    }

    // Feedback has to arrive in a normal human beat, not in two 1.5 s ticks; this only
    // runs while an attempt is in flight.
    Timer {
        id: fastPoll
        interval: 400
        repeat: true
        onTriggered: root.refresh()
    }

    Timer {
        id: clearTimer
        onTriggered: {
            // Both outcomes clear: an error that stays forever buries the key hints.
            if (root.statusKind === "ok" || root.statusKind === "error") {
                root.status = "";
                root.statusKind = "";
            }
        }
    }

    Connections {
        target: root.watched
        function onConnectionFailed(reason) { root.onNetworkFailed(reason); }
    }

    Component.onCompleted: root.resolveDevice()

    // The device can appear, disappear or be re-created (radio off/on, iwd restart).
    Timer {
        interval: 1500
        running: true
        repeat: true
        onTriggered: {
            if (!root.wifiDevice)
                root.resolveDevice();
            else
                root.refresh();
        }
    }

    Connections {
        target: Networking.devices
        function onObjectInsertedPost() { root.resolveDevice(); }
    }
}
