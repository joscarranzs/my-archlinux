import QtQuick
import "."
import ".."

// Month title between the shared gallery rule and the navigation buttons.
// Same rule, tracking and letter spacing as the launcher header, so the two
// panels read as one family.
Item {
    id: header

    property Appearance appearance: Appearance {}
    property string title: ""

    signal previous()
    signal next()

    Rectangle {
        id: rule
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        width: header.appearance.ruleWidth
        height: header.appearance.ruleThickness
        color: header.appearance.gilt
    }

    Text {
        id: titleLabel
        anchors.left: rule.right
        anchors.leftMargin: header.appearance.spacingSmall
        anchors.right: navRow.left
        anchors.rightMargin: header.appearance.spacingSmall
        anchors.verticalCenter: parent.verticalCenter
        text: header.title
        color: header.appearance.text
        elide: Text.ElideRight
        font.family: header.appearance.displayFont
        font.weight: header.appearance.fontWeightDisplay
        font.variableAxes: header.appearance.fontVariableAxesDisplay
        // Body size, not the display size: at 20 px the month and year need more
        // width than the grid leaves between the rule and the nav buttons, and a
        // clipped title ("NOVEMBER 2…") reads as a broken panel.
        font.pixelSize: header.appearance.fontSizeBody
        font.letterSpacing: header.appearance.letterSpacingDisplay
    }

    Row {
        id: navRow
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        spacing: header.appearance.cellGap

        NavButton {
            appearance: header.appearance
            icon: "chevron_left"
            Accessible.name: "Previous month"
            onClicked: header.previous()
        }

        NavButton {
            appearance: header.appearance
            icon: "chevron_right"
            Accessible.name: "Next month"
            onClicked: header.next()
        }
    }
}
