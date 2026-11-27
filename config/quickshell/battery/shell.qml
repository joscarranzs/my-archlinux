import Quickshell
import Quickshell.Wayland
import QtQuick
import "services"
import "components"
import "."

// On-demand battery panel (Quickshell).
//
// Launched by scripts/session/battery.sh (a click on the pack glyph in the bar),
// closed by Esc or a scrim click. Nothing to refresh: upower pushes every change
// over D-Bus, so the plaque follows a charger being plugged in while it is open.
ShellRoot {
    id: root

    Appearance { id: appearance }

    BatteryState {
        id: battery
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
        WlrLayershell.namespace: "quickshell:battery"
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

        BatteryPanel {
            id: panel

            anchors.centerIn: parent
            appearance: appearance
            battery: battery

            onDismissRequested: Qt.quit()

            Component.onCompleted: requestFocus()
        }
    }
}
