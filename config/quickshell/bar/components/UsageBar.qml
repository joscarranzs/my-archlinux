import QtQuick
import ".."

// A consumed fraction, as a bar.
//
// The track carries its own alpha in the colour instead of an `opacity` on the
// parent: Qt multiplies a parent's opacity into every child, so the old track
// (opacity 0.14) painted the fill at 14 % as well and every allowance read as
// empty. One geometry, two rectangles, no inherited alpha.
Item {
    id: root

    property Appearance appearance: Appearance {}
    property real percent: 0
    property color fillColor: appearance.textMuted

    implicitHeight: appearance.usageBarHeight
    implicitWidth: 0

    Rectangle {
        anchors.fill: parent
        radius: height / 2
        color: Qt.rgba(root.appearance.textMuted.r, root.appearance.textMuted.g,
                       root.appearance.textMuted.b, root.appearance.usageBarTrack)
    }

    Rectangle {
        width: parent.width * Math.min(1, Math.max(0, root.percent / 100))
        height: parent.height
        radius: height / 2
        color: root.fillColor
    }
}
