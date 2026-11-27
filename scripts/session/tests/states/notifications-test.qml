import QtQuick
import Quickshell
import Quickshell.Services.Notifications
import "@URL@/bar/components"

// The toast's own states, forced offscreen: the sender's icon resolved to a real
// file, the sender's icon that resolves to nothing at all, and the two things a
// toast says about itself -- the urgency on its edge and the copy target.
//
// The unresolved case is why this file exists. `Quickshell.iconPath()` answers for
// *any* string, so an icon no theme ships used to paint the image provider's broken
// placeholder instead of falling back to the urgency glyph, and nothing failed:
// QML cannot tell a resolved icon from a missing one. The harness drives the real
// helper through the real popup, so the state that regressed is the state under
// test here, and the tile is read by name (`mark-image`) because "an image or a
// glyph" is the one thing that cannot be seen from outside the card.
//
// The material states come last and come apart in time: the shared recipe animates
// the fill over `motionControlDuration`, so a hover read in the same tick as the
// hook that forces it still returns the resting value.
ShellRoot {
    id: root

    property int pass: 0
    property int fail: 0

    // A real PNG that ships with the repository: the resolved case has to prove the
    // tile *renders* an image, not merely that a string came back, and every other
    // icon on a machine depends on what happens to be installed.
    readonly property string assetIcon: ("" + "@URL@").replace("file://", "") + "/tokens/assets/nous.png"

    function check(name, condition, detail) {
        if (condition) {
            root.pass += 1;
            console.log("PASS " + name);
        } else {
            root.fail += 1;
            console.log("FAIL " + name + " :: " + (detail === undefined ? "" : detail));
        }
    }

    function byText(item, text, found) {
        if (item.text !== undefined && item.text === text)
            found.push(item);
        for (let i = 0; i < item.children.length; i += 1)
            root.byText(item.children[i], text, found);
        return found;
    }

    function byObjectName(item, name, found) {
        if (item.objectName === name)
            found.push(item);
        for (let i = 0; i < item.children.length; i += 1)
            root.byObjectName(item.children[i], name, found);
        return found;
    }

    function one(parent, name) {
        return root.byObjectName(parent, name, [])[0];
    }

    // The notification object the popup reads: the panel only ever consumes these
    // fields, so a plain object is a faithful stub for the bus.
    function stub(props) {
        return Object.assign({
            urgency: NotificationUrgency.Normal,
            appIcon: "",
            appName: "KITTY",
            summary: "Summary line",
            body: "Body line",
            dismiss: function () {},
        }, props);
    }

    Window {
        width: 400
        height: 620
        visible: true

        Column {
            anchors.centerIn: parent
            spacing: 12

            // The sender names an icon that exists.
            NotificationPopup {
                id: resolved
                notification: root.stub({ appIcon: root.assetIcon })
            }

            // The sender names one that does not: no theme ships it, and no
            // `.desktop` entry answers to that name either.
            NotificationPopup {
                id: unresolved
                notification: root.stub({ appIcon: "zzz-bogus", appName: "No Such App" })
            }

            // A critical message with an error in its text: the edge goes danger and
            // the message becomes copyable.
            NotificationPopup {
                id: critical
                notification: root.stub({
                    urgency: NotificationUrgency.Critical,
                    appIcon: "zzz-bogus",
                    summary: "Deploy failed",
                    body: "traceback: connection refused",
                })
            }
        }
    }

    // 1. Everything that does not need the shared recipe settled. The icon is
    //    resolved by a helper process, so the first look waits for it: 60 ms of
    //    Python plus the offscreen load, with room to spare.
    Timer {
        interval: 1500
        running: true
        onTriggered: {
            const appearance = resolved.appearance;

            // --- the sender's icon, resolved -------------------------------------
            root.check("a sender's icon that exists resolves to that file",
                resolved.appIconPath === root.assetIcon, resolved.appIconPath);

            const resolvedMark = root.one(resolved, "mark-image");
            root.check("the tile renders the sender's icon",
                resolvedMark !== undefined && resolvedMark.ready === true,
                resolvedMark === undefined ? "no mark-image"
                    : resolvedMark.source + " status=" + resolvedMark.status);
            root.check("the urgency glyph stays hidden while the icon is on screen",
                root.byText(resolved, "notifications", [])[0].visible === false);

            // --- the sender's icon, missing -------------------------------------
            root.check("an icon no theme ships resolves to nothing",
                unresolved.appIconPath === "", "[" + unresolved.appIconPath + "]");

            const missingMark = root.one(unresolved, "mark-image");
            // `source` is a url, not a string: an empty one is not `=== ""` in QML.
            root.check("a missing icon leaves the tile with nothing to draw",
                missingMark !== undefined && String(missingMark.source) === ""
                && missingMark.ready === false,
                missingMark === undefined ? "no mark-image"
                    : "[" + missingMark.source + "] status=" + missingMark.status
                        + " ready=" + missingMark.ready);
            root.check("a missing icon falls back to the urgency glyph",
                root.byText(unresolved, "notifications", [])[0].visible === true);

            // --- the message in two voices --------------------------------------
            const headline = root.byText(resolved, "Summary line", [])[0];
            const body = root.byText(resolved, "Body line", [])[0];
            root.check("the headline takes the title rung",
                headline !== undefined && headline.font.pixelSize === appearance.fontSizeTitle,
                headline === undefined ? "no headline" : headline.font.pixelSize);
            root.check("the headline is bright ink, not a wash",
                headline !== undefined && Qt.colorEqual(headline.color, appearance.textBright)
                && headline.font.bold === true,
                headline === undefined ? "no headline" : headline.color);
            root.check("the body takes the caption rung",
                body !== undefined && body.font.pixelSize === appearance.fontSizeCaption,
                body === undefined ? "no body" : body.font.pixelSize);
            root.check("the body is muted ink",
                body !== undefined && Qt.colorEqual(body.color, appearance.textMuted)
                && body.opacity === 1,
                body === undefined ? "no body" : body.color);

            const appName = root.byText(resolved, "KITTY", [])[0];
            root.check("the app name keeps the eyebrow rung",
                appName !== undefined && appName.font.pixelSize === appearance.fontSizeSmall,
                appName === undefined ? "no app name" : appName.font.pixelSize);

            // --- the identity is the card's own rung ----------------------------
            root.check("the tile takes the card's plate rung",
                resolvedMark !== undefined && resolvedMark.parent.width === appearance.fieldHeight,
                resolvedMark === undefined ? "no mark-image" : resolvedMark.parent.width);
            root.check("the mark takes the card's mark rung",
                resolvedMark !== undefined
                && resolvedMark.sourceSize.width === appearance.iconSizeMd,
                resolvedMark === undefined ? "no mark-image" : resolvedMark.sourceSize.width);
            root.check("the tile is round, from the house shape ladder",
                resolvedMark !== undefined && resolvedMark.parent.radius === appearance.shapeMedium,
                resolvedMark === undefined ? "no mark-image" : resolvedMark.parent.radius);

            // --- the urgency on the edge ----------------------------------------
            root.check("a normal toast keeps the plaque's gilt edge",
                Qt.colorEqual(root.one(resolved, "toast-card").border.color, appearance.gilt),
                root.one(resolved, "toast-card").border.color);
            root.check("a critical toast is framed in danger",
                Qt.colorEqual(root.one(critical, "toast-card").border.color, appearance.danger),
                root.one(critical, "toast-card").border.color);

            const chip = root.one(critical, "chip");
            const wanted = "CRITICAL \u00b7 " + critical.clockLabel;
            root.check("a critical toast names its type",
                chip !== undefined && chip.text === wanted,
                "chip=[" + (chip === undefined ? "none" : chip.text) + "] wanted=[" + wanted + "]");
            root.check("a critical toast marks the chip with a dot",
                chip !== undefined && chip.showDot === true);

            // --- the copy target, at rest ----------------------------------------
            root.check("a normal message offers nothing to copy",
                root.one(resolved, "copy-row").visible === false,
                root.one(resolved, "copy-row").visible);

            const copy = root.one(critical, "copy-button");
            root.check("an error message offers a copy target",
                root.one(critical, "copy-row").visible === true && copy !== undefined,
                root.one(critical, "copy-row").visible);

            if (copy !== undefined) {
                root.check("the copy target is a button, not a bare glyph",
                    copy.width === appearance.iconButtonSize
                    && copy.height === appearance.iconButtonSize
                    && copy.radius === appearance.radius,
                    copy.width + "x" + copy.height + " r=" + copy.radius
                        + " want=" + appearance.iconButtonSize + " r=" + appearance.radius);
                root.check("the copy target rests with no fill and no edge",
                    Qt.colorEqual(copy.color, "transparent")
                    && Qt.colorEqual(copy.border.color, "transparent"),
                    copy.color + " / " + copy.border.color);

                critical.forceHover = true;
            }
        }
    }

    // 2. Hover, once the shared recipe has had its `motionControlDuration` to run.
    Timer {
        interval: 1800
        running: true
        onTriggered: {
            const appearance = critical.appearance;
            const copy = root.one(critical, "copy-button");

            root.check("hover steps the copy target's own fill up and ignites its edge",
                Qt.colorEqual(copy.color, appearance.hoverFill)
                && Qt.colorEqual(copy.border.color, appearance.gilt),
                copy.color + " / " + copy.border.color);

            critical.forcePressed = true;
        }
    }

    // 3. Press, and the verdict.
    Timer {
        interval: 2100
        running: true
        onTriggered: {
            const copy = root.one(critical, "copy-button");
            root.check("press steps the fill back down",
                Qt.colorEqual(copy.color, critical.appearance.pressFill),
                copy.color);

            console.log("RESULT pass=" + root.pass + " fail=" + root.fail);
            Qt.quit();
        }
    }

    Timer {
        interval: 8000
        running: true
        onTriggered: Qt.quit()
    }
}
