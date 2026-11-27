import QtQuick
import QtQuick.Layouts
import ".."

// One pill recipe for the creator's actions. The buttons differ only in their
// label, glyph and whether they are the primary action; shape, fill ladder,
// edge and type all come from this file so the row reads as one set.
Rectangle {
    id: root

    property Appearance appearance: Appearance {}
    property string label: ""
    property string glyph: ""
    // The primary action wears the accent; the others stay on the tonal rung.
    property bool active: false
    property bool actionEnabled: true

    signal clicked()

    objectName: "action-button"

    // Equal token widths plus fillWidth split the row evenly: a zero preferred
    // width lets Qt distribute the surplus by an undefined ratio.
    Layout.fillWidth: true
    Layout.preferredWidth: root.appearance.buttonHeight
    Layout.preferredHeight: root.appearance.buttonHeight

    radius: root.appearance.shapeLarge
    color: root.active
        ? root.appearance.accent
        : (press.pressed ? root.appearance.pressFill
            : (press.containsMouse ? root.appearance.hoverFill
                : root.appearance.surfaceContainerHigh))
    border.width: root.appearance.borderWidth
    border.color: root.active
        ? root.appearance.accent
        : (press.containsMouse ? root.appearance.gilt : root.appearance.outline)

    readonly property color ink: root.active
        ? root.appearance.accentText
        : (press.containsMouse ? root.appearance.accentInk : root.appearance.textMuted)

    RowLayout {
        anchors.centerIn: parent
        spacing: root.appearance.spacingSmall

        MaterialIcon {
            icon: root.glyph
            iconSize: root.appearance.iconSizeSm
            iconColor: root.ink
        }

        Text {
            text: root.label
            color: root.ink
            renderType: Text.NativeRendering
            font.family: root.appearance.uiFont
            font.weight: root.appearance.fontWeightUi
            font.variableAxes: root.appearance.fontVariableAxesUi
            font.pixelSize: root.appearance.fontSizeCaption
            font.letterSpacing: root.appearance.letterSpacingCaption
        }
    }

    MouseArea {
        id: press

        anchors.fill: parent
        hoverEnabled: true
        enabled: root.actionEnabled
        cursorShape: root.actionEnabled ? Qt.PointingHandCursor : Qt.ArrowCursor
        onClicked: root.clicked()
    }
}
