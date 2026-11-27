import QtQuick
import ".."

// Hairline that divides two groups of modules, sized to the bar's content row.
Item {
    id: root

    property Appearance appearance: Appearance {}

    width: appearance.borderWidth
    height: appearance.contentHeight

    Rectangle {
        anchors.centerIn: parent
        width: appearance.borderWidth
        height: appearance.separatorHeight
        color: appearance.outline
    }
}
