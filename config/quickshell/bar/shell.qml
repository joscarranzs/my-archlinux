import QtQuick
import Quickshell
import Quickshell.Wayland
import "services"
import "components"
import "."

ShellRoot {
    Appearance {
        id: appearance
    }

    // The daemon belongs to the process, not to the strip: the toast window is a
    // second surface in this same process and reads the same live notifications.
    Notifications {
        id: notifications
    }

    PanelWindow {
        id: panel

        anchors.top: true
        anchors.left: true
        anchors.right: true
        margins.top: appearance.margin
        margins.left: appearance.margin
        margins.right: appearance.margin

        implicitHeight: appearance.height
        exclusiveZone: appearance.height
        color: "transparent"

        WlrLayershell.layer: WlrLayer.Top
        WlrLayershell.namespace: "quickshell:bar"

        Bar {
            anchors.fill: parent
            appearance: appearance
        }
    }

    // Toasts, top right, one offset below the bar that now owns that edge. Sized
    // to the stack, so with nothing to show the surface is zero-height and draws
    // nothing. It never takes focus: a notification must not pull the keyboard
    // out of what the user is typing into.
    PanelWindow {
        id: toastWindow

        anchors.top: true
        anchors.right: true
        margins.top: appearance.height + appearance.notificationsOffset
        margins.right: appearance.notificationsOffset

        color: "transparent"
        // -1: ignore the strips other surfaces reserve, so the toasts hug the real
        // screen corner; Ignore: reserve nothing for a surface that floats.
        exclusiveZone: -1
        exclusionMode: ExclusionMode.Ignore
        focusable: false

        implicitWidth: appearance.notificationsWidth
        implicitHeight: stack.implicitHeight

        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "quickshell:notifications"
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

        NotificationPopups {
            id: stack

            appearance: appearance
            notifications: notifications
        }
    }
}