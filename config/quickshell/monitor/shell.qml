import Quickshell
import Quickshell.Wayland
import QtQuick
import "services"
import "components"
import "."

// On-demand monitor overlay (Quickshell).
//
// Opened by scripts/session/monitor.sh; closes on Esc or a scrim click.
// External monitors only: resolution and scale apply hot through
// `hyprctl eval hl.monitor(...)`. The laptop panel is a locked readout and no
// config file is ever written.
ShellRoot {
    id: root

    Appearance { id: appearance }

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
        // screen and the plaque centers on the output.
        exclusiveZone: -1
        WlrLayershell.namespace: "quickshell:monitor"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand

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

        MonitorPanel {
            id: panel

            anchors.centerIn: parent
            appearance: appearance
            onDismissed: Qt.quit()

            Component.onCompleted: requestFocus()
        }
    }
}
