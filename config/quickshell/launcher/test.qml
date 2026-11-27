import QtQuick
import QtQuick.Layouts
import Quickshell
import "services"
import "components"
import "."

// Preview the launcher in a floating window (no compositor layer-shell needed).
ShellRoot {
    id: root

    Appearance { id: appearance }

    FloatingWindow {
        implicitWidth: appearance.panelWidth + appearance.spacingLarge * 2
        implicitHeight: appearance.panelMaxHeight
        title: "Launcher preview"

        Rectangle {
            anchors.fill: parent
            color: appearance.surface

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: appearance.spacingLarge
                spacing: appearance.spacingMedium

                SearchField {
                    id: searchField
                    Layout.fillWidth: true
                    appearance: appearance
                    onQueryChanged: (text) => AppSearch.query = text
                    onAccepted: root.launchSelected()
                    onNavigate: (delta) => appGrid.moveSelection(delta)
                }

                AppGrid {
                    id: appGrid
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    appearance: appearance
                    model: AppSearch.results
                    onAppActivated: (entry) => root.launchEntry(entry)
                }
            }

            Component.onCompleted: searchField.forceFocus()
        }
    }

    Connections {
        target: Quickshell
        function onLastWindowClosed() { Qt.quit() }
    }

    function launchEntry(entry) {
        if (!entry) return;
        entry.execute();
        Qt.quit();
    }

    function launchSelected() {
        const results = AppSearch.results;
        if (results.length === 1) {
            root.launchEntry(results[0]);
            return;
        }
        const selected = appGrid.selectedEntry();
        if (selected) {
            root.launchEntry(selected);
        }
    }
}