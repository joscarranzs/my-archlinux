import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import "../services"
import "../config"

// Elevated unlock card: user row, labelled password field, a status line that
// only speaks when there is something to say (it still reserves its slot, so
// nothing jumps when an attempt fails) and the action button.
// The card carries one accent at a time: gold on focus, red on error.
Rectangle {
	id: root
	property LockAppearance appearance: LockAppearance {}
	required property LockContext context

	// Show the failure line for a few seconds after a failed attempt.
	property bool showFailureHint: false

	// Track Caps Lock state via the main keyboard reported by Hyprland.
	property bool capsLockOn: false

	// One line, one source of truth. Empty means "nothing to report": a lock
	// screen that repeats LOCKED is noise, not information.
	readonly property string statusText: context.unlockInProgress
		? "VERIFYING…"
		: (root.showFailureHint
			? "INCORRECT PASSWORD"
			: (root.capsLockOn ? "CAPS LOCK IS ON" : ""))
	readonly property bool statusAlert: root.showFailureHint || root.capsLockOn

	// Caps Lock is read from the compositor, but only when the answer can have
	// changed: when the card appears, after a keystroke and after a failed
	// attempt. The old version asked every 500 ms for the whole time the screen
	// was locked — measured at two spawns a second, each one bash + python3 +
	// hyprctl, to answer a question nobody was asking.
	function checkCapsLock() {
		if (!capsLockProcess.running)
			capsLockProcess.running = true
	}

	Process {
		id: capsLockProcess
		command: [Quickshell.env("HOME") + "/.scripts/session/capslock-state.sh"]
		stdout: StdioCollector {}
		onExited: {
			var value = stdout.text.trim()
			root.capsLockOn = (value === "1")
		}
	}

	// Collapses a burst of keystrokes into one spawn.
	Timer {
		id: capsLockDebounce
		interval: 200
		onTriggered: root.checkCapsLock()
	}

	Component.onCompleted: root.checkCapsLock()

	Timer {
		id: focusRetry
		interval: 120
		repeat: true
		property int remaining: 0
		onTriggered: {
			if (passwordInput.activeFocus || root.context.unlockInProgress) {
				stop()
				return
			}
			passwordInput.forceActiveFocus()
			remaining -= 1
			if (remaining <= 0)
				stop()
		}
	}

	implicitWidth: appearance.cardWidth
	implicitHeight: content.implicitHeight + appearance.contentPad * 2
	radius: appearance.shapeExtraLarge
	color: appearance.surfaceContainer
	// Edge: gilt (accent.tertiary) at look.borders.width — the plaque's frame.
	border.color: appearance.gilt
	border.width: root.appearance.borderWidth

	Connections {
		target: root.context

		function onShowFailureChanged() {
			if (!root.context.showFailure) return
			root.showFailureHint = true
			failureTimer.restart()
			focusRetry.remaining = 20
			focusRetry.restart()
			// A rejected password with Caps Lock on is the first thing to
			// rule out, so the failure is one of the moments worth asking.
			root.checkCapsLock()
		}

		function onUnlockInProgressChanged() {
			if (!root.context.unlockInProgress) {
				focusRetry.remaining = 20
				focusRetry.restart()
			}
		}
	}

	Timer {
		id: failureTimer
		interval: root.appearance.failureHintMs
		onTriggered: root.showFailureHint = false
	}

	ColumnLayout {
		id: content
		anchors.fill: parent
		anchors.margins: appearance.contentPad
		spacing: appearance.spacingSmall

		// --- who is unlocking
		RowLayout {
			Layout.fillWidth: true
			spacing: appearance.spacingSmall

			MaterialIcon {
				icon: "account_circle"
				iconColor: root.appearance.textMuted
				iconSize: root.appearance.iconSizeLg
			}

			Label {
				Layout.fillWidth: true
				text: Quickshell.env("USER")
				elide: Text.ElideRight
				renderType: Text.NativeRendering
				font.family: root.appearance.uiFont
				font.weight: root.appearance.fontWeightUi
				font.variableAxes: root.appearance.fontVariableAxesUi
				font.pixelSize: root.appearance.fontSizeTitle
				color: root.appearance.text
			}
		}

		// --- password field
		ColumnLayout {
			Layout.fillWidth: true
			spacing: root.appearance.spacingSmall

			// Persistent label: the field keeps saying what it wants after the
			// first keystroke, instead of a placeholder that vanishes.
			// One ink step, no opacity: textMuted at 55 % composited to 3.43:1
			// over the card, under the 4.5 target; solid textMuted is 7.66:1,
			// which is what every panel's header label already does.
			Text {
				objectName: "passwordLabel"

				text: "PASSWORD"
				color: root.appearance.textMuted
				renderType: Text.NativeRendering
				font.family: root.appearance.uiFont
				font.weight: root.appearance.fontWeightUi
				font.variableAxes: root.appearance.fontVariableAxesUi
				font.pixelSize: root.appearance.fontSizeSmall
				font.letterSpacing: root.appearance.letterSpacingLabel
			}

			Rectangle {
				id: passwordField
				Layout.fillWidth: true
				Layout.preferredHeight: root.appearance.fieldHeightTall
				radius: root.appearance.shapeMedium
				color: root.appearance.surface
				border.color: root.showFailureHint
					? root.appearance.danger
					: (passwordInput.activeFocus ? root.appearance.accent : root.appearance.outline)
				border.width: root.appearance.borderWidth

				RowLayout {
					anchors.fill: parent
					anchors.leftMargin: root.appearance.spacingMedium
					anchors.rightMargin: root.appearance.spacingMedium
					spacing: root.appearance.spacingSmall

					MaterialIcon {
						icon: "lock"
						iconColor: passwordInput.activeFocus
							? root.appearance.accentInk
							: root.appearance.textMuted
						iconSize: root.appearance.iconSizeMd
					}

					Item {
						Layout.fillWidth: true
						Layout.fillHeight: true

						TextInput {
							id: passwordInput
							anchors.fill: parent
							verticalAlignment: TextInput.AlignVCenter
							focus: true
							enabled: !root.context.unlockInProgress
							echoMode: TextInput.Password
							inputMethodHints: Qt.ImhSensitiveData
							renderType: Text.NativeRendering
							font.family: root.appearance.textFont
							font.weight: root.appearance.fontWeightText
							font.pixelSize: root.appearance.fontSizeBody
							font.letterSpacing: root.appearance.letterSpacingPassword
							color: root.appearance.text
							selectionColor: root.appearance.accent
							selectedTextColor: root.appearance.accentText

							// Block cursor. Visible while the field is focused
							// even when empty, otherwise a focused field is
							// indistinguishable from an idle one.
							cursorDelegate: Component {
								Rectangle {
									width: root.appearance.cursorWidth
									height: root.appearance.cursorHeight
									color: root.appearance.accent
									visible: passwordInput.activeFocus
								}
							}

							onTextChanged: {
								root.context.currentText = text
								if (text.length > 0) {
									// A keystroke is the only moment Caps Lock
									// can have changed, so it is the only
									// moment worth asking about.
									capsLockDebounce.restart()
									root.showFailureHint = false
									failureTimer.stop()
								}
							}
							onAccepted: root.context.tryUnlock()

							Component.onCompleted: {
								forceActiveFocus()
								focusRetry.remaining = 50
								focusRetry.restart()
							}

							Keys.onPressed: function(event) {
								if (event.key === Qt.Key_Escape || (event.modifiers & Qt.ControlModifier && event.key === Qt.Key_U)) {
									root.context.currentText = ""
									passwordInput.text = ""
									event.accepted = true
								}
							}

							Connections {
								target: root.context
								function onCurrentTextChanged() { passwordInput.text = root.context.currentText }
							}
						}
					}
				}
			}
		}

		// --- status line: fixed slot, never reflow
		Item {
			Layout.fillWidth: true
			Layout.preferredHeight: root.appearance.statusHeight

			// The slot is reserved; the ink is not dimmed. A status that has
			// nothing to say is an empty string, so opacity bought nothing here
			// beyond making VERIFYING… dimmer than the rest of the card.
			Text {
				objectName: "statusText"

				anchors.left: parent.left
				anchors.verticalCenter: parent.verticalCenter
				text: root.statusText
				color: root.statusAlert ? root.appearance.danger : root.appearance.textMuted
				renderType: Text.NativeRendering
				font.family: root.appearance.uiFont
				font.weight: root.appearance.fontWeightUi
				font.variableAxes: root.appearance.fontVariableAxesUi
				font.pixelSize: root.appearance.fontSizeSmall
				font.letterSpacing: root.appearance.letterSpacingCaption
			}
		}

		// --- action
		Rectangle {
			id: unlockButton
			objectName: "unlockButton"

			Layout.fillWidth: true
			Layout.topMargin: root.appearance.spacingSmall
			Layout.preferredHeight: root.appearance.buttonHeightLarge
			radius: root.appearance.shapeFull
			// Resting fill steps one rung up with a gilt edge, and press steps
			// it back down to pressFill: the recipe every plaque uses. The
			// resting fill is already raisedHigh, so hover takes the rung
			// above it (hoverFillHigh), which is what ChoiceField does for the
			// same reason. The accent-filled state cannot step a rung at all,
			// so it takes a state layer of accentText instead, the way the
			// monitor's APPLY button does. Border width is constant now:
			// arming the button no longer shifts its contents by the hairline
			// it used to drop.
			color: unlockButton.armed
				? root.appearance.accent
				: (unlockMouse.pressed ? root.appearance.pressFill
					: (unlockHover.hovered ? root.appearance.hoverFillHigh
						: root.appearance.surfaceContainerHigh))
			border.width: root.appearance.borderWidth
			border.color: unlockButton.armed
				? root.appearance.accent
				: (unlockHover.hovered || unlockMouse.pressed
					? root.appearance.gilt : root.appearance.outline)

			readonly property bool armed: !root.context.unlockInProgress
				&& root.context.currentText !== ""

			Behavior on color {
				ColorAnimation {
					duration: root.appearance.motionControlDuration
					easing.type: root.appearance.motionControlEasing
				}
			}

			Behavior on border.color {
				ColorAnimation {
					duration: root.appearance.motionControlDuration
					easing.type: root.appearance.motionControlEasing
				}
			}

			// State layer: only the accent fill needs one, because it has no
			// rung above it on the tonal ladder.
			Rectangle {
				anchors.fill: parent
				radius: parent.radius
				color: root.appearance.accentText
				opacity: unlockButton.armed && unlockHover.hovered
					? root.appearance.opacityStateLayer : 0

				Behavior on opacity {
					NumberAnimation {
						duration: root.appearance.motionControlDuration
						easing.type: root.appearance.motionControlEasing
					}
				}
			}

			RowLayout {
				anchors.centerIn: parent
				spacing: root.appearance.spacingSmall

				MaterialIcon {
					icon: "arrow_forward"
					iconColor: unlockButton.armed
						? root.appearance.accentText
						: root.appearance.textMuted
					iconSize: root.appearance.iconSizeMd
				}

				Label {
					text: root.context.unlockInProgress ? "VERIFYING…" : "UNLOCK"
					renderType: Text.NativeRendering
					font.family: root.appearance.uiFont
					font.weight: root.appearance.fontWeightUi
					font.variableAxes: root.appearance.fontVariableAxesUi
					font.pixelSize: root.appearance.fontSizeBody
					font.letterSpacing: root.appearance.letterSpacingCaption
					color: unlockButton.armed
						? root.appearance.accentText
						: root.appearance.textMuted
				}
			}

			// Hover comes from a handler, not the MouseArea: a disabled
			// MouseArea receives no mouse events at all, so an inert button
			// would have no hover state either, and it still has one.
			HoverHandler {
				id: unlockHover
			}

			MouseArea {
				id: unlockMouse
				anchors.fill: parent
				enabled: unlockButton.armed
				onClicked: root.context.tryUnlock()
				cursorShape: unlockButton.armed ? Qt.PointingHandCursor : Qt.ArrowCursor
			}
		}
	}
}
