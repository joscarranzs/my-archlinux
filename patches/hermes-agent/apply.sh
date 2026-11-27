#!/usr/bin/env bash
# Apply the local patches under patches/hermes-agent/ to the Hermes Agent checkout,
# then rebuild the TUI bundle when anything actually changed.
#
# Idempotent: a patch whose reverse applies cleanly is already in place and is
# skipped. Refuses to guess when neither direction applies.
#
# Hermes Agent is installed from a detached-HEAD checkout under git, so
# `hermes update` replaces these files. Re-run this script after every update.

set -euo pipefail

AGENT_DIR="${HERMES_AGENT_DIR:-$HOME/.hermes/hermes-agent}"
PATCH_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [[ ! -d "$AGENT_DIR/.git" && ! -f "$AGENT_DIR/.git" ]]; then
    echo "error: $AGENT_DIR is not a git checkout" >&2
    exit 1
fi

applied=0
shopt -s nullglob
patches=("$PATCH_DIR"/*.patch)
shopt -u nullglob

if ((${#patches[@]} == 0)); then
    echo "no patches in $PATCH_DIR"
    exit 0
fi

for patch in "${patches[@]}"; do
    name="$(basename "$patch")"

    if git -C "$AGENT_DIR" apply --reverse --check "$patch" 2>/dev/null; then
        echo "already applied: $name"
        continue
    fi

    if git -C "$AGENT_DIR" apply --check "$patch" 2>/dev/null; then
        git -C "$AGENT_DIR" apply "$patch"
        echo "applied: $name"
        applied=$((applied + 1))
        continue
    fi

    echo "error: $name applies neither forward nor in reverse — resolve by hand" >&2
    exit 1
done

if ((applied == 0)); then
    echo "nothing to do"
    exit 0
fi

# The TUI runs ui-tui/dist/entry.js; the launcher rebuilds it on startup anyway,
# but doing it here keeps the checkout consistent for the next launch.
if [[ -f "$AGENT_DIR/ui-tui/dist/entry.js" ]]; then
    ( cd "$AGENT_DIR/ui-tui" && node ../scripts/build/tui.mjs >/dev/null )
    echo "rebuilt: ui-tui/dist/entry.js"
fi

echo "done: $applied patch(es) applied. Restart any running Hermes session to pick them up."
