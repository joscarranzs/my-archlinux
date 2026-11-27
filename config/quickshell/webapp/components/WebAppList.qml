import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import ".."
import "."

// Manage subpanel: every installed web app in a tonal row, each with its own
// delete action. The helper owns the filesystem (list/delete subcommands);
// this view only renders what it reports and never touches a file itself.
ColumnLayout {
    id: root

    property Appearance appearance: Appearance {}
    property string helper: ""
    property var apps: []
    property bool loading: false
    property string message: ""
    property bool messageAlert: false

    signal back()

    spacing: appearance.spacingLarge

    readonly property string note: {
        if (root.message !== "")
            return root.message;
        if (root.loading)
            return "LOADING…";
        if (root.apps.length === 0)
            return "NO WEB APPS INSTALLED";
        return "";
    }

    // ---------------------------------------------------------- header
    RowLayout {
        Layout.fillWidth: true
        spacing: root.appearance.spacingSmall

        // Fixed-width icon cell: Material Symbols glyphs have different
        // advances, and a back arrow must not shift the title by a pixel.
        Item {
            Layout.preferredWidth: root.appearance.iconSizeMd
            Layout.preferredHeight: root.appearance.iconSizeMd

            MaterialIcon {
                anchors.centerIn: parent
                icon: "arrow_back"
                iconSize: root.appearance.iconSizeSm
                iconColor: backArea.containsMouse
                    ? root.appearance.accentInk
                    : root.appearance.textMuted
            }
            MouseArea {
                id: backArea
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.back()
            }
        }

        Rectangle {
            Layout.alignment: Qt.AlignVCenter
            Layout.preferredWidth: root.appearance.ruleWidth
            Layout.preferredHeight: root.appearance.ruleThickness
            color: root.appearance.gilt
        }

        Text {
            Layout.alignment: Qt.AlignVCenter
            text: "INSTALLED WEB APPS"
            color: root.appearance.textMuted
            renderType: Text.NativeRendering
            font.family: root.appearance.uiFont
            font.weight: root.appearance.fontWeightUi
            font.variableAxes: root.appearance.fontVariableAxesUi
            font.pixelSize: root.appearance.fontSizeSmall
            font.letterSpacing: root.appearance.letterSpacingLabel
        }

        Item { Layout.fillWidth: true }

        Text {
            Layout.alignment: Qt.AlignVCenter
            text: String(root.apps.length)
            color: root.appearance.textFaint
            renderType: Text.NativeRendering
            font.family: root.appearance.uiFont
            font.weight: root.appearance.fontWeightUi
            font.variableAxes: root.appearance.fontVariableAxesUi
            font.pixelSize: root.appearance.fontSizeSmall
            font.letterSpacing: root.appearance.letterSpacingLabel
        }
    }

    // ------------------------------------------------------------ rows
    ListView {
        id: list
        Layout.fillWidth: true
        Layout.preferredHeight: Math.min(contentHeight, root.appearance.listMaxHeight)
        clip: true
        spacing: root.appearance.spacingSmall
        model: root.apps
        visible: root.apps.length > 0

        delegate: Rectangle {
            id: row
            required property var modelData
            width: ListView.view.width
            height: root.appearance.rowHeight
            radius: root.appearance.shapeMedium
            color: root.appearance.surfaceContainerHigh
            border.width: root.appearance.borderWidth
            border.color: root.appearance.outline

            readonly property string host: {
                const value = String(row.modelData.url || "").replace(/^https?:\/\//, "");
                return value.split("/")[0];
            }

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: root.appearance.spacingLarge
                anchors.rightMargin: root.appearance.spacingLarge
                spacing: root.appearance.spacingSmall

                Item {
                    Layout.preferredWidth: root.appearance.iconSizeMd
                    Layout.preferredHeight: root.appearance.iconSizeMd

                    Image {
                        id: rowIcon
                        anchors.fill: parent
                        sourceSize.width: root.appearance.iconSizeMd * 2
                        sourceSize.height: root.appearance.iconSizeMd * 2
                        fillMode: Image.PreserveAspectFit
                        smooth: true
                        visible: status === Image.Ready
                    }
                    Text {
                        anchors.centerIn: parent
                        visible: rowIcon.status !== Image.Ready
                        text: String(row.modelData.name || "?").charAt(0).toUpperCase()
                        renderType: Text.NativeRendering
                        font.family: root.appearance.uiFont
                        font.weight: root.appearance.fontWeightUi
                        font.variableAxes: root.appearance.fontVariableAxesUi
                        font.pixelSize: root.appearance.iconSizeSm
                        color: root.appearance.accentInk
                    }
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 0

                    Text {
                        Layout.fillWidth: true
                        text: row.modelData.name || ""
                        color: root.appearance.text
                        elide: Text.ElideRight
                        renderType: Text.NativeRendering
                        font.family: root.appearance.uiFont
                        font.weight: root.appearance.fontWeightUi
                        font.variableAxes: root.appearance.fontVariableAxesUi
                        font.pixelSize: root.appearance.fontSizeSmall
                        font.letterSpacing: root.appearance.letterSpacingCaption
                    }
                    Text {
                        Layout.fillWidth: true
                        text: row.host
                        color: root.appearance.textFaint
                        elide: Text.ElideRight
                        renderType: Text.NativeRendering
                        font.family: root.appearance.uiFont
                        font.weight: root.appearance.fontWeightUi
                        font.variableAxes: root.appearance.fontVariableAxesUi
                        font.pixelSize: root.appearance.fontSizeSmall
                        font.letterSpacing: root.appearance.letterSpacingCaption
                    }
                }

                Item {
                    Layout.preferredWidth: root.appearance.iconSizeMd
                    Layout.preferredHeight: root.appearance.iconSizeMd

                    MaterialIcon {
                        anchors.centerIn: parent
                        icon: "delete"
                        iconSize: root.appearance.iconSizeSm
                        iconColor: deleteArea.containsMouse
                            ? root.appearance.danger
                            : root.appearance.textMuted
                    }
                    MouseArea {
                        id: deleteArea
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.removeApp(row.modelData)
                    }
                }
            }

            // Same resolution as the launcher's AppItem: a path loads local,
            // a theme name goes through Quickshell.iconPath, and anything that
            // cannot decode (a webp without the plugin) keeps the letter.
            Component.onCompleted: {
                const icon = String(row.modelData.icon || "");
                if (icon.indexOf("/") === 0) {
                    rowIcon.source = "file://" + icon;
                    return;
                }
                if (icon === "")
                    return;
                try {
                    const resolved = Quickshell.iconPath(icon, true);
                    if (resolved && resolved.length > 0 && !resolved.includes("image-missing"))
                        rowIcon.source = resolved;
                } catch (error) {
                    // Keep the letter fallback.
                }
            }
        }
    }

    // ------------------------------------------------------------ note
    Item {
        Layout.fillWidth: true
        Layout.preferredHeight: root.appearance.noteHeight

        Text {
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            text: root.note
            color: root.messageAlert ? root.appearance.danger : root.appearance.textMuted
            renderType: Text.NativeRendering
            font.family: root.appearance.uiFont
            font.weight: root.appearance.fontWeightUi
            font.variableAxes: root.appearance.fontVariableAxesUi
            font.pixelSize: root.appearance.fontSizeSmall
            font.letterSpacing: root.appearance.letterSpacingCaption
        }
    }

    Process {
        id: lister
        stdout: StdioCollector {}
        onExited: (code) => {
            root.loading = false;
            if (code !== 0) {
                root.message = "COULD NOT READ THE APP LIST";
                root.messageAlert = true;
                return;
            }
            try {
                root.apps = JSON.parse(lister.stdout.text);
            } catch (error) {
                root.apps = [];
                root.message = "COULD NOT READ THE APP LIST";
                root.messageAlert = true;
            }
        }
    }

    Process {
        id: deleter
        property string pendingName: ""
        stdout: StdioCollector {}
        stderr: StdioCollector {}
        onExited: (code) => {
            if (code === 0) {
                root.message = "DELETED " + deleter.pendingName.toUpperCase();
                root.messageAlert = false;
                root.refresh();
            } else {
                const detail = String(deleter.stderr.text || "")
                    .replace("webapp:", "").trim();
                root.message = detail !== "" ? detail.toUpperCase() : "COULD NOT DELETE THE APP";
                root.messageAlert = true;
            }
        }
    }

    function refresh() {
        // A helper nobody configured cannot answer, and a Process whose command
        // is empty never starts and never exits -- which left the list reading
        // LOADING… for as long as the panel stayed open. The failure is named
        // instead, the same way a non-zero exit is.
        if (root.helper === "") {
            root.loading = false;
            root.apps = [];
            root.message = "COULD NOT READ THE APP LIST";
            root.messageAlert = true;
            return;
        }
        root.loading = true;
        lister.running = false;
        lister.command = [root.helper, "list"];
        lister.running = true;
    }

    function removeApp(app) {
        if (deleter.running)
            return;
        root.message = "";
        deleter.pendingName = String(app.name || app.slug);
        deleter.running = false;
        deleter.command = [root.helper, "delete", String(app.slug)];
        deleter.running = true;
    }

    Keys.onEscapePressed: root.back()
    Component.onCompleted: root.refresh()
}
