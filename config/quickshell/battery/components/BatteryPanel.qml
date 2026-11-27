import QtQuick
import QtQuick.Layouts
import ".."

// The battery plaque: level, state, time left or time to full, drain rate,
// energy and health.
//
// Holds no window policy (no scrim, no layer-shell) so the real overlay and the
// preview draw the same pixels, and it reads nothing itself: every number is a
// property of the BatteryState component the caller hands in.
Rectangle {
    id: panel

    property Appearance appearance: Appearance {}
    property var battery: null

    signal dismissRequested()

    readonly property bool available: panel.battery ? panel.battery.available : false
    readonly property bool charging: panel.battery ? panel.battery.charging : false
    readonly property real percent: panel.battery ? panel.battery.percent : 0
    readonly property real health: panel.battery ? panel.battery.health : 0

    readonly property string stateLabel: panel.battery ? panel.battery.stateLabel : "no battery"

    // The state is the one word that changes what the numbers mean, so it carries
    // the colour: gold while the pack takes charge, red when it is about to die,
    // muted the rest of the time.
    readonly property color stateColor: panel.available && panel.percent <= panel.appearance.batteryCriticalThreshold
        ? panel.appearance.danger
        : (panel.charging ? panel.appearance.accentInk : panel.appearance.textMuted)

    // A level with no time behind it reads as a measurement, so the fill follows
    // the same thresholds the bar's glyph does.
    readonly property color levelColor: !panel.available ? panel.appearance.textMuted
        : (panel.percent <= panel.appearance.batteryCriticalThreshold ? panel.appearance.danger
            : (panel.percent <= panel.appearance.batteryAlertThreshold ? panel.appearance.accent
                : panel.appearance.text))

    // A pack below 80 % of its design capacity is no longer "fine": the reading
    // takes the danger ink at the same size, so the panel says it without adding
    // a badge. Above the floor the number stays ordinary text.
    readonly property color healthColor: !panel.available ? panel.appearance.textMuted
        : (panel.health > 0 && panel.health < 80 ? panel.appearance.danger : panel.appearance.text)

    function requestFocus() {
        keyCatcher.forceActiveFocus();
    }

    // Seconds to "3h 12m". A zero means upower is not estimating (on AC, or a
    // pack whose firmware publishes no rate), and an invented estimate is worse
    // than a dash.
    function duration(seconds) {
        if (!seconds || seconds <= 0 || !isFinite(seconds))
            return "\u2014";
        const total = Math.round(seconds / 60);
        const hours = Math.floor(total / 60);
        const minutes = total % 60;
        return hours > 0 ? hours + "h " + minutes + "m" : minutes + "m";
    }

    function watts(value) {
        if (value === undefined || value === null || !isFinite(value))
            return "\u2014";
        return value.toFixed(1) + " W";
    }

    function wattHours(value) {
        if (value === undefined || value === null || !isFinite(value))
            return "\u2014";
        return value.toFixed(2) + " Wh";
    }

    function percentText(value) {
        if (value === undefined || value === null || !isFinite(value) || value <= 0)
            return "\u2014";
        return value.toFixed(1) + " %";
    }

    width: appearance.batteryWidth
    height: layout.implicitHeight + appearance.contentPad * 2
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
        id: layout

        x: appearance.contentPad
        y: appearance.contentPad
        width: panel.width - appearance.contentPad * 2
        spacing: appearance.spacingSmall

        PanelCard {
            id: chargeCard

            Layout.fillWidth: true
            appearance: panel.appearance
            title: "Charge"
            chipText: panel.stateLabel
            chipColor: panel.stateColor
            chipDot: true

            Text {
                Layout.fillWidth: true
                text: panel.available ? panel.percent + "%" : "\u2014"
                color: panel.appearance.text
                font.family: panel.appearance.displayFont
                font.weight: panel.appearance.fontWeightDisplay
                font.variableAxes: panel.appearance.fontVariableAxesDisplay
                font.pixelSize: panel.appearance.fontSizeDisplay
                font.bold: true
                font.letterSpacing: panel.appearance.letterSpacingDisplay
            }

            LevelBar {
                Layout.fillWidth: true
                appearance: panel.appearance
                fraction: panel.percent / 100
                fill: panel.levelColor
            }

            // Time left while the pack drains, time to full while it charges: one row,
            // because the pack is never doing both.
            DetailRow {
                Layout.fillWidth: true
                appearance: panel.appearance
                label: panel.charging ? "time to full" : "time left"
                value: panel.available ? panel.duration(panel.charging
                    ? panel.battery.secondsToFull : panel.battery.secondsToEmpty) : "\u2014"
                valueColor: panel.appearance.text
            }

        }

        PanelCard {
            id: healthCard

            Layout.fillWidth: true
            appearance: panel.appearance
            title: "Health"
            // Health as the chip too: 65 % of design capacity is a number most
            // people cannot place, and its own colour says whether to care.
            chipText: panel.available ? panel.percentText(panel.health) : ""
            chipColor: panel.healthColor
            chipDot: true

            DetailRow {
                Layout.fillWidth: true
                appearance: panel.appearance
                label: "rate"
                value: panel.available ? panel.watts(panel.battery.rate) : "\u2014"
                valueColor: panel.appearance.text
            }

            DetailRow {
                Layout.fillWidth: true
                appearance: panel.appearance
                label: "energy"
                value: panel.available
                    ? panel.wattHours(panel.battery.energy) + " / " + panel.wattHours(panel.battery.energyCapacity)
                    : "\u2014"
                valueColor: panel.appearance.text
            }

            DetailRow {
                Layout.fillWidth: true
                appearance: panel.appearance
                label: "health"
                value: panel.available ? panel.percentText(panel.health) : "\u2014"
                valueColor: panel.healthColor
            }

            // Health as a strip too: 65 % of design capacity is a number most people
            // cannot place, and the fill places it without a second label.
            LevelBar {
                Layout.fillWidth: true
                appearance: panel.appearance
                fraction: panel.health / 100
                fill: panel.healthColor
            }


            // Which pack this is. A dash when upower publishes no model, never a
            // guess: two batteries on one machine look identical without it.
            Text {
                Layout.fillWidth: true
                elide: Text.ElideRight
                text: panel.available && panel.battery.model.length > 0
                    ? "model " + panel.battery.model : "model \u2014"
                color: panel.appearance.textMuted
                font.family: panel.appearance.uiFont
                font.weight: panel.appearance.fontWeightUi
                font.variableAxes: panel.appearance.fontVariableAxesUi
                font.pixelSize: panel.appearance.fontSizeCaption
                font.letterSpacing: panel.appearance.letterSpacingCaption
            }

        }

        // --------------------------------------------------------- footer
        Item {
            Layout.fillWidth: true
            Layout.preferredHeight: panel.appearance.footerHeight + panel.appearance.contentPad
                - panel.appearance.borderWidth
            // The band runs from its rule to the plaque's inner bottom edge, and the
            // legend centres inside it: pinned to the content margin it sat glued to the
            // rule with a pocket of dead space under it.
            Layout.bottomMargin: -(panel.appearance.contentPad - panel.appearance.borderWidth)

            Rectangle {
                anchors.top: parent.top
                width: parent.width
                height: panel.appearance.hairline
                color: panel.appearance.outline
                opacity: panel.appearance.opacityFrame
            }

            // The keys, as keys: one cap each, the tracked label beside it. The cap
            // recipe is generated (components/LegendRow.qml), so this footer and the
            // kanban's legend cannot drift into two different objects.
            RowLayout {
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.verticalCenter: parent.verticalCenter
                spacing: panel.appearance.spacingMedium

                LegendRow {
                    appearance: panel.appearance
                    key: "Esc"
                    label: "close"
                    tracked: true
                }
            }
        }
    }

    // Nothing here is editable, so an invisible item owns the keys instead of
    // relying on the window.
    Item {
        id: keyCatcher

        anchors.fill: parent
        focus: true

        Keys.onPressed: (event) => {
            if (event.key === Qt.Key_Escape) {
                panel.dismissRequested();
            } else {
                return;
            }
            event.accepted = true;
        }
    }
}
