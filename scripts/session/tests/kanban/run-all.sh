#!/usr/bin/env bash
# Every kanban UI check in one pass.
#
#   panel-test.qml  drop geometry, move matrix, drag, keyboard, edit guards,
#                   the header status line, the lane dismiss area
#   feed-test.qml   the same panel over the real hermes backend (creates and
#                   archives one throwaway task on the live board)
#   card/run.sh     QTest against the real card: hold, swipe, double click, edit,
#                   and the click a drop must NOT turn into
#   section/run.sh  QTest against the real lane: a press beside a task closes the
#                   sheet, a press on one does not
#
# The QML harnesses import the panel through the @KANBAN@ placeholder: Quickshell
# only synthesises a qmldir for directories inside the config folder, so the
# absolute URL is rendered into a temp copy at run time.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(git -C "$HERE" rev-parse --show-toplevel)"
KANBAN_URL="file://${REPO}/config/quickshell/kanban"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

status=0

run_qml() {
	local name="$1" file="$2" out
	sed "s|@KANBAN@|${KANBAN_URL}|g" "$HERE/$file" > "$TMP/$file"
	out="$(cd "$TMP" && QT_QPA_PLATFORM=offscreen timeout 120 quickshell -p "$file" 2>&1 |
		sed 's/\x1b\[[0-9;]*m//g')"
	echo "== ${name}"
	echo "$out" | grep -E 'RESULT pass=|FAIL|TIME OUT|ERROR' || echo "   no result line - the harness died"
	if ! echo "$out" | grep -q 'RESULT pass=[0-9]* fail=0'; then
		status=1
	fi
}

run_qml "panel logic" panel-test.qml
run_qml "backend round trip" feed-test.qml

echo "== card gestures"
card_out="$("$HERE/card/run.sh" 2>&1)"
echo "$card_out" | grep -E 'Totals:|FAIL'
if ! echo "$card_out" | grep -q 'Totals: .* 0 failed'; then
	status=1
fi

echo "== lane dismiss"
section_out="$("$HERE/section/run.sh" 2>&1)"
echo "$section_out" | grep -E 'Totals:|FAIL'
if ! echo "$section_out" | grep -q 'Totals: .* 0 failed'; then
	status=1
fi

exit "$status"
