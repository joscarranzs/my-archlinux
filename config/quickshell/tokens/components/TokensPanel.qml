import QtQuick
import QtQuick.Layouts
import ".."
import "../usage-rule.js" as UsageRule

// The AI plaque: three accounts, one card each.
//
// It used to be a single column of bare headings -- today's tokens, the session,
// the plan, the balance -- which is one receipt pretending to be an overview. The
// three things it reports answer three different questions ("what does my prepaid
// wallet hold", "how much of the plan is left", "what is the open session
// burning"), so each one gets a card: identity in the header, its own numbers
// below, and no rule between sections to make them read as one list.
//
// Holds no window policy (no scrim, no layer-shell) so the real overlay and the
// preview draw the same pixels. It reads one JSON blob from services/TokenFeed
// and never touches the network: every number here is a field of that blob.
Rectangle {
    id: panel

    property Appearance appearance: Appearance {}
    property var feed: null

    signal dismissRequested()
    signal refreshRequested()

    readonly property var nous: feed ? feed.nous : ({})
    readonly property var go: feed ? feed.go : ({})
    readonly property var tokens: feed ? feed.tokens : ({})
    readonly property var session: tokens.session || null
    readonly property var windows: go.windows || []

    readonly property bool stale: !!(nous.stale || go.stale)
    readonly property bool waiting: !feed || !feed.hasData
    // The row belongs to the session, not to the data: while a chat is open the
    // line stays on screen even when one of its two numbers is missing. `!!session`
    // first: a bare `session.context_max` on a null session is a TypeError in a
    // binding. Both facts are optional and independent -- the ceiling comes from
    // the model, the buffer from the agent log -- so each gets its own flag
    // instead of one flag hiding the row when either is absent.
    readonly property bool contextReading: !!session
    readonly property bool contextPercent: contextReading && session.context_pct !== null
        && session.context_pct !== undefined
    readonly property bool contextCapacity: contextReading && session.context_max > 0
    readonly property bool contextBuffer: contextReading && session.context_used !== null
        && session.context_used !== undefined
    // Context pressure is a budget like any other, so it walks the one ladder in
    // usage-rule.js: accent while there is room, gilt near the limit, danger at
    // it, muted when the number is not there.
    readonly property color contextFill: UsageRule.fill(
        appearance, contextPercent ? session.context_pct : null, false)
    readonly property color contextInk: UsageRule.ink(
        appearance, contextPercent ? session.context_pct : null, false)

    // The prepaid wallet is drawdown, not headroom: 0 % is a full balance and
    // 100 % is an empty one, the same scale the allowance windows use, so the
    // same thresholds mean the same thing on both cards.
    readonly property real nousPercent: {
        var spent = Number(nous.spent_usd);
        var purchased = Number(nous.purchased_usd);
        if (!nousReading || !isFinite(spent) || !isFinite(purchased) || purchased <= 0)
            return -1;
        return spent / purchased * 100;
    }

    // The metric row is four equal columns across the card's inner width. Derived
    // from the plaque, so the cells and the bars above them share one grid.
    readonly property int metricCellWidth: Math.floor(
        (width - appearance.contentPad * 2 - appearance.cardPad * 2
         - appearance.tokensMetricGap * 3) / 4)

    readonly property bool nousReading: !!feed && feed.hasData && (nous.ok || !!nous.fetched_at)
    readonly property bool goReading: !!feed && feed.hasData && (go.ok || !!go.fetched_at)

    // The plan's state is what the endpoint answered, not a guess from the
    // percentages: a refused read is stale, a missing key is inactive, and a
    // 200 with windows is active. Nothing else can be claimed from here.
    readonly property string goState: go.ok ? "active" : (go.stale ? "stale" : "inactive")
    readonly property color goStateColor: go.ok ? appearance.accent : appearance.danger

    // Which pocket pays for the open session: a plan allowance or prepaid
    // credits. Absent when the route is unknown, because a chip that says
    // "unknown" is worse than no chip: it dresses a gap as an answer.
    readonly property string routeLabel: {
        if (!session || !session.route)
            return "";
        return session.route === "plan" ? "plan" : (session.route === "credit" ? "credit" : "");
    }
    readonly property color routeColor: session && session.route === "credit" ? appearance.gilt : appearance.accent

    function requestFocus() {
        keyCatcher.forceActiveFocus();
    }

    // 1.2K / 34.5M: token counts never fit a column at full precision and the
    // panel is a glance, not an invoice.
    function compact(value) {
        if (value === undefined || value === null)
            return "—";
        var number = Number(value);
        if (!isFinite(number))
            return "—";
        if (number >= 1e9)
            return (number / 1e9).toFixed(1) + "B";
        if (number >= 1e6)
            return (number / 1e6).toFixed(number >= 1e7 ? 0 : 1) + "M";
        if (number >= 1e3)
            return (number / 1e3).toFixed(number >= 1e4 ? 0 : 1) + "K";
        return String(Math.round(number));
    }

    function usd(value) {
        if (value === undefined || value === null)
            return "—";
        var number = Number(value);
        if (!isFinite(number))
            return "—";
        return "$" + number.toFixed(2);
    }

    function clock(iso) {
        if (!iso)
            return "";
        var stamp = Date.parse(iso);
        if (isNaN(stamp))
            return "";
        return Qt.formatDateTime(new Date(stamp), "HH:mm");
    }

    // A renewal is a date the user plans around, so it is written as one --
    // month and day plus the time -- instead of the countdown the allowance rows
    // use for windows measured in hours.
    function renewal(iso) {
        if (!iso)
            return "";
        var stamp = Date.parse(iso);
        if (isNaN(stamp))
            return "";
        return Qt.formatDateTime(new Date(stamp), "dd MMM HH:mm");
    }

    // The window names the endpoint reports. "rolling" is not a day: it restarts
    // every few hours, so it is labelled by what it is and not by the "daily"
    // bucket it would advertise.
    function windowLabel(key) {
        if (key === "rolling")
            return "5h";
        return key;
    }

    width: appearance.tokensWidth
    height: layout.implicitHeight + appearance.contentPad * 2
    // The plaque is the well, the cards are raised on it: grouping reads as
    // elevation, so the outer fill steps down a rung instead of framing three
    // cards in the same tone they sit on.
    color: appearance.surface
    radius: appearance.shapeExtraLarge
    // Edge: gilt (accent.tertiary) at look.borders.width -- the plaque's frame.
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
        // The gap between cards is wider than the gap inside one: that is what
        // makes three blocks read as three blocks and not as a taller list.
        spacing: appearance.cardGap

        // Header: what this is, and how fresh the numbers are.
        Item {
            Layout.fillWidth: true
            Layout.preferredHeight: appearance.headerHeight

            Text {
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                text: "AI USAGE"
                color: panel.appearance.text
                font.family: panel.appearance.displayFont
                font.weight: panel.appearance.fontWeightDisplay
                font.variableAxes: panel.appearance.fontVariableAxesDisplay
                font.pixelSize: panel.appearance.fontSizeTitle
                font.bold: true
                font.letterSpacing: panel.appearance.letterSpacingLabel
            }

            Text {
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                text: panel.waiting ? "reading…" : ((panel.stale ? "STALE · " : "") + panel.clock(panel.feed.data.generated_at))
                color: panel.stale ? panel.appearance.danger : panel.appearance.textMuted
                font.family: panel.appearance.uiFont
                font.weight: panel.appearance.fontWeightUi
                font.variableAxes: panel.appearance.fontVariableAxesUi
                font.pixelSize: panel.appearance.fontSizeCaption
                font.letterSpacing: panel.appearance.letterSpacingCaption
                font.capitalization: Font.AllUppercase
            }
        }

        // 1. Nous Portal: what the prepaid wallet still holds, and how much of it
        //    has already been spent. One figure carries the card; the bar and the
        //    sentence underneath are the same fact, told twice on purpose -- a
        //    dollar amount and a fraction answer different questions.
        PanelCard {
            Layout.fillWidth: true
            appearance: panel.appearance
            title: "Nous Portal"
            imageSource: Qt.resolvedUrl("../assets/nous.png")
            // Line art: it needs the whole box to keep its silhouette readable.
            markSize: panel.appearance.iconSizeLg
            chipText: panel.waiting ? "" : (panel.nous.stale ? "stale" : "prepaid")
            chipColor: panel.nous.stale ? panel.appearance.danger : panel.appearance.gilt
            chipDot: true

            RowLayout {
                Layout.fillWidth: true
                spacing: panel.appearance.spacingSmall

                Text {
                    Layout.alignment: Qt.AlignBottom
                    text: panel.nousReading || panel.waiting ? panel.usd(panel.waiting ? null : panel.nous.balance_usd) : "—"
                    // The accent marks a verified balance. A stale one keeps the
                    // figure (it is the last thing that was true) in muted ink.
                    color: panel.nous.stale ? panel.appearance.textMuted : panel.appearance.accentInk
                    font.family: panel.appearance.displayFont
                    font.weight: panel.appearance.fontWeightDisplay
                    font.variableAxes: panel.appearance.fontVariableAxesDisplay
                    font.pixelSize: panel.appearance.fontSizeDisplay
                    font.bold: true
                }

                Text {
                    Layout.fillWidth: true
                    Layout.alignment: Qt.AlignBottom
                    Layout.bottomMargin: panel.appearance.spacingXs
                    elide: Text.ElideRight
                    text: "left"
                    color: panel.appearance.textMuted
                    font.family: panel.appearance.uiFont
                    font.weight: panel.appearance.fontWeightUi
                    font.variableAxes: panel.appearance.fontVariableAxesUi
                    font.pixelSize: panel.appearance.fontSizeCaption
                }
            }

            UsageBar {
                Layout.fillWidth: true
                appearance: panel.appearance
                percent: panel.nousPercent < 0 ? 0 : panel.nousPercent
                fillColor: UsageRule.fill(panel.appearance,
                    panel.nousPercent < 0 ? null : panel.nousPercent, panel.nous.stale)
            }

            Text {
                Layout.fillWidth: true
                elide: Text.ElideRight
                text: {
                    if (panel.waiting)
                        return "";
                    if (!panel.nous.ok && !panel.nous.fetched_at)
                        return panel.nous.error || "no data";
                    return "spent " + panel.usd(panel.nous.spent_usd) + " of " + panel.usd(panel.nous.purchased_usd);
                }
                color: panel.appearance.textMuted
                font.family: panel.appearance.uiFont
                font.weight: panel.appearance.fontWeightUi
                font.variableAxes: panel.appearance.fontVariableAxesUi
                font.pixelSize: panel.appearance.fontSizeSmall
            }
        }

        // 2. OpenCode Go: a plan, not a wallet. Its renewal date, its state, and
        //    the three windows the endpoint actually reports.
        PanelCard {
            Layout.fillWidth: true
            appearance: panel.appearance
            title: "OpenCode Go"
            imageSource: Qt.resolvedUrl("../assets/opencode.svg")
            // Its frame is a 25 %-thick stroke: at md it outweighed the line-art
            // mark beside it, so it takes the next rung down.
            markSize: panel.appearance.iconSizeSm
            chipText: panel.waiting ? "" : panel.goState
            chipColor: panel.goStateColor
            chipDot: true

            Text {
                Layout.fillWidth: true
                elide: Text.ElideRight
                text: {
                    if (panel.waiting)
                        return "";
                    var date = panel.renewal(panel.go.renews_at);
                    return date ? "renews " + date : "renewal date not reported";
                }
                color: panel.appearance.textMuted
                font.family: panel.appearance.uiFont
                font.weight: panel.appearance.fontWeightUi
                font.variableAxes: panel.appearance.fontVariableAxesUi
                font.pixelSize: panel.appearance.fontSizeSmall
            }

            Repeater {
                model: panel.windows

                delegate: AllowanceRow {
                    Layout.fillWidth: true
                    appearance: panel.appearance
                    stale: !!panel.go.stale
                    label: panel.windowLabel(modelData.key)
                    percent: modelData.percent
                    resetsAt: modelData.resets_at
                }
            }

            // The block is not optional: a missing key or a refused request has
            // to say so, or the card looks like a plan with nothing consumed.
            Text {
                Layout.fillWidth: true
                elide: Text.ElideRight
                visible: !panel.waiting && panel.windows.length === 0
                text: panel.waiting ? "" : (panel.go.error || "no data")
                color: panel.appearance.textMuted
                font.family: panel.appearance.uiFont
                font.weight: panel.appearance.fontWeightUi
                font.variableAxes: panel.appearance.fontVariableAxesUi
                font.pixelSize: panel.appearance.fontSizeSmall
            }
        }

        // 3. The session that is still open: what it runs on, who serves it, what
        //    pays for it, and what it has burned. This is the card whose numbers
        //    move while the user watches, so it sits last, closest to the footer.
        PanelCard {
            Layout.fillWidth: true
            appearance: panel.appearance
            title: "Session"
            glyph: "bolt"
            chipText: panel.waiting ? "" : panel.routeLabel
            chipColor: panel.routeColor
            chipDot: true

            Text {
                Layout.fillWidth: true
                text: {
                    if (panel.waiting)
                        return "";
                    if (!panel.session)
                        return "no open session";
                    return panel.session.model ? panel.session.model.split("/").pop() : "unknown model";
                }
                // Middle, not right: the tail of a model id is the version.
                elide: Text.ElideMiddle
                color: panel.session ? panel.appearance.text : panel.appearance.textMuted
                font.family: panel.appearance.uiFont
                font.weight: panel.appearance.fontWeightUi
                font.variableAxes: panel.appearance.fontVariableAxesUi
                font.pixelSize: panel.appearance.fontSizeBody
                font.bold: true
            }

            Text {
                Layout.fillWidth: true
                elide: Text.ElideMiddle
                visible: !!panel.session
                text: {
                    if (!panel.session)
                        return "";
                    var provider = panel.session.provider ? panel.session.provider : "unknown provider";
                    var route = panel.session.route === "plan" ? "plan" : (panel.session.route === "credit" ? "credit" : "");
                    return route ? provider + " · " + route : provider;
                }
                color: panel.appearance.textMuted
                font.family: panel.appearance.uiFont
                font.weight: panel.appearance.fontWeightUi
                font.variableAxes: panel.appearance.fontVariableAxesUi
                font.pixelSize: panel.appearance.fontSizeSmall
            }

            // Context pressure: the provider's own prompt size for the last
            // request over the model's window. The figure the user asked for --
            // "% of context used" -- and the only honest way to give it, since
            // the local store has no per-request usage: the agent log does. `~`
            // marks the fallback (per-request average) so an estimate never reads
            // as a measurement. Same anatomy as an allowance row, because it is
            // the same kind of reading: a fraction of a fixed budget.
            RowLayout {
                Layout.fillWidth: true
                Layout.topMargin: panel.appearance.spacingXs
                visible: panel.contextReading
                spacing: panel.appearance.spacingSmall

                Text {
                    Layout.preferredWidth: panel.appearance.tokensLabelWidth
                    text: "ctx"
                    color: panel.appearance.textMuted
                    font.family: panel.appearance.uiFont
                    font.weight: panel.appearance.fontWeightUi
                    font.variableAxes: panel.appearance.fontVariableAxesUi
                    font.pixelSize: panel.appearance.fontSizeSmall
                    font.letterSpacing: panel.appearance.letterSpacingLabel
                    font.capitalization: Font.AllUppercase
                }

                UsageBar {
                    Layout.fillWidth: true
                    Layout.alignment: Qt.AlignVCenter
                    appearance: panel.appearance
                    percent: panel.contextPercent ? panel.session.context_pct : 0
                    fillColor: panel.contextFill
                }

                Text {
                    Layout.preferredWidth: panel.appearance.tokensPercentWidth
                    horizontalAlignment: Text.AlignRight
                    text: !panel.contextReading
                        ? ""
                        : (panel.contextPercent
                           ? (panel.session.context_estimated ? "~" : "") + panel.session.context_pct + "%"
                           : "—")
                    color: panel.contextInk
                    font.family: panel.appearance.uiFont
                    font.weight: panel.appearance.fontWeightUi
                    font.variableAxes: panel.appearance.fontVariableAxesUi
                    font.pixelSize: panel.appearance.fontSizeSmall
                    font.bold: true
                }

                Text {
                    Layout.preferredWidth: panel.appearance.tokensContextWidth
                    horizontalAlignment: Text.AlignRight
                    elide: Text.ElideRight
                    text: panel.contextReading
                        ? (panel.contextBuffer ? panel.compact(panel.session.context_used) : "—")
                          + " / " + (panel.contextCapacity ? panel.compact(panel.session.context_max) : "—")
                        : ""
                    color: panel.appearance.textMuted
                    font.family: panel.appearance.uiFont
                    font.weight: panel.appearance.fontWeightUi
                    font.variableAxes: panel.appearance.fontVariableAxesUi
                    font.pixelSize: panel.appearance.fontSizeCaption
                }
            }

            // Equal columns with an explicit width, not `Layout.fillWidth`:
            // MetricCell is a Column whose implicitWidth is 0 (its children size
            // themselves from the parent), so a RowLayout handed every pixel to
            // the last cell and left the other three at width 0 -- measured, the
            // card showed only CALLS. The column width is arithmetic instead.
            Row {
                Layout.fillWidth: true
                Layout.topMargin: panel.appearance.spacingXs
                spacing: panel.appearance.tokensMetricGap

                MetricCell {
                    width: panel.metricCellWidth
                    appearance: panel.appearance
                    label: "in"
                    value: panel.waiting || !panel.session ? "—" : panel.compact(panel.session.input)
                    muted: !panel.session
                }

                MetricCell {
                    width: panel.metricCellWidth
                    appearance: panel.appearance
                    label: "out"
                    value: panel.waiting || !panel.session ? "—" : panel.compact(panel.session.output)
                    muted: !panel.session
                }

                MetricCell {
                    width: panel.metricCellWidth
                    appearance: panel.appearance
                    label: "cached"
                    value: panel.waiting || !panel.session ? "—" : panel.compact(panel.session.cache_read + panel.session.cache_write)
                    muted: !panel.session
                }

                MetricCell {
                    width: panel.metricCellWidth
                    appearance: panel.appearance
                    label: "calls"
                    value: panel.waiting || !panel.session ? "—" : String(panel.session.calls)
                    muted: !panel.session
                }
            }
        }

        // The keys, in the footer where every other panel puts them: the panel has
        // no visible buttons, and Esc is the only way out that is not a scrim click.
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
                    key: "R"
                    label: "refresh"
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
                panel.dismissRequested();
            } else if (event.key === Qt.Key_R) {
                panel.refreshRequested();
            } else {
                return;
            }
            event.accepted = true;
        }
    }
}
