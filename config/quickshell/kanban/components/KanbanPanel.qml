import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import ".."

// The kanban plaque: three status columns (new / process / completed) over
// the current board, a creator row on top and one action row per card.
//
// Holds no data of its own: every list comes from services/KanbanFeed and
// every mutation goes back through feed.act, so the panel is a pure function
// of the feed plus the creator text. Status -> action map lives here because
// it is presentation policy, not backend truth.
//
// Geometry is fixed from the panel size down: the outer ColumnLayout fills
// the plaque, the columns row takes the remaining height, each column hands
// its height to its scroll areas. No implicit-height chains, so a long board
// scrolls inside its column instead of pushing the panel off-screen.
//
// Two overlays sit above the columns and are direct children of the plaque,
// outside the layouts, so showing one never moves the board: the preview sheet
// a single click on a card opens (which never takes the pointer away from the
// board), and the archive confirmation a right click opens (which does, because
// a confirmation has to own the click that answers it).
//
// Drag is resolved here, not by Qt's drag-and-drop: every column and footer
// zone registers itself as a drop target, and the column under the cursor is
// found by walking their real geometry. That keeps hit-testing honest (it
// works over the whole card, not just the label) and testable offscreen.
Rectangle {
    id: panel

    property Appearance appearance: Appearance {}
    property var feed: null

    property string dropHover: ""
    property string dropTarget: ""
    // The hovered lane is the one the card already lives in: nothing would
    // change, so this is not a refused move and must not read as one.
    property string dropSame: ""
    property var dragCard: null

    // The task whose action is in flight, and what to say when it lands.
    property string pendingId: ""
    property string pendingNote: ""

    // Which sheet field is open for editing ("title" / "body" / ""). The sheet
    // owns the text and the field; the panel owns which one is open, so a second
    // double click, a click elsewhere and Esc all have one place to consult.
    property string editingField: ""

    // The task queued for deletion. The trash on a card only fills these in:
    // the dialog is the only thing that can start an archive, and Esc or a
    // click on the scrim backs out of it.
    property string deleteId: ""
    property string deleteTitle: ""

    // The task the preview sheet shows. It holds the ID, not the row, so the
    // sheet always paints the live task: a move, a rename or a new category
    // lands without reopening it. Nothing else clears it -- the panel closes it
    // on Esc, on a click beside the sheet, and as soon as an editor opens.
    property string previewId: ""

    readonly property var previewTask: {
        var id = previewId;
        if (id === "")
            return null;
        var list = tasks;
        for (var i = 0; i < list.length; ++i) {
            if (list[i].id === id)
                return list[i];
        }
        return null;
    }

    property string statusText: ""
    property string statusTone: "info"

    // How long a press must hold before the card starts dragging. Short enough
    // to discover; the card stays put and the ghost takes over.
    readonly property int holdDelay: 180

    // Creator field limits. One source of truth for the field, the counter and
    // the placeholder: the counter used to be a second hardcoded number
    // ((30 - length) and (70 - length)) that drifted from maximumLength, so it
    // went negative while the field was still accepting input.
    readonly property int titleLimit: 80
    readonly property int descriptionLimit: 200

    // Category axis. It is not a priority: a category says which front the task
    // belongs to (C1 urgent .. C4 optional) and the priority ranks tasks inside
    // it (P1..P9). 0 means nobody classified it yet, so an unclassified card
    // sinks to the bottom of its lane instead of looking urgent.
    readonly property var categoryNames: ["none", "urgent", "important", "necessary", "optional"]
    // The category the creator stamps on the next task. It survives a creation
    // on purpose: filing three tasks under C1 must not mean clicking C1 thrice.
    property int newCategory: 0
    // Rank inside the category, 0 = none. Nine chips would not fit in the row
    // and a cycling chip turns P1..P9 into a guessing game, so the composer
    // takes two steps and a number.
    property int newPriority: 0

    // How long a manual "move to IN PROGRESS" holds the task.
    //
    // That lane is not a column a person can own: the backend's only way into it
    // is `claim`, which is a worker lease with an expiry (900 s by default). This
    // panel is not a worker, so nothing heartbeats the lease and the daemon
    // reclaims the task back to `ready` -- which reads as "the task I put in
    // progress went back to new" (measured: claimed 15:02:07, reclaimed 15:17:38
    // with retry_status `ready`). Eight hours keeps the gesture useful for a
    // working day and the footer says what it means; anything longer is a promise
    // the backend would not keep either.
    readonly property int claimTtlSeconds: 28800

    property var dropTargets: []

    signal dismissRequested()
    signal refreshRequested()

    readonly property var tasks: feed ? feed.tasks : []
    readonly property bool waiting: !feed
    readonly property string feedError: feed ? feed.error : ""
    readonly property bool saving: !!feed && feed.busy

    readonly property color statusColor: statusTone === "ok" ? appearance.ok
                                     : statusTone === "warn" ? appearance.warn
                                     : statusTone === "error" ? appearance.danger
                                     : appearance.textMuted

    Connections {
        target: panel.feed

        function onActionDone(ok, error, verb) {
            panel.pendingId = "";
            if (ok) {
                if (verb === "create") {
                    titleField.clear();
                    descField.clear();
                }
                panel.report(panel.pendingNote !== "" ? panel.pendingNote : "Done", "ok");
            } else {
                panel.report(error !== "" ? error : "the action failed", "error");
            }
            panel.pendingNote = "";
        }
    }

    // Lane order: category first, then priority, then title. An unclassified or
    // unranked task sorts after the classified ones - "nobody decided" is not a
    // stronger claim than C1, it is a hole in the board. Sorting here and not in
    // the backend keeps the rule in one place: the CLI orders by priority alone,
    // which would put a C4 P1 above a C1 P2.
    function ordered(list) {
        return list.slice().sort((a, b) => {
            var ca = a.category || 0;
            var cb = b.category || 0;
            if (ca !== cb) {
                if (ca === 0)
                    return 1;
                if (cb === 0)
                    return -1;
                return ca - cb;
            }
            var pa = a.priority || 0;
            var pb = b.priority || 0;
            if (pa !== pb) {
                if (pa === 0)
                    return 1;
                if (pb === 0)
                    return -1;
                return pa - pb;
            }
            return (a.title || "").localeCompare(b.title || "");
        });
    }

    function categoryName(value) {
        var names = panel.categoryNames;
        return (value >= 0 && value < names.length) ? names[value] : names[0];
    }

    // "C1-URGENT": the number files the card, the word says what the file means.
    // Empty for 0 so a chip renders as "C0" only where that is meaningful -- it
    // never is, so uncategorised surfaces simply draw no badge.
    function categoryLabel(value) {
        if (!value || value < 1)
            return "";
        return "C" + value + "-" + panel.categoryName(value).toUpperCase();
    }

    function requestPreview(id) {
        if (!id)
            return;
        previewId = id;
    }

    function closePreview() {
        if (previewId === "")
            return;
        commitOpenField();
        editingField = "";
        previewId = "";
    }

    function fresh() {
        return panel.ordered(panel.tasks.filter((t) => ["triage", "todo", "scheduled", "ready"].includes(t.status)));
    }
    function active() {
        return panel.ordered(panel.tasks.filter((t) => ["running", "blocked"].includes(t.status)));
    }
    function running() {
        return panel.ordered(panel.tasks.filter((t) => t.status === "running"));
    }
    function stalled() {
        return panel.ordered(panel.tasks.filter((t) => t.status === "blocked"));
    }
    // Awaiting the user's word. It is not part of IN PROGRESS any more: work
    // that is finished but unapproved is a different thing from work in flight,
    // and the person reviewing needs to see it as its own queue.
    function inReview() {
        return panel.ordered(panel.tasks.filter((t) => t.status === "review"));
    }
    function finished() {
        return panel.ordered(panel.tasks.filter((t) => t.status === "done"));
    }

    function moveArgs(task, dest) {
        // Backend truth: claim only leaves fresh work, unblock returns
        // parked work to fresh, schedule parks running work, complete
        // closes anything but parked work. Anything else is refused.
        var id = task.id;
        switch (dest) {
        case "new":
            if (task.status === "blocked" || task.status === "scheduled")
                return ["unblock", id];
            return null;
        case "process":
            if (["triage", "todo", "ready"].includes(task.status))
                return ["claim", id, "--ttl", String(panel.claimTtlSeconds)];
            // The one way back. review -> in progress is the only reverse move
            // the board allows: a rejected card goes back to the work, it does
            // not fall out of the flow into NEW. The helper runs reopen-review
            // (which lands in ready) and claims it again in the same act.
            if (task.status === "review")
                return ["reopen", id];
            return null;
        case "review":
            // Only a card that is actually running can be offered for review:
            // from ready it would skip the work, from done it makes no sense.
            if (task.status === "running")
                return ["request-review", id, "--summary", "Sent from the panel"];
            return null;
        case "completed":
            if (task.status !== "done" && task.status !== "scheduled")
                return ["complete", "--result", "Completed from the panel", id];
            return null;
        default:
            return null;
        }
    }

    function canMove(task, dest) {
        return moveArgs(task, dest) !== null;
    }

    // Which lane a status is shown in. It cannot be read off the status name:
    // NEW holds four of them (triage, todo, scheduled, ready) and PROCESS holds
    // the blocked ones under their own header. Without this, a card dropped back
    // on its own lane looked like an illegal move — only parked work can "move
    // to NEW" (that is the unblock), so a ready card sitting in NEW was told it
    // could not move to NEW.
    function columnOf(status) {
        if (["triage", "todo", "scheduled", "ready"].includes(status))
            return "new";
        if (["running", "blocked"].includes(status))
            return "process";
        if (status === "review")
            return "review";
        if (status === "done")
            return "completed";
        return "";
    }

    function destName(dest) {
        return { new: "TO DO", process: "IN PROGRESS", review: "IN REVIEW", completed: "DONE" }[dest] || dest;
    }

    // One place for every message the user gets: the header's right corner,
    // coloured by tone and cleared on a timer. No popups in a layer-shell
    // surface.
    function report(message, tone) {
        panel.statusText = message || "";
        panel.statusTone = tone || "info";
        statusTimer.interval = tone === "error" ? 8000 : (tone === "warn" ? 5000 : 3500);
        statusTimer.restart();
    }

    function requestFocus() {
        keyCatcher.forceActiveFocus();
    }

    // The sheet's two fields open and close through these. Opening is the
    // sheet's double click; closing hands the focus back to the panel, which is
    // what keeps Esc and R working once the text is no longer being edited.
    function beginFieldEdit(field) {
        if (previewId === "" || (field !== "title" && field !== "body"))
            return;
        if (!canEdit(previewTask)) {
            report(readOnlyMessage(previewTask), "warn");
            return;
        }
        commitOpenField();
        editingField = field;
    }

    // Editing is limited to the work nobody has picked up yet: the four statuses
    // TO DO holds. Once a card is claimed, parked or closed its state has moved
    // past the words, so renaming it would rewrite work that already happened.
    // The sheet stays a reading surface for those, which is why this is asked at
    // the entry (the double click) and again at the commit -- a task can leave TO
    // DO while its field is open, and the dispatcher is exactly the thing that
    // does it.
    function canEdit(task) {
        return !!task && columnOf(task.status) === "new";
    }

    function readOnlyMessage(task) {
        return String((task && task.status) || "this").toUpperCase()
             + " is read-only - only a TO DO task can be edited";
    }

    // Moving between fields, or putting the sheet away, is not a reason to drop
    // what was typed: whichever field is open commits first, exactly as a blur
    // would have done. Esc is the one path that reverts, and it does it on the
    // field itself before calling endFieldEdit.
    function commitOpenField() {
        if (editingField === "title")
            commitTitle(previewTitleField.text);
        else if (editingField === "body")
            commitBody(previewBodyField.text);
    }

    function endFieldEdit() {
        editingField = "";
        requestFocus();
    }

    function moveTask(id, dest) {
        var task = panel.tasks.find((t) => t.id === id);
        if (!task) {
            panel.report("That task is gone - press R to refresh", "warn");
            return;
        }
        var args = panel.moveArgs(task, dest);
        if (!args) {
            panel.report("A " + task.status.toUpperCase() + " task can't move to " + panel.destName(dest), "error");
            return;
        }
        panel.pendingId = id;
        panel.pendingNote = "\"" + (task.title || "") + "\" → " + panel.destName(dest);
        // A move into IN PROGRESS is a lease, not a column: say so at the moment
        // it happens, because the task comes back to NEW by design when the
        // claim runs out and nothing heartbeats it.
        panel.report(dest === "process"
            ? (task.status === "review"
                ? "Reopened - back in IN PROGRESS"
                : "Claimed for " + Math.round(panel.claimTtlSeconds / 3600)
                  + " h - it returns to TO DO unless a worker takes it")
            : "Moving to " + panel.destName(dest) + "…", "busy");
        panel.feed.act(args);
    }

    function editTitle(id, title) {
        panel.pendingId = id;
        panel.pendingNote = "Renamed to \"" + title + "\"";
        panel.report("Renaming…", "busy");
        panel.feed.act(["edit", "--title", title, id]);
    }

    // The sheet's fields commit through these. Both compare against the row
    // first: an edit that changes nothing must not spend a backend call nor
    // rewrite the status line.
    function commitTitle(text) {
        var task = panel.previewTask;
        var next = String(text || "").trim();
        if (!task)
            return;
        if (!panel.canEdit(task)) {
            panel.report(panel.readOnlyMessage(task), "warn");
            return;
        }
        if (next === "") {
            panel.report("A task needs a title", "warn");
            return;
        }
        if (next !== String(task.title || ""))
            panel.editTitle(task.id, next);
    }

    function commitBody(text) {
        var task = panel.previewTask;
        if (!task)
            return;
        if (!panel.canEdit(task)) {
            panel.report(panel.readOnlyMessage(task), "warn");
            return;
        }
        var next = String(text || "");
        if (next !== String(task.body || ""))
            panel.editBody(task.id, next);
    }

    function editBody(id, body) {
        // An empty description is a real state -- clearing stale notes is the
        // point -- so it takes the same path as any other change.
        panel.pendingId = id;
        panel.pendingNote = "Description updated";
        panel.report("Saving…", "busy");
        panel.feed.act(["edit", "--body", body, id]);
    }

    // Deletion is a two-step on purpose: the card only asks, and the dialog is
    // the single place that can archive. Archive is what the CLI exposes and
    // it is not reversible from the board, so a stray click must not reach it.
    function requestDelete(id) {
        var task = panel.tasks.find((t) => t.id === id);
        if (!task) {
            panel.report("That task is gone - press R to refresh", "warn");
            return;
        }
        panel.deleteId = id;
        panel.deleteTitle = task.title || "";
    }

    function cancelDelete() {
        if (panel.deleteId === "")
            return;
        panel.deleteId = "";
        panel.deleteTitle = "";
        panel.requestFocus();
    }

    function confirmDelete() {
        if (panel.deleteId === "")
            return;
        var id = panel.deleteId;
        var title = panel.deleteTitle;
        panel.deleteId = "";
        panel.deleteTitle = "";
        panel.pendingId = id;
        panel.pendingNote = "Archived \"" + title + "\"";
        panel.report("Archiving…", "busy");
        panel.feed.act(["archive", id]);
        panel.requestFocus();
    }

    // Whether the commit button can act at all. A create needs a title and a
    // board that is not already saving; asking first and answering "Type a
    // title first" afterwards is a state the button should never have offered.
    function stepPriority(delta) {
        panel.newPriority = Math.max(0, Math.min(9, panel.newPriority + delta));
    }

    function canCreate() {
        return titleField.text.trim() !== "" && !panel.waiting && !panel.saving;
    }

    function createTask() {
        var title = titleField.text.trim();
        if (title === "") {
            panel.report("Type a title first", "warn");
            titleField.forceActiveFocus();
            return;
        }
        var args = ["create", "--json", title];
        var body = descField.text.trim();
        if (body !== "")
            args.push("--body", body);
        // The helper strips --category before calling the CLI and pins it on the
        // row the CLI just created: `hermes kanban` has no category of its own.
        if (panel.newCategory > 0)
            args.push("--category", "C" + panel.newCategory);
        if (panel.newPriority > 0)
            args.push("--priority", String(panel.newPriority));
        panel.pendingNote = "Created \"" + title + "\""
            + (panel.newCategory > 0 ? " · C" + panel.newCategory : "")
            + (panel.newPriority > 0 ? " · P" + panel.newPriority : "");
        panel.report("Creating…", "busy");
        panel.feed.act(args);
    }

    // Drop targets register themselves; destAt walks the live geometry.
    function registerDrop(item, dest) {
        var list = panel.dropTargets.slice();
        list.push({ item: item, dest: dest });
        panel.dropTargets = list;
    }

    function destAt(x, y) {
        var list = panel.dropTargets;
        for (var i = list.length - 1; i >= 0; i--) {
            var entry = list[i];
            var origin = entry.item.mapToItem(panel, 0, 0);
            if (x >= origin.x && x <= origin.x + entry.item.width && y >= origin.y && y <= origin.y + entry.item.height)
                return entry.dest;
        }
        return "";
    }

    // Drag lifecycle: the card reports the hold, this moves the ghost, resolves
    // the drop by geometry and paints the destination; release resolves it.
    function beginDrag(card) {
        panel.dragCard = card;
        card.dragging = true;
        panel.dropHover = "";
        panel.dropTarget = "";
        panel.dropSame = "";
        ghostTitle.text = card.task.title || "";
        ghost.visible = true;
        panel.updateDrag(card.mapToItem(panel, card.width / 2, card.height / 2));
    }

    function updateDrag(point) {
        panel.moveGhost(point);
        var dest = panel.destAt(point.x, point.y);
        var task = panel.dragCard ? panel.dragCard.task : null;
        var home = task ? panel.columnOf(task.status) : "";
        panel.dropHover = dest;
        panel.dropTarget = (dest !== "" && task && panel.canMove(task, dest)) ? dest : "";
        // Back over the card's own lane: no action to take, so no refusal either.
        panel.dropSame = (dest !== "" && dest === home && panel.dropTarget !== dest) ? dest : "";
        var allowed = dest !== "" && panel.dropTarget === dest;
        var idles = panel.dropSame !== "";
        ghostDest.text = allowed ? "→ " + panel.destName(dest) : (idles ? "no move" : "");
        ghostDest.color = idles ? panel.appearance.warn : panel.appearance.accent;
        // The block sign is for a move the backend would refuse, not for a card
        // going home.
        ghostIcon.visible = dest !== "" && !allowed && !idles;
    }

    // The drag lives inside the four lanes and nowhere else: not the header,
    // not the creator, not the footer.
    function dragBounds() {
        var top = columnsRow.mapToItem(panel, 0, 0);
        return {
            x: top.x,
            y: top.y,
            w: columnsRow.width,
            h: columnsRow.height
        };
    }

    function moveGhost(point) {
        var b = panel.dragBounds();
        ghost.x = Math.max(b.x, Math.min(point.x - ghost.width / 2, b.x + b.w - ghost.width));
        ghost.y = Math.max(b.y, Math.min(point.y - ghost.height / 2, b.y + b.h - ghost.height));
    }

    function resetDrag() {
        if (panel.dragCard)
            panel.dragCard.dragging = false;
        panel.dragCard = null;
        panel.dropHover = "";
        panel.dropTarget = "";
        panel.dropSame = "";
        ghost.visible = false;
    }

    function cancelDrag() {
        panel.resetDrag();
    }

    function finishDrag() {
        var card = panel.dragCard;
        var dest = panel.dropTarget;
        var hover = panel.dropHover;
        var same = panel.dropSame;
        panel.resetDrag();
        if (!card)
            return;
        if (dest !== "") {
            panel.moveTask(card.task.id, dest);
            return;
        }
        // Released over the lane the card already sits in: say nothing moved,
        // in the neutral tone. A refusal is a different thing and keeps the
        // error tone that matches the red lane.
        if (same !== "") {
            panel.report("Nothing moved - it's already in " + panel.destName(same), "warn");
            return;
        }
        if (hover !== "")
            panel.report("A " + (card.task.status || "").toUpperCase() + " task can't move to " + panel.destName(hover), "error");
    }

    width: appearance.kanbanWidth
    height: appearance.maxHeight + appearance.contentPad * 2
    color: appearance.surfaceContainer
    radius: appearance.shapeExtraLarge
    // Edge: gilt (accent.tertiary) at look.borders.width — the plaque's frame.
    border.color: appearance.gilt
    border.width: appearance.borderWidth

    // Entrance: the plaque fades in and lifts its last few pixels rather than
    // popping. The lift rides a transform, not `y`: the plaque is anchored
    // (centerIn) by its shell, and a translate moves the paint without fighting
    // the anchor. Reduced motion zeroes the offset in apply-theme.py, so no
    // branch on the flag belongs here.
    opacity: 0
    Behavior on opacity {
        NumberAnimation {
            duration: appearance.motionEntranceDuration
            easing: appearance.motionEntranceEasing
        }
    }
    property real entranceLift: appearance.motionEntranceOffset
    Behavior on entranceLift {
        NumberAnimation {
            duration: appearance.motionEntranceDuration
            easing: appearance.motionEntranceEasing
        }
    }
    transform: Translate {
        y: panel.entranceLift
    }
    Component.onCompleted: {
        entranceLift = 0;
        opacity = 1;
    }

    // Keeps clicks from passing through the plaque, and puts the preview away:
    // this is the click-anywhere-else path for the header, the composer and the
    // gaps between columns. The lanes carry the same gesture of their own, since
    // a Flickable never lets a press through to this one. Cards and the sheet are
    // declared after it, so they sit above and only empty space reaches here.
    MouseArea {
        anchors.fill: parent
        onPressed: panel.closePreview()
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: panel.appearance.contentPad
        spacing: panel.appearance.spacingMedium

        // Header: what this is, plus one line of state under it. The count moved
        // out of a centred caption and into that line -- a caption floating in
        // the middle of the bar said "5 tasks" without saying what the 5 were.
        // The action feedback answers in the right corner: nothing else is drawn
        // there, so a long message has the whole width of the header to itself.
        // It used to sit at the left of the footer capped at a third, right under
        // the legend's ~300 px start, and every message longer than ~42 chars
        // ran beneath it.
        Item {
            Layout.fillWidth: true
            Layout.preferredHeight: panel.appearance.headerHeightTall + panel.appearance.spacingXs

            Column {
                id: headerTitle

                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                spacing: 0

                Text {
                    text: "TASKS"
                    color: panel.appearance.text
                    font.family: panel.appearance.displayFont
                    font.weight: panel.appearance.fontWeightDisplay
                    font.variableAxes: panel.appearance.fontVariableAxesDisplay
                    font.pixelSize: panel.appearance.fontSizeTitle
                    font.bold: true
                    font.letterSpacing: panel.appearance.letterSpacingLabel
                    elide: Text.ElideRight
                }

                Text {
                    objectName: "task-header-subtitle"
                    text: panel.waiting ? "reading the board…"
                        : (panel.saving ? "saving…"
                        : panel.tasks.length + " tasks · " + panel.fresh().length + " open")
                    color: panel.saving ? panel.appearance.accent : panel.appearance.textMuted
                    font.family: panel.appearance.uiFont
                    font.weight: panel.appearance.fontWeightUi
                    font.variableAxes: panel.appearance.fontVariableAxesUi
                    font.pixelSize: panel.appearance.fontSizeSmall
                }
            }

            // The one line every action answers with: what moved, what was
            // refused, what failed. Right-aligned against the plaque's own edge,
            // elided rather than allowed to grow, and never wider than the space
            // the title block leaves it.
            Text {
                objectName: "kanban-status"
                anchors.left: headerTitle.right
                anchors.leftMargin: panel.appearance.spacingMedium
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                text: panel.feedError !== "" ? panel.feedError
                    : (panel.statusText !== "" ? panel.statusText
                    : (panel.feed && panel.feed.parsingFailed ? "broken read - press R" : ""))
                color: panel.feedError !== "" || (panel.feed && panel.feed.parsingFailed) ? panel.appearance.danger : panel.statusColor
                horizontalAlignment: Text.AlignRight
                font.family: panel.appearance.uiFont
                font.weight: panel.appearance.fontWeightUi
                font.variableAxes: panel.appearance.fontVariableAxesUi
                font.pixelSize: panel.appearance.fontSizeCaption
                elide: Text.ElideRight
                maximumLineCount: 1
            }
        }


        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: panel.appearance.hairline
            color: panel.appearance.outline
            opacity: panel.appearance.opacityFrame
        }

        // Composer: one container with two lines inside it. The fields sit on
        // top, the axis and the commit beneath. As three bare rows on the plaque
        // it read as the first thing on the board; boxed, it reads as the tool
        // that feeds the board, which is what it is.
        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: composer.implicitHeight + panel.appearance.spacingMedium * 2
            color: panel.appearance.surfaceContainer
            radius: panel.appearance.shapeLarge
            border.color: panel.appearance.outline
            border.width: panel.appearance.borderWidth

            ColumnLayout {
                id: composer

                anchors.left: parent.left
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                anchors.leftMargin: panel.appearance.spacingMedium
                anchors.rightMargin: panel.appearance.spacingMedium
                spacing: panel.appearance.spacingSmall

                RowLayout {
                    Layout.fillWidth: true
                    Layout.preferredHeight: panel.appearance.fieldHeight

                    TextField {
                        id: titleField
                        objectName: "task-title-field"

                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        maximumLength: panel.titleLimit
                        placeholderText: "Title (max " + panel.titleLimit + ")… Enter to create"
                        placeholderTextColor: panel.appearance.textFaint
                        color: panel.appearance.text
                        font.family: panel.appearance.uiFont
                        font.pixelSize: panel.appearance.fontSizeBody
                        enabled: !panel.waiting && !panel.saving
                        // Room for the counter that now lives inside the field.
                        rightPadding: panel.appearance.counterWidth
                        background: Rectangle {
                            color: panel.appearance.surfaceContainerHigh
                            radius: panel.appearance.shapeMedium
                            border.color: titleField.activeFocus ? panel.appearance.accent : panel.appearance.outline
                            border.width: panel.appearance.borderWidth

                            // The count sits inside the field instead of floating in
                            // a column of its own to the right: outside, "80" read as
                            // a stray number between the field and the panel edge.
                            Text {
                                objectName: "task-title-counter"

                                anchors.right: parent.right
                                anchors.rightMargin: panel.appearance.spacingSmall
                                anchors.verticalCenter: parent.verticalCenter
                                text: (panel.titleLimit - titleField.length) + ""
                                // Muted, not faint: faint on this fill measures
                                // 2.8:1, and a counter nobody can read is decoration.
                                color: panel.appearance.textMuted
                                font.family: panel.appearance.uiFont
                                font.weight: panel.appearance.fontWeightUi
                                font.variableAxes: panel.appearance.fontVariableAxesUi
                                font.pixelSize: panel.appearance.fontSizeSmall
                            }
                        }
                        onAccepted: panel.createTask()
                        Keys.onPressed: (event) => {
                            if (event.key === Qt.Key_Escape) {
                                clear();
                                panel.requestFocus();
                                event.accepted = true;
                            }
                        }
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    Layout.preferredHeight: panel.appearance.fieldHeightCompact
                    spacing: panel.appearance.spacingSmall

                    TextField {
                        id: descField
                objectName: "task-desc-field"

                Layout.fillWidth: true
                Layout.fillHeight: true
                maximumLength: panel.descriptionLimit
                placeholderText: "Short description (max " + panel.descriptionLimit + ", optional)"
                placeholderTextColor: panel.appearance.textFaint
                color: panel.appearance.text
                font.family: panel.appearance.uiFont
                font.pixelSize: panel.appearance.fontSizeBody
                enabled: titleField.enabled
                rightPadding: panel.appearance.counterWidth
                background: Rectangle {
                    color: panel.appearance.surfaceContainerHigh
                    radius: panel.appearance.shapeMedium
                    border.color: descField.activeFocus ? panel.appearance.accent : panel.appearance.outline
                    border.width: panel.appearance.borderWidth

                    Text {
                        objectName: "task-desc-counter"

                        anchors.right: parent.right
                        anchors.rightMargin: panel.appearance.spacingSmall
                        anchors.verticalCenter: parent.verticalCenter
                        text: (panel.descriptionLimit - descField.length) + ""
                        color: panel.appearance.textMuted
                        font.family: panel.appearance.uiFont
                        font.weight: panel.appearance.fontWeightUi
                        font.variableAxes: panel.appearance.fontVariableAxesUi
                        font.pixelSize: panel.appearance.fontSizeSmall
                    }
                }
                onAccepted: panel.createTask()
                Keys.onPressed: (event) => {
                    if (event.key === Qt.Key_Escape) {
                        clear();
                        panel.requestFocus();
                        event.accepted = true;
                    }
                }
            }

                    // The axis sits after the fields, not before them: it is a
                    // property of the task being typed, and a row of chips above
                    // the title read as a filter for a board that has none.
                    Repeater {
                        model: [1, 2, 3, 4]

                        CategoryChip {
                            required property int modelData

                            appearance: panel.appearance
                            category: modelData
                            interactive: true
                            selected: panel.newCategory === modelData
                            // Only the chosen chip spells itself out: four full
                            // labels would be four bars fighting the fields.
                            label: panel.newCategory === modelData ? panel.categoryLabel(modelData) : ""
                            Layout.alignment: Qt.AlignVCenter
                            onActivated: panel.newCategory = panel.newCategory === modelData ? 0 : modelData
                        }
                    }

                    // Rank inside the chosen category. Same two-step rhythm as
                    // the delete confirmation: a control that only ever moves by
                    // one, so a wrong P is one click away from right.
                    RowLayout {
                        Layout.alignment: Qt.AlignVCenter
                        spacing: panel.appearance.spacingXs

                        Text {
                            Layout.alignment: Qt.AlignVCenter
                            text: "P"
                            color: panel.appearance.textMuted
                            font.family: panel.appearance.uiFont
                            font.weight: panel.appearance.fontWeightUi
                            font.variableAxes: panel.appearance.fontVariableAxesUi
                            font.pixelSize: panel.appearance.fontSizeSmall
                        }

                        Rectangle {
                            objectName: "task-priority-down"
                            Layout.preferredWidth: panel.appearance.badgeHeight
                            Layout.preferredHeight: panel.appearance.badgeHeight
                            radius: panel.appearance.shapeSmall
                            color: downArea.containsMouse ? panel.appearance.surface : "transparent"
                            border.width: panel.appearance.borderWidth
                            border.color: panel.newPriority > 0 ? panel.appearance.outline : "transparent"

                            Text {
                                anchors.centerIn: parent
                                text: "-"
                                color: panel.newPriority > 0 ? panel.appearance.text : panel.appearance.textFaint
                                font.family: panel.appearance.uiFont
                                font.pixelSize: panel.appearance.fontSizeBody
                            }

                            MouseArea {
                                id: downArea
                                anchors.fill: parent
                                enabled: panel.newPriority > 0
                                hoverEnabled: true
                                cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                                onClicked: panel.stepPriority(-1)
                            }
                        }

                        Text {
                            objectName: "task-priority-value"
                            Layout.preferredWidth: panel.appearance.badgeHeight
                            horizontalAlignment: Text.AlignHCenter
                            Layout.alignment: Qt.AlignVCenter
                            text: panel.newPriority > 0 ? panel.newPriority + "" : "0"
                            color: panel.newPriority > 0 ? panel.appearance.accentInk : panel.appearance.textFaint
                            font.family: panel.appearance.uiFont
                            font.weight: panel.appearance.fontWeightUi
                            font.variableAxes: panel.appearance.fontVariableAxesUi
                            font.pixelSize: panel.appearance.fontSizeSmall
                        }

                        Rectangle {
                            objectName: "task-priority-up"
                            Layout.preferredWidth: panel.appearance.badgeHeight
                            Layout.preferredHeight: panel.appearance.badgeHeight
                            radius: panel.appearance.shapeSmall
                            color: upArea.containsMouse ? panel.appearance.surface : "transparent"
                            border.width: panel.appearance.borderWidth
                            border.color: panel.appearance.outline

                            Text {
                                anchors.centerIn: parent
                                text: "+"
                                color: panel.newPriority < 9 ? panel.appearance.text : panel.appearance.textFaint
                                font.family: panel.appearance.uiFont
                                font.pixelSize: panel.appearance.fontSizeBody
                            }

                            MouseArea {
                                id: upArea
                                anchors.fill: parent
                                enabled: panel.newPriority < 9
                                hoverEnabled: true
                                cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                                onClicked: panel.stepPriority(1)
                            }
                        }
                    }

                    // Primary action: filled at rest, lit one rung up on hover
                    // (accent -> accentInk), which is this palette's own hover
                    // doctrine. Disabled is a real state, not a fake: a create
                    // with no title used to answer with a warning message
                    // instead of never being offered.
                    Rectangle {
                        objectName: "task-create-button"
                        Layout.preferredWidth: panel.appearance.buttonMinWidth
                        Layout.preferredHeight: panel.appearance.buttonHeight
                        radius: panel.appearance.shapeMedium
                        color: createArea.enabled
                            ? (createArea.containsMouse ? panel.appearance.accentInk : panel.appearance.accent)
                            : "transparent"
                        border.width: panel.appearance.borderWidth
                        border.color: createArea.enabled
                            ? (createArea.containsMouse ? panel.appearance.accentInk : panel.appearance.accent)
                            : panel.appearance.outline

                        Text {
                            anchors.centerIn: parent
                            text: "CREATE"
                            color: createArea.enabled ? panel.appearance.surface : panel.appearance.textFaint
                            font.family: panel.appearance.uiFont
                            font.weight: panel.appearance.fontWeightUi
                            font.variableAxes: panel.appearance.fontVariableAxesUi
                            font.pixelSize: panel.appearance.fontSizeCaption
                            font.letterSpacing: panel.appearance.letterSpacingCaption
                        }

                        MouseArea {
                            id: createArea

                            anchors.fill: parent
                            enabled: panel.canCreate()
                            hoverEnabled: true
                            cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                            onClicked: panel.createTask()
                        }
                    }
                }
            }
        }

        // Four lanes: TO DO, IN PROGRESS, IN REVIEW, DONE. Blocked lives inside
        // PROCESS so a stuck card stays visible next to the work it belongs to;
        // review is its own column because finished-but-unapproved is a queue a
        // person has to empty, not a shade of in-flight.
        Row {
            id: columnsRow

            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: panel.appearance.columnGap

            KanbanSection {
                appearance: panel.appearance
                dest: "new"
                width: panel.appearance.columnWidth
                height: parent.height
                title: "TO DO"
                count: panel.fresh().length
                tasks: panel.fresh()
                panel: panel
            }

            KanbanSection {
                appearance: panel.appearance
                dest: "process"
                width: panel.appearance.columnWidth
                height: parent.height
                title: "IN PROGRESS"
                count: panel.running().length
                tasks: panel.running()
                extraTitle: "BLOCKED"
                extraCount: panel.stalled().length
                extraTasks: panel.stalled()
                panel: panel
            }

            KanbanSection {
                appearance: panel.appearance
                dest: "review"
                width: panel.appearance.columnWidth
                height: parent.height
                title: "IN REVIEW"
                count: panel.inReview().length
                tasks: panel.inReview()
                panel: panel
            }

            KanbanSection {
                appearance: panel.appearance
                dest: "completed"
                width: panel.appearance.columnWidth
                height: parent.height
                title: "DONE"
                count: panel.finished().length
                tasks: panel.finished()
                dimmed: true
                panel: panel
            }
        }

        // Legend. It answers for the gestures alone now: the action feedback
        // moved up to the header's right corner, where nothing else is painted.
        // One footer used to do both jobs in one sentence, so an action message
        // erased the legend exactly when the user was acting.
        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: panel.appearance.hairline
            color: panel.appearance.outline
            opacity: panel.appearance.opacityFrame
        }

        // Footer: the legend centred on the plaque. Right-aligned legends read as
        // a toolbar bolted to the edge; centred, they read as the caption of the
        // board above them, which is what they are.
        Item {
            id: footerRow

            Layout.fillWidth: true
            Layout.preferredHeight: panel.appearance.fieldHeightCompact
                + panel.appearance.contentPad - panel.appearance.borderWidth
            Layout.bottomMargin: -(panel.appearance.contentPad - panel.appearance.borderWidth)

            // Pointing gestures have no key to show, so the sign is a glyph: the
            // open hand is the cursor the plaque actually uses to drag, the arrow
            // is the pointer that renames, the mouse is the button that archives.
            // Keyboard entries follow, past a hairline, because a key and a mouse
            // gesture are two kinds of sign and the legend says so.
            Row {
                id: legendRow

                anchors.centerIn: parent
                spacing: panel.appearance.spacingMedium

                LegendRow {
                    appearance: panel.appearance
                    glyph: "pan_tool"
                    label: "Drag a task"
                }

                LegendRow {
                    appearance: panel.appearance
                    glyph: "arrow_selector_tool"
                    label: "Double-click to edit"
                }

                LegendRow {
                    appearance: panel.appearance
                    glyph: "mouse"
                    label: "Right-click archives"
                }

                Rectangle {
                    width: panel.appearance.hairline
                    height: panel.appearance.spacingMedium
                    anchors.verticalCenter: parent.verticalCenter
                    color: panel.appearance.outline
                    opacity: panel.appearance.opacityFrame
                }

                LegendRow {
                    appearance: panel.appearance
                    key: "R"
                    label: "refresh"
                    tracked: true
                }

                LegendRow {
                    appearance: panel.appearance
                    key: "Esc"
                    label: "close"
                    tracked: true
                }
            }
        }
    }

    // The creator owns the focus while typing; this catcher routes the keys
    // everywhere else instead of relying on the window.
    Item {
        id: keyCatcher

        anchors.fill: parent
        focus: true

        Keys.onPressed: (event) => {
            if (event.key === Qt.Key_Escape) {
                if (panel.deleteId !== "") {
                    panel.cancelDelete();
                } else if (panel.editingField !== "") {
                    panel.endFieldEdit();
                } else if (panel.previewId !== "") {
                    panel.closePreview();
                } else {
                    panel.dismissRequested();
                }
            } else if (event.key === Qt.Key_R) {
                panel.report("Refreshing…", "busy");
                panel.refreshRequested();
            } else {
                return;
            }
            event.accepted = true;
        }
    }

    Timer {
        id: statusTimer

        onTriggered: panel.statusText = ""
    }

    // Ghost chip: follows the cursor while a card drags, and names the
    // destination it is over. A direct child of the plaque, outside the layout,
    // so showing it never moves anything.
    Rectangle {
        id: ghost

        objectName: "kanban-ghost"
        visible: false
        width: panel.appearance.ghostWidth
        height: panel.appearance.ghostHeight
        color: panel.appearance.surfaceContainerHigh
        radius: panel.appearance.shapeSmall
        border.color: panel.dropTarget !== "" ? panel.appearance.accent : panel.appearance.danger
        border.width: panel.appearance.borderWidth
        opacity: 0.96

        RowLayout {
            anchors.fill: parent
            anchors.margins: panel.appearance.spacingSmall
            spacing: panel.appearance.spacingSmall

            Text {
                id: ghostTitle

                Layout.fillWidth: true
                verticalAlignment: Text.AlignVCenter
                text: ""
                color: panel.appearance.text
                font.family: panel.appearance.uiFont
                font.weight: panel.appearance.fontWeightUi
                font.variableAxes: panel.appearance.fontVariableAxesUi
                font.pixelSize: panel.appearance.fontSizeBody
                elide: Text.ElideRight
                maximumLineCount: 1
            }

            Text {
                id: ghostDest

                text: ""
                color: panel.appearance.accent
                font.family: panel.appearance.uiFont
                font.weight: panel.appearance.fontWeightUi
                font.variableAxes: panel.appearance.fontVariableAxesUi
                font.pixelSize: panel.appearance.fontSizeCaption
            }

            // A refused drop shows a sign, not a sentence.
            Text {
                id: ghostIcon

                visible: false
                text: "block"
                color: panel.appearance.danger
                font.family: panel.appearance.iconFont
                font.weight: panel.appearance.fontWeightIcons
                font.variableAxes: panel.appearance.fontVariableAxesIcons
                font.pixelSize: panel.appearance.fontSizeBody
            }
        }
    }

    // Preview sheet. One click on a card shows the task in full: the body the
    // card can only elide to one line, and the two axes that place it on the
    // board. It is not a dialog -- nothing is being confirmed, nothing is
    // destructive -- so it paints no scrim and, more importantly, captures
    // nothing: a catcher over the board ate the click that was meant for the
    // card underneath, so the sheet's own hint ("double click to edit") did
    // nothing while it was open. Esc puts it away, a click on another card moves
    // it, and a click on the empty board too. The text itself is editable: a
    // double click on the title or the description opens that field, which is
    // where a task is renamed or re-described. Read-only past TO DO -- a claimed,
    // parked or closed task keeps its words, and its hint says so.
    Item {
        id: preview

        objectName: "kanban-preview"
        anchors.fill: parent
        visible: panel.previewTask !== null
        z: panel.appearance.zOverlay

        Rectangle {
            id: previewSheet

            objectName: "kanban-preview-sheet"
            anchors.top: parent.top
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            anchors.margins: panel.appearance.contentPad
            width: Math.min(panel.appearance.dialogMaxWidth,
                            panel.width - 2 * panel.appearance.contentPad)
            color: panel.appearance.surfaceContainerHigh
            radius: panel.appearance.shapeMedium
            border.color: panel.appearance.outline
            border.width: panel.appearance.borderWidth
            opacity: preview.visible ? 1 : 0

            // Swallow: a click inside the sheet is reading, not dismissing.
            MouseArea {
                anchors.fill: parent
            }

            // It arrives the way every other transient surface on this desktop
            // does: a short fade with a small offset, the same easing the
            // panel's own entrance uses.
            transform: Translate {
                x: preview.visible ? 0 : panel.appearance.motionEntranceOffset

                Behavior on x {
                    NumberAnimation {
                        duration: panel.appearance.motionEntranceDuration
                        easing.type: panel.appearance.motionEntranceEasing
                    }
                }
            }

            Behavior on opacity {
                NumberAnimation { duration: panel.appearance.motionEntranceDuration }
            }

            ColumnLayout {
                id: previewColumn

                // No anchors.fill: the footer is anchored to the sheet instead,
                // and filling both ends would close a binding loop on height.
                x: panel.appearance.contentPadTight
                y: panel.appearance.contentPadTight
                width: parent.width - 2 * panel.appearance.contentPadTight
                spacing: panel.appearance.spacingSmall

                RowLayout {
                    Layout.fillWidth: true
                    spacing: panel.appearance.spacingSmall

                    Text {
                        objectName: "kanban-preview-status"
                        text: panel.previewTask ? String(panel.previewTask.status || "").toUpperCase() : ""
                        color: panel.appearance.textMuted
                        font.family: panel.appearance.uiFont
                        font.weight: panel.appearance.fontWeightUi
                        font.variableAxes: panel.appearance.fontVariableAxesUi
                        font.pixelSize: panel.appearance.fontSizeSmall
                        font.letterSpacing: panel.appearance.letterSpacingLabel
                    }

                    Item {
                        Layout.fillWidth: true
                    }

                    // The handle the CLI takes: the one thing on this sheet that
                    // is not meant to be read as prose.
                    Text {
                        objectName: "kanban-preview-id"
                        text: panel.previewTask ? String(panel.previewTask.id || "") : ""
                        color: panel.appearance.textMuted
                        font.family: panel.appearance.uiFont
                        font.weight: panel.appearance.fontWeightText
                        font.variableAxes: panel.appearance.fontVariableAxesUi
                        font.pixelSize: panel.appearance.fontSizeCaption
                    }
                }

                // Title: the same words, read or edited, and NO lineHeight on
                // either side. Text honours lineHeight; TextInput and TextEdit
                // do not, so a tuned value here laid the reading view out at
                // 26.6 px per line and the editor at 19 -- the text jumped the
                // moment a field opened. The slots measure both at the same
                // size, which is what keeps the swap silent.
                Item {
                    id: previewTitleSlot

                    Layout.fillWidth: true
                    Layout.preferredHeight: Math.max(previewTitleText.contentHeight,
                                                     previewTitleField.contentHeight)

                    Text {
                        id: previewTitleText

                        objectName: "kanban-preview-title"
                        width: parent.width
                        text: panel.previewTask ? String(panel.previewTask.title || "") : ""
                        visible: panel.editingField !== "title"
                        color: panel.appearance.text
                        font.family: panel.appearance.uiFont
                        font.weight: panel.appearance.fontWeightUi
                        font.variableAxes: panel.appearance.fontVariableAxesUi
                        font.pixelSize: panel.appearance.fontSizeTitle
                        wrapMode: Text.Wrap
                    }

                    // Double click opens the field. A single click does nothing
                    // here: this is a reading surface first.
                    MouseArea {
                        objectName: "kanban-preview-title-hit"
                        anchors.fill: parent
                        enabled: !previewTitleField.visible
                        onDoubleClicked: panel.beginFieldEdit("title")
                    }

                    // TextEdit, not TextInput: the title wraps in the reading
                    // view, and a single-line input clipped it instead of
                    // showing the second line. Enter stays the commit key (a
                    // title has no newlines), so it is swallowed below.
                    TextEdit {
                        id: previewTitleField

                        objectName: "kanban-preview-title-field"
                        width: parent.width
                        height: Math.max(contentHeight, panel.appearance.fontSizeTitle * 1.4)
                        visible: panel.editingField === "title"
                        text: panel.previewTask ? String(panel.previewTask.title || "") : ""
                        color: panel.appearance.text
                        selectionColor: panel.appearance.accent
                        selectedTextColor: panel.appearance.surface
                        font.family: panel.appearance.uiFont
                        font.weight: panel.appearance.fontWeightUi
                        font.variableAxes: panel.appearance.fontVariableAxesUi
                        font.pixelSize: panel.appearance.fontSizeTitle
                        wrapMode: TextEdit.Wrap
                        selectByMouse: true
                        onVisibleChanged: {
                            if (!visible)
                                return;
                            forceActiveFocus();
                            selectAll();
                        }
                        onActiveFocusChanged: {
                            if (!activeFocus && panel.editingField === "title")
                                panel.commitTitle(text);
                        }
                        Keys.onPressed: (event) => {
                            if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                                panel.commitTitle(text);
                                panel.endFieldEdit();
                                event.accepted = true;
                            } else if (event.key === Qt.Key_Escape) {
                                // Esc drops what was typed; the panel's own Esc
                                // then has a sheet to close.
                                text = panel.previewTask ? String(panel.previewTask.title || "") : "";
                                panel.endFieldEdit();
                                event.accepted = true;
                            }
                        }
                    }
                }

                RowLayout {
                    objectName: "kanban-preview-meta"
                    Layout.fillWidth: true
                    spacing: panel.appearance.spacingSmall
                    visible: panel.previewTask
                             ? ((panel.previewTask.category || 0) > 0 || (panel.previewTask.priority || 0) > 0)
                             : false

                    CategoryChip {
                        appearance: panel.appearance
                        category: panel.previewTask ? (panel.previewTask.category || 0) : 0
                        label: panel.previewTask ? panel.categoryLabel(panel.previewTask.category || 0) : ""
                        visible: panel.previewTask ? (panel.previewTask.category || 0) > 0 : false
                        Layout.alignment: Qt.AlignVCenter
                    }

                    Text {
                        visible: panel.previewTask ? (panel.previewTask.priority || 0) > 0 : false
                        text: panel.previewTask ? "P" + panel.previewTask.priority : ""
                        color: panel.appearance.textMuted
                        font.family: panel.appearance.uiFont
                        font.weight: panel.appearance.fontWeightUi
                        font.variableAxes: panel.appearance.fontVariableAxesUi
                        font.pixelSize: panel.appearance.fontSizeCaption
                        Layout.alignment: Qt.AlignVCenter
                    }
                }

                Rectangle {
                    Layout.fillWidth: true
                    Layout.topMargin: panel.appearance.spacingXs
                    height: panel.appearance.hairline
                    color: panel.appearance.outline
                }

                // Description: the same split as the title, one line box taller
                // because this text wraps.
                Item {
                    id: previewBodySlot

                    Layout.fillWidth: true
                    Layout.preferredHeight: Math.max(previewBodyText.contentHeight,
                                                     previewBodyField.contentHeight)

                    Text {
                        id: previewBodyText

                        objectName: "kanban-preview-body"
                        width: parent.width
                        text: panel.previewTask && String(panel.previewTask.body || "").length > 0
                              ? String(panel.previewTask.body)
                              : "No description."
                        visible: panel.editingField !== "body"
                        // textMuted, never textFaint: the empty state is a
                        // sentence to read, and faint ink lands at 2.84:1 on
                        // this fill against the 4.5 target.
                        color: panel.appearance.textMuted
                        font.family: panel.appearance.uiFont
                        font.weight: panel.appearance.fontWeightText
                        font.variableAxes: panel.appearance.fontVariableAxesUi
                        font.pixelSize: panel.appearance.fontSizeBody
                        wrapMode: Text.Wrap
                    }

                    MouseArea {
                        objectName: "kanban-preview-body-hit"
                        anchors.fill: parent
                        enabled: !previewBodyField.visible
                        onDoubleClicked: panel.beginFieldEdit("body")
                    }

                    TextEdit {
                        id: previewBodyField

                        objectName: "kanban-preview-body-field"
                        width: parent.width
                        height: Math.max(contentHeight, panel.appearance.fontSizeBody * 1.4)
                        visible: panel.editingField === "body"
                        text: panel.previewTask ? String(panel.previewTask.body || "") : ""
                        color: panel.appearance.textMuted
                        selectionColor: panel.appearance.accent
                        selectedTextColor: panel.appearance.surface
                        font.family: panel.appearance.uiFont
                        font.weight: panel.appearance.fontWeightText
                        font.variableAxes: panel.appearance.fontVariableAxesUi
                        font.pixelSize: panel.appearance.fontSizeBody
                        wrapMode: TextEdit.Wrap
                        selectByMouse: true
                        onVisibleChanged: {
                            if (visible)
                                forceActiveFocus();
                        }
                        onActiveFocusChanged: {
                            if (!activeFocus && panel.editingField === "body")
                                panel.commitBody(text);
                        }
                        Keys.onPressed: (event) => {
                            if (event.key !== Qt.Key_Escape)
                                return;
                            text = panel.previewTask ? String(panel.previewTask.body || "") : "";
                            panel.endFieldEdit();
                            event.accepted = true;
                        }
                    }
                }
            }

            Text {
                objectName: "kanban-preview-hint"
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                anchors.margins: panel.appearance.contentPadTight
                text: panel.canEdit(panel.previewTask)
                      ? "Double click the title or the description to edit · Esc closes"
                      : "Read only · only a TO DO task can be edited · Esc closes"
                color: panel.appearance.textMuted
                font.family: panel.appearance.uiFont
                font.weight: panel.appearance.fontWeightText
                font.variableAxes: panel.appearance.fontVariableAxesUi
                font.pixelSize: panel.appearance.fontSizeCaption
                elide: Text.ElideRight
                maximumLineCount: 1
            }
        }
    }

    // Destructive confirmation. The trash on a card only opens this: archiving
    // removes the task from the board and there is no unarchive in the CLI, so
    // the gesture must never be enough. Esc, a click on the scrim or Cancel all
    // back out; only the Delete button reaches the feed.
    Item {
        id: deleteDialog

        objectName: "kanban-delete-dialog"
        anchors.fill: parent
        visible: panel.deleteId !== ""
        z: panel.appearance.zOverlay

        Rectangle {
            anchors.fill: parent
            color: panel.appearance.scrim
            opacity: panel.appearance.scrimOpacity
        }

        MouseArea {
            anchors.fill: parent
            onClicked: panel.cancelDelete()
        }

        Rectangle {
            id: deleteCard

            anchors.centerIn: parent
            width: Math.min(panel.width - 2 * panel.appearance.contentPad,
                            panel.appearance.dialogMaxWidth)
            height: deleteColumn.implicitHeight + 2 * panel.appearance.contentPad
            color: panel.appearance.surfaceContainerHigh
            radius: panel.appearance.shapeMedium
            border.color: panel.appearance.outline
            border.width: panel.appearance.borderWidth

            // Swallow clicks: the plaque behind the dialog is out of reach.
            MouseArea {
                anchors.fill: parent
            }

            ColumnLayout {
                id: deleteColumn

                // No anchors.fill here: the card's height comes from this
                // layout's implicitHeight, and filling it back would close a
                // binding loop. A width is enough for the wrapped texts.
                x: panel.appearance.contentPad
                y: panel.appearance.contentPad
                width: parent.width - 2 * panel.appearance.contentPad
                spacing: panel.appearance.spacingSmall

                Text {
                    Layout.fillWidth: true
                    text: "Archive this task?"
                    color: panel.appearance.text
                    font.family: panel.appearance.uiFont
                    font.weight: panel.appearance.fontWeightUi
                    font.variableAxes: panel.appearance.fontVariableAxesUi
                    font.pixelSize: panel.appearance.fontSizeTitle
                    elide: Text.ElideRight
                    maximumLineCount: 1
                }

                Text {
                    Layout.fillWidth: true
                    text: "\"" + panel.deleteTitle + "\""
                    color: panel.appearance.danger
                    font.family: panel.appearance.uiFont
                    font.weight: panel.appearance.fontWeightUi
                    font.variableAxes: panel.appearance.fontVariableAxesUi
                    font.pixelSize: panel.appearance.fontSizeBody
                    wrapMode: Text.Wrap
                    maximumLineCount: 2
                    elide: Text.ElideRight
                }

                Text {
                    Layout.fillWidth: true
                    text: "It leaves the board. The task stays in the database, and the board can't bring it back."
                    color: panel.appearance.textMuted
                    font.family: panel.appearance.uiFont
                    font.weight: panel.appearance.fontWeightUi
                    font.variableAxes: panel.appearance.fontVariableAxesUi
                    font.pixelSize: panel.appearance.fontSizeCaption
                    wrapMode: Text.Wrap
                }

                RowLayout {
                    Layout.fillWidth: true
                    Layout.topMargin: panel.appearance.spacingSmall
                    spacing: panel.appearance.spacingSmall

                    Item {
                        Layout.fillWidth: true
                    }

                    Rectangle {
                        objectName: "kanban-delete-cancel"
                        Layout.preferredWidth: panel.appearance.buttonMinWidth
                        Layout.preferredHeight: panel.appearance.buttonHeight
                        color: cancelArea.containsMouse ? panel.appearance.surface : "transparent"
                        radius: panel.appearance.shapeMedium
                        border.color: panel.appearance.outline
                        border.width: panel.appearance.borderWidth

                        Text {
                            anchors.centerIn: parent
                            text: "Cancel"
                            color: panel.appearance.textMuted
                            font.family: panel.appearance.uiFont
                            font.weight: panel.appearance.fontWeightUi
                            font.variableAxes: panel.appearance.fontVariableAxesUi
                            font.pixelSize: panel.appearance.fontSizeBody
                        }

                        MouseArea {
                            id: cancelArea

                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: panel.cancelDelete()
                        }
                    }

                    Rectangle {
                        objectName: "kanban-delete-confirm"
                        Layout.preferredWidth: panel.appearance.buttonMinWidth
                        Layout.preferredHeight: panel.appearance.buttonHeight
                        color: confirmArea.containsMouse ? panel.appearance.danger : "transparent"
                        radius: panel.appearance.shapeMedium
                        border.color: panel.appearance.danger
                        border.width: panel.appearance.borderWidth

                        Text {
                            anchors.centerIn: parent
                            text: "Archive"
                            color: confirmArea.containsMouse ? panel.appearance.surface : panel.appearance.danger
                            font.family: panel.appearance.uiFont
                            font.weight: panel.appearance.fontWeightUi
                            font.variableAxes: panel.appearance.fontVariableAxesUi
                            font.pixelSize: panel.appearance.fontSizeBody
                        }

                        MouseArea {
                            id: confirmArea

                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: panel.confirmDelete()
                        }
                    }
                }
            }
        }
    }
}
