import QtQuick
import ".."

// Workspace dots: the active one is a gold pill, a workspace holding windows is
// a firm dot, an unused one is a faint dot. Clicking a dot switches to it. The
// pill morphs between slots — width and tone animate, so the row slides instead
// of snapping.
Row {
    id: root

    property Appearance appearance: Appearance {}
    property int count: 5
    property int active: 1
    property var occupied: []

    signal selected(int workspace)

    height: appearance.contentHeight
    spacing: appearance.itemGap

    function hasWindows(id) {
        for (let i = 0; i < occupied.length; i++) {
            if (occupied[i] === id) {
                return true;
            }
        }
        return false;
    }

    Repeater {
        model: root.count

        delegate: Item {
            required property int index

            readonly property int workspace: index + 1
            readonly property bool isActive: workspace === root.active
            readonly property bool hasWindows: root.hasWindows(workspace)

            width: isActive ? root.appearance.dotActiveWidth : root.appearance.dotSize
            height: root.height

            // On the delegate, not on the dot: the Row reflows as this animates,
            // which is what makes the neighbouring dots slide with it.
            Behavior on width {
                NumberAnimation {
                    duration: root.appearance.motionWorkspaceDuration
                    easing: root.appearance.motionWorkspaceEasing
                }
            }

            Rectangle {
                anchors.verticalCenter: parent.verticalCenter
                width: parent.width
                height: root.appearance.dotSize
                radius: height / 2
                color: parent.isActive ? root.appearance.accent
                    : (parent.hasWindows ? root.appearance.textMuted : root.appearance.textFaint)
                // No opacity here: on paper a dimmed dot drops to 1.6:1 and reads as
                // a missing element. The three states are three inks instead —
                // gold fill, firm ink, quiet ink — which is one step each.

                Behavior on color {
                    ColorAnimation {
                        duration: root.appearance.motionWorkspaceDuration
                        easing: root.appearance.motionWorkspaceEasing
                    }
                }

                Behavior on opacity {
                    NumberAnimation {
                        duration: root.appearance.motionWorkspaceDuration
                        easing: root.appearance.motionWorkspaceEasing
                    }
                }
            }

            // A 6 px dot is a cruel click target: the hit area grows by a token.
            MouseArea {
                anchors.fill: parent
                anchors.margins: -root.appearance.dotHitPad
                cursorShape: Qt.PointingHandCursor
                onClicked: root.selected(parent.workspace)
            }
        }
    }
}
