#!/usr/bin/env bash
# Every plaque entrance, one run per panel.
#
#   entrance-test.qml   the fade and the lift, asserted offscreen: the offset the
#                       plaque starts at, the deceleration, the landing, and the
#                       rendered edge (mapToItem, not just the token).
#
# The launcher's plaque lives inside its shell.qml, so it cannot be instantiated
# without a PanelWindow backend; it is checked live instead (open it and read the
# panel log). Every other plaque has a component of its own.
#
# The harness imports the panel through the @URL@ placeholder: Quickshell only
# synthesises a qmldir for directories inside the config folder, so the absolute
# URL is rendered into a temp copy at run time.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(git -C "$HERE" rev-parse --show-toplevel)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# panel directory : component name
PANELS=(
	"tokens:TokensPanel"
	"brightness:BrightnessPanel"
	"calendar:CalendarPanel"
	"kanban:KanbanPanel"
	"battery:BatteryPanel"
	"wifi:WifiPanel"
	"volume:VolumePanel"
	"monitor:MonitorPanel"
)

status=0

for entry in "${PANELS[@]}"; do
	dir="${entry%%:*}"
	component="${entry##*:}"
	url="file://${REPO}/config/quickshell/${dir}"
	sed -e "s|@URL@|${url}|g" -e "s|@PANEL@|${component}|g" \
		"$HERE/entrance-test.qml" > "$TMP/${dir}.qml"
	out="$(cd "$TMP" && QT_QPA_PLATFORM=offscreen timeout 60 quickshell -p "${dir}.qml" 2>&1 |
		sed 's/\x1b\[[0-9;]*m//g')"
	echo "== ${dir}"
	echo "$out" | grep -E 'RESULT pass=|FAIL|TIME OUT|ERROR' || echo "   no result line - the harness died"
	if ! echo "$out" | grep -q 'RESULT pass=[0-9]* fail=0' ||
		echo "$out" | grep -qE 'ERROR|is not a type|Cannot assign|ReferenceError|Failed to load'; then
		status=1
	fi
done

exit "$status"
