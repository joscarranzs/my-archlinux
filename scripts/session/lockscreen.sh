#!/usr/bin/env bash
# Launch the Quickshell lockscreen on the compositor that started this script.
# Called by hypridle (lock_cmd) and by the SUPER+CTRL+L bind.
set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/wayland-display.sh"

LOCK_QML="${HOME}/.config/quickshell/lockscreen/shell.qml"

if ! WAYLAND_DISPLAY=$(wait_for_wayland_display); then
	echo "lockscreen: no Wayland socket found" >&2
	exit 1
fi
export WAYLAND_DISPLAY

# A keybind or hypridle starts this without a terminal, so anything quickshell
# prints - including a QML load error - disappears. Keep it on disk instead.
LOG="${XDG_RUNTIME_DIR:-/tmp}/lockscreen.log"
exec >"$LOG" 2>&1

# Idempotent: hypridle and the keybind can both ask for a lock within the same
# second. One lock shell is enough; a second instance would map a duplicate
# lock surface.
#
# The guard is a held file lock, not a process-table grep. Grepping for the path
# also matched commands that merely mentioned it, and a false positive exited 0
# *without locking anything* - a silent security hole. The descriptor is
# inherited by the exec below, so the lock lives exactly as long as the lock
# surface does.
LOCK_FILE="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/quickshell-lockscreen.lock"
exec 9>"$LOCK_FILE"
if ! flock -n 9; then
	exit 0
fi

exec quickshell -n -p "$LOCK_QML"
