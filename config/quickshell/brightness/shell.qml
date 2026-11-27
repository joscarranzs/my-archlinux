import Quickshell
import Quickshell.Wayland
import QtQuick
import "services"
import "components"
import "."

// On-demand brightness overlay (Quickshell).
//
// Opened by scripts/session/brightness.sh; closes on Esc or a scrim click.
// Up/Down step the backlight by the theme's token and the slider writes straight
// through to logind, which is the only writable path: the sysfs node is
// root-owned and brightnessctl/light are not installed here.
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
        WlrLayershell.namespace: "quickshell:brightness"
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

        BrightnessPanel {
            id: panel

            anchors.centerIn: parent
            appearance: appearance
            available: Brightness.available
            deviceName: Brightness.deviceName
            glyph: Brightness.glyph
            value: Brightness.value

            onBrightnessRequested: (value) => Brightness.setValue(value)
            onDismissed: Qt.quit()

            Component.onCompleted: requestFocus()
        }
    }
}
