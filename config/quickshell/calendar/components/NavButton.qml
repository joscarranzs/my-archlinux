import QtQuick
import ".."

// Square icon button for month navigation. Hover lights the button — one rung up
// the tonal ladder plus a gilt hairline — so navigation and the app tiles feel
// like the same desktop.
Item {
    id: button

    property Appearance appearance: Appearance {}
    property string icon: ""

    property bool forcePressed: false
    readonly property bool hovered: mouseArea.containsMouse
    readonly property bool held: forcePressed || mouseArea.pressed

    signal clicked()

    width: appearance.navSize
    height: appearance.navSize

    // Painted as its own child so the glyph keeps full opacity while the fill
    // moves under it.
    Rectangle {
        anchors.fill: parent
        radius: button.appearance.shapeSmall
        color: button.held
            ? button.appearance.pressFill
            : (button.hovered ? button.appearance.hoverFill : "transparent")
        border.width: button.appearance.borderWidth
        border.color: button.hovered || button.held ? button.appearance.gilt : "transparent"
        Behavior on color {
            ColorAnimation {
                duration: button.held ? button.appearance.motionPressDuration : button.appearance.motionControlDuration
                easing: button.appearance.motionControlEasing
            }
        }
        Behavior on border.color {
            ColorAnimation {
                duration: button.appearance.motionControlDuration
                easing: button.appearance.motionControlEasing
            }
        }
    }

    MaterialIcon {
        anchors.centerIn: parent
        icon: button.icon
        iconColor: button.appearance.textMuted
        iconSize: button.appearance.iconSizeSm
    }

    MouseArea {
        id: mouseArea
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: button.clicked()
    }
}
