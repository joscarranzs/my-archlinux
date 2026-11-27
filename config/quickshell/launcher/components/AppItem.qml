import QtQuick
import Quickshell

// Material Design 3 style app tile: a tonal icon container with a
// single-line label underneath and a state-layer hover/selection effect.
Item {
    id: root

    property var appearance
    property var entry
    property bool selected: false

    // Review hook: this host has no pointer automation, so a preview can force
    // the pressed state while a capture runs.
    property bool forcePressed: false
    readonly property bool hovered: mouseArea.containsMouse
    readonly property bool held: forcePressed || mouseArea.pressed

    signal clicked()

    width: appearance.gridCell
    height: appearance.gridCell

    // The icon sits in a rounded, tonal container (MD3 shape + surface roles).
    // The container is also the hover target: the fill steps one rung up the
    // ladder (hoverFillHigh, because the tile already rests at hoverFill) and the
    // edge ignites gilt. Selection keeps the accent edge and the ochre label, so
    // the ornament and the action never carry the same signal.
    Rectangle {
        id: tile
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        anchors.topMargin: appearance.spacingXs
        width: appearance.gridCell - appearance.spacingSmall
        height: width
        radius: appearance.shapeLarge
        color: root.held
            ? appearance.pressFill
            : (root.hovered ? appearance.hoverFillHigh : appearance.surfaceContainerHigh)
        border.width: root.appearance.borderWidth * (root.selected ? 2 : 1)
        border.color: root.selected
            ? appearance.accent
            : (root.hovered || root.held ? appearance.gilt : appearance.outline)

        Behavior on color {
            ColorAnimation {
                duration: root.held ? appearance.motionPressDuration : appearance.motionControlDuration
                easing: appearance.motionControlEasing
            }
        }

        Behavior on border.color {
            ColorAnimation {
                duration: appearance.motionControlDuration
                easing: appearance.motionControlEasing
            }
        }

        // Icon. The tile is 104 px of the 112 px cell, so the icon takes the tile
        // rung of the ladder (48) and not iconXs — 16 px inside a tile that size
        // is a speck, which is what the launcher shipped with.
        Image {
            id: iconImage
            anchors.centerIn: parent
            width: appearance.iconSizeTile
            height: appearance.iconSizeTile
            sourceSize.width: appearance.iconSizeTile * 2
            sourceSize.height: appearance.iconSizeTile * 2
            source: ""
            visible: false
            fillMode: Image.PreserveAspectFit
            smooth: true
        }

        // Fallback: first letter of the app name, at the same rung so an app with
        // no icon still reads as an object and not as a gap.
        Text {
            id: iconFallback
            anchors.centerIn: parent
            text: root.entry ? (root.entry.name ? root.entry.name.charAt(0).toUpperCase() : "?") : "?"
            font.family: appearance.uiFont
            font.weight: appearance.fontWeightUi
            font.variableAxes: appearance.fontVariableAxesUi
            font.pixelSize: appearance.iconSizeTile
            font.bold: true
            color: appearance.accentInk
            visible: true
        }

        // Load icon asynchronously via Quickshell.iconPath.
        Component.onCompleted: root.resolveIcon()
    }

    // Label below the icon container. Two lines, because a 104 px column fits
    // about fifteen JetBrainsMono characters at 11 px (0.6000 em, against Space
    // Mono's 0.6120) and three of the owner's apps are longer ("Yazi File
    // Manager" is seventeen): one line elided them, two lines wrap the name
    // instead of hiding it, and the cell is 136 px tall so there is room. The
    // elide stays for the name that needs a third line.
    Text {
        id: label
        anchors.top: tile.bottom
        anchors.topMargin: appearance.spacingXs
        anchors.horizontalCenter: parent.horizontalCenter
        width: parent.width - appearance.spacingSmall
        text: root.entry ? (root.entry.name || "") : ""
        font.family: appearance.uiFont
        font.weight: appearance.fontWeightUi
        font.variableAxes: appearance.fontVariableAxesUi
        font.pixelSize: appearance.fontSizeSmall
        font.letterSpacing: appearance.letterSpacingDisplay
        color: root.selected ? appearance.accentInk : appearance.textMuted
        horizontalAlignment: Text.AlignHCenter
        maximumLineCount: 2
        wrapMode: Text.Wrap
        elide: Text.ElideRight
    }

    MouseArea {
        id: mouseArea
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.clicked()
    }

    // Resolve the entry icon to a filesystem path.
    function resolveIcon() {
        if (!root.entry) return;
        const name = root.entry.icon || "";
        if (name.length === 0) return;
        // Use Quickshell.iconPath if available.
        try {
            const resolved = Quickshell.iconPath(name, true);
            if (resolved && resolved.length > 0 && !resolved.includes("image-missing")) {
                iconImage.source = resolved;
                iconImage.visible = true;
                iconFallback.visible = false;
            }
        } catch (e) {
            // Keep fallback letter.
        }
    }
}
