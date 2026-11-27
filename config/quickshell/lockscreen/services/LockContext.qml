import QtQuick
import Quickshell
import Quickshell.Services.Pam

Scope {
	id: root
	signal unlocked()
	signal failed()

	property string currentText: ""
	property bool unlockInProgress: false
	property bool showFailure: false

	onCurrentTextChanged: showFailure = false

	function tryUnlock() {
		if (currentText === "") return;
		root.unlockInProgress = true
		// start() answers false when the PAM handle or the config directory is
		// not usable. Ignoring the answer left the card disabled and reading
		// VERIFYING… with no way back, because the field is gated on
		// unlockInProgress and nothing else would ever clear it.
		if (!pam.start())
			root.abandon("start() refused")
	}

	// One way out of a failed attempt, whether PAM answered "no", answered
	// nothing, or never started: clear the field, hand the card its failure
	// state, and drop the in-progress flag that disables everything.
	function abandon(why) {
		console.warn("lockscreen: unlock attempt ended early (" + why + ")")
		root.unlockInProgress = false
		root.currentText = ""
		root.showFailure = true
		root.failed()
	}

	PamContext {
		id: pam
		configDirectory: Quickshell.env("HOME") + "/.config/quickshell/lockscreen/pam"
		config: "password.conf"

		onPamMessage: {
			if (this.responseRequired) {
				this.respond(root.currentText)
			}
		}

		// The other way a PamContext can end: a protocol or PAM-level error,
		// which never reaches onCompleted.
		onError: (error) => root.abandon("pam error " + error)

		onCompleted: result => {
			if (result == PamResult.Success) {
				root.unlocked()
				root.unlockInProgress = false
			} else {
				root.currentText = ""
				root.showFailure = true
				root.failed()
				root.unlockInProgress = false
			}
		}
	}
}
