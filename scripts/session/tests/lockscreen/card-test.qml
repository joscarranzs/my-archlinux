import QtQuick
import Quickshell
import "@URL@/components"
import "@URL@/services"

// Offscreen harness for the unlock card's state machine and its ink.
//
// The card is instantiated whole, with the real LockContext, because what broke
// twice was the wiring rather than the layout: a label dimmed with opacity
// instead of a step of ink, and a card that could stay disabled and reading
// VERIFYING... forever because nothing cleared the in-progress flag. Both are
// assertions, not screenshots.
//
// PAM is never started here: the harness drives the context's own properties, so
// no password is ever offered to a real service.
ShellRoot {
    id: root

    property int pass: 0
    property int fail: 0

    LockContext {
        id: context
    }

    Window {
        width: 480
        height: 440
        visible: true
        color: "transparent"

        LockCard {
            id: card

            anchors.centerIn: parent
            context: context
        }
    }

    function check(name, condition, detail) {
        if (condition) {
            root.pass += 1;
            console.log("PASS " + name);
        } else {
            root.fail += 1;
            console.log("FAIL " + name + " :: " + (detail === undefined ? "" : detail));
        }
    }

    function named(item, name) {
        if (item.objectName === name)
            return item;
        for (let i = 0; i < item.children.length; i += 1) {
            const hit = root.named(item.children[i], name);
            if (hit !== null)
                return hit;
        }
        return null;
    }

    readonly property var passwordLabel: root.named(card, "passwordLabel")
    readonly property var statusText: root.named(card, "statusText")
    readonly property var unlockButton: root.named(card, "unlockButton")

    Component.onCompleted: {
        root.check("the card built its nodes", root.passwordLabel !== null
            && root.statusText !== null && root.unlockButton !== null);

        // Ink, not opacity: the label reads as ink at 7.66:1 on the card. A
        // re-added `opacity: 0.55` composites it to 3.43:1 and fails here.
        root.check("the PASSWORD label is not dimmed with opacity",
            root.passwordLabel.opacity === 1, root.passwordLabel.opacity);
        root.check("the PASSWORD label uses the muted ink",
            Qt.colorEqual(root.passwordLabel.color, card.appearance.textMuted));
        root.check("the status line is not dimmed with opacity",
            root.statusText.opacity === 1, root.statusText.opacity);

        // Idle: nothing to say, and the slot says nothing.
        root.check("an idle status is silent", root.statusText.text === "", root.statusText.text);

        // Resting button: the control's own fill, not the accent.
        root.check("an empty field leaves the button unarmed", !root.unlockButton.armed);
        root.check("an unarmed button rests on surfaceContainerHigh",
            Qt.colorEqual(root.unlockButton.color, card.appearance.surfaceContainerHigh));
    }

    Timer {
        interval: 250
        running: true
        onTriggered: {
            context.currentText = "x";
            root.check("a typed character arms the button", root.unlockButton.armed);
        }
    }

    // The fill animates at motionControlDuration, so the target colour is read
    // after it has landed rather than on the first frame.
    Timer {
        interval: 400
        running: true
        onTriggered: {
            root.check("an armed button fills with the accent",
                Qt.colorEqual(root.unlockButton.color, card.appearance.accent),
                root.unlockButton.color);
        }
    }

    Timer {
        interval: 500
        running: true
        onTriggered: {
            context.unlockInProgress = true;
            root.check("an attempt in flight disarms the button", !root.unlockButton.armed);
            root.check("an attempt in flight says VERIFYING...",
                root.statusText.text === "VERIFYING…", root.statusText.text);
            context.unlockInProgress = false;
        }
    }

    Timer {
        interval: 750
        running: true
        onTriggered: {
            context.currentText = "wrong";
            context.showFailure = true;
            root.check("a failed attempt is named in the status line",
                root.statusText.text === "INCORRECT PASSWORD", root.statusText.text);
            root.check("a failed attempt uses the alert ink",
                Qt.colorEqual(root.statusText.color, card.appearance.danger));
        }
    }

    Timer {
        interval: 1000
        running: true
        onTriggered: {
            card.showFailureHint = false;
            context.showFailure = false;
            card.capsLockOn = true;
            root.check("Caps Lock gets its own line",
                root.statusText.text === "CAPS LOCK IS ON", root.statusText.text);
            card.capsLockOn = false;
            root.check("clearing Caps Lock clears the line", root.statusText.text === "",
                root.statusText.text);
        }
    }

    // Long enough for the spawn probe outside to watch an idle card: the Caps
    // Lock check must not be a poll.
    Timer {
        interval: 3200
        running: true
        onTriggered: {
            console.log("RESULT pass=" + root.pass + " fail=" + root.fail);
            Qt.quit();
        }
    }

    Timer {
        interval: 6000
        running: true
        onTriggered: Qt.quit()
    }
}
