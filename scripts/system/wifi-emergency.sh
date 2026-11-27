#!/usr/bin/env bash
# EMERGENCY: put the wireless back on the stack that is known to work on this host.
#
# Target state: iwd associates, systemd-networkd does DHCP, NetworkManager and
# wpa_supplicant are off. That is how this machine ran for months before any
# NetworkManager experiment, so it is the honest fallback.
#
# Written to be used when you have no network and no time: it does not depend on a
# snapshot being intact, on NetworkManager being alive, or on nmcli working. The
# networkd profile is rebuilt from an embedded copy and the result is verified with
# `ip` and `iwctl` only.
#
# Usage:
#   sudo wifi-emergency.sh [--dry-run] [--ssid NAME]
#
set -uo pipefail

readonly NETWORKD_FILE=/etc/systemd/network/20-wlan.network
readonly NM_CONF=/etc/NetworkManager/conf.d/wifi-backend.conf
readonly DEV=wlan0

DRY_RUN=0
SSID=""
while [ $# -gt 0 ]; do
	case "$1" in
		--dry-run) DRY_RUN=1 ;;
		--ssid) shift; SSID="${1:-}" ;;
		-h | --help) sed -n '2,15p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
		*) echo "unknown argument: $1" >&2; exit 1 ;;
	esac
	shift
done

say() { printf '\n== %s\n' "$*"; }
info() { printf '   %s\n' "$*"; }
warn() { printf '   ! %s\n' "$*" >&2; }

STAMP=$(date +%Y%m%d-%H%M%S)
STATE_DIR="/var/tmp/wifi-emergency-$STAMP"

networkd_profile() {
	cat <<-'CONF'
		[Match]
		Type=wlan

		[Link]
		RequiredForOnline=routable

		[Network]
		DHCP=yes
		MulticastDNS=yes

		# systemd-networkd does not set per-interface-type default route metrics
		# https://github.com/systemd/systemd/issues/17698
		# Explicitly set route metric, so that Ethernet is preferred over Wi-Fi and Wi-Fi is preferred over mobile broadband.
		# Use values from NetworkManager. From nm_device_get_route_metric_default in
		# https://gitlab.freedesktop.org/NetworkManager/NetworkManager/-/blob/main/src/core/devices/nm-device.c
		[DHCPv4]
		RouteMetric=600

		[IPv6AcceptRA]
		RouteMetric=600
	CONF
}

have_ip() {
	[ -n "$(ip -4 -o addr show dev "$DEV" 2>/dev/null | awk '{print $4}')" ]
}

gateway_up() {
	local gw
	gw=$(ip route show default 2>/dev/null | awk '{print $3}' | head -1)
	[ -n "$gw" ] && ping -c1 -W2 "$gw" >/dev/null 2>&1
}

known_ssid() {
	iwctl known-networks list 2>/dev/null | sed 's/\x1b\[[0-9;]*m//g' \
		| awk 'NF && $0 !~ /Known Networks|^ *-+|^ *Name/ {print $1; exit}'
}

report() {
	say "estado"
	info "wlan0: $(ip -br addr show "$DEV" 2>/dev/null | awk '{print $1, $2, $3}')"
	info "ruta:  $(ip route show default 2>/dev/null | head -1)"
	info "iwd:   $(systemctl is-active iwd 2>&1)/$(systemctl is-enabled iwd 2>&1)"
	for unit in NetworkManager wpa_supplicant systemd-networkd; do
		info "$unit: $(systemctl is-active "$unit" 2>&1)/$(systemctl is-enabled "$unit" 2>&1)"
	done
	iwctl station "$DEV" show 2>/dev/null | sed -n '1,12p' | sed 's/^/   /'
}

if [ "$DRY_RUN" = "1" ]; then
	say "dry run — nothing will be changed"
	info "would write $NETWORKD_FILE (wlan: DHCP=yes, RouteMetric=600)"
	info "would disable+stop NetworkManager and wpa_supplicant"
	info "would enable+start iwd, then restart systemd-networkd"
	info "would re-associate to '${SSID:-<first known network>}' if needed"
	info "would require an IPv4 address on $DEV and a gateway ping before claiming success"
	say "now"
	report
	exit 0
fi

[ "$(id -u)" = "0" ] || { echo "run as root: sudo $0" >&2; exit 1; }

say "backup -> $STATE_DIR"
mkdir -p "$STATE_DIR"
[ -f "$NETWORKD_FILE" ] && cp -a "$NETWORKD_FILE" "$STATE_DIR/20-wlan.network.bak"
[ -f "$NM_CONF" ] && cp -a "$NM_CONF" "$STATE_DIR/wifi-backend.conf.bak"
for unit in iwd wpa_supplicant NetworkManager systemd-networkd; do
	printf '%s %s/%s\n' "$unit" "$(systemctl is-active "$unit" 2>&1)" "$(systemctl is-enabled "$unit" 2>&1)"
done >"$STATE_DIR/units.txt"
info "saved"

say "1/5 networkd vuelve a manejar wlan0"
networkd_profile >"$NETWORKD_FILE"
info "wrote $NETWORKD_FILE"

say "2/5 saco del medio a NetworkManager"
systemctl disable --now NetworkManager 2>/dev/null
info "NetworkManager: $(systemctl is-active NetworkManager 2>&1)/$(systemctl is-enabled NetworkManager 2>&1)"

say "3/5 saco a wpa_supplicant, levanto iwd"
systemctl disable --now wpa_supplicant 2>/dev/null
systemctl enable --now iwd 2>/dev/null
info "wpa_supplicant: $(systemctl is-active wpa_supplicant 2>&1) | iwd: $(systemctl is-active iwd 2>&1)"

say "4/5 networkd recarga y levanto el link"
systemctl daemon-reload
ip link set "$DEV" up 2>/dev/null
systemctl restart systemd-networkd 2>/dev/null

# iwd may come up with the radio down and nothing associated.
sleep 3
state=$(iwctl station "$DEV" show 2>/dev/null | sed 's/\x1b\[[0-9;]*m//g' \
	| sed -n 's/.*State *//p' | head -1 | sed 's/[[:space:]]*$//')
info "iwd state: ${state:-?}"
if [ "$state" != "connected" ]; then
	target="${SSID:-$(known_ssid)}"
	if [ -n "$target" ]; then
		warn "no asociado; conectando a '$target' con la red guardada"
		iwctl station "$DEV" connect "$target" >/dev/null 2>&1
		sleep 5
	else
		warn "iwd no tiene redes guardadas; hay que conectar a mano con iwctl"
	fi
fi

say "5/5 esperando dirección y gateway (hasta 60s)"
for i in $(seq 1 20); do
	sleep 3
	if have_ip && gateway_up; then
		say "LISTO — red de vuelta"
		info "ip: $(ip -4 -o addr show dev "$DEV" | awk '{print $4}')"
		info "ruta: $(ip route show default | head -1)"
		report
		exit 0
	fi
	info "t+$((i * 3))s ip=$(have_ip && echo sí || echo no) gw=$(gateway_up && echo ok || echo no)"
done

say "SIN RED — esto es todo lo que hay"
report
warn "backup en $STATE_DIR"
exit 2
