import QtQuick
import "."

// One lane in isolation: a fake panel records the calls the section makes, so
// the C++ harness can tell a press on a card from a press on empty lane space.
Rectangle {
    id: root

    property int dismisses: 0
    property string lastPreview: ""
    property string lastDelete: ""

    width: 360
    height: 520
    color: "#101010"

    Item {
        id: fakePanel

        objectName: "fakePanel"
        visible: false
        width: 0
        height: 0

        property string pendingId: ""
        property int holdDelay: 180
        property var dragCard: null
        property string dropTarget: ""
        property string dropHover: ""
        property string dropSame: ""

        readonly property var categoryNames: ["none", "urgent", "important", "necessary", "optional"]
        function categoryLabel(value) {
            if (!value || value < 1)
                return "";
            return "C" + value + "-" + categoryNames[value].toUpperCase();
        }

        function registerDrop() {}
        function beginDrag() {}
        function updateDrag() {}
        function finishDrag() {}
        function cancelDrag() {}

        // The two the lane actually talks to: dismissing the sheet, and asking
        // for a task to be shown in it.
        function closePreview() {
            root.dismisses += 1;
        }
        function requestPreview(id) {
            root.lastPreview = id;
        }
        function requestDelete(id) {
            root.lastDelete = id;
        }
    }

    KanbanSection {
        id: section

        objectName: "section"
        x: 0
        y: 0
        width: 286
        height: 500
        appearance: Appearance {}
        panel: fakePanel
        dest: "new"
        title: "TO DO"
        count: 2
        tasks: [
            { id: "t1", title: "First card", status: "ready", priority: 1 },
            { id: "t2", title: "Second card", status: "ready", priority: 0 }
        ]
    }
}
