#!/usr/bin/env bash
# Empty and error states, forced offscreen, one run per surface.
#
# These are the states nobody ever sees on a healthy machine: no external
# monitor, no network in range, no token blob, no tasks on the board, no web app
# installed, and each surface's own error line. They went unverified for exactly
# that reason, so this suite renders each one and asserts what it says and the
# ink it says it in.
#
# The harnesses import the panels through the @URL@ placeholder: Quickshell only
# synthesises a qmldir for directories inside the config folder, so the absolute
# URL is rendered into a temp copy at run time (same recipe as the lockscreen and
# panel entrance suites).
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(git -C "$HERE" rev-parse --show-toplevel)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

URL="file://${REPO}/config/quickshell"
status=0

# A webapp helper that answers `list` with an empty board: the harness must run a
# real lister, because forcing `apps: []` would assert against a list that never
# loaded (and "LOADING… forever" is one of the states under test).
HELPER="${TMP}/webapp-helper.sh"
printf '#!/bin/sh\necho "[]"\n' >"$HELPER"
chmod +x "$HELPER"

for source in "$HERE"/*-test.qml; do
	name="$(basename "$source" -test.qml)"
	sed -e "s|@URL@|${URL}|g" -e "s|@HELPER@|${HELPER}|g" "$source" >"$TMP/${name}.qml"
	out="$(cd "$TMP" && QT_QPA_PLATFORM=offscreen timeout 60 quickshell -p "${name}.qml" 2>&1 |
		sed 's/\x1b\[[0-9;]*m//g')"
	echo "== ${name}"
	echo "$out" | grep -E 'PASS|FAIL|RESULT|ERROR|is not a type|Cannot assign|ReferenceError|Failed to load|TypeError' ||
		echo "   no result line - the harness died"
	if ! echo "$out" | grep -q 'RESULT pass=[0-9]* fail=0' ||
		echo "$out" | grep -qE 'FAIL|ERROR|is not a type|Cannot assign|ReferenceError|Failed to load|TypeError'; then
		status=1
	fi
done

exit "$status"
