import QtQuick
import QtQuick.Layouts
import ".."

// One external monitor: name, resolution dropdown, scale dropdown, Apply.
//
// Selections are held as picks (-1 = follow the live value). A pick that differs
// from what hyprctl reports makes the card dirty and enables Apply; when the
// read-back matches the pick, the card syncs back to live on its own. Nothing
// applies on selection: the write only happens on an explicit Apply.
PanelCard {
    id: card

    property Appearance appearance: Appearance {}
    property var monitor: null
    // The output's own helpers (mode list, scale list, labels) come from the
    // panel's injected state, never from the singleton: a card that reached for
    // MonitorState behind the panel's back could not be rendered against a stub.
    property var state: null
    property bool cardFocused: false
    property int controlIndex: 0

    property alias resField: resField
    property alias scaleField: scaleField

    // The contract the plaque's key ring runs on: which field answers which
    // control, which one is open, and which sibling a newly opened one replaces.
    readonly property var openField: resField.open ? resField
        : (scaleField.open ? scaleField : null)
    // Resolution, scale, apply: no reset on an external output -- the panel has no
    // original for it beyond the rule, and a second button would say it does.
    readonly property int controlCount: 3

    // -1 means "show whatever the monitor reports right now".
    property int modePick: -1
    property int scalePick: -1

    readonly property var modeOptions: {
        const out = [];
        if (!card.state)
            return out;
        const modes = card.monitor ? card.monitor.modes : [];
        for (let i = 0; i < modes.length; i++) {
            out.push({
                label: modes[i].w + "×" + modes[i].h,
                rowLabel: modes[i].w + "×" + modes[i].h + " · "
                    + card.state.rateLabel(modes[i].rate),
                value: i,
            });
        }
        return out;
    }
    readonly property var scaleOptions: {
        const out = [];
        if (!card.state)
            return out;
        const steps = card.state.scaleOptions(card.monitor);
        for (let i = 0; i < steps.length; i++)
            out.push({ label: card.state.scaleLabel(steps[i]), value: steps[i] });
        return out;
    }

    readonly property int liveModeIndex: card.monitor && card.state
        ? card.state.modeIndexOf(card.monitor, card.monitor.width, card.monitor.height) : 0
    readonly property int liveScaleIndex: card.monitor && card.state
        ? card.state.scaleIndexOf(card.monitor, card.monitor.scale) : 0
    readonly property int effectiveModeIndex: card.modePick >= 0 ? card.modePick : card.liveModeIndex
    readonly property int effectiveScaleIndex: card.scalePick >= 0 ? card.scalePick : card.liveScaleIndex
    readonly property bool dirty: card.monitor !== null
        && (card.effectiveModeIndex !== card.liveModeIndex
            || card.effectiveScaleIndex !== card.liveScaleIndex)

    signal controlTouched(int control)
    signal listClosed()
    signal applyRequested()

    function openControl(control) {
        if (control === 0)
            resField.openList();
        else if (control === 1)
            scaleField.openList();
        else if (control === 2 && card.dirty)
            card.applyRequested();
    }

    function closeLists() {
        resField.closeList();
        scaleField.closeList();
    }

    // Which field a control opens, and which sibling it displaces. Sequential
    // alternative presses (a menu seen with the arrow keys) must not leave two
    // lists open on one card.
    function fieldAt(control) {
        if (control === 0)
            return resField;
        if (control === 1)
            return scaleField;
        return null;
    }

    function closeOtherThan(control) {
        if (control === 0)
            scaleField.closeList();
        else if (control === 1)
            resField.closeList();
    }

    // A poll hands over a fresh object every tick. Follow the live value only
    // while the user has no pending pick, so a refresh never eats a selection.
    onMonitorChanged: {
        if (!card.dirty) {
            card.modePick = -1;
            card.scalePick = -1;
        }
    }

    width: parent ? parent.width : 0
    // The card is the shared one now: same fill, radius, inset and hairline as the
    // AI plaque's blocks, so an external monitor and an account are built from one
    // recipe instead of two that merely look alike.
    title: card.monitor ? card.monitor.name : ""
    glyph: "desktop_windows"
    chipText: card.dirty ? "MODIFIED"
        : (card.monitor && card.monitor.disabled ? "OFF"
            : (card.monitor && card.state ? card.state.rateLabel(card.monitor.refresh) : ""))
    chipColor: card.dirty ? card.appearance.accentInk : card.appearance.textMuted
    chipDot: card.dirty

    // What the panel can say about this output that is not its name: the model
    // line, which the header has no room for.
    Text {
        Layout.fillWidth: true
        text: card.monitor ? card.monitor.description : ""
        color: card.appearance.textFaint
        elide: Text.ElideRight
        font.family: card.appearance.uiFont
        font.weight: card.appearance.fontWeightUi
        font.variableAxes: card.appearance.fontVariableAxesUi
        font.pixelSize: card.appearance.fontSizeCaption
        font.letterSpacing: card.appearance.letterSpacingCaption
    }

    // -------------------------------------------------------- fields row
    RowLayout {
        width: parent.width
        spacing: card.appearance.fieldGap

        ChoiceField {
            id: resField

            Layout.fillWidth: true
            Layout.alignment: Qt.AlignTop
            appearance: card.appearance
            label: "RESOLUTION"
            options: card.modeOptions
            currentIndex: card.effectiveModeIndex
            fieldFocused: card.cardFocused && card.controlIndex === 0
            onOpened: card.controlTouched(0)
            onClosed: card.listClosed()
            onPicked: (index) => card.modePick = index
        }

        ChoiceField {
            id: scaleField

            Layout.fillWidth: true
            Layout.alignment: Qt.AlignTop
            appearance: card.appearance
            label: "SCALE"
            options: card.scaleOptions
            currentIndex: card.effectiveScaleIndex
            fieldFocused: card.cardFocused && card.controlIndex === 1
            onOpened: card.controlTouched(1)
            onClosed: card.listClosed()
            onPicked: (index) => card.scalePick = index
        }
    }

    // -------------------------------------------------------- apply row
    RowLayout {
        width: parent.width
        spacing: card.appearance.spacingSmall

        Item { Layout.fillWidth: true }

        Rectangle {
            id: applyBox

            readonly property bool focused: card.cardFocused && card.controlIndex === 2

            Layout.preferredHeight: card.appearance.buttonHeightDense
            Layout.preferredWidth: applyLabel.implicitWidth + card.appearance.spacingMedium * 2
            radius: card.appearance.shapeMedium
            color: card.dirty ? card.appearance.accent : card.appearance.surfaceContainerHigh
            border.width: card.appearance.borderWidth
            border.color: applyBox.focused && card.dirty
                ? card.appearance.accentInk
                : (card.dirty ? card.appearance.accent : card.appearance.outline)
            opacity: card.dirty ? 1 : card.appearance.opacityDisabled

            Rectangle {
                anchors.fill: parent
                radius: parent.radius
                color: card.appearance.accentText
                opacity: card.dirty && applyHover.hovered
                    ? card.appearance.opacityStateLayer : 0

                Behavior on opacity {
                    NumberAnimation {
                        duration: card.appearance.motionControlDuration
                        easing.type: card.appearance.motionControlEasing
                    }
                }
            }

            Text {
                id: applyLabel

                anchors.centerIn: parent
                text: "APPLY"
                color: card.dirty ? card.appearance.accentText : card.appearance.textFaint
                font.family: card.appearance.uiFont
                font.weight: card.appearance.fontWeightUi
                font.variableAxes: card.appearance.fontVariableAxesUi
                font.pixelSize: card.appearance.fontSizeSmall
                font.letterSpacing: card.appearance.letterSpacingLabel
            }

            HoverHandler { id: applyHover }

            MouseArea {
                anchors.fill: parent
                enabled: card.dirty
                onClicked: {
                    card.controlTouched(2);
                    card.applyRequested();
                }
            }
        }
}
}
