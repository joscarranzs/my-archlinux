import QtQuick
import Quickshell
import "."

// Preview: the bar over the real wallpaper, at the desktop's logical width.
// The strip only: the notification daemon and its toasts live in bar/shell.qml,
// not in Bar, so the preview does not instantiate them (a second daemon could
// not register the bus name anyway while the live bar owns it).
ShellRoot {
    Appearance {
        id: appearance
    }

    FloatingWindow {
        id: window

        implicitWidth: 1280
        implicitHeight: 240
        color: appearance.surface

        Image {
            anchors.fill: parent
            source: "file://" + Quickshell.env("HOME") + "/.wallpapers/current/default-background"
            fillMode: Image.PreserveAspectCrop
        }

        Bar {
            x: appearance.margin
            y: appearance.margin
            width: window.width - 2 * appearance.margin
            height: appearance.height
            appearance: appearance
        }

        onClosed: Qt.quit()
    }
}