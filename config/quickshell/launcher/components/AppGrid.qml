import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

// Scrollable grid of app tiles with keyboard selection.
GridView {
    id: root

    property var appearance
    property int selectedIndex: 0

    signal appActivated(var entry)

    function moveSelection(delta) {
        const count = root.count;
        if (count === 0) return;
        let next = root.selectedIndex + delta;
        if (next < 0) next = count - 1;
        if (next >= count) next = 0;
        root.selectedIndex = next;
        root.positionViewAtIndex(next, GridView.Contain);
    }

    function selectedEntry() {
        if (root.count === 0) return null;
        const idx = Math.max(0, Math.min(root.selectedIndex, root.count - 1));
        return root.model[idx];
    }

    // Square tile plus the label line underneath: the cell is taller than it
    // is wide so the label never gets clipped.
    readonly property int columnSpan: appearance.gridCell
    readonly property int rowSpan: appearance.gridCell + appearance.spacingXl

    cellWidth: columnSpan
    cellHeight: rowSpan
    clip: true
    boundsBehavior: Flickable.StopAtBounds

    // Thin gutter scroll so it doesn't cover the last column's tile.
    // AsNeeded + a thin track keeps the cell readable; outline at 0.6
    // matches the panel's hairline instead of competing with accent.
    ScrollBar.vertical: ScrollBar {
        policy: ScrollBar.AsNeeded
        width: root.appearance.spacingXs
        contentItem: Rectangle {
            radius: root.appearance ? root.appearance.shapeSmall : 3
            color: root.appearance ? root.appearance.outline : "#4a414a"
            opacity: 0.6
        }
        background: Item {}
    }

    delegate: AppItem {
        appearance: root.appearance
        entry: modelData
        selected: index === root.selectedIndex
        onClicked: root.appActivated(modelData)
    }
}