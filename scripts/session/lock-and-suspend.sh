#!/usr/bin/env bash
# Lid close: lock the session, wait for the lock surface's readiness marker,
# and only then suspend. logind ignores the lid (etc/systemd/logind.conf.d/
# 00-suspend.conf); this script, fired by the Hyprland switch bind, owns the
# flow. A systemd sleep hook cannot: user.slice is frozen before pre hooks run,
# so the locker would only load after the thaw (the post-resume flash).
#
# The marker ($XDG_RUNTIME_DIR/session-locked) is touched by LockSurface.qml
# once the lock surface is mapped and removed on unlock. No marker, no suspend:
# suspending an unconfirmed session would defeat the whole point.
#
# Usage: lock-and-suspend.sh [--no-suspend]
#   --no-suspend  lock and confirm only; tests the lock half without sleeping.
set -uo pipefail

RUNTIME="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
MARKER="$RUNTIME/session-locked"
LOG="$RUNTIME/lock-and-suspend.log"
TIMEOUT=120   # 0.1s ticks -> 12s; the locker cold-starts in ~2s

NO_SUSPEND=0
[ "${1:-}" = "--no-suspend" ] && NO_SUSPEND=1

# A keybind gives this no terminal; keep the evidence on disk.
exec >>"$LOG" 2>&1
echo "== $(date '+%F %T') lid flow (no-suspend=$NO_SUSPEND)"

# If the idle listener already locked, the marker is there and this is instant.
if [[ ! -f $MARKER ]]; then
    loginctl lock-session 2>/dev/null || true
    for ((tick = 0; tick < TIMEOUT; tick++)); do
        [[ -f $MARKER ]] && break
        sleep 0.1
    done
fi

if [[ ! -f $MARKER ]]; then
    echo "ABORT: no lock confirmation after 12s; not suspending an unlocked session" >&2
    exit 1
fi
echo "lock confirmed (marker present)"

if [ "$NO_SUSPEND" = "1" ]; then
    echo "--no-suspend: stopping here"
    exit 0
fi
exec systemctl suspend