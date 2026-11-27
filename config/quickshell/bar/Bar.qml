import QtQuick
import Quickshell
import "."
import "components"
import "services"

// The bar: the workspace dots on the left, the date and clock in the middle, the
// module glyphs on the right. Floating it is a plaque with four corners and a
// frame; flush with the screen edges it is a plain strip with no border at all.
// The workspaces read the live compositor state, the pack
// comes from upower, and the notification daemon lives in this process: bluetooth
// and the monitor glyph are still visual.
Rectangle {
    id: root

    property Appearance appearance: Appearance {}
    property int workspaceCount: 5

    readonly property HyprlandWorkspaces workspaces: HyprlandWorkspaces {}
    readonly property BatteryState battery: BatteryState {}

    radius: appearance.barRadius
    color: appearance.surface
    border.width: appearance.barFloating ? appearance.borderWidth : 0
    // The bar's own frame: gilt (accent.tertiary), width from look.borders.width.
    border.color: appearance.gilt

    WorkspaceStrip {
        appearance: root.appearance
        count: root.workspaceCount
        active: root.workspaces.active
        occupied: root.workspaces.occupied
        onSelected: workspace => root.workspaces.select(workspace)
        anchors.left: parent.left
        anchors.leftMargin: root.appearance.padX
        anchors.verticalCenter: parent.verticalCenter
    }

    BarClock {
        appearance: root.appearance
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.verticalCenter: parent.verticalCenter
    }

    StatusCluster {
        appearance: root.appearance
        battery: root.battery
        anchors.right: parent.right
        anchors.rightMargin: root.appearance.padX
        anchors.verticalCenter: parent.verticalCenter
    }
}
