import QtQuick
import ".."

// One day in the month grid.
//
// Four states, in the order they matter: out-of-month (dimmed), today (accent
// number plus a dot), selected (raised fill and hairline) and hover (state layer
// only). The accent is spent on "today" alone; a selection is a surface change,
// so the two never fight for the eye.
Rectangle {
    id: cell

    property Appearance appearance: Appearance {}
    property int dayNumber: 1
    property bool inMonth: true
    property bool today: false
    property bool selected: false

    signal activated()

    width: appearance.cellSize
    height: appearance.cellSize
    radius: appearance.shapeSmall
    // Selection takes the rung above hover (the palette's own selection step), so
    // a hovered cell can never be mistaken for a chosen day. Hover lights the
    // cell — one rung up plus a gilt hairline — and press steps it back down.
    color: cell.selected
        ? appearance.hoverFillHigh
        : (cell.held ? appearance.pressFill
            : (cell.hovered ? appearance.hoverFill : "transparent"))
    border.width: appearance.borderWidth
    border.color: cell.selected
        ? appearance.outline
        : (cell.hovered || cell.held ? appearance.gilt : "transparent")

    Behavior on color {
        ColorAnimation {
            duration: cell.held ? appearance.motionPressDuration : appearance.motionControlDuration
            easing: appearance.motionControlEasing
        }
    }

    Behavior on border.color {
        ColorAnimation {
            duration: appearance.motionControlDuration
            easing: appearance.motionControlEasing
        }
    }

    property bool forcePressed: false
    readonly property bool hovered: mouseArea.containsMouse
    readonly property bool held: forcePressed || mouseArea.pressed

    Text {
        anchors.centerIn: parent
        anchors.verticalCenterOffset: cell.today ? -1 : 0
        text: cell.dayNumber
        color: cell.today
            ? appearance.accentInk
            : (cell.inMonth ? appearance.text : appearance.textFaint)
        font.family: appearance.uiFont
        font.weight: appearance.fontWeightUi
        font.variableAxes: appearance.fontVariableAxesUi
        font.pixelSize: appearance.fontSizeBody
        font.bold: cell.today
    }

    // Today keeps a marker of its own: once the day is also selected, the raised
    // fill leaves the accent number with less contrast than its neighbours.
    Rectangle {
        visible: cell.today
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: appearance.spacingSmall / 2
        width: appearance.todayDot
        height: appearance.todayDot
        radius: appearance.shapeFull
        color: appearance.accent
    }

    MouseArea {
        id: mouseArea
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: cell.activated()
    }
}
