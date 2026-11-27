import QtQuick

// Date math for the month grid.
//
// Holds the visible month and turns it into the fixed set of cells the panel
// draws, so the QML side stays presentational and never calls Date() itself.
// The grid is deliberately a fixed rows x columns block: a month that fits in
// five rows would otherwise shrink the panel and move the frame under the
// pointer.
QtObject {
    id: math

    // Any date inside the visible month; only year and month are read.
    property date anchor: new Date()

    // Supplied by the panel from the theme tokens (columns * rows).
    property int cellCount: 42

    readonly property int year: anchor.getFullYear()
    readonly property int month: anchor.getMonth()

    // Monday-first index of the 1st. JavaScript counts Sunday as 0, so shifting
    // by six keeps a European week from starting on Sunday.
    readonly property int firstColumn: (new Date(year, month, 1).getDay() + 6) % 7

    readonly property string monthLabel: monthNames[month] + " " + year

    readonly property var monthNames: [
        "JANUARY", "FEBRUARY", "MARCH", "APRIL", "MAY", "JUNE",
        "JULY", "AUGUST", "SEPTEMBER", "OCTOBER", "NOVEMBER", "DECEMBER"
    ]

    // Rebuilt whenever the month, the anchor or the cell count changes. The two
    // bare reads below are the explicit dependencies: without them a function
    // call in the expression leaves QML free to keep the old array.
    readonly property var cells: {
        math.anchor;
        math.cellCount;
        return math.buildCells();
    }

    function buildCells() {
        const cells = [];
        const today = new Date();
        for (let index = 0; index < cellCount; index += 1) {
            const date = new Date(year, month, 1 - firstColumn + index);
            cells.push({
                "day": date.getDate(),
                "inMonth": date.getMonth() === month && date.getFullYear() === year,
                "today": isSameDay(date, today)
            });
        }
        return cells;
    }

    function isSameDay(left, right) {
        return left.getDate() === right.getDate()
            && left.getMonth() === right.getMonth()
            && left.getFullYear() === right.getFullYear();
    }

    // Move the visible month, keeping the 1st as the anchor so stepping back
    // from the 31st does not skip a month.
    function step(months) {
        anchor = new Date(year, month + months, 1);
    }

    function reset() {
        anchor = new Date();
    }
}
