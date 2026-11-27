#!/usr/bin/env bash
# Move NetworkManager's wifi backend from iwd to wpa_supplicant, without leaving the
# host without a link.
#
# The trap this script exists for: with wifi.backend=iwd, NetworkManager never needs
# a PSK -- iwd owns it -- so the NM profile for the current network is stored with
# `802-11-wireless-security.key-mgmt=wpa-psk` and **no psk at all** (measured: empty).
# Flipping the backend on that profile hands wpa_supplicant a connection it cannot
# authenticate with, which fails as "secrets were required but not provided" and
# leaves the machine offline. So the PSK is copied out of iwd's own store into the NM
# profile and verified *before* anything is switched.
#
# Why bother: the iwd backend refuses to connect to a network iwd does not already
# know (net.connman.iwd.Failed: Operation failed, ~80 ms, both from Quickshell and
# from nmcli with a stored psk), so the panel can only reach saved networks. The
# wpa_supplicant backend is the supported path for adding new ones.
#
# Usage:
#   sudo nm-wifi-backend.sh [--dry-run] [--yes]
#   sudo nm-wifi-backend.sh --rollback
#
# Exit codes: 0 switched and verified, 1 refused (nothing changed), 2 verified failed
# -> rolled back to a working link, 3 rolled back but the link did NOT come back.
set -uo pipefail

readonly NM_CONF_DIR=/etc/NetworkManager/conf.d
readonly NM_CONF_FILE="$NM_CONF_DIR/wifi-backend.conf"
readonly NM_UNIT_DROPIN_DIR=/etc/systemd/system/NetworkManager.service.d
readonly NM_UNIT_DROPIN="$NM_UNIT_DROPIN_DIR/10-after-iwd.conf"
readonly IWD_STORE=/var/lib/iwd
readonly DEV=wlan0
readonly CONNECT_TIMEOUT=240

DRY_RUN=0
ASSUME_YES=0
FORCE_ROLLBACK=0
for arg in "$@"; do
	case "$arg" in
		--dry-run) DRY_RUN=1 ;;
		--yes | -y) ASSUME_YES=1 ;;
		--rollback) FORCE_ROLLBACK=1 ;;
		-h | --help) sed -n '2,23p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
		*) echo "unknown argument: $arg" >&2; exit 1 ;;
	esac
done

say() { printf '\n== %s\n' "$*"; }
info() { printf '   %s\n' "$*"; }
warn() { printf '   ! %s\n' "$*" >&2; }

STAMP=$(date +%Y%m%d-%H%M%S)
STATE_DIR="/var/tmp/nm-wifi-backend-$STAMP"
LAST_LINK="/var/tmp/nm-wifi-backend-last"

current_ssid() {
	nmcli -t -f ACTIVE,SSID device wifi 2>/dev/null | awk -F: '$1=="yes"{print $2; exit}'
}

psk_file_for() {
	printf '%s/%s.psk' "$IWD_STORE" "$1"
}

# The psk as NetworkManager will see it. Empty means the profile cannot authenticate
# on a backend that owns its own secrets, i.e. switching would drop the link for good.
profile_psk_len() {
	nmcli -s -g 802-11-wireless-security.psk connection show "$1" 2>/dev/null |
		awk '{print length($0)}'
}

snapshot() {
	say "snapshot -> $STATE_DIR"
	mkdir -p "$STATE_DIR" || return 1
	for unit in NetworkManager iwd wpa_supplicant systemd-networkd; do
		printf '%s active=%s enabled=%s\n' "$unit" \
			"$(systemctl is-active "$unit" 2>&1)" \
			"$(systemctl is-enabled "$unit" 2>&1)"
	done >"$STATE_DIR/units.txt"

	current_ssid >"$STATE_DIR/ssid.txt"
	ip route show default | head -1 >"$STATE_DIR/default-route.txt"
	ip -4 -o addr show dev "$DEV" | awk '{print $4}' >"$STATE_DIR/address.txt"
	[ -f "$NM_CONF_FILE" ] && cp -a "$NM_CONF_FILE" "$STATE_DIR/wifi-backend.conf.bak"
	[ -f "$NM_UNIT_DROPIN" ] && cp -a "$NM_UNIT_DROPIN" "$STATE_DIR/10-after-iwd.conf.bak"
	tar -C /etc/NetworkManager -cf "$STATE_DIR/system-connections.tar" system-connections 2>/dev/null

	ln -sfn "$STATE_DIR" "$LAST_LINK"
	info "before: $(head -1 "$STATE_DIR/address.txt" 2>/dev/null) ssid=$(cat "$STATE_DIR/ssid.txt" 2>/dev/null)"
	return 0
}

wait_for_connection() {
	local i state addr gw
	for i in $(seq 1 $((CONNECT_TIMEOUT / 3))); do
		sleep 3
		state=$(nmcli -t -f DEVICE,STATE device 2>/dev/null | awk -F: -v d="$DEV" '$1==d{print $2}')
		addr=$(ip -4 -o addr show dev "$DEV" | awk '{print $4}' | head -1)
		gw=$(ip route show default | awk '{print $3}' | head -1)
		info "t+$((i * 3))s nmcli=${state:-?} addr=${addr:-none} gw=${gw:-none}"
		if [ "$state" = "connected" ] && [ -n "$addr" ] && [ -n "$gw" ] && ping -c1 -W2 "$gw" >/dev/null 2>&1; then
			return 0
		fi
	done
	return 1
}

collect_diagnostics() {
	{
		echo "### date"; date
		echo "### units"
		for unit in NetworkManager iwd wpa_supplicant systemd-networkd; do
			printf '%s %s/%s\n' "$unit" "$(systemctl is-active "$unit" 2>&1)" "$(systemctl is-enabled "$unit" 2>&1)"
		done
		echo "### ip"; ip -br addr; ip route
		echo "### profiles"; nmcli -t -f NAME,UUID,TYPE connection show 2>&1
		echo "### nmcli device"; nmcli -t device 2>&1 | head -10
		echo "### NetworkManager journal (last 100)"
		journalctl -u NetworkManager -b --no-pager 2>&1 | tail -100
		echo "### wpa_supplicant journal (last 40)"
		journalctl -u wpa_supplicant -b --no-pager 2>&1 | tail -40
	} >"$STATE_DIR/diagnostics.txt" 2>&1
	info "diagnostics: $STATE_DIR/diagnostics.txt"
}

rollback() {
	local reason="$1" ssid
	say "ROLLBACK ($reason)"
	ssid=$(cat "$STATE_DIR/ssid.txt" 2>/dev/null || true)

	# Backend back to iwd first, so NetworkManager starts with the one iwd owns.
	if [ -f "$STATE_DIR/wifi-backend.conf.bak" ]; then
		cp -a "$STATE_DIR/wifi-backend.conf.bak" "$NM_CONF_FILE"
	else
		rm -f "$NM_CONF_FILE"
	fi
	if [ -f "$STATE_DIR/10-after-iwd.conf.bak" ]; then
		mkdir -p "$NM_UNIT_DROPIN_DIR"
		cp -a "$STATE_DIR/10-after-iwd.conf.bak" "$NM_UNIT_DROPIN"
	fi
	systemctl disable --now wpa_supplicant 2>/dev/null
	systemctl enable --now iwd 2>/dev/null
	systemctl daemon-reload
	systemctl restart NetworkManager 2>/dev/null
	info "waiting for the link to come back on the iwd backend"

	local i
	for i in $(seq 1 15); do
		[ -n "$(ip -4 -o addr show dev "$DEV" | awk '{print $4}')" ] && break
		sleep 1
	done
	if [ -z "$(ip -4 -o addr show dev "$DEV" | awk '{print $4}')" ] && [ -n "$ssid" ]; then
		warn "no address yet, re-associating through iwd to '$ssid'"
		iwctl station "$DEV" connect "$ssid" >/dev/null 2>&1
		for i in $(seq 1 25); do
			[ -n "$(ip -4 -o addr show dev "$DEV" | awk '{print $4}')" ] && break
			sleep 1
		done
	fi

	local gw
	gw=$(ip route show default | awk '{print $3}' | head -1)
	if [ -n "$gw" ] && ping -c1 -W2 "$gw" >/dev/null 2>&1; then
		say "link restored on iwd: $(ip -4 -o addr show dev "$DEV" | awk '{print $4}') via $gw"
		collect_diagnostics
		return 0
	fi
	say "LINK NOT BACK — read $STATE_DIR/diagnostics.txt"
	collect_diagnostics
	return 1
}

# --------------------------------------------------------------- preconditions
prepare_psk() {
	local ssid conn psk_file psk
	ssid=$(current_ssid)
	if [ -z "$ssid" ]; then
		warn "no active wifi connection; cannot copy a secret out of iwd"
		return 1
	fi
	# The profile for the active SSID, not just the first wifi one: modifying the wrong
	# profile would leave the real one without a secret.
	conn=$(nmcli -t -f NAME connection show | grep -Fx -- "$ssid" | head -1)
	if [ -z "$conn" ]; then
		conn=$(nmcli -t -f NAME,TYPE connection show | awk -F: '$2=="802-11-wireless"{print $1; exit}')
	fi
	if [ -z "$conn" ]; then
		warn "no saved wifi profile in NetworkManager"
		return 1
	fi
	info "active ssid: $ssid | profile: $conn"

	if [ "$(profile_psk_len "$conn")" -gt 0 ]; then
		info "profile already stores a PSK ($(profile_psk_len "$conn") chars)"
		return 0
	fi

	psk_file=$(psk_file_for "$ssid")
	if [ ! -r "$psk_file" ]; then
		warn "iwd store has no readable secret at $psk_file"
		warn "refusing to switch: wpa_supplicant would have nothing to authenticate with"
		return 1
	fi
	psk=$(sed -n 's/^PreSharedKey=//p' "$psk_file" | head -1)
	if [ -z "$psk" ]; then
		warn "no PreSharedKey in $psk_file (enterprise or open network?)"
		warn "refusing to switch"
		return 1
	fi
	info "found a PSK for '$ssid' in iwd's store (${#psk} chars) — copying it into the NM profile"
	nmcli connection modify "$conn" wifi-sec.psk "$psk" || return 1
	if [ "$(profile_psk_len "$conn")" -gt 0 ]; then
		info "profile now stores a PSK ($(profile_psk_len "$conn") chars) — safe to switch"
		return 0
	fi
	warn "the PSK did not land in the profile; refusing to switch"
	return 1
}

apply() {
	say "1/5 NetworkManager: wpa_supplicant as the wifi backend"
	mkdir -p "$NM_CONF_DIR"
	cat >"$NM_CONF_FILE" <<-'CONF'
		# Wireless goes through wpa_supplicant, NetworkManager's supported backend.
		# The iwd backend refuses connections to networks iwd does not already know
		# (net.connman.iwd.Failed: Operation failed), which made adding a network from
		# the panel impossible.
		[device]
		wifi.backend=wpa_supplicant
	CONF
	info "wrote $NM_CONF_FILE"

	say "2/5 drop the boot ordering that pulled iwd in"
	if [ -f "$NM_UNIT_DROPIN" ]; then
		rm -f "$NM_UNIT_DROPIN"
		rmdir "$NM_UNIT_DROPIN_DIR" 2>/dev/null
		info "removed $NM_UNIT_DROPIN"
	else
		info "no $NM_UNIT_DROPIN to remove"
	fi
	systemctl daemon-reload

	say "3/5 start wpa_supplicant, stop iwd"
	systemctl enable wpa_supplicant || return 1
	systemctl start wpa_supplicant
	info "wpa_supplicant: $(systemctl is-active wpa_supplicant)"
	# iwd leaves the netdev DOWN and NetworkManager marks it unmanaged: stopping it
	# before NetworkManager restarts keeps NM from ever seeing 'supplicant-failed'.
	systemctl disable --now iwd
	info "iwd: $(systemctl is-active iwd) / $(systemctl is-enabled iwd 2>&1)"
	sleep 2

	say "4/5 restart NetworkManager on the new backend"
	systemctl restart NetworkManager
	info "NetworkManager: $(systemctl is-active NetworkManager)"

	# Measured failure: for ~2 minutes NetworkManager had no wlan0 at all ("Device
	# wlan0 does not exist") because iwd exiting leaves the link down and NM drops the
	# device as unmanaged. A netlink bounce makes NM re-detect it instead of waiting
	# for a change that may never come.
	local i
	for i in $(seq 1 20); do
		nmcli -t -f DEVICE device 2>/dev/null | grep -qx "$DEV" && break
		sleep 2
	done
	if ! nmcli -t -f DEVICE device 2>/dev/null | grep -qx "$DEV"; then
		warn "NetworkManager does not see $DEV yet — bouncing the link"
		ip link set "$DEV" down 2>/dev/null
		sleep 1
		ip link set "$DEV" up 2>/dev/null
		for i in $(seq 1 10); do
			nmcli -t -f DEVICE device 2>/dev/null | grep -qx "$DEV" && break
			sleep 2
		done
		info "$DEV visible: $(nmcli -t -f DEVICE device 2>/dev/null | grep -cx "$DEV")"
	fi
	return 0
}

main() {
	if [ "$FORCE_ROLLBACK" = "1" ]; then
		[ "$(id -u)" = "0" ] || { echo "run --rollback as root" >&2; exit 1; }
		[ -d "$LAST_LINK" ] || { echo "no snapshot at $LAST_LINK" >&2; exit 1; }
		STATE_DIR=$(readlink -f "$LAST_LINK")
		rollback "operator request" || exit 3
		exit 0
	fi

	if [ "$DRY_RUN" = "1" ]; then
		say "dry run — nothing will be changed"
		info "active ssid: $(current_ssid)"
		info "profile psk length: $(profile_psk_len "$(nmcli -t -f NAME,TYPE connection show | awk -F: '$2=="802-11-wireless"{print $1; exit}')")"
		[ "$(id -u)" = "0" ] || info "(as non-root iwd's store is unreadable: the real check needs sudo)"
		info "would write $NM_CONF_FILE (wifi.backend=wpa_supplicant)"
		info "would remove $NM_UNIT_DROPIN (the After=iwd.service ordering)"
		info "would copy iwd's PreSharedKey into the NM profile if the profile has none"
		info "would run: enable+start wpa_supplicant, disable+stop iwd, restart NetworkManager"
		info "would then require: nmcli '$DEV'=connected + IPv4 + default route + gateway ping"
		info "on failure: backend back to iwd, drop-in restored, iwd restarted, iwctl re-associate"
		exit 0
	fi

	[ "$(id -u)" = "0" ] || { echo "run as root: sudo $0 --yes" >&2; exit 1; }

	if [ "$ASSUME_YES" != "1" ]; then
		printf 'This switches NetworkManager to wpa_supplicant and stops iwd. It copies the\nsecret first and rolls back on its own, but the link WILL drop for some seconds.\nContinue? [y/N] '
		read -r answer
		[[ "$answer" == [yY]* ]] || { echo "aborted"; exit 1; }
	fi

	snapshot || { echo "snapshot failed, refusing to touch the system" >&2; exit 1; }

	# The one step that must happen before any change: without a secret in the profile,
	# a backend that owns no secrets of its own cannot reconnect.
	prepare_psk || { echo "preconditions failed; nothing was changed" >&2; exit 1; }

	apply || { rollback "apply failed"; exit 2; }

	say "5/5 verifying the connection (up to ${CONNECT_TIMEOUT}s)"
	if wait_for_connection; then
		say "SUCCESS"
		info "backend:      $(nmcli -g GENERAL.STATE device show "$DEV" 2>/dev/null | head -1)"
		info "nmcli:        $(nmcli -t -f DEVICE,STATE,CONNECTION device | grep "^$DEV:")"
		info "address:      $(ip -4 -o addr show dev "$DEV" | awk '{print $4}')"
		info "route:        $(ip route show default | head -1)"
		info "wpa_supplicant: $(systemctl is-active wpa_supplicant), iwd: $(systemctl is-active iwd)"
		info "backup:       $STATE_DIR"
		exit 0
	fi

	warn "no verified connection after ${CONNECT_TIMEOUT}s"
	rollback "connection never came up" || exit 3
	exit 2
}

main
