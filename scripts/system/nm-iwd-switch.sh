#!/usr/bin/env bash
# Move wireless management from standalone iwd to NetworkManager with iwd as its
# wifi backend, and put the machine back if wlan0 does not come up connected.
#
# Why this is a script and not a sequence of commands: enabling NetworkManager
# takes wlan0 away from iwd and re-runs association and DHCP through a different
# path (/usr/lib/NetworkManager/<ver>/libnm-device-plugin-wifi.so with
# wifi.backend=iwd). If any link in that chain is wrong the host keeps an
# associated radio with no address, which on a machine with no other uplink
# means no way to read the instructions that would fix it. Every change is
# snapshotted before it is made, and the failure path restores the snapshot
# instead of printing advice.
#
# Usage:
#   sudo nm-iwd-switch.sh [--dry-run] [--yes]
#   sudo nm-iwd-switch.sh --rollback          # restore the last snapshot
#
# Exit codes: 0 switched and verified, 1 refused, 2 verified failed -> rolled
# back to a working link, 3 rolled back but the link did NOT come back.
set -uo pipefail

readonly NM_CONF_DIR=/etc/NetworkManager/conf.d
readonly NM_CONF_FILE="$NM_CONF_DIR/wifi-backend.conf"
readonly NETWORKD_DIR=/etc/systemd/network
readonly NETWORKD_WLAN="$NETWORKD_DIR/20-wlan.network"
readonly NM_UNIT_DROPIN_DIR=/etc/systemd/system/NetworkManager.service.d
readonly NM_UNIT_DROPIN="$NM_UNIT_DROPIN_DIR/10-after-iwd.conf"
readonly DEV=wlan0
readonly CONNECT_TIMEOUT=90

DRY_RUN=0
ASSUME_YES=0
FORCE_ROLLBACK=0
for arg in "$@"; do
	case "$arg" in
		--dry-run) DRY_RUN=1 ;;
		--yes | -y) ASSUME_YES=1 ;;
		--rollback) FORCE_ROLLBACK=1 ;;
		-h | --help) sed -n '2,19p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
		*) echo "unknown argument: $arg" >&2; exit 1 ;;
	esac
done

say() { printf '\n== %s\n' "$*"; }
info() { printf '   %s\n' "$*"; }
warn() { printf '   ! %s\n' "$*" >&2; }

# ---------------------------------------------------------------- snapshot
STAMP=$(date +%Y%m%d-%H%M%S)
STATE_DIR="/var/tmp/nm-iwd-switch-$STAMP"
LAST_LINK="/var/tmp/nm-iwd-switch-last"

snapshot() {
	say "snapshot -> $STATE_DIR"
	mkdir -p "$STATE_DIR" || return 1
	{
		for unit in NetworkManager iwd systemd-networkd wpa_supplicant; do
			printf '%s active=%s enabled=%s\n' "$unit" \
				"$(systemctl is-active "$unit" 2>&1)" \
				"$(systemctl is-enabled "$unit" 2>&1)"
		done
	} >"$STATE_DIR/units.txt"

	iwctl station "$DEV" show 2>/dev/null |
		sed -n 's/.*Connected network *//p' | sed 's/[[:space:]]*$//' | head -1 >"$STATE_DIR/ssid.txt"
	ip route show default | head -1 >"$STATE_DIR/default-route.txt"
	ip -4 -o addr show dev "$DEV" | awk '{print $4}' >"$STATE_DIR/address.txt"

	[ -f "$NM_CONF_FILE" ] && cp -a "$NM_CONF_FILE" "$STATE_DIR/wifi-backend.conf.bak"
	[ -f "$NETWORKD_WLAN" ] && cp -a "$NETWORKD_WLAN" "$STATE_DIR/20-wlan.network.bak"
	[ -f "$NM_UNIT_DROPIN" ] && cp -a "$NM_UNIT_DROPIN" "$STATE_DIR/10-after-iwd.conf.bak"
	[ -d /etc/NetworkManager/system-connections ] &&
		tar -C /etc/NetworkManager -cf "$STATE_DIR/system-connections.tar" system-connections 2>/dev/null

	ln -sfn "$STATE_DIR" "$LAST_LINK"
	info "network before: $(cat "$STATE_DIR/address.txt" 2>/dev/null | head -1) via $(awk '{print $3}' "$STATE_DIR/default-route.txt" 2>/dev/null)"
	info "ssid before:    $(cat "$STATE_DIR/ssid.txt" 2>/dev/null)"
	return 0
}

# --------------------------------------------------------------- rollback
rollback() {
	local reason="$1" ssid
	say "ROLLBACK ($reason)"
	ssid=$(cat "$STATE_DIR/ssid.txt" 2>/dev/null || true)

	systemctl disable --now NetworkManager 2>/dev/null
	if [ -f "$STATE_DIR/wifi-backend.conf.bak" ]; then
		cp -a "$STATE_DIR/wifi-backend.conf.bak" "$NM_CONF_FILE"
	else
		rm -f "$NM_CONF_FILE"
	fi
	# networkd's wlan profile was moved aside, not edited: move the original back.
	if [ -f "$STATE_DIR/20-wlan.network.moved" ]; then
		mv -f "$STATE_DIR/20-wlan.network.moved" "$NETWORKD_WLAN"
	elif [ ! -f "$NETWORKD_WLAN" ] && [ -f "$STATE_DIR/20-wlan.network.bak" ]; then
		cp -a "$STATE_DIR/20-wlan.network.bak" "$NETWORKD_WLAN"
	fi
	if [ -f "$STATE_DIR/10-after-iwd.conf.bak" ]; then
		cp -a "$STATE_DIR/10-after-iwd.conf.bak" "$NM_UNIT_DROPIN"
	else
		rm -f "$NM_UNIT_DROPIN"
	fi
	rmdir "$NM_UNIT_DROPIN_DIR" 2>/dev/null

	systemctl enable --now iwd 2>/dev/null
	systemctl restart systemd-networkd 2>/dev/null
	info "waiting for the link to come back"

	local i
	for i in $(seq 1 20); do
		[ -n "$(ip -4 -o addr show dev "$DEV" | awk '{print $4}')" ] && break
		sleep 1
	done

	if [ -z "$(ip -4 -o addr show dev "$DEV" | awk '{print $4}')" ] && [ -n "$ssid" ]; then
		warn "no address yet, re-associating to '$ssid'"
		iwctl station "$DEV" connect "$ssid" >/dev/null 2>&1
		for i in $(seq 1 25); do
			[ -n "$(ip -4 -o addr show dev "$DEV" | awk '{print $4}')" ] && break
			sleep 1
		done
	fi

	local gw
	gw=$(ip route show default | awk '{print $3}' | head -1)
	if [ -n "$gw" ] && ping -c1 -W2 "$gw" >/dev/null 2>&1; then
		say "link restored: $(ip -4 -o addr show dev "$DEV" | awk '{print $4}') via $gw"
		collect_diagnostics
		return 0
	fi
	say "LINK NOT BACK — read $STATE_DIR/diagnostics.txt"
	collect_diagnostics
	return 1
}

collect_diagnostics() {
	{
		echo "### date"; date
		echo "### units"
		for unit in NetworkManager iwd systemd-networkd wpa_supplicant; do
			printf '%s %s/%s\n' "$unit" "$(systemctl is-active "$unit" 2>&1)" "$(systemctl is-enabled "$unit" 2>&1)"
		done
		echo "### ip"; ip -br addr; ip route
		echo "### iwd"; iwctl station "$DEV" show 2>&1 | head -25
		echo "### networkctl"; networkctl status "$DEV" 2>&1 | head -20
		echo "### nmcli device"; nmcli -t device 2>&1 | head -10
		echo "### NetworkManager journal (last 80)"
		journalctl -u NetworkManager -b --no-pager 2>&1 | tail -80
	} >"$STATE_DIR/diagnostics.txt" 2>&1
	info "diagnostics: $STATE_DIR/diagnostics.txt"
}

# ------------------------------------------------------------ verification
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

# ------------------------------------------------------------------- apply
apply() {
	say "1/4 NetworkManager config: iwd as the wifi backend"
	mkdir -p "$NM_CONF_DIR"
	cat >"$NM_CONF_FILE" <<-'CONF'
		# Wireless is handled by iwd, not wpa_supplicant. NetworkManager keeps the
		# connection profiles and the IP configuration; iwd owns association and the
		# stored PSKs. /usr/lib/NetworkManager/<ver>/libnm-device-plugin-wifi.so has
		# the backend compiled in (it references net.connman.iwd).
		[device]
		wifi.backend=iwd
	CONF
	info "wrote $NM_CONF_FILE"

	say "2/4 hand wlan0 over: move networkd's wlan profile aside"
	if [ -f "$NETWORKD_WLAN" ]; then
		mv -f "$NETWORKD_WLAN" "$STATE_DIR/20-wlan.network.moved"
		info "moved $NETWORKD_WLAN -> $STATE_DIR/20-wlan.network.moved"
	else
		info "no $NETWORKD_WLAN to move"
	fi
	info "networkd now has no .network matching a station-mode wlan link"

	say "3/4 make NetworkManager start after iwd"
	mkdir -p "$NM_UNIT_DROPIN_DIR"
	cat >"$NM_UNIT_DROPIN" <<-'CONF'
		# The iwd backend talks to iwd over D-Bus; starting NetworkManager first
		# leaves it with no station to manage at boot.
		[Unit]
		After=iwd.service
		Wants=iwd.service
	CONF
	systemctl daemon-reload
	info "wrote $NM_UNIT_DROPIN"

	say "4/4 enable and start NetworkManager (the link drops here)"
	systemctl enable NetworkManager || return 1
	systemctl restart systemd-networkd
	systemctl start NetworkManager
	info "NetworkManager: $(systemctl is-active NetworkManager)"
}

# -------------------------------------------------------------------- main
main() {
	if [ "$FORCE_ROLLBACK" = "1" ]; then
		[ "$(id -u)" = "0" ] || { echo "run --rollback as root" >&2; exit 1; }
		[ -d "$LAST_LINK" ] || { echo "no snapshot at $LAST_LINK" >&2; exit 1; }
		STATE_DIR=$(readlink -f "$LAST_LINK")
		rollback "operator request" || exit 3
		exit 0
	fi

	if [ "$DRY_RUN" = "1" ]; then
		[ "$(id -u)" = "0" ] || { echo "note: --dry-run without root can only inspect" >&2; }
		say "dry run — nothing will be changed"
		info "would write $NM_CONF_FILE (wifi.backend=iwd)"
		info "would move $NETWORKD_WLAN aside (networkd stops configuring the wlan link)"
		info "would write $NM_UNIT_DROPIN (After=iwd.service)"
		info "would run: systemctl enable NetworkManager && systemctl start NetworkManager"
		info "would then require: nmcli '$DEV'=connected + IPv4 + default route + gateway ping"
		info "on failure: disable NetworkManager, restore the two files + the moved networkd profile,"
		say "current state"
		for unit in NetworkManager iwd systemd-networkd wpa_supplicant; do
			info "$unit: $(systemctl is-active "$unit" 2>&1)/$(systemctl is-enabled "$unit" 2>&1)"
		done
		info "backend compiled in: $(strings /usr/lib/NetworkManager/[0-9]*/libnm-device-plugin-wifi.so 2>/dev/null | grep -c 'net.connman.iwd') iwd references"
		exit 0
	fi

	[ "$(id -u)" = "0" ] || { echo "run as root: sudo $0 --yes" >&2; exit 1; }

	if [ "$ASSUME_YES" != "1" ]; then
		printf 'This takes wlan0 away from iwd and re-does association and DHCP through\nNetworkManager. It rolls back on its own if the link does not come back, but\nthe link WILL drop for a few seconds. Continue? [y/N] '
		read -r answer
		[[ "$answer" == [yY]* ]] || { echo "aborted"; exit 1; }
	fi

	snapshot || { echo "snapshot failed, refusing to touch the system" >&2; exit 1; }

	apply || { rollback "apply failed"; exit 2; }

	say "verifying the connection (up to ${CONNECT_TIMEOUT}s)"
	if wait_for_connection; then
		say "SUCCESS"
		info "nmcli:  $(nmcli -t -f DEVICE,STATE,CONNECTION device | grep "^$DEV:")"
		info "address: $(ip -4 -o addr show dev "$DEV" | awk '{print $4}')"
		info "route:   $(ip route show default | head -1)"
		info "ssid:    $(nmcli -t -f ACTIVE,SSID device wifi | awk -F: '$1=="yes"{print $2}')"
		info "backup:  $STATE_DIR"
		exit 0
	fi

	warn "no verified connection after ${CONNECT_TIMEOUT}s"
	rollback "connection never came up" || exit 3
	exit 2
}

main
