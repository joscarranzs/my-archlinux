import QtQuick
import Quickshell
import "."

// Preview the wallpaper surface in a floating window (no layer-shell needed).
ShellRoot {
    property Appearance appearance: Appearance {}

    FloatingWindow {
        implicitWidth: 960
        implicitHeight: 540
        title: "Wallpaper preview"

        Image {
            anchors.fill: parent
            source: "file://" + Quickshell.env("HOME") + "/.wallpapers/current/default-background"
            fillMode: Image.PreserveAspectCrop
            cache: false
        }

        // Subtle gold hairline frame around the painting (gallery look),
        // same treatment as the real wallpaper surface.
        Rectangle {
            anchors.fill: parent
            anchors.margins: appearance.hairline
            color: "transparent"
            border.color: appearance.frameLine
            border.width: appearance.hairline
        }
    }

    Connections {
        target: Quickshell
        function onLastWindowClosed() { Qt.quit() }
    }
}
