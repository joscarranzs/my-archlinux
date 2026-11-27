import Quickshell
import Quickshell.Wayland
import QtQuick
import "services"
import "components"
import "."

// On-demand volume overlay (Quickshell).
//
// Opened by scripts/session/volume.sh; closes on Esc or a scrim click. Up/Down
// step the level by the theme's token, M toggles mute, the glyph is the mute
// button and the slider writes straight through to PipeWire.
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
        WlrLayershell.namespace: "quickshell:volume"
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

        VolumePanel {
            id: panel

            anchors.centerIn: parent
            appearance: appearance
            available: AudioOutput.available
            deviceName: AudioOutput.deviceName
            glyph: AudioOutput.glyph
            percent: AudioOutput.percent
            value: AudioOutput.volume
            muted: AudioOutput.muted

            onVolumeRequested: (value) => AudioOutput.setVolume(value)
            onMuteToggled: AudioOutput.toggleMute()
            onDismissed: Qt.quit()

            Component.onCompleted: requestFocus()
        }
    }
}
