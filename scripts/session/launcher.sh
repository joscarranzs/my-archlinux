#!/usr/bin/env bash
# Launch the Quickshell app launcher on the compositor that started this script.
# Called by the SUPER+SPACE bind in Hyprland.
set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/wayland-display.sh"

LAUNCHER_QML="${HOME}/.config/quickshell/launcher/shell.qml"

if ! WAYLAND_DISPLAY=$(wait_for_wayland_display); then
	echo "launcher: no Wayland socket found" >&2
	exit 1
fi
export WAYLAND_DISPLAY

exec quickshell -n -p "$LAUNCHER_QML"
