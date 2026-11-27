import QtQuick
import ".."
import "."

// The toast stack.
//
// Newest first, so a new notification lands in the top corner and pushes the rest
// down: the newest is always the one closest to the top-right corner. The window
// around this column is sized to it, so the stack grows from the corner downward.
Column {
    id: root

    property Appearance appearance: Appearance {}
    property var notifications: null

    readonly property var popups: root.notifications ? root.notifications.popups : []

    width: root.appearance.notificationsWidth
    spacing: root.appearance.notificationsGap

    // Indexed, not `model: root.popups`: with an array model the delegate gets the
    // element injected as `modelData`, and a delegate that reads nothing but its own
    // `notification` renders empty when that injection does not happen. Reading the
    // element out of the array by index is the same list with one fewer invisible
    // contract.
    Repeater {
        model: root.popups.length

        delegate: NotificationPopup {
            required property int index

            appearance: root.appearance
            notification: root.popups[root.popups.length - 1 - index]
        }
    }
}
