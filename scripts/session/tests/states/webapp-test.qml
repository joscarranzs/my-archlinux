import QtQuick
import Quickshell
import "@URL@/webapp/components"

// Empty and error, forced on the manage subpanel: no installed web app, a helper
// that answers with nothing, and a helper that was never configured.
//
// WebAppList owns the lister process, so the harness gives it a real one: a
// throwaway script that prints `[]` for `list`. Forcing `apps: []` alone would
// have asserted against a list that never loaded -- and "LOADING… forever" is
// exactly the state this suite found, with an empty helper path, where the
// Process never starts and never exits.
ShellRoot {
    id: root

    property int pass: 0
    property int fail: 0

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

    function inside(item, ancestor) {
        let parent = item.parent;
        while (parent !== null) {
            if (parent.objectName === ancestor)
                return true;
            parent = parent.parent;
        }
        return false;
    }

    Window {
        width: 520
        height: 760
        visible: true

        Column {
            anchors.centerIn: parent
            spacing: 24

            // A helper that works and reports an empty list.
            WebAppList {
                id: list
                width: 480
                helper: "@HELPER@"
            }

            // A host that never set the helper path: this one used to sit in
            // LOADING… for as long as it stayed open.
            WebAppList {
                id: orphan
                width: 480
                helper: ""
            }
        }
    }

    // The creator plaque itself, rendered at 1:1. The list harness above proves
    // the states; this one proves the card owns the form and its status line.
    Window {
        width: 520
        height: 900
        visible: true

        WebAppForm {
            id: form
            anchors.centerIn: parent
        }
    }

    Timer {
        interval: 700
        running: true
        onTriggered: {
            root.check("an empty helper answer stops the loading state",
                list.loading === false, list.loading);

            const note = root.byText(list, "NO WEB APPS INSTALLED", []);
            root.check("an empty install list says so", note.length === 1, note.length);
            if (note.length === 1) {
                root.check("the empty note is muted ink, not opacity",
                    note[0].opacity === 1
                    && Qt.colorEqual(note[0].color, list.appearance.textMuted),
                    note[0].color);
            }

            root.check("an unconfigured helper is named, not left loading",
                root.byText(orphan, "COULD NOT READ THE APP LIST", []).length === 1,
                orphan.note);
            root.check("the unconfigured helper takes the alert ink",
                Qt.colorEqual(orphan.messageAlert ? orphan.appearance.danger
                    : orphan.appearance.textMuted, orphan.appearance.danger));

            // The creator is three cards: identity, actions, then the inputs.
            const names = ["card-identity", "card-actions", "card-fields"];
            const cards = names.map((name) => root.byObjectName(form, name, []));
            root.check("the creator has three cards",
                cards.every((c) => c.length === 1), cards.map((c) => c.length).join(","));
            if (cards.every((c) => c.length === 1)) {
                const identity = cards[0][0];
                const actions = cards[1][0];
                const fields = cards[2][0];

                root.check("all three cards are visible",
                    identity.visible && actions.visible && fields.visible);
                root.check("all three cards use the shared recipe",
                    cards.every((c) => Qt.colorEqual(c[0].color, form.appearance.cardFill)
                        && Qt.colorEqual(c[0].border.color, form.appearance.outline)));
                root.check("the cards stack in order with the shared gap",
                    identity.y < actions.y && actions.y < fields.y
                    && Math.abs((actions.y - identity.y - identity.height)
                        - form.appearance.cardGap) <= 1
                    && Math.abs((fields.y - actions.y - actions.height)
                        - form.appearance.cardGap) <= 1,
                    identity.y + "," + actions.y + "," + fields.y);
                root.check("the stack fits inside the plaque",
                    fields.y + fields.height + form.appearance.contentPad
                        <= form.height + 1);

                root.check("the first card is the logo strip",
                    root.byText(identity, "Logo preview", []).length === 1
                    && root.byText(identity, "NEW WEB APP", []).length === 0);
                const preview = root.byObjectName(identity, "logo-preview", [])[0];
                const previewLabel = root.byText(identity, "Logo preview", [])[0];
                const labelPoint = previewLabel.mapToItem(identity, 0, 0);
                const previewPoint = preview.mapToItem(identity, 0, 0);
                root.check("the preview card uses the shared padding and centres its row",
                    preview !== undefined && previewLabel !== undefined
                    && Math.abs(labelPoint.x - form.appearance.cardPad) <= 1
                    && Math.abs(previewPoint.x + preview.width
                        - (identity.width - form.appearance.cardPad)) <= 1
                    && Math.abs(labelPoint.y + previewLabel.height / 2
                        - identity.height / 2) <= 1
                    && Math.abs(previewPoint.y + preview.height / 2
                        - identity.height / 2) <= 1
                    && Math.abs(identity.height
                        - (preview.height + form.appearance.cardPad * 2)) <= 1,
                    labelPoint.x + "," + (previewPoint.x + preview.width)
                        + " h=" + identity.height);
                const buttons = root.byObjectName(actions, "action-button", [])
                    .filter((b) => b.visible && b.width > 0 && b.height > 0);
                root.check("the second card holds both actions",
                    buttons.length === 2
                    && buttons.some((b) => b.label === "CREATE")
                    && buttons.some((b) => b.label === "INSTALLED"),
                    buttons.map((b) => b.label).join(","));
                root.check("the two actions share one design and split the row",
                    buttons.length === 2
                    && Math.abs(buttons[0].width - buttons[1].width) <= 1
                    && buttons.every((b) => b.height === form.appearance.buttonHeight
                        && b.radius === form.appearance.shapeLarge
                        && b.border.width === form.appearance.borderWidth),
                    buttons.map((b) => b.width + "x" + b.height).join(","));

                const actionTitle = root.byText(actions, "ACTIONS", [])[0];
                const fieldsTitle = root.byText(fields, "DETAILS", [])[0];
                root.check("card titles use the small rung",
                    actionTitle !== undefined && fieldsTitle !== undefined
                    && actionTitle.font.pixelSize === form.appearance.fontSizeSmall
                    && fieldsTitle.font.pixelSize === form.appearance.fontSizeSmall,
                    (actionTitle ? actionTitle.font.pixelSize : "?") + ","
                        + (fieldsTitle ? fieldsTitle.font.pixelSize : "?"));
                for (const label of ["NAME", "URL", "ICON (OPTIONAL)"]) {
                    const found = root.byText(fields, label, []);
                    root.check("the third card holds the " + label + " field",
                        found.length === 1 && root.inside(found[0], "card-fields"), found.length);
                }
                const surfaces = root.byObjectName(fields, "field-surface", []);
                root.check("the third card holds three small inputs",
                    surfaces.length === 3 && surfaces.every((s) => s.height > 0
                        && s.height <= form.appearance.fieldHeight + 1),
                    surfaces.map((s) => s.height).join(","));
                const note = root.byObjectName(fields, "note", []);
                root.check("the status line is inside the third card",
                    note.length === 1 && root.inside(note[0], "card-fields"), note.length);
            }
        }
    }

    Timer {
        interval: 850
        running: true
        onTriggered: {
            list.message = "cannot reach the webapp helper";
            list.messageAlert = true;
        }
    }

    Timer {
        interval: 900
        running: true
        onTriggered: form.showInstalled()
    }

    Timer {
        interval: 1200
        running: true
        onTriggered: {
            const names = ["card-identity", "card-actions", "card-fields"];
            const cards = names.map((name) => root.byObjectName(form, name, []));
            root.check("the cards yield to the installed view",
                cards.every((c) => c.length === 1 && c[0].visible === false),
                cards.map((c) => c.length).join(","));
            root.check("the installed view is back on the plaque",
                root.byText(form, "INSTALLED WEB APPS", []).length === 1);

            const note = root.byText(list, "cannot reach the webapp helper", []);
            root.check("a helper failure replaces the empty note", note.length === 1,
                note.length);
            if (note.length === 1) {
                root.check("a helper failure takes the alert ink",
                    Qt.colorEqual(note[0].color, list.appearance.danger), note[0].color);
            }

            console.log("RESULT pass=" + root.pass + " fail=" + root.fail);
            Qt.quit();
        }
    }

    Timer {
        interval: 5000
        running: true
        onTriggered: Qt.quit()
    }
}
