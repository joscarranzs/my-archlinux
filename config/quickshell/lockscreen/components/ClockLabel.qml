import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../config"

ColumnLayout {
	id: root
	property LockAppearance appearance: LockAppearance {}
	property date currentDate: new Date()

	spacing: root.appearance.spacingSmall
	Layout.alignment: Qt.AlignHCenter

	Timer {
		running: true
		repeat: true
		interval: 1000
		onTriggered: root.currentDate = new Date()
	}

	// Museum-plaque label: the UI face, ink, letterspaced, all-caps date.
	Label {
		text: Qt.formatDate(root.currentDate, "dddd, MMMM d").toUpperCase()
		renderType: Text.NativeRendering
		font.family: root.appearance.uiFont
		font.weight: root.appearance.fontWeightUi
		font.variableAxes: root.appearance.fontVariableAxesUi
		font.pixelSize: root.appearance.fontSizeCaption
		font.letterSpacing: root.appearance.letterSpacingLabel
		color: root.appearance.accentInk
		Layout.alignment: Qt.AlignHCenter
	}

	// The time itself: the same face as everything else, at clock size and 600.
	// It used to be Fraunces: one family per surface, and the size carries the
	// hierarchy.
	Label {
		text: root.currentDate.getHours().toString().padStart(2, "0")
			+ ":" + root.currentDate.getMinutes().toString().padStart(2, "0")
		renderType: Text.NativeRendering
		font.family: root.appearance.displayFont
		font.weight: root.appearance.fontWeightDisplay
		font.variableAxes: root.appearance.fontVariableAxesDisplay
		font.pixelSize: root.appearance.fontSizeClock
		color: root.appearance.text
		Layout.alignment: Qt.AlignHCenter
	}

	// Gold plaque rule: the single accent that ties clock and card together.
	Rectangle {
		Layout.alignment: Qt.AlignHCenter
		Layout.preferredWidth: root.appearance.ruleWidth
		Layout.preferredHeight: root.appearance.ruleThickness
		color: root.appearance.gilt
	}
}
