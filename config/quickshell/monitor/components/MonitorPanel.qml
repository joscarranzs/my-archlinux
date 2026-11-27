import QtQuick
import QtQuick.Layouts
import ".."
import "../services"

// The monitor plaque: one card per output -- the laptop card first, then one
// card per external monitor -- and key hints.
//
// Holds no window policy (no scrim, no layer-shell), so the overlay and the
// preview draw exactly the same pixels. The laptop panel is a readout for its
// mode and a control for the two things that cannot cost the user his screen:
// the compositor scale and the desktop's text scale. panel.state.apply() refuses
// an internal output whose mode differs from the live one.
Rectangle {
    id: panel

    property Appearance appearance: Appearance {}
    // The state object this panel renders, injected rather than reached for.
    // It is the MonitorState singleton in production; the state tests hand it a
    // stub, which is how "no external output" and "the write was refused" can be
    // rendered and asserted without a second compositor to unplug.
    property var state: MonitorState
    // The desktop's text scale: a second object, because it is a preference of
    // the desktop and not a property of an output. Injected for the same reason.
    property var textScaleState: TextScaleState

    // Focus coordinates over every card: which card, which control
    // (0 scale, 1 text/size, 2 apply). Both card kinds expose three controls, so
    // one ring covers them and the laptop comes first.
    property int focusCard: 0
    property int focusControl: 0

    // The field whose menu is floating over the plaque, null when none is open.
    // Only one menu exists at a time; it is drawn above the content so opening
    // it never resizes the plaque.
    property var activeField: null

    readonly property var externals: panel.state.externals
    readonly property var laptop: panel.state.internal
    readonly property int cardCount: (panel.laptop !== null ? 1 : 0) + panel.externals.length

    // Two writers, one slot. The monitor's own result outranks the text result,
    // except that an error always wins: a refused change must not scroll past
    // behind "text 110 %".
    readonly property string footerStatus: {
        const monitorLine = String(panel.state.status || "");
        const textLine = panel.textScaleState ? String(panel.textScaleState.status || "") : "";
        if (monitorLine !== "" && textLine !== "")
            return panel.state.statusKind === "error" ? monitorLine : textLine;
        return monitorLine !== "" ? monitorLine : textLine;
    }
    readonly property string footerKind: panel.textScaleState
        && panel.footerStatus === String(panel.textScaleState.status || "")
        ? panel.textScaleState.statusKind : panel.state.statusKind

    signal dismissed()

    function requestFocus() {
        keyCatcher.forceActiveFocus();
    }

    function cardAt(i) {
        if (panel.laptop !== null)
            return i === 0 ? laptopCard : cardRepeater.itemAt(i - 1);
        return cardRepeater.itemAt(i);
    }

    function anyListOpen() {
        for (let i = 0; i < panel.cardCount; i++) {
            const card = panel.cardAt(i);
            if (card && card.openField)
                return true;
        }
        return false;
    }

    function openField() {
        const card = panel.cardAt(panel.focusCard);
        return card ? card.openField : null;
    }

    function closeAllLists() {
        for (let i = 0; i < panel.cardCount; i++) {
            const card = panel.cardAt(i);
            if (card)
                card.closeLists();
        }
    }

    // A field reports opened() AFTER it set open = true, so closing everything
    // here would shut the list the user just opened. Close the other cards and
    // the sibling field only; which sibling that is, is the card's own business
    // (the laptop's controls are scale and text, an external's resolution and
    // scale, and this panel does not keep a second copy of that mapping).
    function focusTouched(i, control) {
        for (let j = 0; j < panel.cardCount; j++) {
            const other = panel.cardAt(j);
            if (other && j !== i)
                other.closeLists();
        }
        const card = panel.cardAt(i);
        if (card) {
            card.closeOtherThan(control);
            panel.activeField = card.fieldAt(control);
        } else {
            panel.activeField = null;
        }
        panel.focusCard = i;
        panel.focusControl = control;
    }

    // Anchor the menu under its field, flipping above it when the plaque has
    // no room below. Runs once per open: the plaque's geometry is static while
    // a menu is up, so the anchor cannot drift.
    function placeMenu() {
        const f = panel.activeField;
        if (!f)
            return;
        const below = f.mapToItem(panel, 0, f.boxBottom);
        const above = f.mapToItem(panel, 0, f.boxTop);
        const h = Math.min(f.options.length * appearance.popupRowHeight,
                           appearance.popupMaxHeight);
        menu.x = below.x;
        menu.width = f.width;
        menu.y = below.y + h > panel.height - appearance.spacingSmall
            ? above.y - h : below.y;
    }

    onActiveFieldChanged: placeMenu()
    // A hotplug rebuilds the cards; a menu pointing at a destroyed field must
    // not survive the rebuild, and the key ring must not point past the last
    // card -- unplugging the monitor the ring was on would otherwise leave the
    // focus on a row that no longer exists.
    onExternalsChanged: {
        panel.activeField = null;
        panel.focusCard = Math.min(panel.focusCard, Math.max(0, panel.cardCount - 1));
    }

    function moveCard(delta) {
        if (panel.cardCount === 0)
            return;
        panel.closeAllLists();
        panel.focusCard = Math.max(0, Math.min(panel.cardCount - 1, panel.focusCard + delta));
        panel.focusControl = 0;
    }

    // The ring wraps inside the focused card: the laptop owns four controls
    // (scale, text, apply, reset) and an external three, so the modulus is the
    // card's, not one number for both.
    function moveControl(delta) {
        const card = panel.cardAt(panel.focusCard);
        if (!card)
            return;
        panel.closeAllLists();
        const count = card.controlCount;
        panel.focusControl = (panel.focusControl + delta + count) % count;
    }

    function activate() {
        const card = panel.cardAt(panel.focusCard);
        if (card)
            card.openControl(panel.focusControl);
    }

    // RESET: back to the rule's scale and the theme's own text size, through the
    // same two paths an apply takes, and only for what is actually off.
    function resetLaptop() {
        const card = laptopCard;
        if (!panel.laptop || !card.canReset)
            return;
        if (card.originalScale > 0
                && Math.abs(panel.laptop.scale - card.originalScale) >= 0.001)
            panel.state.apply(panel.laptop.name, panel.laptop.width,
                              panel.laptop.height, panel.laptop.refresh,
                              card.originalScale);
        if (Math.abs(panel.appearance.textScale - card.originalText) >= 0.001
                && panel.textScaleState)
            panel.textScaleState.apply(card.originalText);
    }

    function doApply(i) {
        const card = panel.cardAt(i);
        if (!card || !card.monitor || !card.dirty)
            return;
        const mon = card.monitor;
        const mode = mon.modes[card.effectiveModeIndex];
        const scale = panel.state.scaleOptions(mon)[card.effectiveScaleIndex];
        if (!mode)
            return;
        panel.state.apply(mon.name, mode.w, mode.h, mode.rate, scale);
    }

    // What monitors.lua declares for the laptop: the original RESET goes back to.
    readonly property real laptopOriginalScale:
        (panel.laptop && panel.state.originalScale)
            ? panel.state.originalScale(panel.laptop.name) : 0
    readonly property real laptopOriginalText: 1

    // The laptop writes two things, on two different paths: the compositor scale
    // through MonitorState (with its read-back), the text size through the script
    // that owns the state file.
    function applyLaptop() {
        const card = laptopCard;
        if (!panel.laptop || !card.dirty)
            return;
        if (card.scaleDirty)
            panel.state.apply(panel.laptop.name, panel.laptop.width,
                              panel.laptop.height, panel.laptop.refresh,
                              card.requestedScale);
        if (card.textDirty && panel.textScaleState)
            panel.textScaleState.apply(card.requestedText);
    }

    // The plaque is never narrower than its own footer: the legend is the
    // widest fixed row on the surface, and the text scale grows it while the
    // width token does not. At rest the token still wins, so nothing moves.
    width: Math.max(appearance.panelWidth, legendRow.implicitWidth + appearance.contentPad * 2)
    // The plaque follows its content: the list is capped, the rest is chrome.
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

    MouseArea { anchors.fill: parent }

    ColumnLayout {
        id: layout

        // NOT anchors.fill: panel.height derives from this layout's
        // implicitHeight, and filling the parent closes a binding loop.
        x: appearance.contentPad
        y: appearance.contentPad
        width: panel.width - appearance.contentPad * 2
        height: implicitHeight
        spacing: appearance.spacingSmall

        // ---------------------------------------------------- laptop card
        // The output he is reading: its name in the title, its live scale in the
        // chip, and the only two controls that cannot take the screen away.
        LaptopCard {
            id: laptopCard

            Layout.fillWidth: true
            visible: panel.laptop !== null
            appearance: panel.appearance
            monitor: panel.laptop
            state: panel.state
            textScale: panel.appearance.textScale
            textSteps: (panel.textScaleState && panel.textScaleState.steps)
                ? panel.textScaleState.steps : []
            originalScale: panel.laptopOriginalScale
            originalText: panel.laptopOriginalText
            writeInFlight: panel.state.verify !== undefined && panel.state.verify !== null
            cardFocused: panel.laptop !== null && panel.focusCard === 0
            controlIndex: panel.focusControl
            onControlTouched: (control) => panel.focusTouched(0, control)
            onListClosed: panel.activeField = null
            onApplyRequested: panel.applyLaptop()
            onResetRequested: panel.resetLaptop()
        }

        // --------------------------------------------------- external cards
        Flickable {
            id: listView

            Layout.fillWidth: true
            Layout.preferredHeight: Math.min(cards.implicitHeight, panel.appearance.listMaxHeight)
            visible: panel.externals.length > 0
            contentHeight: cards.implicitHeight
            clip: true
            boundsBehavior: Flickable.StopAtBounds

            Column {
                id: cards

                width: listView.width
                spacing: panel.appearance.cardGap

                Repeater {
                    id: cardRepeater

                    model: panel.externals

                    MonitorCard {
                        width: cards.width
                        appearance: panel.appearance
                        monitor: modelData
                        state: panel.state
                        cardFocused: panel.focusCard === index + (panel.laptop !== null ? 1 : 0)
                        controlIndex: panel.focusControl
                        onControlTouched: (control) => {
                            panel.focusTouched(index + (panel.laptop !== null ? 1 : 0), control);
                        }
                        onListClosed: panel.activeField = null
                        onApplyRequested: panel.doApply(index)
                    }
                }
            }
        }

        // Empty state: no external output is a real answer, not a bug. It sits
        // in a card so the plaque is the same object with zero outputs as with
        // three -- a title and a body -- instead of a naked line on the well.
        PanelCard {
            Layout.fillWidth: true
            visible: panel.externals.length === 0 && panel.state.ready
            appearance: panel.appearance
            title: "Outputs"

            Text {
                Layout.fillWidth: true
                Layout.preferredHeight: panel.appearance.rowHeight
                verticalAlignment: Text.AlignVCenter
                horizontalAlignment: Text.AlignHCenter
                text: "no external monitor connected"
                color: panel.appearance.textMuted
                font.family: panel.appearance.uiFont
                font.weight: panel.appearance.fontWeightUi
                font.variableAxes: panel.appearance.fontVariableAxesUi
                font.pixelSize: panel.appearance.fontSizeBody
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

            // One slot for both writers: the status message takes over the hint
            // line while it shows, so a result never resizes the plaque.
            Text {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                visible: panel.footerStatus !== ""
                text: panel.footerStatus
                color: panel.footerKind === "error" ? panel.appearance.danger
                    : (panel.footerKind === "ok" ? panel.appearance.accentInk
                        : panel.appearance.textMuted)
                elide: Text.ElideRight
                font.family: panel.appearance.uiFont
                font.weight: panel.appearance.fontWeightUi
                font.variableAxes: panel.appearance.fontVariableAxesUi
                font.pixelSize: panel.appearance.fontSizeSmall
                font.letterSpacing: 0
            }

            // The keys, as keys: one cap each, the tracked label beside it. The cap
            // recipe is generated (components/LegendRow.qml), so this footer and the
            // kanban's legend cannot drift into two different objects.
            RowLayout {
                id: legendRow

                anchors.horizontalCenter: parent.horizontalCenter
                anchors.verticalCenter: parent.verticalCenter
                visible: panel.footerStatus === ""
                spacing: panel.appearance.spacingMedium

                LegendRow {
                    appearance: panel.appearance
                    key: "↑↓"
                    label: "monitor"
                    tracked: true
                }

                LegendRow {
                    appearance: panel.appearance
                    key: "Tab"
                    label: "control"
                    tracked: true
                }

                LegendRow {
                    appearance: panel.appearance
                    key: "↵"
                    label: "apply"
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

    // Click anywhere on the plaque outside the menu closes it. Sits below the
    // menu (z 100) and above all content, so the first click dismisses instead
    // of activating whatever is underneath.
    MouseArea {
        anchors.fill: parent
        z: panel.appearance.zPopover
        visible: panel.activeField !== null
        onClicked: panel.closeAllLists()
    }

    ChoiceMenu {
        id: menu

        z: panel.appearance.zModal
        appearance: panel.appearance
        field: panel.activeField
    }

    Item {
        id: keyCatcher

        anchors.fill: parent
        focus: true

        Keys.onPressed: (event) => {
            if (event.key === Qt.Key_Escape) {
                if (panel.anyListOpen())
                    panel.closeAllLists();
                else
                    panel.dismissed();
                event.accepted = true;
                return;
            }
            const open = panel.openField();
            if (open) {
                if (event.key === Qt.Key_Up)
                    open.move(-1);
                else if (event.key === Qt.Key_Down)
                    open.move(1);
                else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter)
                    open.commit();
                else
                    return;
                event.accepted = true;
                return;
            }
            if (event.key === Qt.Key_Up)
                panel.moveCard(-1);
            else if (event.key === Qt.Key_Down)
                panel.moveCard(1);
            else if (event.key === Qt.Key_Left || event.key === Qt.Key_Backtab)
                panel.moveControl(-1);
            else if (event.key === Qt.Key_Right || event.key === Qt.Key_Tab)
                panel.moveControl(1);
            else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter)
                panel.activate();
            else
                return;
            event.accepted = true;
        }
    }
}
