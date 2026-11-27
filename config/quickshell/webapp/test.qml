import Quickshell
import QtQuick
import "components"
import "."

// Preview the web app creator in a floating window (no layer-shell needed).
ShellRoot {
    id: root

    // Typed and defaulted: the form binding below reads this on creation, and
    // a bare `Appearance { id: appearance }` is not a property of root, so the
    // binding logged "Unable to assign [undefined] to Appearance*" on start.
    property Appearance appearance: Appearance {}

    FloatingWindow {
        implicitWidth: appearance.panelWidth + appearance.spacingLarge * 2
        implicitHeight: form.implicitHeight + appearance.spacingLarge * 2
        title: "Web app preview"

        Rectangle {
            anchors.fill: parent
            color: appearance.surface

            WebAppForm {
                id: form
                anchors.centerIn: parent
                appearance: root.appearance
                onFinished: console.log("preview: finished")
            }
        }
    }

    Connections {
        target: Quickshell
        function onLastWindowClosed() { Qt.quit() }
    }
}
