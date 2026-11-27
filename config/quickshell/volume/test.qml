import Quickshell
import QtQuick
import "services"
import "components"
import "."

// Preview the volume panel in a floating window (no compositor layer-shell needed).
ShellRoot {
    id: root

    Appearance { id: appearance }

    FloatingWindow {
        implicitWidth: appearance.panelWidth + appearance.spacingMedium * 2
        implicitHeight: appearance.panelHeight + appearance.spacingMedium * 2
        title: "Volume preview"

        Rectangle {
            anchors.fill: parent
            color: appearance.surface

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

    Connections {
        target: Quickshell
        function onLastWindowClosed() { Qt.quit() }
    }
}
