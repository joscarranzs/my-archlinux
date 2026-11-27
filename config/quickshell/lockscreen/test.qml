import QtQuick
import Quickshell
import "services"

// Shows the lock UI in a floating window so it can be checked without locking.
ShellRoot {
	LockContext {
		id: lockContext
		onUnlocked: Qt.quit()
	}

	FloatingWindow {
		// Same logical size as the laptop panel so the preview is representative.
		implicitWidth: 1280
		implicitHeight: 720

		LockSurface {
			anchors.fill: parent
			context: lockContext
		}
	}

	Connections {
		target: Quickshell
		function onLastWindowClosed() { Qt.quit() }
	}
}
