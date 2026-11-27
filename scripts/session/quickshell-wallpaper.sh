#!/usr/bin/env bash
# Draw the desktop wallpaper with Quickshell on the compositor that started it.
#
# Compositors run exec commands before exporting WAYLAND_DISPLAY, so resolve the
# socket from the Hyprland instance file, then restart the renderer if it crashes.

set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/wayland-display.sh"

SHELL_QML="${HOME}/.config/quickshell/wallpaper/shell.qml"
LOCK="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/quickshell-wallpaper.lock"
PIDFILE="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/quickshell-wallpaper.pid"

# One renderer per session. Hyprland runs this from an exec-once, and exec-once
# runs again on every `hyprctl reload`, so without a lock a reload stacked a
# second wallpaper surface on top of the first. The lock is held for the life of
# the wrapper, so the second copy exits instead of drawing.
exec 9>"${LOCK}"
if ! flock -n 9; then
	exit 0
fi

if ! WAYLAND_DISPLAY=$(wait_for_wayland_display); then
	echo "wallpaper: no Wayland socket found" >&2
	exit 1
fi
export WAYLAND_DISPLAY

# Publish the renderer PID: the switcher can only make it reload with SIGKILL
# (every other signal is honoured as "session ending"), and reading this file
# beats grepping the process table, which also matched commands that merely
# mention the path. Removed on exit so a stale PID is never read.
trap 'rm -f "$PIDFILE"' EXIT

while :; do
	# `set -e` would abort the wrapper before `status=$?` runs, so a crashing
	# renderer killed the wallpaper for the rest of the session instead of being
	# respawned. Capture the code without tripping errexit.
	status=0
	quickshell -n -p "$SHELL_QML" &
	renderer=$!
	printf '%s\n' "$renderer" >"$PIDFILE"
	wait "$renderer" || status=$?
	# 0 = asked to quit; 129/130/143 = SIGHUP/SIGINT/SIGTERM, honour them.
	case $status in
		0 | 129 | 130 | 143) exit "$status" ;;
	esac
	# Anything else (134 SIGABRT, 137 SIGKILL, 139 SIGSEGV, ...) is a crash: retry.
	sleep 1
done
