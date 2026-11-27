import QtQuick
import QtQuick.Layouts
import ".."
import "../services"

// The wifi plaque: header, current connection, the scan list, an optional
// passphrase field and key hints.
//
// Holds no window policy (no scrim, no layer-shell), so the overlay and the
// preview draw exactly the same pixels. Nothing here writes to the radio on its
// own: a connection only changes when the user picks a network and, for a secured
// one, types the passphrase.
Rectangle {
    id: panel

    property Appearance appearance: Appearance {}
    // Injected state object: the NetworkState singleton in production, a stub in
    // the state tests. Same reason as the monitor's — an empty scan and a failed
    // connect are states, and they have to be renderable on demand.
    property var state: NetworkState

    // List state lives here, not in the service: it is the panel that owns "which
    // row is highlighted".
    property int selected: 0
    property var pending: null
    property string passphrase: ""

    readonly property var nets: panel.state.networks
    readonly property var current: panel.state.current

    signal connectRequested(var network, string passphrase)
    signal dismissed()

    // The single exit for Esc and for the scrim. Blocking the close while an attempt
    // runs is what trapped the panel: cancelling has to be reachable from the same
    // place closing is.
    function requestClose() {
        if (panel.state.attempting) {
            panel.state.cancelAttempt();
            return;
        }
        panel.dismissed();
    }

    function requestFocus() {
        keyCatcher.forceActiveFocus();
    }

    function moveSelection(delta) {
        if (nets.length === 0 || panel.state.attempting)
            return;
        panel.selected = Math.max(0, Math.min(nets.length - 1, panel.selected + delta));
    }

    function activateSelected() {
        if (nets.length === 0)
            return;
        activate(nets[panel.selected]);
    }

    function activate(network) {
        if (!network || panel.state.attempting)
            return;
        // A saved network normally holds its secret, but `known` can be stale (NM
        // recreates the access-point objects while scanning) and a network that just
        // failed with a wrong passphrase still has a profile NM wrote. Either way the
        // field has to come back, not an activation of a profile with no secret.
        const mustAsk = panel.state.needsPassword(network)
            && (!network.known || panel.state.lastFailedSsid === network.name);
        if (!mustAsk) {
            panel.connectRequested(network, "");
            return;
        }
        panel.pending = network;
        panel.passphrase = "";
        passField.forceActiveFocus();
    }

    function cancelPending() {
        panel.pending = null;
        panel.passphrase = "";
        panel.requestFocus();
    }

    function submitPassphrase() {
        if (panel.pending === null)
            return;
        const target = panel.pending;
        const secret = panel.passphrase;
        panel.pending = null;
        panel.passphrase = "";
        panel.requestFocus();
        panel.connectRequested(target, secret);
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


    MouseArea {
        anchors.fill: parent
    }

    ColumnLayout {
        id: layout

        // Deliberately NOT `anchors.fill: parent`: `panel.height` is derived from
        // this layout's implicitHeight, so filling the parent closes a binding loop
        // that QML breaks by laying the children out against a stale height -- the
        // current-link block and the list row then landed on the same y and drew on
        // top of each other.
        x: appearance.contentPad
        y: appearance.contentPad
        width: panel.width - appearance.contentPad * 2
        // A ColumnLayout positions NOTHING unless it has a height of its own: with 0
        // it puts every child at y=0 and they all draw on top of each other. Setting
        // it from its own implicitHeight gives it the height it asked for without
        // depending on the panel (which depends on this).
        height: implicitHeight
        spacing: appearance.spacingSmall

        PanelCard {
            id: connectionCard

            Layout.fillWidth: true
            appearance: panel.appearance
            title: "Connection"
            chipColor: panel.appearance.danger
            chipText: !panel.state.available ? "NO DEVICE" : (!panel.state.radioOn ? "RADIO OFF" : "")

            // -------------------------------------------------- current link
            Item {
                id: currentBlock
                Layout.fillWidth: true
                Layout.preferredHeight: panel.appearance.rowHeight
                visible: panel.current !== null

                Column {
                    id: currentLines

                    anchors.left: parent.left
                    anchors.leftMargin: panel.appearance.spacingSmall * 2
                    anchors.right: bars.left
                    anchors.rightMargin: panel.appearance.spacingSmall
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: panel.appearance.hairline

                    Text {
                        width: currentLines.width
                        text: panel.current ? panel.current.name : ""
                        color: panel.appearance.text
                        elide: Text.ElideRight
                        font.family: panel.appearance.uiFont
                        font.weight: panel.appearance.fontWeightUi
                        font.variableAxes: panel.appearance.fontVariableAxesUi
                        font.pixelSize: panel.appearance.fontSizeBody
                    }

                    Text {
                        width: currentLines.width
                        text: panel.current
                            ? "connected · " + panel.state.signalPercent(panel.current) + "% · "
                              + panel.state.securityLabel(panel.current)
                            : ""
                        color: panel.appearance.accentInk
                        elide: Text.ElideRight
                        font.family: panel.appearance.uiFont
                        font.weight: panel.appearance.fontWeightUi
                        font.variableAxes: panel.appearance.fontVariableAxesUi
                        font.pixelSize: panel.appearance.fontSizeSmall
                        font.letterSpacing: panel.appearance.letterSpacingCaption
                    }
                }

                SignalBars {
                    id: bars
                    anchors.right: parent.right
                    anchors.rightMargin: panel.appearance.spacingSmall * 2
                    anchors.verticalCenter: parent.verticalCenter
                    appearance: panel.appearance
                    percent: panel.current ? panel.state.signalPercent(panel.current) : 0
                    barColor: panel.appearance.accent
                }
            }

        }

        PanelCard {
            id: networksCard

            Layout.fillWidth: true
            appearance: panel.appearance
            title: "Networks"
            // A count, but only when there is one to give: the empty state already
            // says "no networks in range", and a chip reading 0 networks would be
            // the same sentence twice.
            chipText: panel.nets.length === 0 ? ""
                : (panel.nets.length + (panel.nets.length === 1 ? " network" : " networks"))

            // ------------------------------------------------------ network list
            Flickable {
                id: listView

                Layout.fillWidth: true
                Layout.preferredHeight: Math.min(networks.implicitHeight, panel.appearance.listMaxHeight)
                contentHeight: networks.implicitHeight
                clip: true
                boundsBehavior: Flickable.StopAtBounds

                Column {
                    id: networks
                    width: listView.width
                    spacing: panel.appearance.rowGap

                    Repeater {
                        model: panel.nets

                        NetworkRow {
                            width: networks.width
                            appearance: panel.appearance
                            ssid: modelData.name
                            subtitle: panel.state.securityLabel(modelData)
                                + (modelData.known ? " · saved" : "")
                                + (modelData.connected ? " · connected" : "")
                            percent: panel.state.signalPercent(modelData)
                            connected: modelData.connected
                            selected: panel.pending === null && index === panel.selected
                            onActivated: {
                                panel.selected = index;
                                panel.activate(modelData);
                            }
                        }
                    }
                }
            }

            // Empty state: a scan that found nothing is a real answer, not a bug.
            Text {
                Layout.fillWidth: true
                Layout.preferredHeight: appearance.rowHeight
                visible: panel.nets.length === 0
                verticalAlignment: Text.AlignVCenter
                horizontalAlignment: Text.AlignHCenter
                text: !panel.state.available || !panel.state.radioOn ? ""
                    : (panel.current !== null ? "no other networks in range" : "no networks in range")
                color: panel.appearance.textMuted
                font.family: panel.appearance.uiFont
                font.weight: panel.appearance.fontWeightUi
                font.variableAxes: panel.appearance.fontVariableAxesUi
                font.pixelSize: panel.appearance.fontSizeSmall
                font.letterSpacing: panel.appearance.letterSpacingCaption
            }

        }

        PanelCard {
            id: passCard

            Layout.fillWidth: true
            appearance: panel.appearance
            title: "Passphrase"
            chipColor: panel.appearance.accent
            visible: panel.pending !== null
            chipText: panel.pending ? panel.pending.name : ""

            // ---------------------------------------------------- passphrase
            ColumnLayout {
                Layout.fillWidth: true
                spacing: panel.appearance.spacingSmall / 2
                visible: panel.pending !== null


                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: panel.appearance.fieldHeightDense
                    radius: panel.appearance.shapeMedium
                    color: panel.appearance.surfaceContainerHigh
                    border.width: panel.appearance.borderWidth
                    border.color: passField.activeFocus
                        ? panel.appearance.accent : panel.appearance.outline

                    TextInput {
                        id: passField

                        anchors.fill: parent
                        anchors.leftMargin: panel.appearance.spacingSmall
                        anchors.rightMargin: panel.appearance.spacingSmall
                        verticalAlignment: TextInput.AlignVCenter
                        echoMode: TextInput.Password
                        passwordCharacter: "•"
                        color: panel.appearance.text
                        selectionColor: panel.appearance.accent
                        selectedTextColor: panel.appearance.surface
                        font.family: panel.appearance.uiFont
                        font.pixelSize: panel.appearance.fontSizeBody
                        clip: true

                        // Placeholder bound to emptiness, never to focus: the field is
                        // focused the moment it appears.
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            visible: passField.text.length === 0
                            text: "passphrase…"
                            color: panel.appearance.textMuted
                            opacity: panel.appearance.opacityPlaceholder
                            font.family: panel.appearance.uiFont
                            font.weight: panel.appearance.fontWeightUi
                            font.variableAxes: panel.appearance.fontVariableAxesUi
                            font.pixelSize: panel.appearance.fontSizeBody
                        }

                        cursorDelegate: Rectangle {
                            width: panel.appearance.borderWidth * 2
                            color: panel.appearance.accent
                            visible: passField.text.length > 0
                        }

                        onTextEdited: panel.passphrase = text
                        onAccepted: panel.submitPassphrase()

                        Keys.onPressed: (event) => {
                            if (event.key === Qt.Key_Escape) {
                                panel.cancelPending();
                                event.accepted = true;
                            }
                        }
                    }
                }
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

            // One slot for both: a message takes over the hint line while it is
            // showing, so a failure never resizes the plaque and never hides behind
            // a "select / connect" hint the user is not reading right now. Messages
            // stay prose -- a sentence in the middle of a legend reads as a legend
            // entry -- and the hint lists are legends.
            Text {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                visible: panel.state.status !== "" || panel.state.attempting
                text: panel.state.status !== "" ? panel.state.status
                    : "esc cancels the attempt"
                color: panel.state.statusKind === "error" ? panel.appearance.danger
                    : (panel.state.statusKind === "ok" ? panel.appearance.accentInk
                        : panel.appearance.textMuted)
                elide: Text.ElideRight
                font.family: panel.appearance.uiFont
                font.weight: panel.appearance.fontWeightUi
                font.variableAxes: panel.appearance.fontVariableAxesUi
                font.pixelSize: panel.appearance.fontSizeSmall
                font.letterSpacing: 0
            }

            // The keys, as keys: one cap each, the tracked label beside it, and the
            // cap recipe is generated (components/LegendRow.qml).
            //
            // R rescans and is deliberately not in the legend: the four entries
            // measure 336 px against this plaque's 312 px of footer (measured
            // 2026-11-23), and a legend that elides its last key teaches the wrong
            // thing. The key still works. Widen the plaque before adding it back.
            RowLayout {
                id: legendRow

                anchors.horizontalCenter: parent.horizontalCenter
                anchors.verticalCenter: parent.verticalCenter
                visible: panel.state.status === "" && !panel.state.attempting
                spacing: panel.appearance.spacingMedium

                LegendRow {
                    appearance: panel.appearance
                    key: "↑↓"
                    label: "select"
                    tracked: true
                    visible: panel.pending === null
                }

                LegendRow {
                    appearance: panel.appearance
                    key: "↵"
                    label: "connect"
                    tracked: true
                }

                LegendRow {
                    appearance: panel.appearance
                    key: "Esc"
                    label: "back"
                    tracked: true
                    visible: panel.pending !== null
                }

                LegendRow {
                    appearance: panel.appearance
                    key: "Esc"
                    label: "close"
                    tracked: true
                    visible: panel.pending === null
                }
            }
        }
    }


    Item {
        id: keyCatcher

        anchors.fill: parent
        focus: panel.pending === null
        enabled: panel.pending === null

        Keys.onPressed: (event) => {
            if (event.key === Qt.Key_Escape) {
                panel.requestClose();
            } else if (event.key === Qt.Key_Up) {
                panel.moveSelection(-1);
            } else if (event.key === Qt.Key_Down) {
                panel.moveSelection(1);
            } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                panel.activateSelected();
            } else if (event.key === Qt.Key_R) {
                panel.state.rescan();
            } else {
                return;
            }
            event.accepted = true;
        }
    }
}
