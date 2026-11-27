import QtQuick
import QtQuick.Layouts
import ".."

// The laptop panel: name, model, a scale field, a text-size field and Apply.
//
// It is a readout for everything except the two things that can be changed
// without risking the screen the user is reading: the compositor scale and the
// desktop's text scale. The mode is deliberately absent -- MonitorState refuses
// an internal output whose mode differs from the live one -- and so is the
// resolution field: a one-item list is furniture, not a control.
//
// Selections follow MonitorCard's contract: a pick of -1 means "whatever is live
// right now", a pick that differs makes the card dirty, and nothing is written
// until Apply. The two picks are compared by VALUE, not by index, because both
// live values can move under the card (a poll for the scale, the watched state
// file for the text) and a stale index would report a change that is not there.
PanelCard {
    id: card

    property Appearance appearance: Appearance {}
    property var monitor: null
    // The output's own helpers (scale list, scale labels) come from the panel's
    // injected state, never from the singleton: a card that reads MonitorState
    // behind the panel's back cannot be rendered against a stub, and this one is
    // the card most worth forcing.
    property var state: null
    // The desktop's text scale, live, and the steps worth offering. Handed in by
    // the panel, which already reads the first from its own Appearance.
    property real textScale: 1
    property var textSteps: []
    // The original this card can go back to: the compositor scale monitors.lua
    // declares, and the theme's own text size (1 = the tokens as generated).
    // 0 means the rule declares no scale, so there is nothing honest to restore.
    property real originalScale: 0
    property real originalText: 1
    // True while a scale write is waiting for its read-back. MonitorState polls on
    // a 2 s tick, so without this the card believes it is still at the original for
    // up to two seconds after an apply, and RESET sits dark in that window.
    property bool writeInFlight: false
    // Review hook: no pointer automation on this host, so a preview forces the
    // hover state to check the tint. Same recipe as the volume plaque's mute key.
    property bool forceHover: false

    property bool cardFocused: false
    property int controlIndex: 0

    property alias scaleField: scaleField
    property alias textField: textField

    // The contract the plaque's key ring runs on: which field answers which
    // control, which one is open, and which sibling a newly opened one replaces.
    readonly property var openField: scaleField.open ? scaleField
        : (textField.open ? textField : null)

    property int scalePick: -1
    property int textPick: -1

    readonly property var scaleOptions: {
        const out = [];
        if (!card.state)
            return out;
        const steps = card.state.scaleOptions(card.monitor);
        for (let i = 0; i < steps.length; i++)
            out.push({ label: card.state.scaleLabel(steps[i]), value: steps[i] });
        return out;
    }
    readonly property var textOptions: {
        const out = [];
        const steps = card.textSteps || [];
        for (let i = 0; i < steps.length; i++)
            out.push({ label: Math.round(steps[i] * 100) + " %", value: steps[i] });
        return out;
    }

    readonly property int liveScaleIndex: card.monitor && card.state
        ? card.state.scaleIndexOf(card.monitor, card.monitor.scale) : 0
    readonly property int effectiveScaleIndex: card.scalePick >= 0 ? card.scalePick : card.liveScaleIndex
    readonly property real requestedScale: card.scaleOptions.length > 0
        ? card.scaleOptions[Math.min(card.effectiveScaleIndex, card.scaleOptions.length - 1)].value
        : 1

    // Nearest step, not indexOf: a scale set by hand in the state file is outside
    // the list, and showing 100 % for it would misreport the desktop.
    readonly property int liveTextIndex: {
        const steps = card.textSteps || [];
        let best = 0;
        let distance = Infinity;
        for (let i = 0; i < steps.length; i++) {
            const d = Math.abs(steps[i] - card.textScale);
            if (d < distance) {
                distance = d;
                best = i;
            }
        }
        return best;
    }
    readonly property int effectiveTextIndex: card.textPick >= 0 ? card.textPick : card.liveTextIndex
    readonly property real requestedText: card.textOptions.length > 0
        ? card.textOptions[Math.min(card.effectiveTextIndex, card.textOptions.length - 1)].value
        : card.textScale

    // Reset is not "discard my pick": it restores the two originals, and it is
    // only offered when the live state is away from them.
    readonly property bool canReset: card.monitor !== null
        && (card.writeInFlight
            || (card.originalScale > 0
                && Math.abs(card.monitor.scale - card.originalScale) >= 0.001)
            || Math.abs(card.textScale - card.originalText) >= 0.001)

    // One ring for every card: the laptop owns four controls (scale, text, apply,
    // reset) and an external three, so the count is the card's own.
    readonly property int controlCount: 4

    readonly property bool scaleDirty: card.monitor !== null
        && Math.abs(card.requestedScale - card.monitor.scale) >= 0.001
    readonly property bool textDirty: Math.abs(card.requestedText - card.textScale) >= 0.001
    readonly property bool dirty: card.scaleDirty || card.textDirty

    signal controlTouched(int control)
    signal listClosed()
    signal applyRequested()
    signal resetRequested()

    function openControl(control) {
        if (control === 0)
            scaleField.openList();
        else if (control === 1)
            textField.openList();
        else if (control === 2 && card.dirty)
            card.applyRequested();
        else if (control === 3 && card.canReset)
            card.resetRequested();
    }

    function closeLists() {
        scaleField.closeList();
        textField.closeList();
    }

    // Which field a control opens, and which sibling it displaces: control 0 is
    // the scale, 1 the text size, and 2 is the button and owns no list.
    function fieldAt(control) {
        if (control === 0)
            return scaleField;
        if (control === 1)
            return textField;
        return null;
    }

    function closeOtherThan(control) {
        if (control === 0)
            textField.closeList();
        else if (control === 1)
            scaleField.closeList();
    }

    // A poll hands over a fresh object every tick: drop the pick once the live
    // value already matches it, so a refresh never eats a pending selection and a
    // landed write leaves the card clean.
    onMonitorChanged: {
        if (!card.scaleDirty)
            card.scalePick = -1;
    }

    width: parent ? parent.width : 0
    title: card.monitor ? card.monitor.name : ""
    glyph: "laptop"
    chipText: card.dirty ? "MODIFIED"
        : (card.monitor && card.state ? card.state.scaleLabel(card.monitor.scale) : "")
    chipColor: card.dirty ? card.appearance.accentInk : card.appearance.textMuted
    chipDot: card.dirty

    // What the card can say about this output that is not its name.
    Text {
        Layout.fillWidth: true
        visible: text !== ""
        text: card.monitor ? card.monitor.description : ""
        color: card.appearance.textFaint
        elide: Text.ElideRight
        font.family: card.appearance.uiFont
        font.weight: card.appearance.fontWeightUi
        font.variableAxes: card.appearance.fontVariableAxesUi
        font.pixelSize: card.appearance.fontSizeCaption
        font.letterSpacing: card.appearance.letterSpacingCaption
    }

    // ----------------------------------------------------------- fields row
    RowLayout {
        width: parent.width
        spacing: card.appearance.fieldGap

        ChoiceField {
            id: scaleField

            Layout.fillWidth: true
            Layout.alignment: Qt.AlignTop
            appearance: card.appearance
            label: "SCALE"
            options: card.scaleOptions
            currentIndex: card.effectiveScaleIndex
            fieldFocused: card.cardFocused && card.controlIndex === 0
            onOpened: card.controlTouched(0)
            onClosed: card.listClosed()
            onPicked: (index) => card.scalePick = index
        }

        ChoiceField {
            id: textField

            Layout.fillWidth: true
            Layout.alignment: Qt.AlignTop
            appearance: card.appearance
            label: "TEXT"
            options: card.textOptions
            currentIndex: card.effectiveTextIndex
            fieldFocused: card.cardFocused && card.controlIndex === 1
            onOpened: card.controlTouched(1)
            onClosed: card.listClosed()
            onPicked: (index) => card.textPick = index
        }
    }

    // ------------------------------------------------------ reset/apply row
    // Two halves, both filling the row: the card has exactly two actions and
    // giving one of them the leftover space would rank them. Each one wears its
    // own material -- reset is the ornament (gilt edge, gilt word), apply is the
    // action (accent fill, accent-text ink) -- so "put it back" and "write it"
    // never look like the same button twice.
    RowLayout {
        width: parent.width
        spacing: card.appearance.spacingSmall

        Rectangle {
            id: resetBox

            readonly property bool focused: card.cardFocused && card.controlIndex === 3
            readonly property bool live: card.canReset
            // Hover and press ride the MouseArea, which is this desktop's recipe
            // for a button: a HoverHandler on a plaque with its own click catcher
            // never fired, and the visitor cannot hover a button that does not
            // answer him.
            readonly property bool hovered: (card.forceHover || resetPress.containsMouse) && resetBox.live
            readonly property bool held: resetPress.pressed && resetBox.live

            Layout.fillWidth: true
            Layout.preferredWidth: 1
            Layout.minimumWidth: 0
            Layout.preferredHeight: card.appearance.buttonHeightDense
            radius: card.appearance.shapeMedium
            color: resetBox.held
                ? card.appearance.pressFill
                : (resetBox.hovered ? card.appearance.hoverFill : "transparent")
            border.width: card.appearance.borderWidth
            border.color: resetBox.live
                ? (resetBox.focused ? card.appearance.accentInk
                    : (resetBox.hovered || resetBox.held
                        ? card.appearance.gilt : "transparent"))
                : card.appearance.outline
            opacity: resetBox.live ? 1 : card.appearance.opacityDisabled

            Behavior on color {
                ColorAnimation {
                    duration: resetBox.held ? card.appearance.motionPressDuration
                        : card.appearance.motionControlDuration
                    easing.type: card.appearance.motionControlEasing
                }
            }

            Behavior on border.color {
                ColorAnimation {
                    duration: card.appearance.motionControlDuration
                    easing.type: card.appearance.motionControlEasing
                }
            }

            Text {
                id: resetLabel

                anchors.centerIn: parent
                text: "RESET"
                color: resetBox.live ? card.appearance.giltInk : card.appearance.textFaint
                font.family: card.appearance.uiFont
                font.weight: card.appearance.fontWeightUi
                font.variableAxes: card.appearance.fontVariableAxesUi
                font.pixelSize: card.appearance.fontSizeSmall
                font.letterSpacing: card.appearance.letterSpacingLabel
            }

            MouseArea {
                id: resetPress
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: resetBox.live ? Qt.PointingHandCursor : Qt.ArrowCursor
                enabled: resetBox.live
                onClicked: {
                    card.controlTouched(3);
                    card.resetRequested();
                }
            }
        }

        Rectangle {
            id: applyBox

            readonly property bool focused: card.cardFocused && card.controlIndex === 2
            readonly property bool hovered: (card.forceHover || applyPress.containsMouse) && card.dirty
            readonly property bool held: applyPress.pressed && card.dirty

            Layout.fillWidth: true
            Layout.preferredWidth: 1
            Layout.minimumWidth: 0
            Layout.preferredHeight: card.appearance.buttonHeightDense
            radius: card.appearance.shapeMedium
            color: card.dirty
                ? (applyBox.held ? card.appearance.accentInk : card.appearance.accent)
                : card.appearance.surfaceContainerHigh
            border.width: card.appearance.borderWidth
            border.color: applyBox.focused && card.dirty
                ? card.appearance.accentInk
                : (card.dirty
                    ? (applyBox.hovered || applyBox.held
                        ? card.appearance.accentInk : card.appearance.accent)
                    : card.appearance.outline)
            opacity: card.dirty ? 1 : card.appearance.opacityDisabled

            Rectangle {
                anchors.fill: parent
                radius: parent.radius
                color: card.appearance.accentText
                opacity: card.dirty && applyBox.hovered
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

            MouseArea {
                id: applyPress
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: card.dirty ? Qt.PointingHandCursor : Qt.ArrowCursor
                enabled: card.dirty
                onClicked: {
                    card.controlTouched(2);
                    card.applyRequested();
                }
            }
        }
    }
}
