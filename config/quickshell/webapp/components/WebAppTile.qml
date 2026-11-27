import QtQuick
import Quickshell
import ".."
import "."

// Live preview of the desktop entry icon: whatever the form will write, shown
// in the same tonal tile the launcher uses, with the initial letter as the
// fallback when no icon resolves.
Rectangle {
    id: root

    property Appearance appearance: Appearance {}
    property string iconSource: ""
    property string fallbackText: ""
    // The launcher rung by default; a compact preview card steps down to a
    // smaller ladder rung instead of picking a pixel size of its own.
    property int tileSize: appearance.previewTile

    readonly property string catalogueCdn:
        "https://cdn.jsdelivr.net/gh/homarr-labs/dashboard-icons/png/"

    // Mirrors webapp.py resolve_icon(): paths stay local, URLs load exactly as
    // typed, and a bare word is a Dashboard Icons name used verbatim - the user
    // picks the variant (e.g. "github-light") themselves.
    readonly property string resolved: {
        const value = String(root.iconSource || "").trim();
        if (value === "")
            return "";
        if (value.indexOf("file://") === 0)
            return value;
        if (value.indexOf("/") === 0)
            return "file://" + value;
        if (value.indexOf("~/") === 0)
            return "file://" + Quickshell.env("HOME") + value.slice(1);
        const lower = value.toLowerCase();
        if (lower.indexOf("http://") === 0 || lower.indexOf("https://") === 0) {
            // Catalogue links in any format resolve to the PNG copy of the same
            // name: Qt here has no webp plugin, and the PNG is the same artwork.
            const match = value.match(
                /^https:\/\/cdn\.jsdelivr\.net\/gh\/homarr-labs\/dashboard-icons\/(?:png|webp|svg)\/([a-z0-9._-]+)\.(?:png|webp|svg)$/i);
            return match ? root.catalogueCdn + match[1].toLowerCase() + ".png" : value;
        }
        const name = value.replace(/[^a-zA-Z0-9._-]+/g, "-")
            .replace(/^-+|-+$/g, "").toLowerCase();
        return name === "" ? "" : root.catalogueCdn + name + ".png";
    }

    implicitWidth: root.tileSize
    implicitHeight: root.tileSize
    radius: appearance.shapeMedium
    color: appearance.surfaceContainerHigh
    border.width: appearance.borderWidth
    border.color: appearance.outline

    Image {
        id: iconImage
        anchors.centerIn: parent
        width: root.appearance.iconSizeMd
        height: width
        sourceSize.width: root.appearance.iconSizeMd * 2
        sourceSize.height: root.appearance.iconSizeMd * 2
        source: root.resolved
        fillMode: Image.PreserveAspectFit
        smooth: true
        visible: status === Image.Ready
    }

    MaterialIcon {
        anchors.centerIn: parent
        visible: iconImage.status !== Image.Ready && String(root.fallbackText || "").trim() === ""
        icon: "image"
        iconSize: root.appearance.iconSizeMd
        iconColor: root.appearance.textMuted
    }

    Text {
        anchors.centerIn: parent
        visible: iconImage.status !== Image.Ready && String(root.fallbackText || "").trim() !== ""
        text: String(root.fallbackText || "").trim().charAt(0).toUpperCase()
        renderType: Text.NativeRendering
        font.family: root.appearance.uiFont
        font.weight: root.appearance.fontWeightUi
        font.variableAxes: root.appearance.fontVariableAxesUi
        font.pixelSize: root.appearance.iconSizeMd
        color: root.appearance.accentInk
    }
}
