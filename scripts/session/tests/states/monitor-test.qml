import QtQuick
import Quickshell
import "@URL@/monitor/components"

// Empty and error, forced: no external output, a refused write, and the laptop's
// two controls.
//
// The panel takes its state as an injected object (MonitorPanel.state), so this
// hands it a stub with the same shape as the MonitorState singleton. Nothing
// polls, nothing writes to Hyprland, and each state is reachable on demand --
// which is exactly what "never forced" used to mean.
//
// The laptop card is the one card that is always there, so its contract is
// asserted here too: the ring lands on it first, it offers a compositor scale
// and a text size, and applying it asks for the LIVE mode -- the mode the user is
// reading -- with only the scale changed.
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

    // The empty line predates objectNames; it is found by what it says.
    function byText(item, text, found) {
        if (item.text !== undefined && item.text === text)
            found.push(item);
        for (let i = 0; i < item.children.length; i += 1)
            root.byText(item.children[i], text, found);
        return found;
    }

    QtObject {
        id: stubState

        property var monitors: []
        property var internal: ({
            name: "eDP-1",
            description: "BOE 0x0BCA",
            width: 1920,
            height: 1080,
            refresh: 60,
            // Off the rule's 1.5 on purpose: RESET has something to restore.
            scale: 1.25,
            x: 0,
            y: 0,
            disabled: false,
            internal: true,
            modes: [],
        })
        property var externals: []
        property bool ready: true
        property string status: ""
        property string statusKind: ""
        // Every write the panel attempts, in order: the assertion is about what
        // was asked for, not about whether the compositor obeyed.
        property var calls: []

        function apply(name, w, h, rate, scale) {
            stubState.calls = stubState.calls.concat(
                [{ name: name, w: w, h: h, rate: rate, scale: scale }]);
            stubState.status = "applied · " + name;
            stubState.statusKind = "ok";
        }
        function scaleOptions(monitor) { return [1, 1.25, 1.5, 1.75, 2] }
        function scaleLabel(scale) { return scale + "×" }
        function scaleIndexOf(monitor, scale) {
            return stubState.scaleOptions(monitor).indexOf(scale);
        }
        function resolutions(monitor) { return [] }
        function rateLabel(rate) { return String(rate) }
        function modeIndexOf(monitor, w, h) { return 0 }
        function isInternalName(name) { return true }
        function find(name) { return stubState.internal }
        // What monitors.lua declares for this output.
        function originalScale(name) { return 1.5 }
    }

    // The text preference, as the panel sees it: steps to offer, a status slot,
    // and one write used by the laptop card's second control.
    QtObject {
        id: stubText

        property var steps: [0.9, 1, 1.1, 1.25, 1.4]
        property string status: ""
        property string statusKind: ""
        property var calls: []

        function apply(scale) {
            stubText.calls = stubText.calls.concat([scale]);
            stubText.status = "text " + Math.round(scale * 100) + " %";
            stubText.statusKind = "ok";
        }
    }

    Window {
        width: 460
        height: 620
        visible: true

        MonitorPanel {
            id: panel
            anchors.centerIn: parent
            state: stubState
            textScaleState: stubText
        }
    }

    Timer {
        interval: 400
        running: true
        onTriggered: {
            const empty = root.byText(panel, "no external monitor connected", []);
            root.check("an empty monitor list says so", empty.length === 1, empty.length);
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
            stubState.status = "eDP-1: mode refused by the compositor";
            stubState.statusKind = "error";
        }
    }

    Timer {
        interval: 700
        running: true
        onTriggered: {
            const line = root.byText(panel,
                "eDP-1: mode refused by the compositor", []);
            root.check("a refused write is reported in the footer", line.length === 1,
                line.length);
            if (line.length === 1) {
                root.check("an error status takes the alert ink",
                    Qt.colorEqual(line[0].color, panel.appearance.danger),
                    line[0].color);
            }
        }
    }

    Timer {
        interval: 850
        running: true
        onTriggered: {
            stubState.status = "";
            stubState.statusKind = "";

            const card = panel.cardAt(0);
            root.check("the laptop is the first card in the ring",
                card !== null && card.monitor !== null
                && card.monitor.name === "eDP-1",
                card === null ? "no card" : card.title);
            root.check("the laptop card starts clean", card !== null && !card.dirty);

            // The ring reaches it, and its first control opens the scale list.
            panel.focusCard = 0;
            panel.focusControl = 0;
            panel.activate();
            root.check("the ring opens the laptop's scale",
                panel.activeField !== null
                && panel.activeField === card.scaleField,
                panel.activeField === null ? "no menu" : "wrong field");
            panel.closeAllLists();

            root.check("the laptop offers a compositor scale",
                card.scaleOptions.length > 1, card.scaleOptions.length);
            root.check("the laptop offers a text size",
                card.textOptions.length === stubText.steps.length,
                card.textOptions.length);
            root.check("the text field marks the size in force",
                Math.abs(card.textScale - panel.appearance.textScale) < 0.001
                && card.effectiveTextIndex >= 0,
                card.textScale + " vs " + panel.appearance.textScale);

            // One pick of each, then Apply.
            card.scalePick = card.scaleOptions.length - 1;
            card.textPick = 0;
            root.check("a pick makes the laptop card dirty", card.dirty);

            panel.applyLaptop();
            const call = stubState.calls.length === 1 ? stubState.calls[0] : null;
            root.check("the scale write keeps the live mode",
                call !== null && call.name === "eDP-1"
                && call.w === 1920 && call.h === 1080 && call.rate === 60
                && Math.abs(call.scale - 2) < 0.001,
                JSON.stringify(stubState.calls));
            root.check("the text size goes through the preference",
                stubText.calls.length === 1 && stubText.calls[0] === 0.9,
                JSON.stringify(stubText.calls));

            // ------------------------------------------------------------- reset
            root.check("the ring gives the laptop a fourth control",
                card.controlCount === 4, card.controlCount);

            // The desktop wearing a bigger text size, as a live one: the override
            // is the Appearance review hook, so the state file is never touched.
            panel.appearance.textScaleOverride = 1.25;
            root.check("the text field follows the size in force",
                Math.abs(card.textScale - 1.25) < 0.001, card.textScale);
            root.check("reset is offered while the live state is off the rule",
                card.canReset && Math.abs(card.originalScale - 1.5) < 0.001,
                card.originalScale);

            panel.resetLaptop();
            const restored = stubState.calls.length === 2 ? stubState.calls[1] : null;
            root.check("reset asks the rule's scale, keeping the live mode",
                restored !== null && restored.w === 1920 && restored.h === 1080
                && Math.abs(restored.scale - 1.5) < 0.001,
                JSON.stringify(stubState.calls));
            root.check("reset puts the text size back to the theme's own",
                stubText.calls.length === 2 && stubText.calls[1] === 1,
                JSON.stringify(stubText.calls));

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
