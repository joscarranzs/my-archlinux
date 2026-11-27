import Quickshell
import QtQuick
import "services"
import "components"
import "."

// Preview the wifi panel in a floating window (no compositor layer-shell needed).
ShellRoot {
    id: root

    Appearance { id: appearance }

    Component.onCompleted: NetworkState.startScanning()

    FloatingWindow {
        implicitWidth: appearance.panelWidth + appearance.spacingMedium * 2
        implicitHeight: panel.height + appearance.spacingMedium * 2
        title: "Wifi preview"

        Rectangle {
            anchors.fill: parent
            color: appearance.surface

            WifiPanel {
                id: panel

                anchors.centerIn: parent
                appearance: appearance

                onConnectRequested: (network, passphrase) => NetworkState.connectNetwork(network, passphrase)
                onDismissed: Qt.quit()

                Component.onCompleted: requestFocus()
            }
        }
    }

    Connections {
        target: Quickshell
        function onLastWindowClosed() { Qt.quit() }
    }
}
