#!/usr/bin/env bash
# Set the desktop's text scale: the multiplier every generated Appearance
# applies to its text steps.
#
# Nothing is regenerated when this changes. Each Appearance watches this file
# and recomputes its sizes, so one write moves every surface -- bar, plaques,
# launcher, lock -- in the same frame, with no theme rebuild and no git churn.
#
#   text-scale.sh           print the value in force (1 when never set)
#   text-scale.sh get       the same
#   text-scale.sh 1.1       write it, read it back, print what landed
#
# The value is a preference, not a theme token, so it lives in the state
# directory and never in the repository.
set -euo pipefail

STATE="${XDG_STATE_HOME:-$HOME/.local/state}/dotfiles"
FILE="${STATE}/text-scale"

read_scale() {
	if [ -r "$FILE" ]; then
		tr -d '[:space:]' <"$FILE"
	else
		printf '1'
	fi
}

case "${1:-get}" in
get)
	read_scale
	printf '\n'
	;;
*)
	value="${1}"
	if ! [[ "$value" =~ ^[0-9]+(\.[0-9]+)?$ ]]; then
		echo "text-scale: not a number: ${value}" >&2
		exit 2
	fi
	# The range is this script's promise, not the file's: the panels honour any
	# positive number. 0.85-1.15 is what every plaque was measured clean at
	# (scripts/session/tests/panels gates the top of it). Above that, two rows
	# still hand their text less height than it asks for -- widen this line when
	# they are fixed, not before.
	if ! awk -v v="$value" 'BEGIN { exit !(v >= 0.85 && v <= 1.15) }'; then
		echo "text-scale: outside 0.85-1.15: ${value}" >&2
		exit 2
	fi
	mkdir -p "$STATE"
	# Written in place, in one call: a watcher that read a truncated file would
	# paint a frame at the wrong scale, and a rename would leave the watcher
	# holding the old inode and seeing nothing at all.
	printf '%s\n' "$value" >"$FILE"
	landed="$(read_scale)"
	if [ "$landed" != "$value" ]; then
		echo "text-scale: the write did not land (file says ${landed})" >&2
		exit 1
	fi
	printf '%s\n' "$landed"
	;;
esac
