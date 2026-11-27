import QtQuick
import Quickshell
import Quickshell.Services.Notifications
import ".."

// The desktop's notification daemon, hosted by the bar.
//
// Nothing owned org.freedesktop.Notifications on this machine before it, so every
// sender failed at the bus and its message was dropped on the floor. The server
// lives in the bar because the bar is the only surface that is always up.
//
// There is no history and no panel: a notification is a toast, it lives for the
// theme's timeout, then it is answered to the bus and gone. The live notification
// objects stay here, where the toast window can reach them.
//
// A component, not a singleton, for the reason BatteryState is one: inside a
// `pragma Singleton` the D-Bus side does not exist yet when the object is built.
QtObject {
    id: root

    readonly property Appearance look: Appearance {}

    // Advertise only what the toast actually draws. A capability set to true tells
    // senders to stop escaping that part of the message, so body-markup here would
    // render literal tags on screen.
    property NotificationServer server: NotificationServer {
        keepOnReload: true
        bodySupported: true
        bodyMarkupSupported: false
        imageSupported: false
        actionsSupported: false
        onNotification: notification => root.show(notification)
    }

    // Live toasts, oldest first so the stack grows upward from the corner.
    property var popups: []

    // A close handler can arrive again while it is untracking the same object.
    property var closing: ({})

    function show(notification) {
        var key = String(notification.id);
        notification.closed.connect(function () {
            root.forget(key, notification);
        });
        // The server destroys an untracked notification as soon as it is done with
        // it, and a destroyed QObject reads as null in QML: the toast then paints
        // empty and never expires.
        notification.tracked = true;
        var list = [];
        // A notification the server destroyed behind our back reads as null; a
        // dismiss() on it throws inside this handler and leaves the stack stuck.
        for (var i = 0; i < root.popups.length; i++) {
            if (root.popups[i])
                list.push(root.popups[i]);
        }
        list.push(notification);
        while (list.length > root.look.notificationsMaxPopups) {
            var oldest = list.shift();
            if (oldest)
                oldest.dismiss();
        }
        root.popups = list;
    }

    function forget(key, notification) {
        // Untracking re-emits `closed` for the same object while this call is still
        // removing it from the queue. That nested call must be a no-op, or the
        // handler calls itself until the stack blows.
        if (root.closing[key] === true)
            return;
        root.closing[key] = true;
        var list = [];
        var present = false;
        for (var i = 0; i < root.popups.length; i++) {
            if (root.popups[i] !== notification)
                list.push(root.popups[i]);
            else
                present = true;
        }
        if (!present) {
            delete root.closing[key];
            return;
        }
        root.popups = list;
        notification.tracked = false;
        delete root.closing[key];
    }
}
