#!/usr/bin/env bash
# Launch the Quickshell web app panel on the compositor that started this script.
# Called by the SUPER+SHIFT+W bind in Hyprland.
set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/wayland-display.sh"

PANEL_QML="${HOME}/.config/quickshell/webapp/shell.qml"

if ! WAYLAND_DISPLAY=$(wait_for_wayland_display); then
	echo "webapp: no Wayland socket found" >&2
	exit 1
fi
export WAYLAND_DISPLAY

exec quickshell -n -p "$PANEL_QML"
