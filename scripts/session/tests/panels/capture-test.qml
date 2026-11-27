import QtQuick
import Quickshell
import "@URL@/components"
import "@URL@"

// One offscreen grab per card surface. The panel sets its own width and height
// (some from a token, some from its content), so the harness only centers it;
// forcing a size here would capture a plaque the desktop never draws.
ShellRoot {
    id: root

    property string capturePath: "@OUT@"

    Window {
        width: 900
        height: 900
        visible: true
        color: "transparent"

        Item {
            anchors.fill: parent

            @PANEL@ {
                id: panel
                anchors.centerIn: parent
                @SIZE@
            }
        }
    }

    Timer {
        interval: 600
        running: true
        onTriggered: {
            console.log("CAPTURE " + panel.objectName + " " + panel.width + "x" + panel.height);
            panel.grabToImage(function (result) {
                if (result !== null && result.saveToFile(root.capturePath))
                    console.log("RESULT saved=" + root.capturePath);
                else
                    console.log("RESULT saved=none");
                Qt.quit();
            });
        }
    }

    Timer {
        interval: 8000
        running: true
        onTriggered: Qt.quit()
    }
}
