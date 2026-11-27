import QtQuick
import Quickshell
import "@URL@/kanban/components"

// Empty and error, forced through the panel's own `feed` property: a board with
// no tasks at all, and a feed that cannot reach its backend.
//
// The empty lane is the state this suite found missing: with no cards the column
// header floated over nothing and the lane read as still loading.
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

    function collect(item, name, found) {
        if (item.objectName === name)
            found.push(item);
        for (let i = 0; i < item.children.length; i += 1)
            root.collect(item.children[i], name, found);
        return found;
    }

    function byText(item, text, found) {
        if (item.text !== undefined && item.text === text)
            found.push(item);
        for (let i = 0; i < item.children.length; i += 1)
            root.byText(item.children[i], text, found);
        return found;
    }

    QtObject {
        id: stubFeed

        property var tasks: []
        property string error: ""
        property bool parsingFailed: false
        property bool busy: false
    }

    Window {
        width: 1240
        height: 560
        visible: true

        KanbanPanel {
            id: panel
            anchors.centerIn: parent
            feed: stubFeed
        }
    }

    Timer {
        interval: 500
        running: true
        onTriggered: {
            const lanes = root.collect(panel, "section-empty", []);
            const sections = root.collect(panel, "kanban-section-", []);
            root.check("every lane carries an empty line", lanes.length >= 3, lanes.length);
            root.check("every empty lane line is visible",
                lanes.every(function(line) { return line.visible; }), lanes.length);
            root.check("the empty lane line is muted ink, not opacity",
                lanes.length > 0 && lanes.every(function(line) {
                    return line.opacity === 1
                        && Qt.colorEqual(line.color, panel.appearance.textMuted);
                }), lanes.length);
        }
    }

    Timer {
        interval: 700
        running: true
        onTriggered: {
            stubFeed.error = "the kanban backend is not running";
        }
    }

    Timer {
        interval: 900
        running: true
        onTriggered: {
            const line = root.byText(panel, "the kanban backend is not running", []);
            root.check("a dead backend is reported", line.length === 1, line.length);
            if (line.length === 1) {
                root.check("a feed error takes the alert ink",
                    Qt.colorEqual(line[0].color, panel.appearance.danger), line[0].color);
            }

            console.log("RESULT pass=" + root.pass + " fail=" + root.fail);
            Qt.quit();
        }
    }

    Timer {
        interval: 6000
        running: true
        onTriggered: Qt.quit()
    }
}
