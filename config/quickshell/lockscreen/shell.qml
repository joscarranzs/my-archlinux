import Quickshell
import Quickshell.Wayland
import "services"

// Quickshell lockscreen: locks the session through ext-session-lock-v1 and
// authenticates with PAM. Launch it from hypridle's lock_cmd.
ShellRoot {
	LockContext {
		id: lockContext
		onUnlocked: {
			// Drop the readiness marker before quitting: lock-and-suspend.sh
			// waits on this file, and a stale marker would let a later lid
			// close suspend without a confirmed lock.
			Quickshell.execDetached(["/bin/sh", "-c", "rm -f \"$XDG_RUNTIME_DIR/session-locked\""])
			lock.locked = false
			Qt.quit()
		}
	}

	WlSessionLock {
		id: lock
		locked: true

		// Readiness marker for lock-and-suspend.sh, gated on the COMPOSITOR's
		// confirmation, not on QML item creation. `secure` is the ext-session-lock
		// `locked` event: the compositor has presented a locked frame on every
		// output and no unlocked content is visible. Touching the marker on
		// LockSurface.Component.onCompleted is too early — the item exists but its
		// frame is not presented, so suspend can freeze with the desktop as the
		// last presented frame and flash it on resume (hyprlock #633,
		// DankMaterialShell #2907). Removed on unlock below.
		onSecureChanged: {
			if (lock.secure)
				Quickshell.execDetached(["/bin/sh", "-c", "touch \"$XDG_RUNTIME_DIR/session-locked\""])
		}

		WlSessionLockSurface {
			LockSurface {
				anchors.fill: parent
				context: lockContext
			}
		}
	}
}
