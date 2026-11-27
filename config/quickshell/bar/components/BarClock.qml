import QtQuick
import Quickshell
import ".."
import "."

// Date over a hairline, then the time in the UI face at clock size: the gallery plaque
// composition the other surfaces use.
//
// The whole block is the calendar's click target — a date you cannot click is a
// missed affordance — so it carries a hover state layer and a pointer cursor.
// The padding widens the target without moving the clock off the bar's centre.
Item {
    id: root

    property Appearance appearance: Appearance {}
    property date now: new Date()

    // Review hook: there is no pointer automation on this host (no ydotool), so
    // a preview can force the hover state instead of asking the user to keep the
    // mouse over the clock while a capture runs.
    property bool forceHover: false
    property bool forcePressed: false
    readonly property bool hovered: forceHover || mouseArea.containsMouse
    readonly property bool held: forcePressed || mouseArea.pressed

    implicitWidth: clockRow.implicitWidth + appearance.dotHitPad * 2
    implicitHeight: appearance.contentHeight
    width: implicitWidth
    height: implicitHeight

    Accessible.name: "Open calendar"
    Accessible.role: Accessible.Button

    Rectangle {
        anchors.fill: parent
        radius: root.appearance.radius
        // Hover lights the block instead of tinting it: the fill steps up the
        // tonal ladder and the edge ignites gilt, both from the shared material
        // roles. Press steps the fill back down.
        color: root.held
            ? root.appearance.pressFill
            : (root.hovered ? root.appearance.hoverFill : "transparent")
        border.width: root.appearance.borderWidth
        border.color: root.hovered || root.held ? root.appearance.gilt : "transparent"
        Behavior on color {
            ColorAnimation {
                duration: root.held ? root.appearance.motionPressDuration : root.appearance.motionControlDuration
                easing: root.appearance.motionControlEasing
            }
        }
        Behavior on border.color {
            ColorAnimation {
                duration: root.appearance.motionControlDuration
                easing: root.appearance.motionControlEasing
            }
        }
    }

    Row {
        id: clockRow

        anchors.centerIn: parent
        spacing: root.appearance.clockGap

        Text {
            text: root.dayLabel(root.now)
            color: root.appearance.text
            font.family: root.appearance.uiFont
            font.weight: root.appearance.fontWeightUi
            font.variableAxes: root.appearance.fontVariableAxesUi
            font.pixelSize: root.appearance.fontSizeMicro
            font.letterSpacing: root.appearance.letterSpacingLabel
            height: root.height
            verticalAlignment: Text.AlignVCenter
        }

        BarSeparator {
            appearance: root.appearance
        }

        Text {
            text: Qt.formatTime(root.now, "HH:mm")
            color: root.appearance.textBright
            font.family: root.appearance.displayFont
            font.weight: root.appearance.fontWeightDisplay
            font.variableAxes: root.appearance.fontVariableAxesDisplay
            font.pixelSize: root.appearance.fontSizeBody
            font.letterSpacing: root.appearance.letterSpacingDisplay
            height: root.height
            verticalAlignment: Text.AlignVCenter
        }
    }

    MouseArea {
        id: mouseArea

        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor

        // Same script as SUPER+C. It toggles: a second click closes the panel
        // instead of stacking another copy on top of the first.
        onClicked: Quickshell.execDetached([
            Quickshell.env("HOME") + "/.scripts/session/calendar.sh"
        ])
    }

    Timer {
        interval: 1000
        running: true
        repeat: true
        onTriggered: root.now = new Date()
    }

    // The bar never shows a Spanish abbreviation, whatever the session locale is.
    function dayLabel(when) {
        const days = ["SUN", "MON", "TUE", "WED", "THU", "FRI", "SAT"];
        const months = ["JAN", "FEB", "MAR", "APR", "MAY", "JUN",
                        "JUL", "AUG", "SEP", "OCT", "NOV", "DEC"];
        const day = when.getDate();
        return days[when.getDay()] + " "
            + (day < 10 ? "0" + day : day) + " "
            + months[when.getMonth()];
    }
}
