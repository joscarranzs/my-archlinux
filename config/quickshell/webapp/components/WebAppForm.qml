import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import ".."
import "."
import "../services"

// Card that turns a name, a URL and an optional icon into a freedesktop entry
// for a browser web app. It owns the draft (session scoped), the validation and
// the status line, so the overlay and the floating preview share one form.
Rectangle {
    id: root

    property Appearance appearance: Appearance {}

    // The panel should close now (created, cancelled or dismissed).
    signal finished()

    WebAppDraft { id: draft }

    Connections {
        target: draft
        function onDraftLoaded() {
            root.applyDraft();
            root.focusFirstEmpty();
        }
        function onPersistDone() { root.finished(); }
    }

    property bool creating: false
    property string message: ""
    property bool messageAlert: false

    // The manage subpanel replaces the form inside the same card.
    property bool installedView: false

    readonly property bool nameOk: draft.appName.trim().length > 0
    readonly property bool urlOk: root.validUrl(draft.url)
    readonly property bool canCreate: root.nameOk && root.urlOk && !root.creating
    readonly property bool dirty: draft.appName !== "" || draft.url !== "" || draft.iconName !== ""

    // One line of feedback, one source of truth.
    readonly property string note: {
        if (root.message !== "")
            return root.message;
        if (root.creating)
            return "WRITING THE ENTRY…";
        if (draft.appName !== "" && !root.nameOk)
            return "NAME REQUIRED";
        if (draft.url !== "" && !root.urlOk)
            return "THAT URL DOESN'T LOOK RIGHT";
        if (draft.restored)
            return "DRAFT RESTORED FROM THIS SESSION";
        return "";
    }
    readonly property bool noteAlert: root.messageAlert
        || (draft.url !== "" && !root.urlOk)

    implicitWidth: appearance.panelWidth
    implicitHeight: (installedView ? installedBody.implicitHeight : layout.implicitHeight)
        + appearance.contentPad * 2
    radius: appearance.shapeExtraLarge
    color: appearance.surfaceContainer
    // Edge: gilt (accent.tertiary) at look.borders.width — the plaque's frame.
    border.color: appearance.gilt
    border.width: appearance.borderWidth


    Process {
        id: creator
        stdout: StdioCollector {}
        stderr: StdioCollector {}

        onExited: (code) => {
            root.creating = false;
            if (code === 0) {
                draft.clear();
                root.message = "CREATED";
                root.messageAlert = false;
                closeTimer.restart();
            } else {
                const detail = String(creator.stderr.text || "")
                    .replace("webapp:", "").trim();
                root.message = detail !== "" ? detail.toUpperCase() : "COULD NOT CREATE THE APP";
                root.messageAlert = true;
            }
        }
    }

    Timer {
        id: closeTimer
        interval: 650
        onTriggered: root.finished()
    }

    Keys.onEscapePressed: root.installedView ? root.showForm() : root.dismiss()

    function validUrl(raw) {
        let value = String(raw || "").trim();
        if (value === "")
            return false;
        if (value.indexOf(" ") >= 0 || value.indexOf("\t") >= 0)
            return false;
        const lower = value.toLowerCase();
        if (lower.indexOf("http://") === 0)
            value = value.slice(7);
        else if (lower.indexOf("https://") === 0)
            value = value.slice(8);
        if (value === "" || value.indexOf("/") === 0)
            return false;
        const host = value.split("/")[0].split("?")[0].split("#")[0];
        const parts = host.split(".");
        if (parts.length < 2)
            return false;
        for (let i = 0; i < parts.length; i++) {
            if (parts[i].length === 0)
                return false;
        }
        return parts[parts.length - 1].length >= 2;
    }

    function submit() {
        if (!root.canCreate)
            return;
        draft.persist();
        root.creating = true;
        root.message = "";
        root.messageAlert = false;
        creator.running = false;
        creator.command = [draft.helper, "create", draft.payload()];
        creator.running = true;
    }

    function discard() {
        draft.clear();
        root.message = "";
        root.messageAlert = false;
        root.applyDraft();
        nameField.forceFocus();
    }

    // The fields own their text (an alias cannot stay bound once the user
    // types), so the draft is pushed into them explicitly.
    function applyDraft() {
        nameField.text = draft.appName;
        urlField.text = draft.url;
        iconField.text = draft.iconName;
    }

    // Closing keeps the draft: that is the whole point of the session file.
    // The close waits for the write (draft.persistDone) so a dismiss right
    // after typing cannot tear the writer down mid-save.
    function dismiss() {
        draft.persistAndQuit();
    }

    // The plaque is a well and the form is a stack of three cards: identity,
    // actions, then the fields. The layout is placed, not filled: the plaque
    // derives its height from it, and filling the parent closes a binding loop.
    ColumnLayout {
        id: layout

        x: appearance.contentPad
        y: appearance.contentPad
        width: root.width - appearance.contentPad * 2
        height: implicitHeight
        spacing: appearance.cardGap

        PanelCard {
            id: identityCard

            objectName: "card-identity"
            Layout.fillWidth: true
            appearance: root.appearance
            visible: !root.installedView

            // No title on this one: the card is the logo strip. The label is on
            // the left and the live preview tile on the right, same row.
            RowLayout {
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignVCenter
                spacing: root.appearance.spacingSmall

                Text {
                    Layout.alignment: Qt.AlignVCenter
                    text: "Logo preview"
                    color: root.appearance.textMuted
                    renderType: Text.NativeRendering
                    font.family: root.appearance.uiFont
                    font.weight: root.appearance.fontWeightUi
                    font.variableAxes: root.appearance.fontVariableAxesUi
                    font.pixelSize: root.appearance.fontSizeSmall
                    font.letterSpacing: root.appearance.letterSpacingLabel
                }

                Item { Layout.fillWidth: true }

                WebAppTile {
                    objectName: "logo-preview"
                    Layout.alignment: Qt.AlignVCenter
                    appearance: root.appearance
                    tileSize: root.appearance.iconSizeLg
                    iconSource: draft.iconName
                    fallbackText: draft.appName
                }
            }
        }

        PanelCard {
            id: actionsCard

            objectName: "card-actions"
            Layout.fillWidth: true
            appearance: root.appearance
            title: "ACTIONS"
            glyph: "add"
            titleSize: root.appearance.fontSizeSmall
            visible: !root.installedView

            RowLayout {
                Layout.fillWidth: true
                spacing: root.appearance.spacingSmall

                ActionButton {
                    appearance: root.appearance
                    label: root.creating ? "CREATING…" : "CREATE"
                    glyph: "add"
                    active: root.canCreate
                    actionEnabled: root.canCreate
                    onClicked: root.submit()
                }

                ActionButton {
                    appearance: root.appearance
                    label: "INSTALLED"
                    glyph: "list"
                    onClicked: root.showInstalled()
                }

                ActionButton {
                    visible: root.dirty && !root.creating
                    appearance: root.appearance
                    label: "DISCARD"
                    glyph: "close"
                    onClicked: root.discard()
                }
            }

        }

        PanelCard {
            id: fieldsCard

            objectName: "card-fields"
            Layout.fillWidth: true
            appearance: root.appearance
            title: "DETAILS"
            glyph: "edit"
            titleSize: root.appearance.fontSizeSmall
            visible: !root.installedView

                // ---------------------------------------------------------- fields
            Field {
                id: nameField
                Layout.fillWidth: true
                appearance: root.appearance
                label: "NAME"
                placeholder: "Notion Calendar"
                glyph: "badge"
                onEdited: (value) => { draft.appName = value; draft.restored = false; }
                onAccepted: root.submit()
                onTabPressed: urlField.forceFocus()
                onBacktabPressed: iconField.forceFocus()
            }

            Field {
                id: urlField
                Layout.fillWidth: true
                appearance: root.appearance
                label: "URL"
                placeholder: "calendar.notion.so"
                glyph: "link"
                invalid: draft.url !== "" && !root.urlOk
                onEdited: (value) => { draft.url = value; draft.restored = false; }
                onAccepted: root.submit()
                onTabPressed: iconField.forceFocus()
                onBacktabPressed: nameField.forceFocus()
            }

            Field {
                id: iconField
                Layout.fillWidth: true
                appearance: root.appearance
                label: "ICON (OPTIONAL)"
                placeholder: "youtube  ·  https://…  ·  /path/icon.png"
                glyph: "image"
                onEdited: (value) => { draft.iconName = value; draft.restored = false; }
                onAccepted: root.submit()
                onTabPressed: nameField.forceFocus()
                onBacktabPressed: urlField.forceFocus()
            }

            // ------------------------------------------------------------ note
            Item {
                Layout.fillWidth: true
                Layout.preferredHeight: root.appearance.noteHeight

                Text {
                    objectName: "note"

                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    text: root.note
                    color: root.noteAlert ? root.appearance.danger : root.appearance.textMuted
                    renderType: Text.NativeRendering
                    font.family: root.appearance.uiFont
                    font.weight: root.appearance.fontWeightUi
                    font.variableAxes: root.appearance.fontVariableAxesUi
                    font.pixelSize: root.appearance.fontSizeSmall
                    font.letterSpacing: root.appearance.letterSpacingCaption
                }
            }

        }

        WebAppList {
            id: installedBody
            Layout.fillWidth: true
            visible: root.installedView
            appearance: root.appearance
            helper: draft.helper
            onBack: root.showForm()
        }
    }

    function showInstalled() {
        root.message = "";
        root.messageAlert = false;
        root.installedView = true;
        installedBody.refresh();
        installedBody.forceActiveFocus();
    }

    function showForm() {
        root.installedView = false;
        root.focusFirstEmpty();
    }

    function focusFirstEmpty() {
        if (draft.appName === "")
            nameField.forceFocus();
        else if (draft.url === "")
            urlField.forceFocus();
        else
            iconField.forceFocus();
    }

    // When the status file already exists the read finishes before this runs;
    // otherwise onDraftLoaded takes over once the FileView lands.
    Component.onCompleted: {
        root.applyDraft();
        root.focusFirstEmpty();
    }
}
