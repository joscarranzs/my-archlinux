import QtQuick
import Quickshell
import "@URL@/components"

// Offscreen harness for the plaque entrance: the fade and the lift are one
// gesture, so both halves are asserted. One panel per run -- run-all.sh renders
// this file once per plaque -- because each panel brings its own services.
//
// The lift is measured twice on purpose. `entranceLift` is the token, and
// `mapToItem` is where the paint actually lands: a transform that is declared
// but not applied would pass the first check and fail the second. (Measured
// against a real grab on 2026-11-23: the plaque's top gilt row sits at 40 px at
// rest and 48 px at the offset, so mapToItem equals the rendered edge.)
ShellRoot {
    id: root

    property int pass: 0
    property int fail: 0
    property var samples: []

    Window {
        width: 600
        height: 700
        visible: true
        color: "transparent"

        Item {
            id: frame

            anchors.fill: parent

            @PANEL@ {
                id: panel

                y: 40
            }
        }
    }

    function check(name, condition, detail) {
        if (condition) {
            root.pass += 1;
            console.log("PASS " + name);
        } else {
            root.fail += 1;
            console.log("FAIL " + name + " :: " + (detail === undefined ? "" : detail));
        }
    }

    // Every legend in the plaque, found by the two properties a LegendRow
    // carries. Its parent is the row that lays it out, and that row knows
    // whether the hints fit the footer: an overflowing row has an implicitWidth
    // wider than the width its anchors gave it, and it paints past the plaque's
    // padding instead of eliding.
    function legends(item, out) {
        if (item.key !== undefined && item.label !== undefined) {
            out.push(item);
        }
        for (let i = 0; i < item.children.length; i += 1) {
            legends(item.children[i], out);
        }
        return out;
    }

    function sample(tag) {
        const lift = panel.entranceLift;
        const top = panel.mapToItem(frame, 0, 0).y;
        root.samples.push(lift);
        console.log("SAMPLE " + tag + " lift=" + lift.toFixed(3) + " top=" + top.toFixed(3));
        return { lift: lift, top: top };
    }

    // Every Text drawn taller than the box it was given. A surface whose text is
    // pinned to a fixed height fits while the type ladder is at rest and clips the
    // moment the desktop's text scale grows: this is the assertion that keeps the
    // scale honest on every plaque, not just on the one it was built for.
    //
    // 1.5 px of slack, measured, not guessed: `implicitHeight` is the font's line
    // box rounded up, and a row that follows its tallest child lands 1 px under it
    // and clips no ink. A real bad box (a 12 px slot holding a 20 px line) misses
    // by 4 and up.
    function overflowing(item, out) {
        if (item.text !== undefined && item.text !== "" && item.height > 0
            && item.height < item.implicitHeight - 1.5) {
            out.push(item.text);
        }
        for (let i = 0; i < item.children.length; i += 1)
            root.overflowing(item.children[i], out);
        return out;
    }

    // First descendant carrying an objectName. Used for the availability state,
    // where the thing under test is a specific node (the number, the knob) and
    // not a property a recursive sweep could find on its own.
    function named(item, name) {
        if (item.objectName === name)
            return item;
        for (let i = 0; i < item.children.length; i += 1) {
            const hit = root.named(item.children[i], name);
            if (hit !== null)
                return hit;
        }
        return null;
    }

    Component.onCompleted: {
        const offset = panel.appearance.motionEntranceOffset;
        const first = root.sample("start");
        root.check("entrance starts at the offset token",
            Math.abs(first.lift - offset) < 0.001, first.lift + " vs " + offset);
        root.check("the lift moves the paint, not just the token",
            Math.abs(first.top - (40 + offset)) < 0.001, first.top);
        root.check("the plaque is transparent on its first frame", panel.opacity === 0);
    }

    Timer {
        interval: 60
        running: true
        onTriggered: {
            const s = root.sample("t60");
            root.check("the lift is under way at 60 ms",
                s.lift < panel.appearance.motionEntranceOffset && s.lift > 0, s.lift);
        }
    }
    Timer {
        interval: 140
        running: true
        onTriggered: {
            const s = root.sample("t140");
            root.check("the lift decelerates", s.lift <= root.samples[1], s.lift);
        }
    }
    Timer {
        interval: 400
        running: true
        onTriggered: {
            const s = root.sample("landed");
            root.check("the plaque lands on zero", s.lift === 0, s.lift);
            root.check("the rendered edge lands at its anchor", s.top === 40, s.top);
            root.check("the fade finished too", panel.opacity === 1, panel.opacity);
            // The legend is centred, so the row is as wide as its content and
            // comparing it to itself proves nothing: it has to fit the plaque's
            // content width, which is what the footer can actually hold.
            const room = panel.width - panel.appearance.contentPad * 2;
            const rows = root.legends(panel, []);
            root.check("the plaque has a legend", rows.length > 0, rows.length);
            for (let i = 0; i < rows.length; i += 1) {
                const row = rows[i].parent;
                root.check("legend " + rows[i].key + " " + rows[i].label + " fits the footer",
                    row.implicitWidth <= room,
                    row.implicitWidth.toFixed(1) + " > " + room.toFixed(1));
                // Horizontal fit is half the promise: the footer also has to stay
                // ON the plaque. A card that grew past the fixed height pushed the
                // whole legend out of the frame, and nothing here looked downward.
                const bottom = row.mapToItem(panel, 0, row.height).y;
                root.check("legend " + rows[i].key + " stays on the plaque",
                    bottom <= panel.height - panel.appearance.borderWidth,
                    bottom.toFixed(1) + " > " + panel.height);
            }
            // --------------------------------------------------- no device
            // `available` is the device hook on the volume and brightness
            // plaques. The battery panel carries a read-only property of the same
            // name about its own charge, so the write is this test's opt-in: a
            // plaque whose level goes inert when the device is gone accepts it.
            // The failure mode being asserted is the one the sweep found by
            // reading: with nothing to move, the plaque kept drawing a live strip
            // and a 0 % that no device ever said, and kept advertising keys that
            // the service silently drops.
            var drivesDevice = false;
            try {
                panel.available = false;
                drivesDevice = panel.available === false;
            } catch (e) {
                drivesDevice = false;
            }
            if (drivesDevice) {
                // Two shapes, one behaviour: a plaque either names the state in
                // its header or in its card's chip. The harness asks whichever it
                // has, so a panel mid-migration is still held to the promise.
                const state = root.named(panel, "chip") || root.named(panel, "stateText");
                const percent = root.named(panel, "percentText");
                const knob = root.named(panel, "sliderKnob");
                const strip = root.named(panel, "levelSlider");
                const advertised = root.legends(panel, []).filter((l) => l.visible);
                root.check("an unavailable plaque names the state in its header or chip",
                    state !== null && state.visible && state.text !== "",
                    state === null ? "no state text" : state.text);
                root.check("an unavailable plaque reports no level, not 0 %",
                    percent !== null && percent.text === "—",
                    percent === null ? "no percent text" : percent.text);
                root.check("an unavailable strip draws no knob",
                    knob !== null && knob.visible === false,
                    knob === null ? "no knob" : knob.visible);
                root.check("an unavailable strip is inert",
                    strip !== null && strip.available === false,
                    strip === null ? "no strip" : strip.available);
                root.check("an unavailable plaque advertises only Esc",
                    advertised.length === 1 && advertised[0].key === "Esc",
                    advertised.length);
                panel.available = true;
            }

            // -------------------------------------------------- text scale
            // The same plaque with the desktop's text a size up. The override is
            // the Appearance review hook, so the user's own preference is never
            // touched by a test run.
            panel.appearance.textScaleOverride = 1.1;
        }
    }

    Timer {
        interval: 650
        running: true
        onTriggered: {
            const scaled = 1.1;
            const bad = root.overflowing(panel, []);
            root.check("no text overflows its box at " + scaled + "×",
                bad.length === 0, JSON.stringify(bad));
            const room = panel.width - panel.appearance.contentPad * 2;
            const rows = root.legends(panel, []);
            for (let i = 0; i < rows.length; i += 1) {
                const row = rows[i].parent;
                root.check("legend " + rows[i].key + " " + rows[i].label
                    + " still fits at " + scaled + "×",
                    row.implicitWidth <= room,
                    row.implicitWidth.toFixed(1) + " > " + room.toFixed(1));
                const bottom = row.mapToItem(panel, 0, row.height).y;
                root.check("legend " + rows[i].key + " " + rows[i].label
                    + " stays on the plaque at " + scaled + "×",
                    bottom <= panel.height - panel.appearance.borderWidth,
                    bottom.toFixed(1) + " > " + panel.height);
            }

            console.log("RESULT pass=" + root.pass + " fail=" + root.fail);
            Qt.quit();
        }
    }
    Timer { interval: 2000; running: true; onTriggered: Qt.quit() }
}
