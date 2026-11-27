import Quickshell
import Quickshell.Wayland
import QtQuick
import QtQuick.Layouts
import "services"
import "components"
import "."

// On-demand app launcher overlay (Quickshell).
// Launched by scripts/session/launcher.sh; closes on Esc, scrim click,
// or after launching an application.
//
// Layout, top to bottom: gallery header (gold rule, label, result count),
// unified search bar, app grid, footer with the key hints. Everything sits on
// one content column so the grid edge lines up with the search bar.
ShellRoot {
    id: root

    Appearance { id: appearance }

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
        // screen and the panel centers on the output, not on the usable area.
        exclusiveZone: -1
        WlrLayershell.namespace: "quickshell:launcher"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand

        // Scrim: dismiss on click outside the panel, and it rides the plaque's
        // entrance rather than landing before it. Bound, not animated a second
        // time: the scrim reads the plaque's own entrance alpha, so no timing
        // difference can exist between them. Without it the scrim paints at full
        // strength while the plaque is still at opacity 0 — and the launcher's
        // first polish (18 app tiles and their icons) delays that plaque frame by
        // ~150 ms, which measured as a full scrim with 0.5 % of the plate.
        Rectangle {
            id: scrim
            anchors.fill: parent
            color: Qt.rgba(0, 0, 0, appearance.scrimOpacity)
            opacity: panel.opacity

            MouseArea {
                anchors.fill: parent
                onClicked: Qt.quit()
            }
        }

        // Centered panel.
        Rectangle {
            id: panel
            anchors.centerIn: parent
            width: appearance.panelWidth
            // Height is driven by the real parts (header, field, footer) plus
            // the grid content, capped by the token. A GridView contributes no
            // implicitHeight, so it is read from contentHeight directly.
            readonly property real chromeHeight: appearance.headerHeight
                + appearance.fieldHeightHero
                + appearance.footerHeight
                + appearance.spacingLarge * 3
            readonly property real availableGridHeight: appearance.panelMaxHeight - appearance.contentPad * 2 - chromeHeight
            readonly property real gridHeight: Math.min(Math.max(appGrid.contentHeight, appGrid.rowSpan), availableGridHeight)
            height: appearance.contentPad * 2 + chromeHeight + gridHeight
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


            // Prevent scrim clicks from passing through.
            MouseArea {
                anchors.fill: parent
            }

            ColumnLayout {
                id: contentColumn
                anchors.fill: parent
                anchors.margins: appearance.contentPad
                spacing: appearance.spacingLarge

                // ------------------------------------------------------ header
                Item {
                    id: header
                    Layout.fillWidth: true
                    Layout.preferredHeight: appearance.headerHeight

                    Rectangle {
                        id: headerRule
                        anchors.left: parent.left
                        anchors.verticalCenter: parent.verticalCenter
                        width: appearance.ruleWidth
                        height: appearance.ruleThickness
                        color: appearance.gilt
                    }

                    Text {
                        id: headerLabel
                        anchors.left: headerRule.right
                        anchors.leftMargin: appearance.spacingSmall
                        anchors.verticalCenter: parent.verticalCenter
                        text: "APPLICATIONS"
                        color: appearance.textMuted
                        font.family: appearance.uiFont
                        font.weight: appearance.fontWeightUi
                        font.variableAxes: appearance.fontVariableAxesUi
                        font.pixelSize: appearance.fontSizeSmall
                        font.letterSpacing: appearance.letterSpacingLabel
                    }

                    Text {
                        id: headerCount
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        text: AppSearch.results.length
                        // Ochre, not leaf gold: at this size the leaf sits at 2.4:1
                        // on paper and the count has to be readable at a glance.
                        color: appearance.accentInk
                        font.family: appearance.uiFont
                        font.weight: appearance.fontWeightUi
                        font.variableAxes: appearance.fontVariableAxesUi
                        font.pixelSize: appearance.fontSizeSmall
                        font.letterSpacing: appearance.letterSpacingCaption
                    }
                }

                // ------------------------------------------------------ search
                SearchField {
                    id: searchField
                    Layout.fillWidth: true
                    Layout.preferredHeight: appearance.fieldHeightHero
                    appearance: appearance
                    onQueryChanged: (text) => AppSearch.query = text
                    onAccepted: root.launchSelected()
                    onDismissed: Qt.quit()
                    onNavigate: (delta) => appGrid.moveSelection(delta)
                }

                // -------------------------------------------------------- grid
                AppGrid {
                    id: appGrid
                    Layout.fillWidth: true
                    Layout.preferredHeight: panel.gridHeight
                    Layout.minimumHeight: appGrid.rowSpan
                    appearance: appearance
                    model: AppSearch.results
                    onAppActivated: (entry) => root.launchEntry(entry)
                }

                // ------------------------------------------------------ footer
                Item {
                    id: footer
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
                        height: appearance.borderWidth
                        color: appearance.outline
                    }

                    // The keys, as keys: one cap each, the tracked label beside it. The cap
                    // recipe is generated (components/LegendRow.qml), so this footer and the
                    // kanban's legend cannot drift into two different objects.
                    RowLayout {
                        anchors.horizontalCenter: parent.horizontalCenter
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: appearance.spacingMedium

                        LegendRow {
                            appearance: appearance
                            key: "↵"
                            label: "open"
                            tracked: true
                        }

                        LegendRow {
                            appearance: appearance
                            key: "↑↓"
                            label: "navigate"
                            tracked: true
                        }

                        LegendRow {
                            appearance: appearance
                            key: "Esc"
                            label: "close"
                            tracked: true
                        }
                    }
                }
            }

            // Focus the search field on open.
            Component.onCompleted: {
                searchField.forceFocus();
                entranceLift = 0;
                opacity = 1;
            }
        }
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
