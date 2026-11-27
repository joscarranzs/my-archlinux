import QtQuick
import ".."
import "."

// One status module: a single glyph, no reading. The bar shows state with the
// icon alone; the numbers belong to the panels that open from it.
//
// A module only grows a click target and a hover veil when it is interactive: on
// the bar, the difference between "this opens something" and "this is a readout"
// has to be visible before the pointer commits.
Item {
    id: root

    property Appearance appearance: Appearance {}
    property string icon: ""
    property color iconColor: appearance.textMuted
    property bool interactive: false
    property bool forceHover: false
    property bool forcePressed: false
    // Optical sizing, on by default: the status row is the one place where every
    // glyph variant (volume off / mute / down / up, the seven battery bands) has
    // to look like one set, and the font draws them at different ink sizes.
    property bool optical: true

    readonly property bool hovered: forceHover || mouseArea.containsMouse
    readonly property bool held: forcePressed || mouseArea.pressed

    signal activated()

    // A uniform cell, not the glyph's own advance width. Material Symbols draws
    // every glyph on the same 1 em advance, so the width was never the problem;
    // what made the row look ragged was the ink inside it, which is what
    // MaterialIcon's `optical` flag evens out. This cell keeps the hit target and
    // the hover veil on one box for every module.
    //
    // The cell does NOT depend on `interactive`: giving only the clickable items
    // the extra hit padding set their ink 35 px apart while the readouts sat 25 px
    // apart, which reads as a hole in the cluster. Every module owns the same box;
    // only the veil and the cursor differ.
    width: appearance.iconSizeXs + appearance.dotHitPad * 2
    height: appearance.contentHeight

    Rectangle {
        anchors.fill: parent
        visible: root.interactive
        radius: root.appearance.radius
        // Hover lights the cell instead of tinting it: one rung up the tonal
        // ladder plus a gilt hairline. Press steps the fill back down.
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

    MaterialIcon {
        id: glyph
        anchors.centerIn: parent
        icon: root.icon
        iconSize: root.appearance.iconSizeXs
        iconColor: root.iconColor
        optical: root.optical
    }

    MouseArea {
        id: mouseArea
        anchors.fill: parent
        enabled: root.interactive
        hoverEnabled: root.interactive
        cursorShape: root.interactive ? Qt.PointingHandCursor : Qt.ArrowCursor
        onClicked: root.activated()
    }
}
