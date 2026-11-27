import QtQuick
import QtQuick.Layouts
import ".."
import "."

// Labelled text input for the web app form: small caps label, one hairline
// surface that turns gold on focus and red when the value is wrong.
ColumnLayout {
    id: root

    // Typed with a default instance so bindings never read through undefined.
    property Appearance appearance: Appearance {}
    property string label: ""
    property string placeholder: ""
    property string glyph: ""
    property bool invalid: false
    property alias text: input.text
    property alias textInput: input

    signal edited(string value)
    signal accepted()
    signal tabPressed()
    signal backtabPressed()

    spacing: appearance.spacingXs

    Text {
        text: root.label
        color: root.invalid ? root.appearance.danger : root.appearance.textMuted
        renderType: Text.NativeRendering
        font.family: root.appearance.uiFont
        font.weight: root.appearance.fontWeightUi
        font.variableAxes: root.appearance.fontVariableAxesUi
        font.pixelSize: root.appearance.fontSizeSmall
        font.letterSpacing: root.appearance.letterSpacingLabel
    }

    Rectangle {
        objectName: "field-surface"

        Layout.fillWidth: true
        Layout.preferredHeight: root.appearance.fieldHeight
        radius: root.appearance.shapeMedium
        color: root.appearance.surfaceContainerHigh
        border.width: root.appearance.borderWidth
        border.color: root.invalid
            ? root.appearance.danger
            : (input.activeFocus ? root.appearance.accent : root.appearance.outline)

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: root.appearance.spacingLarge
            anchors.rightMargin: root.appearance.spacingLarge
            spacing: root.appearance.spacingSmall

            MaterialIcon {
                visible: root.glyph.length > 0
                icon: root.glyph
                iconSize: root.appearance.iconSizeSm
                iconColor: input.activeFocus
                    ? root.appearance.accentInk
                    : root.appearance.textMuted
            }

            Item {
                Layout.fillWidth: true
                Layout.fillHeight: true

                TextInput {
                    id: input
                    anchors.fill: parent
                    verticalAlignment: TextInput.AlignVCenter
                    font.family: root.appearance.uiFont
                    font.weight: root.appearance.fontWeightUi
                    font.variableAxes: root.appearance.fontVariableAxesUi
                    font.pixelSize: root.appearance.fontSizeBody
                    color: root.appearance.text
                    selectionColor: root.appearance.accent
                    selectedTextColor: root.appearance.accentText
                    clip: true
                    selectByMouse: true

                    cursorDelegate: Rectangle {
                        width: root.appearance.cursorWidth
                        color: root.appearance.accent
                        opacity: root.appearance.opacityCursor
                        visible: input.text.length > 0
                    }

                    onTextChanged: root.edited(text)
                    onAccepted: root.accepted()

                    // Tab moves between fields; the form decides where to.
                    Keys.onPressed: (event) => {
                        if (event.key === Qt.Key_Tab) {
                            root.tabPressed();
                            event.accepted = true;
                        } else if (event.key === Qt.Key_Backtab) {
                            root.backtabPressed();
                            event.accepted = true;
                        }
                    }
                }

                Text {
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width
                    text: root.placeholder
                    visible: input.text.length === 0
                    elide: Text.ElideRight
                    color: root.appearance.textMuted
                    opacity: root.appearance.opacityPlaceholder
                    renderType: Text.NativeRendering
                    font.family: root.appearance.uiFont
                    font.weight: root.appearance.fontWeightUi
                    font.variableAxes: root.appearance.fontVariableAxesUi
                    font.pixelSize: root.appearance.fontSizeCaption
                    font.letterSpacing: root.appearance.letterSpacingCaption
                }
            }
        }
    }

    function forceFocus() {
        input.forceActiveFocus();
    }
}
