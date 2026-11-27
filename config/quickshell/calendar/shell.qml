import Quickshell
import Quickshell.Wayland
import QtQuick
import "services"
import "components"
import "."

// On-demand calendar overlay (Quickshell).
//
// Launched by scripts/session/calendar.sh (SUPER+C); closes on Esc or a scrim
// click. Left/Right change month, T returns to today, and a click selects a day.
// Month grid only for now: events are a later layer, not part of this surface.
ShellRoot {
    id: root

    Appearance { id: appearance }

    CalendarMath {
        id: calendarMath
        cellCount: appearance.cellCount
    }

    property int selectedIndex: -1

    PanelWindow {
        id: window

        anchors {
            top: true
            bottom: true
            left: true
            right: true
        }
        color: "transparent"

        // -1 ignores the bar's reserved strip, so the scrim covers the whole
        // screen and the plaque centers on the output, not on the usable area.
        exclusiveZone: -1
        WlrLayershell.namespace: "quickshell:calendar"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand

        // Scrim: dismiss on click outside the plaque.
        Rectangle {
            anchors.fill: parent
            color: Qt.rgba(0, 0, 0, appearance.scrimOpacity)
            // The scrim rides the plaque's entrance: one driver, so a slow first frame
            // cannot present the backdrop without the plaque in front of it.
            opacity: panel.opacity

            MouseArea {
                anchors.fill: parent
                onClicked: Qt.quit()
            }
        }

        CalendarPanel {
            id: panel

            anchors.centerIn: parent
            appearance: appearance
            monthLabel: calendarMath.monthLabel
            cells: calendarMath.cells
            selectedIndex: root.selectedIndex

            onDayActivated: (index) => root.selectedIndex = index
            onMonthPrevious: calendarMath.step(-1)
            onMonthNext: calendarMath.step(1)
            onTodayRequested: calendarMath.reset()

            Component.onCompleted: requestFocus()
        }
    }
}
