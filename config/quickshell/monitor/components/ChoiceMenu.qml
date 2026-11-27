import QtQuick
import ".."

// The floating dropdown menu, drawn by the plaque OVER its content instead of
// inside the field. Opening it never changes the plaque's height: the list
// covers the rows below (or flips above the field when there is no room), the
// way an MD3 exposed dropdown menu behaves.
//
// Reads its rows and navigation state straight from the ChoiceField that owns
// it; a click commits through the field so keyboard and mouse share one path.
Item {
    id: menu

    property Appearance appearance: Appearance {}
    property var field: null

    readonly property var options: menu.field ? menu.field.options : []
    readonly property int menuHeight: Math.min(menu.options.length * menu.appearance.popupRowHeight,
                                               menu.appearance.popupMaxHeight)

    width: menu.field ? menu.field.width : 0
    height: menu.menuHeight
    visible: menu.field !== null && menu.options.length > 0

    function ensureVisible() {
        if (!menu.field)
            return;
        const rowY = menu.field.listIndex * menu.appearance.popupRowHeight;
        const maxY = Math.max(0, flick.contentHeight - flick.height);
        flick.contentY = Math.max(0, Math.min(maxY, rowY - flick.height / 2));
    }

    onFieldChanged: menu.ensureVisible()

    Connections {
        target: menu.field
        function onListIndexChanged() { menu.ensureVisible(); }
    }

    Rectangle {
        anchors.fill: parent
        radius: menu.appearance.shapeMedium
        color: menu.appearance.surfaceContainerHigh
        border.width: menu.appearance.borderWidth
        border.color: menu.appearance.outline
    }

    Flickable {
        id: flick

        anchors.fill: parent
        anchors.margins: menu.appearance.borderWidth
        contentHeight: rows.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds

        Column {
            id: rows

            width: flick.width

            Repeater {
                model: menu.options

                Rectangle {
                    id: row

                    required property var modelData
                    required property int index

                    width: rows.width
                    height: menu.appearance.popupRowHeight
                    radius: menu.appearance.shapeSmall
                    // Review hook: no pointer automation on this host, so a
                    // preview can force the pressed state while a capture runs.
                    property bool forcePressed: false
                    readonly property bool current: !!menu.field && row.index === menu.field.listIndex
                    readonly property bool held: row.forcePressed || rowPress.pressed

                    // The keyboard's current row takes the rung above hover, so a
                    // hovered row can never be read as the one Enter would take.
                    color: row.held
                        ? menu.appearance.pressFill
                        : (row.current ? menu.appearance.hoverFillHigh
                            : (rowHover.hovered ? menu.appearance.hoverFill : "transparent"))
                    border.width: menu.appearance.borderWidth
                    border.color: (rowHover.hovered || row.held) && !row.current
                        ? menu.appearance.gilt : "transparent"

                    Behavior on color {
                        ColorAnimation {
                            duration: row.held ? menu.appearance.motionPressDuration : menu.appearance.motionControlDuration
                            easing.type: menu.appearance.motionControlEasing
                        }
                    }

                    Behavior on border.color {
                        ColorAnimation {
                            duration: menu.appearance.motionControlDuration
                            easing.type: menu.appearance.motionControlEasing
                        }
                    }

                    Text {
                        anchors.left: parent.left
                        anchors.leftMargin: menu.appearance.spacingSmall
                        anchors.right: parent.right
                        anchors.rightMargin: menu.appearance.spacingSmall
                        anchors.verticalCenter: parent.verticalCenter
                        text: row.modelData.rowLabel || row.modelData.label
                        color: menu.field && row.index === menu.field.currentIndex
                            ? menu.appearance.accentInk : menu.appearance.text
                        elide: Text.ElideRight
                        font.family: menu.appearance.uiFont
                        font.weight: menu.appearance.fontWeightUi
                        font.variableAxes: menu.appearance.fontVariableAxesUi
                        font.pixelSize: menu.appearance.fontSizeSmall
                    }

                    HoverHandler { id: rowHover }

                    MouseArea {
                        id: rowPress
                        anchors.fill: parent
                        onClicked: {
                            if (!menu.field)
                                return;
                            menu.field.listIndex = row.index;
                            menu.field.commit();
                        }
                    }
                }
            }
        }
    }
}
