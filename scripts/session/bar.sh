#!/usr/bin/env bash
# Draw the status bar with Quickshell on the compositor that started it, and keep
# it alive: this is the strip the whole session reads from, so a renderer crash
# must not leave the desktop headless until the next login.
#
# Safe to run twice: the lock is held for the life of the wrapper, so a second
# invocation (the session autostart plus a manual run, say) exits immediately
# instead of stacking two bars.
set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/wayland-display.sh"

BAR_QML="${HOME}/.config/quickshell/bar/shell.qml"
LOCK="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/quickshell-bar.lock"

# A pgrep guard cannot work here: the shell that launches this script carries
# "quickshell" in its own command line, matches itself, and the bar exits before
# drawing. The lock is held for the life of the process instead.
exec 9>"${LOCK}"
if ! flock -n 9; then
	exit 0
fi

# Compositors run exec commands before exporting WAYLAND_DISPLAY: resolve the
# socket from the Hyprland instance file.
if ! WAYLAND_DISPLAY=$(wait_for_wayland_display); then
	echo "bar: no Wayland socket found" >&2
	exit 1
fi
export WAYLAND_DISPLAY

while :; do
	# `set -e` would abort the wrapper before `status=$?` runs, so a crashing
	# renderer killed the bar for the rest of the session instead of being
	# respawned. Capture the code without tripping errexit.
	status=0
	quickshell -n -p "$BAR_QML" || status=$?
	# 0 = asked to quit; 129/130/143 = SIGHUP/SIGINT/SIGTERM, honour them.
	case $status in
		0 | 129 | 130 | 143) exit "$status" ;;
	esac
	# Anything else (134 SIGABRT, 137 SIGKILL, 139 SIGSEGV, ...) is a crash: retry.
	sleep 1
done
