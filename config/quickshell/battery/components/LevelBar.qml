import QtQuick
import ".."

// A read-only level strip: track at the shared low opacity, fill on top. Same
// geometry as the token panel's allowance bars, so a level reads the same way on
// every plaque.
Item {
    id: root

    property Appearance appearance: Appearance {}
    property real fraction: 0
    property color fill: appearance.text

    implicitHeight: appearance.usageBarHeight
    height: implicitHeight

    Rectangle {
        anchors.fill: parent
        radius: height / 2
        color: root.appearance.text
        opacity: root.appearance.usageBarTrack
    }

    Rectangle {
        width: Math.max(0, Math.min(1, root.fraction)) * parent.width
        height: parent.height
        radius: height / 2
        color: root.fill
    }
}
