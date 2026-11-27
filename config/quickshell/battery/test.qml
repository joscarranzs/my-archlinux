import Quickshell
import QtQuick
import "services"
import "components"
import "."

// Preview the battery panel in a floating window (no compositor layer-shell).
ShellRoot {
    id: root

    Appearance { id: appearance }

    BatteryState {
        id: battery
    }

    FloatingWindow {
        implicitWidth: panel.width + appearance.spacingMedium * 2
        implicitHeight: panel.height + appearance.spacingMedium * 2
        title: "Battery panel preview"

        Rectangle {
            anchors.fill: parent
            color: appearance.surface

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

    Connections {
        target: Quickshell
        function onLastWindowClosed() { Qt.quit() }
    }
}
