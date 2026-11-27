#!/usr/bin/env bash
# Install the systemd power policy from etc/systemd: suspend disabled, no
# hibernation. Run as root: sudo ./scripts/system/install-power-policy.sh
set -euo pipefail

if [[ $EUID -ne 0 ]]; then
    echo "This script must run as root (sudo $0)" >&2
    exit 1
fi

# readlink -f: invoked through the ~/.scripts symlink, BASH_SOURCE still carries
# the symlink path, and dirname/../.. would climb to ~ instead of the repo.
REPO="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/../.." && pwd)"

install -Dm644 "$REPO/etc/systemd/logind.conf.d/00-suspend.conf" /etc/systemd/logind.conf.d/00-suspend.conf
install -Dm644 "$REPO/etc/systemd/sleep.conf.d/00-suspend.conf" /etc/systemd/sleep.conf.d/00-suspend.conf

echo "Installed:"
echo "  /etc/systemd/logind.conf.d/00-suspend.conf"
echo "  /etc/systemd/sleep.conf.d/00-suspend.conf"
echo
echo "logind suspend triggers are off: lid switch, suspend key and idle do nothing."
echo "Lid close is owned by the Hyprland switch bind (lock-and-suspend.sh):"
echo "lock -> wait for the lock marker -> suspend. Manual 'systemctl suspend'"
echo "still works; route it through the script to lock first."
echo
echo "Reboot to apply. Do NOT run 'systemctl restart systemd-logind' on a live"
echo "graphical session: it terminates the session and drops you back to the greeter."
echo "hypridle is managed by the user unit: systemctl --user enable --now hypridle.service"
