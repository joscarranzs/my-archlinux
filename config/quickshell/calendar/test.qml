import Quickshell
import QtQuick
import "services"
import "components"
import "."

// Preview the calendar in a floating window (no compositor layer-shell needed).
ShellRoot {
    id: root

    Appearance { id: appearance }

    CalendarMath {
        id: calendarMath
        cellCount: appearance.cellCount
    }

    property int selectedIndex: -1

    FloatingWindow {
        implicitWidth: appearance.panelWidth + appearance.spacingMedium * 2
        implicitHeight: appearance.panelHeight + appearance.spacingMedium * 2
        title: "Calendar preview"

        Rectangle {
            anchors.fill: parent
            color: appearance.surface

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

    Connections {
        target: Quickshell
        function onLastWindowClosed() { Qt.quit() }
    }
}
