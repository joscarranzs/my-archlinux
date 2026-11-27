import QtQuick
import ".."

// Horizontal level control: track, filled portion, knob.
//
// Same control as volume/components/VolumeSlider.qml, duplicated rather than
// imported: a relative import across two surface directories does not resolve
// reliably in this build, and a symlinked .qml is not registered in the
// directory's synthetic qmldir (it loads as `undefined` with a ReferenceError as
// the only clue). Change one, copy it over the other.
//
// Two values, on purpose. `value` is what the system reports; `visualValue` is
// what the strip draws. During a drag the visual value follows the pointer with
// no easing at all — drawing from `value` makes every mouse event wait for the
// write round-trip, so the fill advances in steps, and a Behavior on top of that
// only adds lag. Outside a drag, changes from the keyboard or another app animate.
Item {
    id: slider

    property Appearance appearance: Appearance {}
    property real value: 0
    property bool dragging: false

    // False when there is no node to move. The control then draws a bare track
    // with no fill and no knob, because a strip that looks full of ink at 0 %
    // and refuses every drag is a lie the eye reads as a bug. Dimming the whole
    // control was the other option and it is wrong here: hierarchy on this
    // desktop is a step of ink, never opacity.
    property bool available: true

    // Lowest value the control can produce. The backlight passes its floor here
    // (a screen at 0 is a screen the user cannot see to undo it); the volume
    // panel leaves it at 0, because silence is recoverable.
    property real minimum: 0

    // What the track, the fill and the knob draw.
    property real visualValue: value

    signal moved(real value)

    Behavior on visualValue {
        enabled: !slider.dragging
        NumberAnimation {
            duration: slider.appearance.motionControlDuration
            easing: slider.appearance.motionControlEasing
        }
    }

    // External changes land here. During a drag the visual value is already where
    // the pointer put it, so this must not fight it.
    onValueChanged: {
        if (!slider.dragging)
            slider.visualValue = slider.value;
    }

    implicitHeight: Math.max(appearance.knobSize, appearance.sliderHeight)
    height: implicitHeight

    readonly property real clamped: Math.max(slider.minimum, Math.min(1, visualValue))

    // Public on purpose: the MouseArea reports a position and the slider owns the
    // conversion. Defining it inside the MouseArea made every click and drag throw
    // "valueAt is not a function" while looking correct on screen.
    function valueAt(x) {
        return Math.max(slider.minimum, Math.max(0, Math.min(1, x / width)));
    }

    Rectangle {
        id: track
        anchors.verticalCenter: parent.verticalCenter
        width: parent.width
        height: slider.appearance.sliderHeight
        radius: height / 2
        color: slider.appearance.surfaceContainerHigh
    }

    Rectangle {
        id: fill

        objectName: "sliderFill"
        visible: slider.available
        anchors.verticalCenter: parent.verticalCenter
        width: track.width * slider.clamped
        height: track.height
        radius: track.radius
        color: slider.appearance.accent
    }

    Rectangle {
        id: knob

        objectName: "sliderKnob"
        visible: slider.available
        anchors.verticalCenter: parent.verticalCenter
        // Kept inside the strip at both ends, so the knob is never half clipped.
        x: Math.max(0, Math.min(track.width - width, track.width * slider.clamped - width / 2))
        width: slider.appearance.knobSize
        height: slider.appearance.knobSize
        radius: width / 2
        color: slider.appearance.accent
        border.width: slider.appearance.borderWidth
        border.color: slider.appearance.surfaceContainer
    }

    // No wheel handler. It does not fire on this layer surface (verified on the
    // volume plaque: the handler never ran once), so the level changes by
    // click/drag or with the arrow keys. Dead code that looks like a feature is
    // worse than no code.
    MouseArea {
        anchors.fill: parent
        enabled: slider.available
        hoverEnabled: true
        cursorShape: slider.available ? Qt.PointingHandCursor : Qt.ArrowCursor

        // onPressed already moves the level, so a click and the first frame of a
        // drag are the same code path instead of two behaviours that diverge.
        onPressed: (mouse) => {
            slider.dragging = true;
            slider.visualValue = slider.valueAt(mouse.x);
            slider.moved(slider.visualValue);
        }

        onPositionChanged: (mouse) => {
            if (!slider.dragging)
                return;
            slider.visualValue = slider.valueAt(mouse.x);
            slider.moved(slider.visualValue);
        }

        onReleased: {
            slider.dragging = false;
            slider.syncTimer.restart();
        }

        onCanceled: {
            slider.dragging = false;
            slider.syncTimer.restart();
        }
    }

    // After a drag, reconcile with what the system actually took: it can quantise
    // to whole sysfs steps or clamp the level, and the strip should not keep
    // drawing a value the backlight never accepted.
    Timer {
        id: syncTimer
        interval: 120
        onTriggered: {
            if (!slider.dragging)
                slider.visualValue = slider.value;
        }
    }
}
