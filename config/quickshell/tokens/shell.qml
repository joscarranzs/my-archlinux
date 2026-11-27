import Quickshell
import Quickshell.Wayland
import QtQuick
import "services"
import "components"
import "."

// On-demand token panel (Quickshell).
//
// Launched by scripts/session/tokens.sh (a click on the robot in the bar), closed
// by Esc or a scrim click. R re-runs the helper instead of waiting for the next
// 60 s tick.
ShellRoot {
    id: root

    Appearance { id: appearance }

    TokenFeed {
        id: feed

        alertThreshold: appearance.tokensAlertThreshold
        criticalThreshold: appearance.tokensCriticalThreshold
    }

    PanelWindow {
        id: window

        anchors {
            top: true
            bottom: true
            left: true
            right: true
        }
        color: "transparent"

        // -1 ignores the bar's reserved strip, so the scrim covers the whole
        // screen and the plaque centers on the output, not on the usable area.
        exclusiveZone: -1
        WlrLayershell.namespace: "quickshell:tokens"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand

        // Scrim: dismiss on click outside the plaque.
        Rectangle {
            anchors.fill: parent
            color: Qt.rgba(0, 0, 0, appearance.scrimOpacity)
            // The scrim rides the plaque's entrance: one driver, so a slow first frame
            // cannot present the backdrop without the plaque in front of it.
            opacity: panel.opacity

            MouseArea {
                anchors.fill: parent
                onClicked: Qt.quit()
            }
        }

        TokensPanel {
            id: panel

            anchors.centerIn: parent
            appearance: appearance
            feed: feed

            onDismissRequested: Qt.quit()
            onRefreshRequested: feed.refresh()

            Component.onCompleted: requestFocus()
        }
    }
}
