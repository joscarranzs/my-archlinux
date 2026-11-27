#!/usr/bin/env bash
# Launch the Quickshell volume panel on the compositor that started this script.
# Called by a click on the volume glyph in the bar.
#
# A second invocation closes the open panel, so clicking the glyph twice does not
# stack two copies. Same contract as calendar.sh.
set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/wayland-display.sh"

VOLUME_QML="${HOME}/.config/quickshell/volume/shell.qml"
RUNTIME="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
LOCK="${RUNTIME}/quickshell-volume.lock"
PIDFILE="${RUNTIME}/quickshell-volume.pid"

# Held for the lifetime of the renderer: the fd survives the exec below, so the
# lock releases exactly when the panel dies.
exec 9>"$LOCK"

if ! flock -n 9; then
	# Already open: this invocation closes it. Validate the pid first, so a
	# recycled pid cannot take an unrelated process down.
	if [ -r "$PIDFILE" ]; then
		pid=$(<"$PIDFILE")
		if [ -r "/proc/${pid}/cmdline" ] &&
			tr '\0' ' ' <"/proc/${pid}/cmdline" | grep -qF "volume/shell.qml"; then
			kill "$pid" 2>/dev/null || true
		fi
	fi
	exit 0
fi

if ! WAYLAND_DISPLAY=$(wait_for_wayland_display); then
	echo "volume: no Wayland socket found" >&2
	exit 1
fi
export WAYLAND_DISPLAY

printf '%s\n' "$$" >"$PIDFILE"

exec quickshell -n -p "$VOLUME_QML"
