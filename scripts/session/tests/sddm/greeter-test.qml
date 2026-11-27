import QtQuick
import Quickshell

// Offscreen harness for the SDDM greeter.
//
// The theme is loaded whole, from a copy that only renames SDDM's four context
// objects to stubs (see stub.py), inside a plain window -- never through
// `sddm-greeter --test-mode`, which takes a live session's keyboard and is the
// way this desktop got locked out once already. Nothing here can touch SDDM, the
// PAM stack or a real password.
//
// What is asserted is what broke before, or would: a card that is not the unlock
// card's, an attempt that is not sent to the session it named, and a failure
// that leaves the greeter stuck in VERIFYING.
ShellRoot {
    id: root

    property int pass: 0
    property int fail: 0

    property string shotPath: "@PNG@"

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

    Window {
        width: 1280
        height: 800
        visible: true

        Loader {
            id: loader

            anchors.fill: parent
            source: "file://@URL@/Main.qml"
        }
    }

    readonly property var page: loader.item
    readonly property var card: page ? root.named(page, "card") : null
    readonly property var label: page ? root.named(page, "passwordLabel") : null
    readonly property var status: page ? root.named(page, "statusText") : null
    readonly property var field: page ? root.named(page, "passwordField") : null
    readonly property var input: page ? root.named(page, "passwordInput") : null
    readonly property var button: page ? root.named(page, "submitButton") : null

    // The theme's token object, reached through the property stub.py injects:
    // the expectations read the roles off the page instead of restating the
    // palette here, so a retuned token moves the verdict with it.
    readonly property var appearance: page ? page.appearanceStub : null

    // --- one: the surface is the unlock card's ---------------------------------
    Timer {
        interval: 250
        running: true
        onTriggered: {
            root.check("the theme loads", root.page !== null && loader.status === Loader.Ready);
            root.check("it builds the card, label, status, field and button",
                root.card !== null && root.label !== null && root.status !== null
                && root.field !== null && root.input !== null && root.button !== null);

            // SDDM runs the greeter with SizeRootObjectToView; the harness's
            // Loader does the same, so a root that does not fill the window
            // would be a root that does not fill the screen.
            root.check("the surface fills the screen",
                Math.abs(root.page.width - loader.width) < 1
                && Math.abs(root.page.height - loader.height) < 1,
                root.page.width + "x" + root.page.height + " in "
                + loader.width + "x" + loader.height);

            root.check("the card carries the plaque's fill, radius and gilt edge",
                root.card.radius === root.appearance.shapeExtraLarge
                && root.card.border.width === root.appearance.borderWidth
                && Qt.colorEqual(root.card.border.color, root.appearance.gilt),
                root.card.radius + "/" + root.card.border.width);

            root.check("the card is the unlock card's width",
                root.card.width === root.appearance.cardWidth, root.card.width);

            root.check("the PASSWORD label is ink, not opacity",
                root.label.opacity === 1
                && Qt.colorEqual(root.label.color, root.appearance.textMuted),
                root.label.opacity);

            root.check("the status slot is reserved", root.status.parent.height
                === root.appearance.statusHeight);

            root.check("an idle greeter says nothing", root.status.text === "", root.status.text);
            root.check("an unarmed button rests on surfaceContainerHigh",
                Qt.colorEqual(root.button.color, root.appearance.surfaceContainerHigh));

            if (root.shotPath.length > 0 && root.shotPath.indexOf("@") !== 0) {
                root.page.grabToImage(function(result) {
                    console.log("GRAB " + root.shotPath + " " + result.saveToFile(root.shotPath));
                });
            }
        }
    }

    // --- two: typing arms the plaque ------------------------------------------
    Timer {
        interval: 400
        running: true
        onTriggered: {
            root.input.text = "hunter2";
            root.check("a typed password arms the button", root.button.armed);
            root.check("the field takes the accent when focused",
                root.input.activeFocus && Qt.colorEqual(root.field.border.color,
                    root.appearance.accent),
                root.field.border.color);
        }
    }

    // --- three: Return goes through the same path as the button ---------------
    Timer {
        interval: 550
        running: true
        onTriggered: {
            root.page.attempt();
            root.check("an attempt in flight says VERIFYING",
                root.status.text === "VERIFYING…", root.status.text);
            root.check("an attempt in flight disables the field", !root.input.enabled);
            root.check("an attempt in flight disarms the button", !root.button.armed);
            const attempts = root.page.sddmStub.attempts;
            root.check("the attempt names the user and the password",
                attempts.length === 1 && attempts[0][0] === "joscarranzs"
                && attempts[0][1] === "hunter2",
                JSON.stringify(attempts));
            // Hyprland is at index 2 of the stub's list, after the uwsm-managed
            // entry: the greeter has to search, and has to prefer the plain one.
            root.check("the attempt starts the plain hyprland session",
                attempts.length === 1 && attempts[0][2] === 2,
                attempts.length ? attempts[0][2] : "no attempt");
        }
    }

    // --- four: a rejection is named and the field comes back ------------------
    Timer {
        interval: 700
        running: true
        onTriggered: {
            root.page.sddmStub.loginFailed();
            root.check("a rejected password is named",
                root.status.text === "INCORRECT PASSWORD", root.status.text);
            root.check("a rejected password uses the alert ink",
                Qt.colorEqual(root.status.color, root.appearance.danger));
            root.check("a rejected password paints the field's edge",
                Qt.colorEqual(root.field.border.color, root.appearance.danger),
                root.field.border.color);
            root.check("a rejected password clears the field", root.input.text === "",
                root.input.text);
            root.check("the field is usable again", root.input.enabled && !root.page.verifying);
        }
    }

    // --- five: the next keystroke takes the line back down --------------------
    Timer {
        interval: 900
        running: true
        onTriggered: {
            root.input.text = "a";
            root.check("typing clears the failure line", root.status.text === "",
                root.status.text);
            root.check("the field edge returns to the accent",
                Qt.colorEqual(root.field.border.color, root.appearance.accent),
                root.field.border.color);
        }
    }

    // --- six: an unanswered attempt is released, not stuck --------------------
    // The interval is the theme's own failureHintMs, so this catches both a
    // missing guard and a guard that was retuned away from the token.
    Timer {
        interval: 1100
        running: true
        onTriggered: {
            root.page.attempt();
            root.check("the second attempt is in flight", root.page.verifying);
        }
    }

    Timer {
        interval: 1100 + 3400
        running: true
        onTriggered: {
            root.check("an unanswered attempt hands the field back",
                !root.page.verifying && root.input.enabled);

            console.log("RESULT pass=" + root.pass + " fail=" + root.fail);
            Qt.quit();
        }
    }

    Timer {
        interval: 9000
        running: true
        onTriggered: Qt.quit()
    }
}
