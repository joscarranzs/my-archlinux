import Quickshell
import Quickshell.Wayland
import QtQuick
import "services"
import "components"
import "."

// On-demand kanban panel (Quickshell).
//
// Launched by scripts/session/kanban.sh (a click on the task icon in the bar),
// closed by Esc or a scrim click. R re-runs the helper instead of waiting for
// the next 30 s tick.
ShellRoot {
    id: root

    Appearance { id: appearance }

    KanbanFeed {
        id: feed
    }

    PanelWindow {
        id: window

        anchors {
            top: true
            bottom: true
            left: true
            right: true
        }
        color: "transparent"

        // -1 ignores the bar's reserved strip, so the scrim covers the whole
        // screen and the plaque centers on the output, not on the usable area.
        exclusiveZone: -1
        WlrLayershell.namespace: "quickshell:kanban"
        WlrLayershell.layer: WlrLayer.Overlay
        // Exclusive, not OnDemand: OnDemand lets the compositor decide, and when
        // it does not hand the focus over, Esc travels to the window underneath
        // and the user closes whatever was behind the panel. The scrim already
        // covers the screen, so the panel is modal and must own the keyboard.
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive

        // Scrim: dismiss on click outside the plaque.
        Rectangle {
            anchors.fill: parent
            color: Qt.rgba(0, 0, 0, appearance.scrimOpacity)
            // The scrim rides the plaque's entrance: one driver, so a slow first frame
            // cannot present the backdrop without the plaque in front of it.
            opacity: panel.opacity

            MouseArea {
                anchors.fill: parent
                onClicked: Qt.quit()
            }
        }

        KanbanPanel {
            id: panel

            anchors.centerIn: parent
            appearance: appearance
            feed: feed

            onDismissRequested: Qt.quit()
            onRefreshRequested: feed.refresh()

            Component.onCompleted: requestFocus()
        }
    }
}
