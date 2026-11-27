pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import ".."

// Wallet drawdown, as the bar sees it.
//
// The bar is the only alert channel that is up when no plaque is: every panel is
// one process per open, so a threshold the plaque paints gold has to be visible
// here. This singleton runs the same helper the panel runs and never touches the
// network itself, on a slower timer than the panel's 60 s: a number that moves in
// minutes does not need a request a minute, and the helper's cache plus its lock
// keep the two consumers from doubling it.
//
// The colour recipe is the panel's own, token for token: muted below the
// threshold, accent at it, danger above the critical one.
Singleton {
    id: root

    // Only for the thresholds handed to the helper, so its own notifications and
    // these colours cannot disagree. Geometry comes from the bar's Appearance.
    readonly property Appearance look: Appearance {}

    property var data: ({})

    readonly property var block: data.nous || ({})

    // A stale or failed reading paints nothing: the previous numbers are still
    // in the cache, but an alert has to be about a number that is true now.
    readonly property bool nousOk: block.ok === true && block.stale !== true

    // Spend percent of the bought wallet: 0 % is a full balance, 100 % is
    // empty. Computed from the wallet drawdown the helper reports, not from
    // the portal's member_spend_usd, which under-counts (see _wallet_spend).
    readonly property real spendPercent: {
        var spent = Number(root.block.spent_usd);
        var purchased = Number(root.block.purchased_usd);
        if (!isFinite(spent) || !isFinite(purchased) || purchased <= 0)
            return -1;
        return spent / purchased * 100;
    }

    // Thresholds are consumed-spend percent on the same 0-100 scale as the old
    // OpenCode Go windows, so the two panels stay on one scale and the same
    // numbers drive both.
    readonly property string level: !root.nousOk || root.spendPercent < 0 ? ""
        : (root.spendPercent >= root.look.tokensCriticalThreshold ? "critical"
            : (root.spendPercent >= root.look.tokensAlertThreshold ? "alert" : ""))
    readonly property color glyphColor: root.level === "critical" ? root.look.danger
        : (root.level === "alert" ? root.look.accentInk : root.look.textMuted)

    function refresh() {
        if (!proc.running)
            proc.running = true;
    }

    Component.onCompleted: refresh()

    Timer {
        interval: 300000
        running: true
        repeat: true
        onTriggered: root.refresh()
    }

    Process {
        id: proc

        command: [
            "/usr/bin/python3",
            Quickshell.env("HOME") + "/.scripts/session/tokens.py",
            "--alert", String(root.look.tokensAlertThreshold),
            "--critical", String(root.look.tokensCriticalThreshold),
        ]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    var parsed = JSON.parse(text);
                    if (parsed && typeof parsed === "object")
                        root.data = parsed;
                } catch (error) {
                    // Keep the previous snapshot: a helper that broke mid-flight
                    // must not reset the bar to "everything is fine".
                }
            }
        }
    }
}
