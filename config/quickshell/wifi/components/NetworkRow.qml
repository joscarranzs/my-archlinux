import QtQuick
import ".."

// One network in the list: name, security/subtitle and signal bars.
//
// Hover and selection share the launcher's state layer (accent at
// look.opacity.stateLayer) painted as a child rectangle, so the glyphs and the
// name keep full opacity while the tint fades. Selection adds the accent bar on
// the left -- the one full-strength accent this row is allowed.
Item {
    id: row

    property Appearance appearance: Appearance {}
    property string ssid: ""
    property string subtitle: ""
    property int percent: 0
    property bool connected: false
    property bool selected: false
    property bool forceHover: false
    property bool forcePressed: false

    signal activated()

    readonly property bool hovered: forceHover || area.containsMouse
    readonly property bool held: forcePressed || area.pressed

    // Width is set by the instance: a Column gives its children no width, so a
    // `parent.width` binding evaluates to 0 at creation and never updates.
    height: appearance.rowHeight

    // Hover lights the row instead of tinting it: the fill steps up the tonal
    // ladder and the edge ignites gilt, both from the shared material roles.
    // Press steps the fill back down.
    Rectangle {
        anchors.fill: parent
        radius: row.appearance.shapeMedium
        color: row.held
            ? row.appearance.pressFill
            : (row.hovered ? row.appearance.hoverFill : "transparent")
        border.width: row.appearance.borderWidth
        border.color: row.hovered || row.held ? row.appearance.gilt : "transparent"
        Behavior on color {
            ColorAnimation {
                duration: row.held ? row.appearance.motionPressDuration : row.appearance.motionControlDuration
                easing: row.appearance.motionControlEasing
            }
        }
        Behavior on border.color {
            ColorAnimation {
                duration: row.appearance.motionControlDuration
                easing: row.appearance.motionControlEasing
            }
        }
    }

    Rectangle {
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        width: row.appearance.borderWidth * 2
        height: row.appearance.rowHeight - row.appearance.spacingSmall * 2
        radius: width / 2
        color: row.appearance.accent
        visible: row.selected
    }

    // Name over subtitle, in a Column: anchoring one to the top and the other to the
    // bottom of a fixed-height row makes them collide as soon as the two lines plus
    // their margins exceed the row height.
    Column {
        id: lines

        anchors.left: parent.left
        anchors.leftMargin: row.appearance.spacingSmall * 2
        anchors.right: bars.left
        anchors.rightMargin: row.appearance.spacingSmall
        anchors.verticalCenter: parent.verticalCenter
        spacing: row.appearance.hairline

        Text {
            width: lines.width
            text: row.ssid
            color: row.appearance.text
            elide: Text.ElideRight
            font.family: row.appearance.uiFont
            font.weight: row.appearance.fontWeightUi
            font.variableAxes: row.appearance.fontVariableAxesUi
            font.pixelSize: row.appearance.fontSizeBody
            font.letterSpacing: 0
        }

        Text {
            width: lines.width
            text: row.subtitle
            color: row.connected ? row.appearance.accentInk : row.appearance.textMuted
            elide: Text.ElideRight
            font.family: row.appearance.uiFont
            font.weight: row.appearance.fontWeightUi
            font.variableAxes: row.appearance.fontVariableAxesUi
            font.pixelSize: row.appearance.fontSizeSmall
            font.letterSpacing: row.appearance.letterSpacingCaption
        }
    }

    SignalBars {
        id: bars

        anchors.right: parent.right
        anchors.rightMargin: row.appearance.spacingSmall * 2
        anchors.verticalCenter: parent.verticalCenter
        appearance: row.appearance
        percent: row.percent
        barColor: row.connected ? row.appearance.accent : row.appearance.textMuted
    }

    MouseArea {
        id: area
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: {
            row.activated();
        }
    }
}
