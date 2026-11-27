#!/usr/bin/env bash
# Launch the Quickshell kanban panel on the compositor that started this script.
# Called by a click on the task icon in the bar status cluster.
#
# A second invocation *closes* the open panel: the surface behaves as a toggle, so
# clicking the icon while the panel is already up must not stack a second copy in
# front of the first.
set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/wayland-display.sh"

KANBAN_QML="${HOME}/.config/quickshell/kanban/shell.qml"
RUNTIME="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
LOCK="${RUNTIME}/quickshell-kanban-panel.lock"
PIDFILE="${RUNTIME}/quickshell-kanban-panel.pid"

# Held for the lifetime of the renderer: the fd survives the exec below, so the
# lock releases exactly when the panel dies and a later launch opens it again.
exec 9>"$LOCK"

if ! flock -n 9; then
	# Already open. Validate the pid against the command line before killing it:
	# a recycled pid must never take an unrelated process down with it.
	if [ -r "$PIDFILE" ]; then
		pid=$(<"$PIDFILE")
		if [ -r "/proc/${pid}/cmdline" ] &&
			tr '\0' ' ' <"/proc/${pid}/cmdline" | grep -qF "kanban/shell.qml"; then
			kill "$pid" 2>/dev/null || true
		fi
	fi

	exit 0
fi

if ! WAYLAND_DISPLAY=$(wait_for_wayland_display); then
	echo "kanban: no Wayland socket found" >&2
	exit 1
fi
export WAYLAND_DISPLAY

printf '%s\n' "$$" >"$PIDFILE"

exec quickshell -n -p "$KANBAN_QML"
