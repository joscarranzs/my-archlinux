import QtQuick
import Quickshell
import "@KANBAN@/components"
import "@KANBAN@/services"

// End-to-end harness: the real panel over the real KanbanFeed, which shells out
// to scripts/session/kanban-feed.py and `hermes kanban`. Creates one throwaway
// task, walks it new -> process -> completed -> archived, and checks the status
// the panel ends up showing at every hop.
ShellRoot {
    id: root

    property int pass: 0
    property int fail: 0
    property var step: null
    property string targetId: ""

    QtObject {
        id: holder

        property var pending: null
    }

    KanbanFeed {
        id: feed
    }

    Item {
        width: 1200
        height: 568

        KanbanPanel {
            id: panel

            feed: feed
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

    function task() {
        if (root.targetId === "")
            return null;
        return panel.tasks.find((t) => t.id === root.targetId) || null;
    }

    function waitFor(name, condition, next) {
        holder.pending = { name: name, condition: condition, next: next, since: Date.now() };
        poll.restart();
    }

    function finish() {
        console.log("RESULT pass=" + root.pass + " fail=" + root.fail);
        Qt.quit();
    }

    function start() {
        waitFor("board loaded", () => feed.tasks !== undefined && !feed.busy, create);
    }

    function create() {
        check("board has a task list", Array.isArray(feed.tasks), String(feed.tasks));
        // Created with a category on purpose: the helper has to pin a column the
        // CLI does not know about, on a row it only learns the id of afterwards.
        feed.act(["create", "--json", "Panel e2e", "--category", "C2"]);
        waitFor("task created", () => {
            var hit = feed.tasks.find((t) => t.title === "Panel e2e");
            if (hit)
                root.targetId = hit.id;
            return !!hit;
        }, toProcess);
    }

    function toProcess() {
        check("created as fresh", (root.task() || {}).status === "ready" || (root.task() || {}).status === "todo", JSON.stringify(root.task()));
        check("category survived the create", (root.task() || {}).category === 2, JSON.stringify(root.task()));
        panel.moveTask(root.targetId, "process");
        check("pending painted", panel.pendingId === root.targetId, panel.pendingId);
        waitFor("claimed", () => !feed.busy && (root.task() || {}).status === "running", toReview);
    }

    function toReview() {
        panel.moveTask(root.targetId, "review");
        check("offered for review", panel.statusText.indexOf("IN REVIEW") >= 0, panel.statusText);
        waitFor("in review", () => !feed.busy && (root.task() || {}).status === "review", backToProcess);
    }

    function backToProcess() {
        // The only reverse move: review -> in progress, which the helper does as
        // reopen-review + claim because neither lands in running alone.
        panel.moveTask(root.targetId, "process");
        check("reopen reported", panel.statusText.indexOf("IN PROGRESS") >= 0, panel.statusText);
        waitFor("back in progress", () => !feed.busy && (root.task() || {}).status === "running", toCompleted);
    }

    function toCompleted() {
        panel.moveTask(root.targetId, "completed");
        waitFor("completed", () => !feed.busy && (root.task() || {}).status === "done", toCategorize);
    }

    function toCategorize() {
        feed.act(["categorize", root.targetId, "C4"]);
        waitFor("recategorised", () => !feed.busy && (root.task() || {}).category === 4, toArchive);
    }

    function toArchive() {
        // The panel has no archive destination any more, so the cleanup speaks
        // to the feed directly.
        feed.act(["archive", root.targetId]);
        waitFor("archived", () => !feed.busy && root.task() === null, done);
    }

    function done() {
        check("no action pending", panel.pendingId === "", panel.pendingId);
        check("success message shown", panel.statusTone === "ok", panel.statusText + " / " + panel.statusTone);
        root.finish();
    }

    Timer {
        id: poll

        interval: 120
        repeat: true

        onTriggered: {
            if (!holder.pending)
                return;
            if (holder.pending.condition()) {
                var next = holder.pending.next;
                holder.pending = null;
                poll.stop();
                next();
            } else if (Date.now() - holder.pending.since > 20000) {
                console.log("TIME OUT at " + holder.pending.name);
                root.fail += 1;
                root.finish();
            }
        }
    }

    Timer {
        interval: 300
        running: true
        onTriggered: root.start()
    }
}
