import QtQuick
import Quickshell
import "components"
import "."

// Floating preview of the monitor plaque: same content as the overlay, no
// layer-shell, so it can be checked without the compositor's overlay layer.
ShellRoot {
    id: root

    Appearance { id: appearance }

    FloatingWindow {
        id: preview

        implicitWidth: appearance.panelWidth + appearance.contentPad * 2
        implicitHeight: 620
        title: "Monitor preview"
        onClosed: Qt.quit()

        Rectangle {
            anchors.fill: parent
            color: appearance.surface

            MonitorPanel {
                anchors.centerIn: parent
                appearance: appearance
                onDismissed: Qt.quit()

                Component.onCompleted: requestFocus()
            }
        }
    }
}
