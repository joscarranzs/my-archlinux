import Quickshell
import Quickshell.Wayland
import QtQuick
import "."

ShellRoot {
    // Tokens live in the generated Appearance next to this file, like every
    // other surface: the frame colour is not a literal any more.
    property Appearance appearance: Appearance {}

    WlrLayershell {
        layer: WlrLayer.Background
        anchors.top: true
        anchors.bottom: true
        anchors.left: true
        anchors.right: true
        // -1 ignores every other surface's exclusive zone. Without it the bar's
        // reserved strip shrinks this surface to 1280x680 at y=40, so the
        // painting stops under the bar.
        exclusiveZone: -1

        Image {
            anchors.fill: parent
            source: "file://" + Quickshell.env("HOME") + "/.wallpapers/current/default-background"
            fillMode: Image.PreserveAspectCrop
        }
    }
}
