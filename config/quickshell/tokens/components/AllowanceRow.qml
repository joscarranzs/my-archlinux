import QtQuick
import QtQuick.Layouts
import ".."
import "../usage-rule.js" as UsageRule

// One allowance window of the OpenCode Go plan: its name, the consumed percent
// as a bar, the number, and when it resets.
//
// The bar is the only place a warning colour is allowed to appear, and it walks
// the system's own ladder (usage-rule.js): the action accent while the window is
// filling, gilt at the alert threshold, danger at the critical one -- so a glance
// says which window is the one to watch. Gold is not decoration here, it is the
// warning step.
Item {
    id: root

    property Appearance appearance: Appearance {}
    property string label: ""
    property real percent: 0
    property string resetsAt: ""
    // A stale window keeps its last numbers on screen, but not their state
    // colours: a bar in the success accent says "confirmed", and this one is not.
    property bool stale: false

    readonly property bool critical: percent >= appearance.tokensCriticalThreshold
    readonly property bool alert: percent >= appearance.tokensAlertThreshold
    readonly property color barColor: UsageRule.fill(appearance, percent, stale)
    readonly property color percentColor: UsageRule.ink(appearance, percent, stale)

    implicitHeight: row.implicitHeight

    // Countdown, never a date: "in 2d 3h" is the number the user acts on, and an
    // absolute timestamp for a window that resets in 4h reads as noise.
    function resetIn(iso) {
        if (!iso)
            return "";
        var target = Date.parse(iso);
        if (isNaN(target))
            return "";
        var ms = target - Date.now();
        if (ms <= 0)
            return "now";
        var minutes = Math.floor(ms / 60000);
        if (minutes < 60)
            return "in " + minutes + "m";
        var hours = Math.floor(minutes / 60);
        if (hours < 24)
            return "in " + hours + "h " + (minutes % 60) + "m";
        return "in " + Math.floor(hours / 24) + "d " + (hours % 24) + "h";
    }

    RowLayout {
        id: row

        anchors.left: parent.left
        anchors.right: parent.right
        spacing: root.appearance.spacingSmall

        Text {
            Layout.preferredWidth: root.appearance.tokensLabelWidth
            text: root.label
            color: root.appearance.textMuted
            elide: Text.ElideRight
            font.family: root.appearance.uiFont
            font.weight: root.appearance.fontWeightUi
            font.variableAxes: root.appearance.fontVariableAxesUi
            font.pixelSize: root.appearance.fontSizeSmall
            font.letterSpacing: root.appearance.letterSpacingLabel
            font.capitalization: Font.AllUppercase
        }

        UsageBar {
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignVCenter
            appearance: root.appearance
            percent: root.percent
            fillColor: root.barColor
        }

        Text {
            Layout.preferredWidth: root.appearance.tokensPercentWidth
            horizontalAlignment: Text.AlignRight
            text: Math.round(root.percent) + "%"
            color: root.percentColor
            font.family: root.appearance.uiFont
            font.weight: root.appearance.fontWeightUi
            font.variableAxes: root.appearance.fontVariableAxesUi
            font.pixelSize: root.appearance.fontSizeSmall
            font.bold: true
        }

        Text {
            Layout.preferredWidth: root.appearance.tokensResetWidth
            horizontalAlignment: Text.AlignRight
            text: root.resetIn(root.resetsAt)
            color: root.appearance.textMuted
            elide: Text.ElideRight
            font.family: root.appearance.uiFont
            font.weight: root.appearance.fontWeightUi
            font.variableAxes: root.appearance.fontVariableAxesUi
            font.pixelSize: root.appearance.fontSizeCaption
        }
    }
}
