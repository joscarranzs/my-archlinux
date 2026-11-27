import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Services.Notifications
import ".."
import "."

// One toast, built on the shared card: the sender's own icon in the tile, the app
// name as the title, the arrival time as the chip, and the message under it.
//
// The card is read the way a panel card is read -- identity first, then the
// message -- so the two rungs of the message are two rungs apart. The headline
// takes the title voice (17) because the message is what the toast exists to say,
// and the body drops to the caption voice (12) under it: at 14 and 11 the two
// lines read as one paragraph with the app name shouting over both. The identity
// takes the card's own tile and mark rungs, undecorated: 36 px of plate around a
// 22 px mark, which is the rung a logo stays a logo at.
//
// The mark is the *sender's* icon, and getting one is not a string lookup: Qt's
// own theme resolution cannot report a miss (see `appIconPath`), so the question
// goes to a helper that looks for the file and answers with a path or with
// nothing. Nothing is a real answer here -- it is what puts the urgency glyph in
// the tile instead of a broken-image placeholder.
//
// The type is carried twice, and neither is a wash: the card's edge takes the
// urgency (danger for critical, the plaque's gilt for normal, the system hairline
// for low) and its mark takes the urgency colour when the sender names no icon of
// its own. Critical and error messages also carry a copy button: the text is gone
// in five seconds, so the error has to be capturable while it is on screen.
//
// The edge is the plaque's recipe -- look.borders.width, one pixel -- with the role
// swapped by type: one material, three values, never a second frame.
// Entry and exit slide horizontally, both out of theme tokens.
Item {
    id: root

    property Appearance appearance: Appearance {}
    property var notification: null

    // Arrival time, for the card's chip: the notification API carries no timestamp,
    // and a toast that says when it arrived is the one thing this panel can add.
    property string clockLabel: ""

    // The sender's expire_timeout is ignored on purpose: every toast gets the same
    // five seconds, normal and critical alike, then it slides out and dies.
    readonly property int lifetimeMs: root.appearance.notificationsTimeoutMs

    readonly property int urgency: root.notification ? root.notification.urgency : NotificationUrgency.Normal
    readonly property string urgencyIcon: root.urgency === NotificationUrgency.Critical ? "priority_high" : "notifications"
    readonly property color urgencyColor: root.urgency === NotificationUrgency.Critical ? root.appearance.danger
        : (root.urgency === NotificationUrgency.Normal ? root.appearance.accentInk : root.appearance.textMuted)

    // An application can send an error at Normal urgency. Match the text as well so
    // "something broke" is copyable even when the sender forgot to shout.
    readonly property bool errorText: {
        if (!root.notification)
            return false;
        var text = String(root.notification.summary) + " " + String(root.notification.body);
        return /\b(error|failed|failure|exception|panic|traceback|fatal|fallo|falló)\b/i.test(text);
    }
    readonly property bool showCopy: root.urgency === NotificationUrgency.Critical || root.errorText

    // Who sent it: the application's own icon, as a file this desktop can draw.
    //
    // The string the sender hands over is not a path, and Qt's theme lookup cannot
    // report a miss -- `Quickshell.iconPath()` always answers `image://icon/<name>`,
    // with or without a fallback, so an unresolvable name paints the image
    // provider's broken placeholder and QML has no way to tell that from a real
    // icon. The question therefore goes to the one thing that can answer it: a
    // helper that looks for the file itself -- as a path, as a name in every
    // installed theme, and as the `Icon=` of the `.desktop` entry the app name
    // names -- and prints nothing when there is none. Empty is the answer that lets
    // the card fall back to its glyph, so a missing icon degrades to the urgency
    // mark instead of to a broken image.
    property string appIconPath: ""

    // Which notification the current answer belongs to. The stack reuses a popup
    // for a later arrival as soon as an earlier one leaves, so an answer that lands
    // after the popup has moved on is dropped rather than worn by the wrong toast.
    property var iconResolvedFor: null

    // There is an answer in flight. The card holds its plate empty while this is
    // true: without it the tile paints the urgency glyph at full strength and swaps
    // it for the icon ~125 ms later, which a grim burst caught (the entrance is
    // over by then, so the first frame is not a faded ghost). It is cleared by the
    // helper's answer, or by the deadline below when the helper never answers.
    property bool iconPending: false

    // The type of the notification, carried by the card's edge: a critical toast is
    // framed in danger, a normal one keeps the plaque's gilt, and a low one is a
    // hairline -- quiet by design, still a card. One edge, three values.
    readonly property color edgeColor: root.urgency === NotificationUrgency.Critical
        ? root.appearance.danger
        : (root.urgency === NotificationUrgency.Normal ? root.appearance.gilt : root.appearance.outline)

    // The type in words, for the one case where a word earns its place.
    readonly property string typeLabel: root.urgency === NotificationUrgency.Critical ? "CRITICAL"
        : (root.urgency === NotificationUrgency.Low ? "LOW" : "")

    property bool leaving: false
    property bool entered: false
    property bool copied: false

    // Review hooks: this host has no pointer automation (no ydotool), so a preview
    // forces the state it wants to judge instead of asking the user to keep the
    // pointer on a five-second toast while a capture runs. Same hooks as the bar's
    // clock and status items.
    property bool forceHover: false
    property bool forcePressed: false
    readonly property bool copyHovered: root.forceHover || copyArea.containsMouse
    readonly property bool copyHeld: root.forcePressed || copyArea.pressed

    // A notification the server destroyed behind our back reads as null here, and an
    // index past the end of the stack's array reads as undefined -- `!== null` lets
    // undefined through and leaves an empty plaque in the corner.
    visible: !!root.notification

    width: root.appearance.notificationsWidth
    height: card.implicitHeight

    // The toast is a card now, with the two things a toast keeps of its own: the
    // plaque's gilt edge (it arrives over the desktop, it is not a block sitting on
    // a well) and the urgency colour on its mark. Tile and mark take the card's own
    // rungs -- `fieldHeight` plate, `iconSizeMd` mark -- because a toast's identity
    // *is* the app that sent it, and the rung the launcher draws a tile at is what
    // makes a logo read as a logo.
    PanelCard {
        id: card

        // Findable by name: the urgency a toast carries lives on this card's edge,
        // and a harness has to read the edge it is framed with, not a property that
        // merely claims it.
        objectName: "toast-card"

        anchors.fill: parent
        appearance: root.appearance
        title: root.notification ? root.notification.appName : ""
        // The app's icon, with the urgency glyph as the fallback the card shows only
        // while the image is not on screen: an icon file that exists but fails to
        // decode leaves a toast with no face at all, which is what this prevents.
        glyph: root.urgencyIcon
        imageSource: root.appIconPath
        markPending: root.iconPending
        titleSize: root.appearance.fontSizeSmall
        markColor: root.urgencyColor
        chipText: root.typeLabel !== "" ? root.typeLabel + " · " + root.clockLabel : root.clockLabel
        chipColor: root.urgencyColor
        chipDot: root.urgency === NotificationUrgency.Critical
        edgeColor: root.edgeColor
        edgeWidth: root.appearance.borderWidth

        // Clicking the toast means "seen": same slide-out as the timer.
        onClicked: root.close()

        // What the sender said, in the title voice: the message is the card's
        // subject, and one rung above the body is what says so without a second ink.
        Text {
            Layout.fillWidth: true
            visible: text.length > 0
            text: root.notification ? root.notification.summary : ""
            color: root.appearance.textBright
            wrapMode: Text.WordWrap
            maximumLineCount: 2
            elide: Text.ElideRight
            font.family: root.appearance.uiFont
            font.weight: root.appearance.fontWeightUi
            font.variableAxes: root.appearance.fontVariableAxesUi
            font.pixelSize: root.appearance.fontSizeTitle
            font.bold: true
        }

        // The detail under it: paths, versions, the actual error line. The caption
        // rung is the one this desktop gives metadata that sits under a headline.
        Text {
            Layout.fillWidth: true
            visible: text.length > 0
            text: root.notification ? root.notification.body : ""
            color: root.appearance.textMuted
            wrapMode: Text.WordWrap
            maximumLineCount: 3
            elide: Text.ElideRight
            font.family: root.appearance.uiFont
            font.weight: root.appearance.fontWeightUi
            font.variableAxes: root.appearance.fontVariableAxesUi
            font.pixelSize: root.appearance.fontSizeCaption
        }

        // Copy target for critical and error messages. It is a row of its own, so a
        // click here copies instead of dismissing the toast, and the message is gone
        // in five seconds either way.
        //
        // The target is a button and not a bare glyph: at `iconSizeSm` the hit area
        // was 18 px, under the rung where a target stops lying about its size. It
        // wears the desktop's one hover recipe -- the fill steps up to `hoverFill`
        // and the edge ignites `gilt`, then the fill steps back down to `pressFill`
        // while held -- so the only control in a toast behaves like every other
        // target on this desktop.
        RowLayout {
            objectName: "copy-row"

            Layout.fillWidth: true
            visible: root.showCopy

            Item { Layout.fillWidth: true }

            Rectangle {
                objectName: "copy-button"

                Layout.preferredWidth: root.appearance.iconButtonSize
                Layout.preferredHeight: root.appearance.iconButtonSize
                radius: root.appearance.radius
                color: root.copyHeld
                    ? root.appearance.pressFill
                    : (root.copyHovered ? root.appearance.hoverFill : "transparent")
                border.width: root.appearance.borderWidth
                border.color: root.copyHovered || root.copyHeld ? root.appearance.gilt : "transparent"

                Behavior on color {
                    ColorAnimation {
                        duration: root.copyHeld ? root.appearance.motionPressDuration : root.appearance.motionControlDuration
                        easing: root.appearance.motionControlEasing
                    }
                }
                Behavior on border.color {
                    ColorAnimation {
                        duration: root.appearance.motionControlDuration
                        easing: root.appearance.motionControlEasing
                    }
                }

                MaterialIcon {
                    anchors.centerIn: parent
                    icon: root.copied ? "check" : "content_copy"
                    iconSize: root.appearance.iconSizeSm
                    iconColor: root.copied ? root.appearance.accentInk : root.appearance.textMuted
                }

                Accessible.name: "Copy message"
                Accessible.role: Accessible.Button

                MouseArea {
                    id: copyArea

                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.copyMessage()
                }
            }
        }
    }

    // One handler, not two: a second `onNotificationChanged` in the same object
    // replaces the first, which is how the chip's clock went missing.
    onNotificationChanged: {
        if (root.notification)
            root.clockLabel = Qt.formatTime(new Date(), "HH:mm");
        root.resolveIcon();
        if (!root.notification || root.entered)
            return;
        root.entered = true;
        root.x = root.width;
        root.opacity = 0;
        enter.start();
    }

    // The icon is asked for once per notification, not once per popup: the stack
    // re-binds a live popup to a later arrival, and a popup that re-resolved on
    // every change would spawn a helper for every toast already on screen.
    function resolveIcon() {
        root.appIconPath = "";
        root.iconResolvedFor = root.notification;
        iconDeadline.stop();
        if (!root.notification) {
            root.iconPending = false;
            return;
        }
        var icon = String(root.notification.appIcon);
        var appName = String(root.notification.appName);
        if (icon === "" && appName === "") {
            // Nothing to ask: no icon string and no application name to look one up
            // by, so the glyph is the answer and there is nothing to wait for.
            root.iconPending = false;
            return;
        }
        root.iconPending = true;
        iconDeadline.restart();
        iconResolver.forNotification = root.notification;
        iconResolver.running = true;
    }

    function close() {
        if (!root.notification || root.leaving)
            return;
        root.leaving = true;
        leave.start();
    }

    function copyMessage() {
        if (!root.notification)
            return;
        var summary = String(root.notification.summary);
        var body = String(root.notification.body);
        Quickshell.clipboardText = [summary, body].filter(part => part.length > 0).join("\n");
        root.copied = true;
        copyFeedback.restart();
    }

    // The one process this panel runs, and it runs on arrival only. It answers with
    // an absolute path on its own line, or with nothing at all.
    Process {
        id: iconResolver

        property var forNotification: null

        command: [
            "/usr/bin/python3",
            Quickshell.env("HOME") + "/.scripts/session/notify-icon.py",
            "--icon", root.notification ? String(root.notification.appIcon) : "",
            "--app-name", root.notification ? String(root.notification.appName) : "",
        ]
        stdout: StdioCollector {
            onStreamFinished: {
                if (root.iconResolvedFor !== iconResolver.forNotification)
                    return;
                root.appIconPath = text.trim();
                root.iconPending = false;
                iconDeadline.stop();
            }
        }
    }

    // The helper is a process, and a process can stall. Past this the plate stops
    // waiting and wears the glyph: a toast with no mark at all is worse than one
    // whose mark arrived late.
    Timer {
        id: iconDeadline

        interval: 300
        onTriggered: root.iconPending = false
    }

    // One shot, no hover pause: the toast dies at five seconds no matter where the
    // pointer sits, and the exit is the animation below, never a hard removal.
    Timer {
        interval: root.lifetimeMs
        running: !!root.notification && !root.leaving
        onTriggered: root.close()
    }

    Timer {
        id: copyFeedback

        interval: 900 // how long the check glyph stays after a copy
        onTriggered: root.copied = false
    }

    ParallelAnimation {
        id: enter

        NumberAnimation {
            target: root
            property: "x"
            to: 0
            duration: root.appearance.motionControlDuration
            easing: root.appearance.motionControlEasing
        }
        NumberAnimation {
            target: root
            property: "opacity"
            to: 1
            duration: root.appearance.motionControlDuration
            easing: root.appearance.motionControlEasing
        }
    }

    ParallelAnimation {
        id: leave

        NumberAnimation {
            target: root
            property: "x"
            to: root.width
            duration: root.appearance.notificationsSlideMs
            easing: root.appearance.motionControlEasing
        }
        NumberAnimation {
            target: root
            property: "opacity"
            to: 0
            duration: root.appearance.notificationsSlideMs
            easing: root.appearance.motionControlEasing
        }
        onFinished: {
            if (root.notification)
                root.notification.dismiss();
        }
    }
}
