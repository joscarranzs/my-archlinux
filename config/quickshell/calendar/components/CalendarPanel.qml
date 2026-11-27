import QtQuick
import QtQuick.Layouts
import ".."

// The calendar plaque itself: frame, month header, day grid and footer.
//
// Holds no window policy (no scrim, no layer-shell), so the real overlay and the
// preview draw exactly the same pixels and a layout fix lands in both. Month
// state lives in services/CalendarMath.qml; this component only reports the
// intents the panel cannot decide for itself.
Rectangle {
    id: panel

    property Appearance appearance: Appearance {}
    property string monthLabel: ""
    property var cells: []
    property int selectedIndex: -1

    signal dayActivated(int index)
    signal monthPrevious()
    signal monthNext()
    signal todayRequested()

    // The panel owns the keyboard, so the window asks it for focus once it exists.
    function requestFocus() {
        keyCatcher.forceActiveFocus();
    }

    // The plaque is never narrower than its own footer: the legend is the
    // widest fixed row on the surface, and the text scale grows it while the
    // width token does not. At rest the token still wins, so nothing moves.
    width: Math.max(appearance.panelWidth, legendRow.implicitWidth + appearance.contentPad * 2)
    height: appearance.panelHeight
    color: appearance.surfaceContainer
    radius: appearance.shapeExtraLarge
    // Edge: gilt (accent.tertiary) at look.borders.width — the plaque's frame.
    border.color: appearance.gilt
    border.width: appearance.borderWidth

    // Entrance: the plaque fades in and lifts its last few pixels rather than
    // popping. The lift rides a transform, not `y`: the plaque is anchored
    // (centerIn) by its shell, and a translate moves the paint without fighting
    // the anchor. Reduced motion zeroes the offset in apply-theme.py, so no
    // branch on the flag belongs here.
    opacity: 0
    Behavior on opacity {
        NumberAnimation {
            duration: appearance.motionEntranceDuration
            easing: appearance.motionEntranceEasing
        }
    }
    property real entranceLift: appearance.motionEntranceOffset
    Behavior on entranceLift {
        NumberAnimation {
            duration: appearance.motionEntranceDuration
            easing: appearance.motionEntranceEasing
        }
    }
    transform: Translate {
        y: panel.entranceLift
    }
    Component.onCompleted: {
        entranceLift = 0;
        opacity = 1;
    }


    // Keeps scrim clicks from passing through the plaque.
    MouseArea {
        anchors.fill: parent
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: appearance.contentPad
        spacing: appearance.spacingSmall

        MonthHeader {
            Layout.fillWidth: true
            Layout.preferredHeight: appearance.headerHeight
            appearance: panel.appearance
            title: panel.monthLabel
            onPrevious: panel.monthPrevious()
            onNext: panel.monthNext()
        }

        CalendarGrid {
            Layout.fillWidth: true
            Layout.fillHeight: true
            appearance: panel.appearance
            cells: panel.cells
            selectedIndex: panel.selectedIndex
            onDayActivated: (index) => panel.dayActivated(index)
        }

        Item {
            Layout.fillWidth: true
            Layout.preferredHeight: appearance.footerHeight + appearance.contentPad
                - appearance.borderWidth
            // The band runs from its rule to the plaque's inner bottom edge, and the
            // legend centres inside it: pinned to the content margin it sat glued to the
            // rule with a pocket of dead space under it.
            Layout.bottomMargin: -(appearance.contentPad - appearance.borderWidth)

            Rectangle {
                anchors.top: parent.top
                width: parent.width
                height: panel.appearance.borderWidth
                color: panel.appearance.outline
            }

            // The keys, as keys: one cap each, the tracked label beside it. The cap
            // recipe is generated (components/LegendRow.qml), so this footer and the
            // kanban's legend cannot drift into two different objects.
            RowLayout {
                id: legendRow

                anchors.horizontalCenter: parent.horizontalCenter
                anchors.verticalCenter: parent.verticalCenter
                spacing: panel.appearance.spacingMedium

                LegendRow {
                    appearance: panel.appearance
                    key: "←→"
                    label: "month"
                    tracked: true
                }

                LegendRow {
                    appearance: panel.appearance
                    key: "T"
                    label: "today"
                    tracked: true
                }

                LegendRow {
                    appearance: panel.appearance
                    key: "Esc"
                    label: "close"
                    tracked: true
                }
            }
        }
    }

    // The panel has no text input, so an invisible item owns the focus and routes
    // the keys instead of relying on the window.
    Item {
        id: keyCatcher

        anchors.fill: parent
        focus: true

        Keys.onPressed: (event) => {
            if (event.key === Qt.Key_Escape) {
                Qt.quit();
            } else if (event.key === Qt.Key_Left) {
                panel.monthPrevious();
            } else if (event.key === Qt.Key_Right) {
                panel.monthNext();
            } else if (event.key === Qt.Key_T) {
                panel.todayRequested();
            } else {
                return;
            }
            event.accepted = true;
        }
    }
}
