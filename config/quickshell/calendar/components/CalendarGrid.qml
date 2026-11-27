import QtQuick
import ".."

// Weekday header plus the fixed grid of day cells.
//
// The cells arrive already computed (see services/CalendarMath.qml), so this
// component only decides how a day looks. The index of the selected cell is a
// plain int because selection is the only state the panel owns.
Column {
    id: grid

    property Appearance appearance: Appearance {}
    property var cells: []
    property int selectedIndex: -1

    signal dayActivated(int index)

    spacing: appearance.spacingSmall

    WeekdayRow {
        appearance: grid.appearance
    }

    Grid {
        columns: grid.appearance.columns
        rowSpacing: grid.appearance.cellGap
        columnSpacing: grid.appearance.cellGap

        Repeater {
            model: grid.cells

            delegate: DayCell {
                required property var modelData
                required property int index

                appearance: grid.appearance
                dayNumber: modelData.day
                inMonth: modelData.inMonth
                today: modelData.today
                selected: grid.selectedIndex === index
                onActivated: grid.dayActivated(index)
            }
        }
    }
}
