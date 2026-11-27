#!/usr/bin/env bash
# Offscreen captures of every surface built from PanelCard.
#
#   bash scripts/session/tests/panels/capture-all.sh [output-dir]
#
# The harness substitutes the panel's component at run time for the same reason
# the entrance suite does: Quickshell only synthesises a qmldir for directories
# inside the config tree. Each grab is saved as <output-dir>/<panel>.png.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(git -C "$HERE" rev-parse --show-toplevel)"
OUT="${1:-/home/joscarranzs/.hermes/cache/scratch/cards}"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$OUT"

# Every panel that actually instantiates PanelCard in its own component.
PANELS=(
	"tokens:TokensPanel"
	"brightness:BrightnessPanel"
	"battery:BatteryPanel"
	"monitor:MonitorPanel"
	"volume:VolumePanel"
	"wifi:WifiPanel"
	"webapp:WebAppForm"
	"bar:Bar"
)

status=0
for entry in "${PANELS[@]}"; do
	dir="${entry%%:*}"
	component="${entry##*:}"
	url="file://${REPO}/config/quickshell/${dir}"
	image="${OUT}/${dir}.png"
	# The bar takes its strip size from the shell; alone it is 0x0. Every other
	# panel sizes itself, so the harness must not impose a width on it.
	size=""
	if [ "$dir" = "bar" ]; then
		size="width: 1280; height: 28"
	fi
	sed -e "s|@URL@|${url}|g" -e "s|@PANEL@|${component}|g" \
		-e "s|@OUT@|${image}|g" -e "s|@SIZE@|${size}|g" \
		"$HERE/capture-test.qml" >"$TMP/${dir}.qml"
	out="$(cd "$TMP" && QT_QPA_PLATFORM=offscreen timeout 30 quickshell -p "${dir}.qml" 2>&1)"
	# Offscreen panels warn about missing live services (network list, monitor
	# outputs). Those are WARN lines, not load failures: only a hard error or a
	# missing image invalidates the capture.
	if ! echo "$out" | grep -q 'RESULT saved=' ||
		echo "$out" | grep -v 'WARN' | grep -qE 'ERROR|is not a type|ReferenceError|Failed to load|TypeError'; then
		status=1
	fi
	printf '%-12s %s\n' "$dir" "$(echo "$out" | grep -E 'RESULT saved=|ERROR|TypeError' | tail -1)"
	if [ ! -s "$image" ]; then
		status=1
		echo "   missing image: $image"
	fi
done

exit "$status"
