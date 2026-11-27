import Quickshell
import Quickshell.Wayland
import QtQuick
import "components"
import "."

// On-demand web app creator (Quickshell).
// Launched by scripts/session/webapp.sh; closes on Esc, scrim click, or after
// creating the entry. Closing keeps the draft for the rest of the session.
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
        // screen and the panel centers on the output, not on the usable area.
        exclusiveZone: -1
        WlrLayershell.namespace: "quickshell:webapp"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand

        // Scrim: dismiss on click outside the panel (the draft is kept).
        Rectangle {
            anchors.fill: parent
            color: Qt.rgba(0, 0, 0, appearance.scrimOpacity)

            MouseArea {
                anchors.fill: parent
                onClicked: form.dismiss()
            }
        }

        WebAppForm {
            id: form
            anchors.centerIn: parent
            appearance: appearance
            onFinished: Qt.quit()
        }
    }
}
