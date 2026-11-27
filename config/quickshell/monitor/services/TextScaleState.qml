pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// The desktop's text scale: the one preference every surface reads.
//
// Sizes stay tokens (theme/typography.json), but the multiplier that grows or
// shrinks them is a runtime preference, because tuning it by regenerating the
// theme would dirty forty generated files per step and take a rebuild to see.
// Each Appearance watches the state file directly, so this object only has to
// write it and say what happened; it never holds a second copy of the value.
Singleton {
    id: root

    // The steps the panel offers, and the whole range on purpose: 0.9-1.1 is what
    // the panels were measured clean at. 1.25 was tried and two rows hand their
    // text 15 px where a 14 px mono wants 19 (the tokens' ctx line and the wifi
    // footer legend), so the next step up needs those rows fixed first, not a
    // bigger list here.
    readonly property var steps: [0.9, 1, 1.1]

    readonly property var options: {
        const out = [];
        for (let i = 0; i < root.steps.length; i++)
            out.push({ label: root.label(root.steps[i]), value: root.steps[i] });
        return out;
    }

    property string status: ""
    property string statusKind: ""

    function label(step) {
        return Math.round(step * 100) + " %";
    }

    // The option index for a live value. A scale the steps do not list (set by
    // hand in the state file) lands on the nearest step rather than on 100 %,
    // which would misreport what the desktop is currently wearing.
    function indexOf(scale) {
        let best = 0;
        let distance = Infinity;
        for (let i = 0; i < root.steps.length; i++) {
            const d = Math.abs(root.steps[i] - scale);
            if (d < distance) {
                distance = d;
                best = i;
            }
        }
        return best;
    }

    function apply(scale) {
        writer.running = false;
        writer.command = [Quickshell.env("HOME") + "/.scripts/session/text-scale.sh",
                          String(scale)];
        writer.running = true;
    }

    // The writer verifies its own write (it reads the file back), so a zero exit
    // with a value on stdout is the proof, not an assumption.
    Process {
        id: writer

        stdout: StdioCollector {}
        stderr: StdioCollector {}

        onExited: (code) => {
            const answer = String(writer.stdout.text || "").trim();
            if (code !== 0) {
                const detail = String(writer.stderr.text || "").trim()
                    .replace(/^text-scale:\s*/, "");
                root.setStatus("error", detail !== "" ? detail : "text scale was not written");
                return;
            }
            if (answer === "") {
                root.setStatus("error", "text scale was not written");
                return;
            }
            root.setStatus("ok", "text " + root.label(parseFloat(answer)));
        }
    }

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
