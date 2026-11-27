import QtQuick
import Quickshell
import "."

// Unified search bar: one surface with a leading glyph, a block caret and a
// single hairline that turns gold while focused. The old double-box layout
// (icon box + input box) competed with the selected app tile for attention.
Rectangle {
    id: root

    property var appearance
    property alias text: input.text

    signal queryChanged(string text)
    signal accepted()
    signal dismissed()
    signal navigate(int delta)

    implicitHeight: appearance.fieldHeightHero
    radius: appearance.shapeMedium
    color: appearance.surfaceContainerHigh
    border.width: appearance.borderWidth
    border.color: input.activeFocus ? appearance.accent : appearance.outline

    MaterialIcon {
        id: leadIcon
        anchors.left: parent.left
        anchors.leftMargin: appearance.spacingLarge
        anchors.verticalCenter: parent.verticalCenter
        icon: "search"
        iconSize: appearance.iconSizeSm
        iconColor: input.activeFocus ? appearance.accentInk : appearance.textMuted
    }

    TextInput {
        id: input
        anchors.left: leadIcon.right
        anchors.leftMargin: appearance.spacingSmall
        anchors.right: parent.right
        anchors.rightMargin: appearance.spacingLarge
        anchors.verticalCenter: parent.verticalCenter
        verticalAlignment: TextInput.AlignVCenter
        font.family: appearance.uiFont
        font.weight: appearance.fontWeightUi
        font.variableAxes: appearance.fontVariableAxesUi
        font.pixelSize: appearance.fontSizeBody
        color: appearance.text
        clip: true
        selectByMouse: true

        // Block caret, hidden while empty so it never sits over the placeholder.
        cursorDelegate: Rectangle {
            width: appearance.cursorWidth
            color: appearance.accent
            opacity: appearance.opacityCursor
            radius: appearance.hairline
            visible: input.text.length > 0
        }

        onTextChanged: root.queryChanged(text)
        onAccepted: root.accepted()

        Keys.onPressed: (event) => {
            if (event.key === Qt.Key_Escape) {
                root.dismissed();
                event.accepted = true;
            } else if (event.key === Qt.Key_Down || event.key === Qt.Key_Right) {
                root.navigate(1);
                event.accepted = true;
            } else if (event.key === Qt.Key_Up || event.key === Qt.Key_Left) {
                root.navigate(-1);
                event.accepted = true;
            }
        }
    }

    // Placeholder bound to the text, never to focus: the field is force-focused
    // on open, so a focus-based condition would flash and vanish instantly.
    Text {
        anchors.left: input.left
        anchors.verticalCenter: parent.verticalCenter
        width: input.width
        text: "search apps…"
        color: appearance.textMuted
        opacity: appearance.opacityPlaceholder
        font.family: appearance.uiFont
        font.weight: appearance.fontWeightUi
        font.variableAxes: appearance.fontVariableAxesUi
        font.pixelSize: appearance.fontSizeBody
        font.letterSpacing: appearance.letterSpacingCaption
        elide: Text.ElideRight
        visible: input.text.length === 0
    }

    function forceFocus() {
        input.forceActiveFocus();
    }
}
