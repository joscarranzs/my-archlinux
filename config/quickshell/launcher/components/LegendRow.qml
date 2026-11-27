import QtQuick
import QtQuick.Layouts
import ".."

// One entry in a plaque's legend: a sign plus its action, the way a map reads.
// The sign is either a key (drawn as a cap, because a key is a key) or a glyph
// (a pointer gesture has no key to show). Labels use the system's annotation
// voice - uppercase, tracked - and hierarchy is a step of ink, never opacity:
// the sign carries the brightest ink, the label the secondary one.
//
// Generated into every plaque that shows keys. It reads the panel's Appearance,
// which is why it is a file per panel and not a shared one, and it is the only
// cap recipe on the desktop: the kanban's footer, the launcher's and the five
// other panels' all render through it. A second inline cap is how two footers
// drift into looking like different products.
RowLayout {
    id: legend

    property Appearance appearance: Appearance {}
    property string key: ""
    property string glyph: ""
    property string label: ""
    // Key hints take the annotation voice (uppercase, tracked). Instructions
    // that happen to sit beside them stay sentence case: a whole sentence in
    // small caps reads as an inscription and shouts.
    property bool tracked: false

    spacing: legend.appearance.spacingSmall

    Rectangle {
        visible: legend.key !== ""
        Layout.preferredWidth: Math.max(legend.appearance.keycapHeight,
                                     cap.implicitWidth + legend.appearance.spacingSmall)
        Layout.preferredHeight: legend.appearance.keycapHeight
        Layout.alignment: Qt.AlignVCenter
        color: "transparent"
        radius: legend.appearance.shapeSmall
        border.color: legend.appearance.outline
        border.width: legend.appearance.hairline

        Text {
            id: cap

            anchors.centerIn: parent
            text: legend.key
            color: legend.appearance.text
            font.family: legend.appearance.uiFont
            font.weight: legend.appearance.fontWeightUi
            font.variableAxes: legend.appearance.fontVariableAxesUi
            font.pixelSize: legend.appearance.fontSizeSmall
            font.letterSpacing: legend.appearance.letterSpacingLabel
        }
    }

    Text {
        visible: legend.glyph !== ""
        Layout.preferredWidth: legend.appearance.keycapHeight
        Layout.alignment: Qt.AlignVCenter
        horizontalAlignment: Text.AlignHCenter
        text: legend.glyph
        color: legend.appearance.text
        font.family: legend.appearance.iconFont
        font.pixelSize: legend.appearance.fontSizeBody
    }

    Text {
        Layout.alignment: Qt.AlignVCenter
        text: legend.label
        color: legend.appearance.textMuted
        font.family: legend.appearance.uiFont
        font.weight: legend.appearance.fontWeightUi
        font.variableAxes: legend.appearance.fontVariableAxesUi
        font.pixelSize: legend.appearance.fontSizeSmall
        font.letterSpacing: legend.tracked ? legend.appearance.letterSpacingCaption : 0.2
        font.capitalization: legend.tracked ? Font.AllUppercase : Font.MixedCase
    }
}
