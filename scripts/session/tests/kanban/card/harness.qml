import QtQuick
import "." 

// Card in isolation: a fake panel records every call the card makes, so the C++
// harness can tell a hold-drag from a scroll and a double click from a single.
Rectangle {
    id: root

    property int dragStarts: 0
    property int dragUpdates: 0
    property int dragFinishes: 0
    property int dragCancels: 0
    property string lastPoint: ""
    property string lastDelete: ""
    property string lastPreview: ""

    width: 400
    height: 300
    color: "#292329"

    // Must be an Item: the card maps its pointer into the panel's coordinates.
    Item {
        id: fakePanel

        objectName: "fakePanel"
        visible: false
        width: 0
        height: 0
        property string pendingId: ""
        property string selectedId: ""
        property int holdDelay: 180

        // The card asks the panel how to spell its category; the fake answers
        // the same way the real one does so the harness exercises the real path.
        readonly property var categoryNames: ["none", "urgent", "important", "necessary", "optional"]
        function categoryLabel(value) {
            if (!value || value < 1)
                return "";
            return "C" + value + "-" + categoryNames[value].toUpperCase();
        }

        // The real panel owns the dragging flag and clears it on release; the
        // fake honours the same contract so the card is exercised for real.
        property var activeCard: null

        function beginDrag(card) {
            root.dragStarts += 1;
            activeCard = card;
            card.dragging = true;
        }
        function updateDrag(point) {
            root.dragUpdates += 1;
            root.lastPoint = Math.round(point.x) + "," + Math.round(point.y);
        }
        function finishDrag() {
            root.dragFinishes += 1;
            if (activeCard)
                activeCard.dragging = false;
            activeCard = null;
        }
        function cancelDrag() {
            root.dragCancels += 1;
            if (activeCard)
                activeCard.dragging = false;
            activeCard = null;
        }
        function requestFocus() {}
        function report(message, tone) {}
    }

    KanbanCard {
        id: card

        objectName: "card"
        appearance: Appearance {}
        panel: fakePanel
        task: ({ id: "t1", title: "Draggable task", body: "a body line to hover on", status: "ready", priority: 1 })
        width: 240
        x: 20
        y: 20

        onDeleteRequested: (id) => {
            root.lastDelete = id;
        }

        onPreviewRequested: (id) => {
            root.lastPreview = id;
        }
    }
}
