#!/usr/bin/env bash
# Disable LLMNR in systemd-resolved and verify the port is closed.
# Run as root: sudo ./scripts/system/install-resolved-hardening.sh
#
# Why: LLMNR answers are unauthenticated link-local broadcasts; any host on the
# LAN can spoof a name. DNS covers this host's resolution and mDNS is left at
# its default, so LLMNR is pure attack surface (UDP/TCP 5355).
#
# Restarting systemd-resolved is safe inside a graphical session (unlike
# systemd-logind): resolution hiccups for a moment, the session stays alive.
set -euo pipefail

if [[ $EUID -ne 0 ]]; then
    echo "This script must run as root (sudo $0)" >&2
    exit 1
fi

# readlink -f: invoked through the ~/.scripts symlink, BASH_SOURCE still carries
# the symlink path, and dirname/../.. would climb to ~ instead of the repo.
REPO="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/../.." && pwd)"
SRC="$REPO/etc/systemd/resolved.conf.d/00-llmnr.conf"
DST=/etc/systemd/resolved.conf.d/00-llmnr.conf

if [[ ! -f "$SRC" ]]; then
    echo "Missing $SRC" >&2
    exit 1
fi

install -Dm644 "$SRC" "$DST"
echo "Installed $DST"
systemctl restart systemd-resolved
# Give resolved a moment to reopen (or not reopen) its sockets.
sleep 1

fail=0
if resolvectl status 2>/dev/null | grep -q '+LLMNR'; then
    echo "check FAILED: resolvectl still reports +LLMNR on a link" >&2
    fail=1
else
    echo "check: no link reports +LLMNR"
fi
if ss -tuln 2>/dev/null | grep -q ':5355 '; then
    echo "check FAILED: port 5355 still open" >&2
    fail=1
else
    echo "check: port 5355 closed"
fi
if grep -qx 'LLMNR=no' "$DST"; then
    echo "check: drop-in selects LLMNR=no"
else
    echo "check FAILED: $DST does not carry LLMNR=no" >&2
    fail=1
fi

echo
if [[ $fail -eq 0 ]]; then
    echo "All checks passed. LLMNR is off; mDNS and DNS are unchanged."
else
    echo "Some checks failed (see above)." >&2
fi
exit "$fail"