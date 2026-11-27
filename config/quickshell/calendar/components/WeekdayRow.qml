import QtQuick
import ".."

// Monday-first weekday header. Static: it does not follow the visible month.
Row {
    id: row

    property Appearance appearance: Appearance {}

    spacing: appearance.cellGap

    Repeater {
        model: ["MO", "TU", "WE", "TH", "FR", "SA", "SU"]

        delegate: Text {
            required property string modelData

            width: row.appearance.cellSize
            horizontalAlignment: Text.AlignHCenter
            text: modelData
            color: row.appearance.textMuted
            font.family: row.appearance.uiFont
            font.weight: row.appearance.fontWeightUi
            font.variableAxes: row.appearance.fontVariableAxesUi
            font.pixelSize: row.appearance.fontSizeSmall
            font.letterSpacing: row.appearance.letterSpacingLabel
        }
    }
}
