#!/usr/bin/env bash
# The unlock card, offscreen: its state machine, its ink, and the one thing about
# it that must never become a poll again.
#
#   card-test.qml   the whole card with the real LockContext, driven through the
#                   context's own properties: the ink on the two labels, the
#                   armed/unarmed fills of the button, and the three status lines.
#   spawn-probe.py  counts capslock-state.sh spawns while the card sits idle.
#
# PAM is never started here and no WlSessionLock is involved, so nothing in this
# suite can lock a live session. The card is a component of its own, which is why
# it can be built in a plain offscreen Window.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(git -C "$HERE" rev-parse --show-toplevel)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# Quickshell only synthesises a qmldir for directories inside the config folder,
# so the absolute URL is rendered into a temp copy at run time.
sed -e "s|@URL@|file://${REPO}/config/quickshell/lockscreen|g" \
	"$HERE/card-test.qml" >"$TMP/card.qml"

python3 "$HERE/spawn-probe.py" 1.4 1.6 >"$TMP/spawns" &
probe=$!

out="$(cd "$TMP" && QT_QPA_PLATFORM=offscreen timeout 60 quickshell -p card.qml 2>&1 |
	sed 's/\x1b\[[0-9;]*m//g')"
wait "$probe" || true
spawns="$(cat "$TMP/spawns" 2>/dev/null || echo missing)"

echo "== unlock card"
echo "$out" | grep -E 'RESULT|FAIL|ERROR|is not a type|Cannot assign|ReferenceError|Failed to load' ||
	echo "   no result line - the harness died"
echo "   capslock-state.sh spawns in the idle tail (1.6-3.0 s): ${spawns} (a 500 ms poll gives 3)"

status=0
echo "$out" | grep -q 'RESULT pass=[0-9]* fail=0' || status=1
echo "$out" | grep -qE 'ERROR|is not a type|Cannot assign|ReferenceError|Failed to load' && status=1
if ! [ "${spawns}" -eq 0 ] 2>/dev/null; then
	echo "   FAIL the card polled the compositor while idle" >&2
	status=1
fi

exit "$status"
