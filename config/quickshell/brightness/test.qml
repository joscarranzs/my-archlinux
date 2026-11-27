import Quickshell
import QtQuick
import "services"
import "components"
import "."

// Preview the brightness panel in a floating window (no compositor layer-shell needed).
ShellRoot {
    id: root

    Appearance { id: appearance }

    FloatingWindow {
        implicitWidth: appearance.panelWidth + appearance.spacingMedium * 2
        implicitHeight: appearance.panelHeight + appearance.spacingMedium * 2
        title: "Brightness preview"

        Rectangle {
            anchors.fill: parent
            color: appearance.surface

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

    Connections {
        target: Quickshell
        function onLastWindowClosed() { Qt.quit() }
    }
}
