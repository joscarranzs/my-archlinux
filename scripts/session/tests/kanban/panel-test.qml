import QtQuick
import Quickshell
import "@KANBAN@/components"

// Offscreen harness for the kanban panel: drives the real component with a fake
// feed and asserts the drop resolution, the move matrix and the action path.
ShellRoot {
    id: root

    property int pass: 0
    property int fail: 0

    QtObject {
        id: fake

        property var tasks: [
            { id: "t_new", title: "New one", body: "", status: "ready", priority: 0 },
            { id: "t_park", title: "Parked one", body: "x", status: "scheduled", priority: 1 },
            { id: "t_run", title: "Running one", body: "", status: "running", priority: 0 },
            { id: "t_block", title: "Blocked one", body: "", status: "blocked", priority: 2 },
            { id: "t_rev", title: "Reviewable one", body: "", status: "review", priority: 1 },
            { id: "t_done", title: "Done one", body: "", status: "done", priority: 0 }
        ]
        property string error: ""
        property bool busy: false
        property bool parsingFailed: false
        property var calls: []

        signal refreshed()
        signal actionDone(bool ok, string error, string verb)

        function refresh() {}
        function act(args) {
            calls = calls.concat([args]);
            // Answer like the real helper does. Synchronous on purpose: the
            // asserts run in the same turn, and a delayed reply would only be
            // testing the event loop.
            fake.actionDone(true, "", (args && args[0]) || "");
        }
    }

    Item {
        width: 1200
        height: 568

        KanbanPanel {
            id: panel

            feed: fake
        }

        // One card with both axes set, outside the board: the badge and the
        // rank are card-level facts, asserted on a card no lane filter can hide.
        KanbanCard {
            objectName: "probe-card"
            width: 300
            appearance: panel.appearance
            panel: panel
            task: ({ id: "probe", title: "Probe", status: "ready", category: 3, priority: 2 })
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

    function find(node, name) {
        if (!node)
            return null;
        if (node.objectName === name)
            return node;
        var kids = node.children || [];
        for (var i = 0; i < kids.length; i++) {
            var hit = root.find(kids[i], name);
            if (hit)
                return hit;
        }
        return null;
    }

    // How many items carry this objectName: some rules are "one per lane", and
    // find() only ever answers the first.
    function count(node, name) {
        if (!node)
            return 0;
        var total = node.objectName === name ? 1 : 0;
        var kids = node.children || [];
        for (var i = 0; i < kids.length; i++)
            total += root.count(kids[i], name);
        return total;
    }

    function target(name) {
        for (var i = 0; i < panel.dropTargets.length; i++) {
            if (panel.dropTargets[i].dest === name)
                return panel.dropTargets[i].item;
        }
        return null;
    }

    function centre(name) {
        var item = root.target(name);
        if (!item)
            return { x: -1, y: -1 };
        var p = item.mapToItem(panel, item.width / 2, item.height / 2);
        return { x: p.x, y: p.y };
    }

    // Offscreen has no polish pass, so the Row of columns never positions its
    // children. Give the three sections the geometry the live layout produces
    // (373 wide, 16 gap, contentPad 24) before asserting anything.
    function place() {
        var names = ["new", "process", "review", "completed"];
        for (var i = 0; i < names.length; i++) {
            var item = root.target(names[i]);
            var rowOrigin = item.parent.mapToItem(panel, 0, 0);
            item.x = 24 + i * (286 + 16) - rowOrigin.x;
            item.y = 245 - rowOrigin.y;
            item.width = 286;
            item.height = 337;
        }
    }

    function run() {
        root.place();
        for (var d = 0; d < panel.dropTargets.length; d++) {
            var e = panel.dropTargets[d];
            var o = e.item.mapToItem(panel, 0, 0);
            console.log("TARGET " + e.dest + " x=" + o.x.toFixed(1) + " y=" + o.y.toFixed(1)
                + " w=" + e.item.width + " h=" + e.item.height
                + " name=" + e.item.objectName + " panelw=" + panel.width + " roww=" + panel.dropTargets[0].item.parent.width);
        }
        // --- registration
        root.check("four drop targets", panel.dropTargets.length === 4, String(panel.dropTargets.length));

        // --- the creator's limits, read off the fields themselves
        var titleField = root.find(panel, "task-title-field");
        var descField = root.find(panel, "task-desc-field");
        root.check("creator fields exist", titleField !== null && descField !== null);
        if (titleField && descField) {
            root.check("title caps at panel.titleLimit", titleField.maximumLength === panel.titleLimit, titleField.maximumLength);
            root.check("description caps at panel.descriptionLimit", descField.maximumLength === panel.descriptionLimit, descField.maximumLength);
            root.check("the placeholder states the title limit",
                titleField.placeholderText.indexOf(String(panel.titleLimit)) >= 0, titleField.placeholderText);
            root.check("the placeholder states the description limit",
                descField.placeholderText.indexOf(String(panel.descriptionLimit)) >= 0, descField.placeholderText);
            // The counters used to be a second hardcoded number in the same row,
            // so they went negative while the field still accepted text. They
            // must count down from the same limit the field enforces.
            var titleCounter = root.find(panel, "task-title-counter");
            var descCounter = root.find(panel, "task-desc-counter");
            var near = "";
            for (var n = 1; n < panel.titleLimit; n++)
                near += "x";
            var nearDesc = "";
            for (var d = 1; d < panel.descriptionLimit; d++)
                nearDesc += "y";
            titleField.text = near;
            descField.text = nearDesc;
            root.check("title counter counts down from the limit",
                titleCounter !== null && titleCounter.text === "1", titleCounter ? titleCounter.text : "missing");
            root.check("description counter counts down from the limit",
                descCounter !== null && descCounter.text === "1", descCounter ? descCounter.text : "missing");
            titleField.text = "";
            descField.text = "";
        }

        // --- geometry
        var names = ["new", "process", "review", "completed"];
        for (var i = 0; i < names.length; i++) {
            var c = root.centre(names[i]);
            root.check("destAt " + names[i], panel.destAt(c.x, c.y) === names[i], "got " + panel.destAt(c.x, c.y) + " at " + c.x + "," + c.y);
        }
        root.check("destAt outside", panel.destAt(-50, -50) === "", String(panel.destAt(-50, -50)));

        // --- move matrix against the backend contract
        var matrix = [
            // ready: into the work, or straight to done; review needs work first
            ["ready", "new", false], ["ready", "process", true], ["ready", "review", false], ["ready", "completed", true],
            // running: can be offered for review or closed
            ["running", "new", false], ["running", "process", false], ["running", "review", true], ["running", "completed", true],
            // review: the one way back is to the work; it can also be closed
            ["review", "new", false], ["review", "process", true], ["review", "review", false], ["review", "completed", true],
            ["blocked", "new", true], ["blocked", "process", false], ["blocked", "review", false], ["blocked", "completed", true],
            ["scheduled", "new", true], ["scheduled", "process", false], ["scheduled", "review", false], ["scheduled", "completed", false],
            ["done", "new", false], ["done", "process", false], ["done", "review", false], ["done", "completed", false]
        ];
        for (var m = 0; m < matrix.length; m++) {
            var row = matrix[m];
            var task = { id: "x", status: row[0] };
            var got = panel.canMove(task, row[1]);
            root.check("matrix " + row[0] + "->" + row[1], got === row[2], "got " + got);
        }

        // --- drag that should work: NEW -> PROCESS
        var card = root.find(panel, "kanban-card-t_new");
        root.check("card found", card !== null);
        if (card) {
            var proc = root.centre("process");
            fake.calls = [];
            panel.beginDrag(card);
            root.check("drag armed", card.dragging === true && panel.dragCard === card);
            panel.updateDrag(proc);
            root.check("drop target resolved", panel.dropTarget === "process", panel.dropTarget);
            root.check("column lit", root.find(panel, "kanban-section-process").dropHot === true);
            // The chip is confined to the board band, never over the header.
            panel.updateDrag({ x: -400, y: -400 });
            var g = root.find(panel, "kanban-ghost");
            var b = panel.dragBounds();
            root.check("ghost clamped to the board", g.x >= b.x && g.y >= b.y,
                "ghost " + g.x + "," + g.y + " band " + b.x + "," + b.y);
            panel.updateDrag(proc);
            panel.finishDrag();
            root.check("drag released", card.dragging === false && panel.dragCard === null);
            // The move carries the panel's own lease length: the backend default
            // is 900 s and nothing heartbeats a claim made from here, so the task
            // came back to NEW fifteen minutes after the drag.
            root.check("claim sent with the panel's ttl",
                fake.calls.length === 1 && fake.calls[0][0] === "claim"
                && fake.calls[0][1] === "t_new"
                && fake.calls[0].indexOf("--ttl") === 2
                && fake.calls[0][3] === String(panel.claimTtlSeconds),
                JSON.stringify(fake.calls));
            root.check("success message", panel.statusTone === "ok" && panel.statusText.indexOf("IN PROGRESS") >= 0, panel.statusText);
        }

        // --- drag that should be refused: DONE -> NEW
        var doneCard = root.find(panel, "kanban-card-t_done");
        if (doneCard) {
            var fresh = root.centre("new");
            fake.calls = [];
            panel.beginDrag(doneCard);
            panel.updateDrag(fresh);
            root.check("refused target is empty", panel.dropTarget === "", panel.dropTarget);
            root.check("refused column is cold", root.find(panel, "kanban-section-new").dropCold === true);
            panel.finishDrag();
            root.check("no action on refusal", fake.calls.length === 0, JSON.stringify(fake.calls));
            root.check("refusal explained", panel.statusTone === "error", panel.statusText + " / " + panel.statusTone);
        }

        // --- drag back to the lane the card already lives in: not a refusal.
        // t_new is status "ready" and ready lives in NEW, so releasing it there
        // changes nothing — and only parked work can "move to NEW" (the unblock),
        // which is what made this report a move that cannot happen.
        var readyCard = root.find(panel, "kanban-card-t_new");
        if (readyCard) {
            var home = root.centre("new");
            fake.calls = [];
            panel.beginDrag(readyCard);
            panel.updateDrag(home);
            root.check("same lane is no target", panel.dropTarget === "" && panel.dropSame === "new",
                panel.dropTarget + " / " + panel.dropSame);
            var newSection = root.find(panel, "kanban-section-new");
            root.check("same lane is not cold", newSection.dropCold === false);
            root.check("same lane is warm", newSection.dropSame === true);
            panel.finishDrag();
            root.check("same lane sends nothing", fake.calls.length === 0, JSON.stringify(fake.calls));
            root.check("same lane explained", panel.statusTone === "warn"
                && panel.statusText.indexOf("Nothing moved") >= 0, panel.statusText + " / " + panel.statusTone);
        }

        // The fix must not swallow a real action: a parked card in the same lane
        // is the unblock, so it stays a move.
        var parkedCard = root.find(panel, "kanban-card-t_park");
        if (parkedCard) {
            fake.calls = [];
            panel.beginDrag(parkedCard);
            panel.updateDrag(root.centre("new"));
            root.check("parked same lane is a move", panel.dropTarget === "new" && panel.dropSame === "",
                panel.dropTarget + " / " + panel.dropSame);
            panel.finishDrag();
            root.check("unblock sent", fake.calls.length === 1 && fake.calls[0][0] === "unblock"
                && fake.calls[0][1] === "t_park", JSON.stringify(fake.calls));
        }

        // --- review is a lane of its own, with exactly one way back
        fake.calls = [];
        panel.moveTask("t_run", "review");
        root.check("running offers itself for review",
            fake.calls.length === 1 && fake.calls[0][0] === "request-review"
            && fake.calls[0][1] === "t_run", JSON.stringify(fake.calls));
        fake.calls = [];
        panel.moveTask("t_rev", "process");
        root.check("review returns to progress as one reopen act",
            fake.calls.length === 1 && fake.calls[0][0] === "reopen"
            && fake.calls[0][1] === "t_rev", JSON.stringify(fake.calls));
        root.check("a reviewed card is drawn in its own lane",
            root.find(panel, "kanban-card-t_rev") !== null
            && panel.inReview().length === 1, String(panel.inReview().length));
        root.check("review is not part of progress", panel.active().length === 2, String(panel.active().length));

        // --- the one move the backend refuses without evidence
        fake.calls = [];
        panel.moveTask("t_run", "completed");
        root.check("complete sent", fake.calls.length === 1 && fake.calls[0][0] === "complete", JSON.stringify(fake.calls));
        root.check("complete carries a result", fake.calls[0].indexOf("--result") > 0, JSON.stringify(fake.calls[0]));

        // --- editing
        fake.calls = [];
        panel.editTitle("t_new", "Renamed");
        root.check("edit sent", fake.calls[0][0] === "edit" && fake.calls[0][1] === "--title", JSON.stringify(fake.calls));

        // Editing belongs to TO DO and nothing else: the four statuses that lane
        // holds stay editable, the ones that already moved on do not.
        var editable = ["triage", "todo", "scheduled", "ready"];
        var lockedStatuses = ["running", "blocked", "review", "done"];
        var allEditable = true;
        for (var es = 0; es < editable.length; es++)
            allEditable = allEditable && panel.canEdit({ id: "x", status: editable[es] });
        root.check("every TO DO status is editable", allEditable, JSON.stringify(editable));
        var allLocked = true;
        for (var ls = 0; ls < lockedStatuses.length; ls++)
            allLocked = allLocked && !panel.canEdit({ id: "x", status: lockedStatuses[ls] });
        root.check("progress, review and done are read-only", allLocked, JSON.stringify(lockedStatuses));
        root.check("no task is not editable", panel.canEdit(null) === false);

        // A double click on a locked sheet opens no field and says why.
        var hint = root.find(panel, "kanban-preview-hint");
        fake.calls = [];
        panel.previewId = "t_run";
        panel.beginFieldEdit("title");
        root.check("locked sheet opens no field", panel.editingField === "", panel.editingField);
        root.check("locked sheet explains itself", panel.statusTone === "warn"
            && panel.statusText.indexOf("read-only") >= 0, panel.statusText + " / " + panel.statusTone);
        root.check("locked sheet sends nothing", fake.calls.length === 0, JSON.stringify(fake.calls));
        root.check("locked hint says read only", hint !== null && hint.text.indexOf("Read only") >= 0,
            hint ? hint.text : "missing");

        // A task can leave TO DO while its field is open (the dispatcher does
        // exactly that), so the commit refuses as well instead of trusting the
        // state that allowed the double click.
        panel.previewId = "t_rev";
        panel.commitTitle("Rewritten");
        panel.commitBody("Rewritten body");
        root.check("commit on a locked task sends nothing", fake.calls.length === 0, JSON.stringify(fake.calls));
        panel.previewId = "t_new";
        root.check("open hint offers the edit", hint !== null && hint.text.indexOf("Double click") >= 0,
            hint ? hint.text : "missing");
        fake.calls = [];
        panel.commitTitle("Renamed again");
        root.check("commit on an open task still sends", fake.calls.length === 1
            && fake.calls[0][0] === "edit", JSON.stringify(fake.calls));
        panel.previewId = "";

        // --- the action feedback answers in the header's right corner
        var status = root.find(panel, "kanban-status");
        var subtitle = root.find(panel, "task-header-subtitle");
        root.check("the status line exists", status !== null);
        root.check("the status line lives in the header",
            status !== null && subtitle !== null && status.parent === subtitle.parent.parent,
            status ? status.parent.objectName : "missing");
        root.check("the status line is right-aligned", status !== null && status.horizontalAlignment === Text.AlignRight,
            status ? String(status.horizontalAlignment) : "missing");
        root.check("the status line elides instead of growing",
            status !== null && status.elide === Text.ElideRight && status.maximumLineCount === 1,
            status ? String(status.elide) : "missing");
        var headerTop = root.target("new").mapToItem(panel, 0, 0).y;
        root.check("the status line sits above the board", status !== null
            && status.mapToItem(panel, 0, 0).y < headerTop,
            status ? status.mapToItem(panel, 0, 0).y + " vs " + headerTop : "missing");
        var longNote = "A refused drop on a task that already sits in IN PROGRESS says exactly this";
        panel.report(longNote, "warn");
        root.check("the status line paints the message", status !== null && status.text === longNote, status ? status.text : "missing");
        root.check("a long message keeps the warn ink", status !== null
            && String(status.color) === String(panel.appearance.warn), status ? String(status.color) : "missing");
        panel.report("", "info");

        // --- a click outside the sheet closes it, over the lanes too
        root.check("every lane carries a dismiss area", count(panel, "section-dismiss") === 4,
            String(count(panel, "section-dismiss")));
        root.check("the blocked band carries one as well", root.find(panel, "section-extra-dismiss") !== null);
        var lane = root.find(panel, "kanban-section-new");
        panel.requestPreview("t_new");
        root.check("the sheet is open before the click", panel.previewId === "t_new", panel.previewId);
        lane.dismissPreview();
        root.check("a lane click closes the sheet", panel.previewId === "", panel.previewId);

        // --- deletion is a two-step: the card asks, the dialog archives
        var delCard = root.find(panel, "kanban-card-t_new");
        fake.calls = [];
        if (delCard)
            delCard.deleteRequested("t_new");
        root.check("trash opens the dialog", panel.deleteId === "t_new", panel.deleteId);
        root.check("dialog names the task", panel.deleteTitle === "New one", panel.deleteTitle);
        root.check("trash alone sends nothing", fake.calls.length === 0, JSON.stringify(fake.calls));
        root.check("dialog is on screen", root.find(panel, "kanban-delete-dialog").visible === true);

        panel.cancelDelete();
        root.check("cancel sends nothing", fake.calls.length === 0 && panel.deleteId === "", JSON.stringify(fake.calls));
        root.check("cancel closes the dialog", root.find(panel, "kanban-delete-dialog").visible === false);

        panel.requestDelete("t_new");
        panel.confirmDelete();
        root.check("archive sent", fake.calls.length === 1 && fake.calls[0][0] === "archive"
            && fake.calls[0][1] === "t_new", JSON.stringify(fake.calls));
        root.check("archive closes the dialog", panel.deleteId === "", panel.deleteId);
        root.check("archive reported", panel.statusTone === "ok" && panel.statusText.indexOf("Archived") >= 0,
            panel.statusText + " / " + panel.statusTone);

        // A confirm with no dialog open must stay inert: pendingId alone must
        // never be enough to archive something.
        fake.calls = [];
        panel.confirmDelete();
        root.check("confirm without dialog is inert", fake.calls.length === 0, JSON.stringify(fake.calls));

        panel.requestDelete("t_nope");
        root.check("unknown task refused", panel.deleteId === "" && panel.statusTone === "warn",
            panel.deleteId + " / " + panel.statusText);

        // --- creator guards
        panel.statusText = "";
        panel.createTask();
        root.check("empty title refused", panel.statusText === "Type a title first", panel.statusText);

        // --- drag cancel leaves no action
        fake.calls = [];
        panel.beginDrag(card);
        panel.updateDrag(root.centre("completed"));
        panel.cancelDrag();
        root.check("cancel sends nothing", fake.calls.length === 0, JSON.stringify(fake.calls));
        root.check("cancel hides ghost", panel.statusText === "Type a title first", panel.statusText);

        // --- category axis: creator chips, the badge, and the lane order
        var catChips = [1, 2, 3, 4].map((n) => root.find(panel, "category-chip-" + n));
        root.check("creator draws four category chips", catChips.every((c) => c !== null),
            JSON.stringify(catChips.map((c) => !!c)));
        root.check("nothing is selected by default", panel.newCategory === 0, String(panel.newCategory));
        root.check("a category has no label at C0", panel.categoryLabel(0) === "", panel.categoryLabel(0));
        root.check("a category gains its name in the label",
            panel.categoryLabel(1) === "C1-URGENT" && panel.categoryLabel(4) === "C4-OPTIONAL",
            panel.categoryLabel(1) + " / " + panel.categoryLabel(4));
        root.check("the card body is a step under the shared body",
            panel.appearance.cardFontSize < panel.appearance.fontSizeBody,
            panel.appearance.cardFontSize + " vs " + panel.appearance.fontSizeBody);
        if (catChips[1]) {
            catChips[1].activated();
            root.check("clicking a chip selects it", panel.newCategory === 2, String(panel.newCategory));
            root.check("the chosen chip spells itself out",
                catChips[1].label === "C2-IMPORTANT", catChips[1].label);
            root.check("the other chips stay short",
                catChips[0].label === "" && catChips[2].label === "",
                catChips[0].label + " / " + catChips[2].label);
            root.check("the selected chip fills", catChips[1].selected === true && catChips[0].selected === false);
            catChips[1].activated();
            root.check("clicking the selected chip clears it", panel.newCategory === 0, String(panel.newCategory));
        }

        // A creation must carry the category out to the helper, and must not
        // send the flag when nothing is selected: C0 is "unclassified", not a
        // category the backend would know.
        var titleForCreate = root.find(panel, "task-title-field");
        fake.calls = [];
        titleForCreate.text = "Categorised";
        panel.newCategory = 3;
        panel.createTask();
        root.check("create carries the category",
            fake.calls.length === 1 && fake.calls[0].indexOf("--category") > 0
            && fake.calls[0][fake.calls[0].indexOf("--category") + 1] === "C3",
            JSON.stringify(fake.calls));
        fake.calls = [];
        panel.newCategory = 0;
        // The first create cleared the field (that is the creator's contract),
        // so the second one needs a title again.
        titleForCreate.text = "Uncategorised";
        panel.createTask();
        root.check("unclassified create sends no category",
            fake.calls.length === 1 && fake.calls[0].indexOf("--category") === -1,
            JSON.stringify(fake.calls));
        titleForCreate.text = "";

        // --- priority rank: two steps and a number, never out of range
        root.check("rank starts at none", panel.newPriority === 0, String(panel.newPriority));
        panel.stepPriority(-1);
        root.check("rank cannot go below none", panel.newPriority === 0, String(panel.newPriority));
        for (var step = 0; step < 12; step++)
            panel.stepPriority(1);
        root.check("rank stops at 9", panel.newPriority === 9, String(panel.newPriority));
        var rankValue = root.find(panel, "task-priority-value");
        root.check("the composer shows the rank", rankValue !== null && rankValue.text === "9",
            rankValue ? rankValue.text : "missing");
        root.check("the down step exists", root.find(panel, "task-priority-down") !== null);
        root.check("the up step exists", root.find(panel, "task-priority-up") !== null);

        fake.calls = [];
        panel.newCategory = 2;
        titleForCreate.text = "Ranked";
        panel.createTask();
        root.check("create carries the rank",
            fake.calls.length === 1 && fake.calls[0].indexOf("--priority") > 0
            && fake.calls[0][fake.calls[0].indexOf("--priority") + 1] === "9",
            JSON.stringify(fake.calls));
        panel.newPriority = 0;
        fake.calls = [];
        titleForCreate.text = "Unranked";
        panel.createTask();
        root.check("an unranked create sends no rank",
            fake.calls.length === 1 && fake.calls[0].indexOf("--priority") === -1,
            JSON.stringify(fake.calls));
        titleForCreate.text = "";
        panel.newCategory = 0;

        // Category outranks priority: a C1 P5 is worked before a C2 P1, an
        // unclassified task sinks below every classified one, and inside a
        // category the rank decides. This is the rule the backend does not
        // have, so it lives here and is asserted here.
        var mix = [
            { id: "a", title: "A", category: 2, priority: 1 },
            { id: "b", title: "B", category: 1, priority: 5 },
            { id: "c", title: "C", category: 0, priority: 1 },
            { id: "d", title: "D", category: 1, priority: 1 },
            { id: "e", title: "E", category: 4, priority: 0 }
        ];
        var sorted = panel.ordered(mix).map((t) => t.id).join("");
        root.check("lane order is category then priority then unclassified", sorted === "dbaec", sorted);

        // The badge itself: a card with a category paints C<n>, and the rank
        // stays a separate mark.
        var probe = root.find(panel, "probe-card");
        if (probe) {
            var badge = root.find(probe, "category-chip-3");
            var rank = root.find(probe, "card-priority");
            root.check("card paints its category", badge !== null && badge.visible === true);
            root.check("card badge carries the name", badge !== null && badge.label === "C3-NECESSARY",
                badge ? badge.label : "missing");
            root.check("card paints its priority", rank !== null && rank.text === "P2", rank ? rank.text : "missing");
        }

        // The preview sheet: one click shows the task in full, and the sheet
        // reads the live row instead of a snapshot, so what it paints is what
        // the board holds.
        panel.requestPreview("t_new");
        root.check("click opens the preview", panel.previewId === "t_new" && panel.previewTask !== null,
            panel.previewId);
        var sheet = root.find(panel, "kanban-preview");
        root.check("preview is on screen", sheet !== null && sheet.visible === true);
        var sheetTitle = root.find(panel, "kanban-preview-title");
        root.check("preview paints the full title", sheetTitle !== null && sheetTitle.text === "New one",
            sheetTitle ? sheetTitle.text : "missing");
        var sheetBody = root.find(panel, "kanban-preview-body");
        root.check("a task with no body says so", sheetBody !== null && sheetBody.text === "No description.",
            sheetBody ? sheetBody.text : "missing");
        var sheetStatus = root.find(panel, "kanban-preview-status");
        root.check("preview names the lane", sheetStatus !== null && sheetStatus.text === "READY",
            sheetStatus ? sheetStatus.text : "missing");
        var sheetId = root.find(panel, "kanban-preview-id");
        root.check("preview carries the CLI handle", sheetId !== null && sheetId.text === "t_new",
            sheetId ? sheetId.text : "missing");

        // The sheet must never own the whole board: it parks on the right and
        // leaves the columns clickable, which is how a double click still
        // reaches a card while it is open (a full-panel dismissal catcher ate
        // exactly that click).
        var sheetRect = root.find(panel, "kanban-preview-sheet");
        root.check("the sheet leaves the board clickable",
            sheetRect !== null && sheetRect.width < panel.width / 2,
            sheetRect ? String(sheetRect.width) : "missing");

        // A click on another card switches the sheet; it does not stack a second
        // one or need the first closed by hand.
        panel.requestPreview("t_park");
        root.check("preview follows the click", panel.previewTask !== null && panel.previewTask.id === "t_park",
            panel.previewTask ? panel.previewTask.id : "none");
        root.check("the body replaces the placeholder",
            root.find(panel, "kanban-preview-body") !== null
            && root.find(panel, "kanban-preview-body").text === "x",
            root.find(panel, "kanban-preview-body") ? root.find(panel, "kanban-preview-body").text : "missing");

        // Editing lives in the sheet: a double click on the title opens the
        // field, and the commit is an `edit --title` on the card being shown.
        fake.calls = [];
        panel.beginFieldEdit("title");
        var titleField = root.find(panel, "kanban-preview-title-field");
        root.check("double click on the title opens its field",
            panel.editingField === "title" && titleField !== null && titleField.visible === true,
            panel.editingField);
        root.check("the read-only title steps aside",
            root.find(panel, "kanban-preview-title").visible === false);
        panel.commitTitle("Renamed from the sheet");
        panel.endFieldEdit();
        root.check("the title commits as an edit --title",
            fake.calls.length === 1
            && JSON.stringify(fake.calls[0]) === JSON.stringify(["edit", "--title", "Renamed from the sheet", "t_park"]),
            JSON.stringify(fake.calls));
        root.check("closing the field leaves the sheet open",
            panel.editingField === "" && panel.previewId === "t_park", panel.previewId);

        // The description takes the same path.
        fake.calls = [];
        panel.beginFieldEdit("body");
        var bodyField = root.find(panel, "kanban-preview-body-field");
        root.check("double click on the description opens its field",
            panel.editingField === "body" && bodyField !== null && bodyField.visible === true,
            panel.editingField);
        panel.commitBody("A real description");
        panel.endFieldEdit();
        root.check("the description commits as an edit --body",
            fake.calls.length === 1
            && JSON.stringify(fake.calls[0]) === JSON.stringify(["edit", "--body", "A real description", "t_park"]),
            JSON.stringify(fake.calls));

        // An edit that changes nothing spends no backend call, and an empty
        // title is refused instead of wiping the task's name.
        fake.calls = [];
        panel.beginFieldEdit("title");
        panel.commitTitle("Parked one");
        panel.commitTitle("");
        panel.endFieldEdit();
        root.check("an unchanged title costs no call", fake.calls.length === 0, JSON.stringify(fake.calls));
        root.check("an empty title is refused", panel.statusTone === "warn", panel.statusTone);

        // Close paths: the sheet, and an id that no longer exists (an archived
        // task must not leave an empty plaque on screen).
        panel.requestPreview("t_rev");
        panel.beginFieldEdit("title");
        panel.closePreview();
        root.check("closing hides the sheet", panel.previewTask === null
            && root.find(panel, "kanban-preview").visible === false);
        root.check("closing also closes the open field", panel.editingField === "", panel.editingField);
        panel.requestPreview("gone");
        root.check("an unknown id paints nothing", panel.previewTask === null, panel.previewId);
        panel.closePreview();

        // Reading and editing must lay out identically. `Text` honours
        // lineHeight and TextEdit does not, so any lineHeight in this sheet made
        // the words jump (measured: 26.6 px per line against the editor's 19)
        // the moment a field opened.
        var longBody = "Una descripcion larga que ocupa varias lineas para que el "
                     + "alto del texto dependa del interlineado y no de una sola linea "
                     + "de palabras cortas";
        var withLong = [];
        for (var t = 0; t < fake.tasks.length; t++)
            withLong.push(fake.tasks[t]);
        withLong[0] = { id: "t_new", title: "New one", body: longBody, status: "ready", priority: 0 };
        fake.tasks = withLong;
        panel.requestPreview("t_new");
        var readBody2 = root.find(panel, "kanban-preview-body");
        var editBody2 = root.find(panel, "kanban-preview-body-field");
        panel.beginFieldEdit("body");
        root.check("read and edit lay the description out the same",
            readBody2 !== null && editBody2 !== null
            && Math.abs(readBody2.contentHeight - editBody2.contentHeight) <= 1,
            (readBody2 ? readBody2.contentHeight : "?") + " vs "
            + (editBody2 ? editBody2.contentHeight : "?"));
        panel.closePreview();

        console.log("RESULT pass=" + root.pass + " fail=" + root.fail);
        Qt.quit();
    }

    Timer {
        interval: 500
        running: true
        onTriggered: root.run()
    }
}
