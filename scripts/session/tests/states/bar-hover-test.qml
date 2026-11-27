import QtQuick
import Quickshell
import "@URL@/bar"
import "@URL@/bar/components"

// The bar's hover geometry, forced: every interactive cell has a review hook that
// paints the hover veil without a pointer, so the box it lights can be measured
// against the strip it sits in. This is the regression that matters -- the veil is
// `anchors.fill` on its cell, so a cell as tall as the bar lights a rectangle that
// butts against both of the bar's edges and reads as if it spilled out of it.
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

    Appearance {
        id: appearance
    }

    Window {
        // A proportion of the strip, not a chosen width: the harness only needs a
        // canvas wider than the two cells it pins to the edges.
        width: appearance.height * 15
        height: appearance.height
        visible: true
        color: "transparent"

        Rectangle {
            id: strip
            anchors.fill: parent
            color: appearance.surface

            BarClock {
                id: clock
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                appearance: appearance
                forceHover: true
            }

            StatusItem {
                id: icon
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                appearance: appearance
                icon: "volume_up"
                interactive: true
                forceHover: true
            }
        }
    }

    Timer {
        interval: 700
        running: true
        onTriggered: {
            const cell = appearance.contentHeight;
            root.check("the cell leaves the bar its padding",
                cell === appearance.height - appearance.barBorder - appearance.padY * 2,
                cell + " in " + appearance.height);
            root.check("the bar keeps a padding at all", appearance.padY > 0, appearance.padY);
            root.check("the clock cell is that height", clock.height === cell, clock.height);
            root.check("the status cell is that height", icon.height === cell, icon.height);
            root.check("no cell is taller than the strip", Math.max(clock.height, icon.height) < appearance.height);
            console.log("RESULT pass=" + root.pass + " fail=" + root.fail);
            Qt.quit();
        }
    }

    Timer {
        interval: 4000
        running: true
        onTriggered: Qt.quit()
    }
}
