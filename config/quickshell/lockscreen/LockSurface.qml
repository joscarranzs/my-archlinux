import QtQuick
import QtQuick.Layouts
import "components"
import "services"
import "config"

// One lock surface per screen: backdrop, clock and unlock card.
Rectangle {
	id: root
	required property LockContext context

	readonly property LockAppearance appearance: LockAppearance {}

	color: appearance.surface

	Image {
		anchors.fill: parent
		source: root.appearance.backdropImage
		fillMode: Image.PreserveAspectCrop
		opacity: root.appearance.opacityBackdrop
		visible: status === Image.Ready
	}

	Rectangle {
		anchors.fill: parent
		color: root.appearance.surface
		opacity: root.appearance.opacityOverlay
	}

	ColumnLayout {
		anchors.centerIn: parent
		spacing: root.appearance.spacingLarge

		ClockLabel {
			Layout.alignment: Qt.AlignHCenter
			appearance: root.appearance
		}

		LockCard {
			Layout.alignment: Qt.AlignHCenter
			appearance: root.appearance
			context: root.context
		}
	}
}
