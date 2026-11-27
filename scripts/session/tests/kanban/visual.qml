import Quickshell
import Quickshell.Wayland
import QtQuick
import "@KANBAN@/components"
import "@KANBAN@/services"
import "@KANBAN@"

// Screenshot rig: paints the real panel and walks it through the states the
// mouse would produce, so the feedback can be photographed. Never sends an
// action to the backend.
ShellRoot {
    id: root

    Appearance { id: appearance }

    KanbanFeed {
        id: feed
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

    function firstCard() {
        if (!feed.tasks || feed.tasks.length === 0)
            return null;
        return root.find(panel, "kanban-card-" + feed.tasks[0].id);
    }

    function centre(dest) {
        for (var i = 0; i < panel.dropTargets.length; i++) {
            if (panel.dropTargets[i].dest === dest) {
                var item = panel.dropTargets[i].item;
                var p = item.mapToItem(panel, item.width / 2, item.height / 2);
                return { x: p.x, y: p.y };
            }
        }
        return { x: 0, y: 0 };
    }

    PanelWindow {
        anchors {
            top: true
            bottom: true
            left: true
            right: true
        }
        color: "transparent"
        exclusiveZone: -1
        WlrLayershell.namespace: "quickshell:kanban-shot"
        WlrLayershell.layer: WlrLayer.Overlay

        Rectangle {
            anchors.fill: parent
            color: Qt.rgba(0, 0, 0, appearance.scrimOpacity)
        }

        KanbanPanel {
            id: panel

            anchors.centerIn: parent
            appearance: appearance
            feed: feed
        }
    }

    Timer {
        interval: 1400
        running: true
        onTriggered: {
            console.log("first card: " + (root.firstCard() ? root.firstCard().objectName : "none")
                + " tasks=" + (feed.tasks ? feed.tasks.length : -1));
        }
    }

    Timer {
        interval: 2600
        running: true
        onTriggered: {
            var card = root.firstCard();
            if (!card)
                return;
            panel.beginDrag(card);
            panel.updateDrag(root.centre("process"));
            var g = root.find(panel, "kanban-ghost");
            console.log("after beginDrag: dragCard=" + (panel.dragCard ? panel.dragCard.objectName : "null")
                + " ghost=" + (g ? ("visible=" + g.visible + " x=" + Math.round(g.x) + " y=" + Math.round(g.y) + " w=" + g.width) : "missing")
                + " drop=" + panel.dropHover + "/" + panel.dropTarget
                + " centre=" + Math.round(root.centre("process").x) + "," + Math.round(root.centre("process").y));
        }
    }

    // Out of the board: the state layer has to vanish without painting a
    // colour the drop never had.
    Timer {
        interval: 4200
        running: true
        onTriggered: {
            panel.updateDrag({ x: panel.width / 2, y: 40 });
            console.log("idle: drop=" + panel.dropHover + "/" + panel.dropTarget);
        }
    }

    Timer {
        interval: 5600
        running: true
        onTriggered: {
            panel.cancelDrag();
            panel.report("A DONE task can't move to IN PROGRESS", "warn");
        }
    }

    Timer {
        interval: 9000
        running: true
        onTriggered: Qt.quit()
    }
}
