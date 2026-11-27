import Quickshell
import Quickshell.Wayland
import QtQuick
import "services"
import "components"
import "."

// On-demand wifi overlay (Quickshell).
//
// Opened by scripts/session/wifi.sh; closes on Esc or a scrim click. Reads the
// radio through Quickshell.Networking (NetworkManager with wpa_supplicant as the
// wifi backend; iwd is retired) and only connects when the user picks a network
// -- there is no auto-connect, no disconnect and no forget anywhere in this panel.
ShellRoot {
    id: root

    Appearance { id: appearance }

    Component.onCompleted: NetworkState.startScanning()
    Component.onDestruction: NetworkState.stopScanning()

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
        WlrLayershell.namespace: "quickshell:wifi"
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
                onClicked: panel.requestClose()
            }
        }

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
