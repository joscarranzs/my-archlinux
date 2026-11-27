#!/usr/bin/env bash
# The SDDM greeter, offscreen: the card it draws, the attempt it sends and the
# state it must never get stuck in.
#
#   stub.py         copies the generated theme and renames SDDM's four context
#                   objects to stubs; the surface itself is not touched.
#   greeter-test.qml loads it in a plain window and asserts against the theme's
#                   own tokens.
#
# It never runs `sddm-greeter --test-mode`: that opens a real fullscreen window
# that takes the keyboard of a live session. This suite needs no greeter process
# and no PAM, so nothing here can lock anybody out.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(git -C "$HERE" rev-parse --show-toplevel)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

if ! theme="$(python3 "$HERE/stub.py" "$TMP/theme")"; then
	echo "harness: could not build the theme copy" >&2
	exit 1
fi
URL="$(dirname "$theme")"
SHOT="${1:-}"

sed -e "s|@URL@|${URL}|g" -e "s|@PNG@|${SHOT}|g" \
	"$HERE/greeter-test.qml" >"$TMP/greeter.qml"

out="$(cd "$TMP" && QT_QPA_PLATFORM=offscreen timeout 90 quickshell -p greeter.qml 2>&1 |
	sed 's/\x1b\[[0-9;]*m//g')"

echo "== sddm greeter"
echo "$out" | grep -E 'RESULT|PASS|FAIL|ERROR|is not a type|Cannot assign|ReferenceError|Failed to load|TypeError|Unable to assign' ||
	echo "   no result line - the harness died"

status=0
echo "$out" | grep -q 'RESULT pass=[0-9]* fail=0' || status=1
echo "$out" | grep -qE 'ERROR|is not a type|Cannot assign|ReferenceError|Failed to load|TypeError' && status=1

# The attempt has to name the session the greeter searched for, not the last one
# SDDM remembered: plain Hyprland is at index 2 of the stub's list, behind the
# uwsm-managed entry and behind Plasma.
if ! echo "$out" | grep -q 'ATTEMPT user=joscarranzs password=hunter2 sessionIndex=2'; then
	echo "   FAIL the attempt did not reach the hyprland session" >&2
	status=1
fi

if [[ -n $SHOT ]]; then
	if echo "$out" | grep -q 'GRAB .* true'; then
		echo "   rendered to ${SHOT}"
	else
		echo "   note: offscreen grab unavailable, no image written" >&2
	fi
fi

exit "$status"
