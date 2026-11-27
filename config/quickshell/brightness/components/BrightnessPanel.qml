import QtQuick
import QtQuick.Layouts
import ".."
import "../services"

// The brightness plaque: header, level glyph and percentage, slider, device name
// and key hints.
//
// Holds no window policy (no scrim, no layer-shell), so the overlay and the
// preview draw exactly the same pixels. Unlike the volume plaque the glyph is
// NOT a button: a backlight has no mute, and an icon that reacts to hover but
// does nothing on click is a promise the panel cannot keep.
Rectangle {
    id: panel

    property Appearance appearance: Appearance {}
    property string deviceName: ""
    property string glyph: ""
    property real value: 0

    // False when the sysfs probe found no backlight. The plaque still draws its
    // frame and its header, because a panel that refuses to open is
    // indistinguishable from a binding that broke: what changes is that the level
    // reads as absent (an em dash, not 0 %), the strip is inert, and the only key
    // announced is the one that still does something.
    property bool available: true

    // The number rides the strip's visual value, not the backlight's: during a
    // drag the two diverge for the throttle window and the number would trail the
    // fill. It animates only when the change comes from outside the drag.
    property real shownPercent: levelSlider.visualValue * 100

    Behavior on shownPercent {
        enabled: !levelSlider.dragging
        NumberAnimation {
            duration: panel.appearance.motionControlDuration
            easing: panel.appearance.motionControlEasing
        }
    }

    signal brightnessRequested(real value)
    signal dismissed()

    function requestFocus() {
        keyCatcher.forceActiveFocus();
    }

    // The plaque is never narrower than its own footer: the legend is the
    // widest fixed row on the surface, and the text scale grows it while the
    // width token does not. At rest the token still wins, so nothing moves.
    width: Math.max(appearance.panelWidth, legendRow.implicitWidth + appearance.contentPad * 2)
    // The token is a floor, not a cage: the plaque now carries a card, and a card
    // whose content grows (a chip, a long device name) must not push the footer
    // legend out of the frame. The column reports what it needs; the token keeps
    // the smallest plaque that still looks like this panel.
    height: Math.max(appearance.panelHeight, column.implicitHeight + appearance.contentPad * 2)
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


    MouseArea {
        anchors.fill: parent
    }

    ColumnLayout {
        id: column

        anchors.fill: parent
        anchors.margins: appearance.contentPad
        spacing: appearance.spacingSmall

        // The card: identity in the header, everything the backlight reports in
        // the body. The plaque's own header is gone -- a title over a card that
        // already carries one is the same word twice.
        PanelCard {
            id: displayCard

            Layout.fillWidth: true
            appearance: panel.appearance
            title: "Display"
            // No backlight outranks any reading: the level would keep showing a
            // number that no device ever said.
            chipText: panel.available ? "" : "NO BACKLIGHT"
            chipColor: panel.appearance.danger
            chipDot: true

            // ---------------------------------------------------------- level
            RowLayout {
                Layout.fillWidth: true
                Layout.preferredHeight: appearance.levelHeight
                spacing: appearance.spacingMedium

                Item {
                    Layout.alignment: Qt.AlignVCenter
                    width: panel.appearance.iconSizeLg + panel.appearance.spacingSmall
                    height: width

                    MaterialIcon {
                        anchors.centerIn: parent
                        icon: panel.glyph
                        iconColor: panel.appearance.text
                        iconSize: panel.appearance.iconSizeLg
                    }
                }

                Text {
                    objectName: "percentText"

                    Layout.fillWidth: true
                    Layout.alignment: Qt.AlignVCenter
                    // No backlight is not 0 %: a zero would be a reading of a device
                    // that is not there. An em dash for "no value" is what the
                    // battery plaque already does when its battery reports nothing.
                    text: panel.available ? Math.round(panel.shownPercent) + "%" : "—"
                    color: panel.appearance.text
                    font.family: panel.appearance.displayFont
                    font.weight: panel.appearance.fontWeightDisplay
                    font.variableAxes: panel.appearance.fontVariableAxesDisplay
                    font.pixelSize: panel.appearance.fontSizeDisplay
                    font.letterSpacing: panel.appearance.letterSpacingDisplay
                }
            }

            // --------------------------------------------------------- slider
            LevelSlider {
                id: levelSlider
                objectName: "levelSlider"
                Layout.fillWidth: true
                Layout.preferredHeight: appearance.knobSize
                appearance: panel.appearance
                available: panel.available
                value: panel.value
                minimum: panel.appearance.brightnessMinimum
                onMoved: (value) => panel.brightnessRequested(value)
            }

            // --------------------------------------------------------- device
            Text {
                Layout.fillWidth: true
                Layout.preferredHeight: appearance.deviceHeight
                verticalAlignment: Text.AlignVCenter
                text: panel.deviceName
                color: panel.appearance.textMuted
                elide: Text.ElideRight
                font.family: panel.appearance.uiFont
                font.weight: panel.appearance.fontWeightUi
                font.variableAxes: panel.appearance.fontVariableAxesUi
                font.pixelSize: panel.appearance.fontSizeSmall
                font.letterSpacing: panel.appearance.letterSpacingCaption
            }

        }

        // --------------------------------------------------------- footer
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
                    key: "↑↓"
                    label: "adjust"
                    tracked: true
                    visible: panel.available
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

    // The plaque owns the keyboard: there is no text input to take focus.
    Item {
        id: keyCatcher

        anchors.fill: parent
        focus: true

        Keys.onPressed: (event) => {
            if (event.key === Qt.Key_Escape) {
                panel.dismissed();
            } else if (event.key === Qt.Key_Up) {
                panel.brightnessRequested(Math.min(1, panel.value + panel.appearance.brightnessStep));
            } else if (event.key === Qt.Key_Down) {
                // Floored: a screen at 0 % is a screen the user cannot see to
                // bring back up.
                panel.brightnessRequested(Math.max(panel.appearance.brightnessMinimum,
                                                   panel.value - panel.appearance.brightnessStep));
            } else {
                return;
            }
            event.accepted = true;
        }
    }
}
