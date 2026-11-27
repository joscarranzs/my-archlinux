import Quickshell
import QtQuick
import "services"
import "components"
import "."

// Preview the token panel in a floating window (no compositor layer-shell needed).
ShellRoot {
    id: root

    Appearance { id: appearance }

    TokenFeed {
        id: feed

        alertThreshold: appearance.tokensAlertThreshold
        criticalThreshold: appearance.tokensCriticalThreshold
    }

    FloatingWindow {
        implicitWidth: panel.width + appearance.spacingMedium * 2
        implicitHeight: panel.height + appearance.spacingMedium * 2
        title: "Token panel preview"

        Rectangle {
            anchors.fill: parent
            color: appearance.surface

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

    Connections {
        target: Quickshell
        function onLastWindowClosed() { Qt.quit() }
    }
}
