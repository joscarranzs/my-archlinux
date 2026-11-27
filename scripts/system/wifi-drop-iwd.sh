#!/usr/bin/env bash
# Remove iwd from the wireless stack without losing the interface.
#
# The reason stopping iwd has always killed the wifi on this host is documented, not
# mysterious:
#
#   * iwd destroys and re-creates the wireless netdev it manages. Gentoo's wiki puts
#     it plainly: "When iwd terminates, it destroys the wireless interface it
#     created."
#   * iwd.config(5): `[DriverQuirks] DefaultInterface=true` means "Do not allow iwd
#     to destroy / recreate wireless interfaces at startup, including default
#     interfaces". The older spelling is `[General] UseDefaultInterface=true`
#     (deprecated).
#   * Arch BBS #260888 is the same symptom: wlan0 disappears when iwd stops, and
#     NetworkManager then reports the device as nonexistent.
#
# So the order matters: set the quirk, let iwd restart once (now it stops owning the
# netdev lifecycle), and only then stop iwd. Every step is verified, and the recovery
# path is the one that already worked on this machine: bring iwd back and restart
# systemd-networkd, which re-associates and re-DHCPs.
#
# Usage: sudo wifi-drop-iwd.sh [--dry-run] [--yes]
# Exit:  0 done and verified, 1 refused, 2 aborted mid-way and recovered, 3 recovery failed
set -uo pipefail

readonly IWD_CONF=/etc/iwd/main.conf
readonly NM_CONF=/etc/NetworkManager/conf.d/wifi-backend.conf
readonly DEV=wlan0

DRY_RUN=0
ASSUME_YES=0
for arg in "$@"; do
	case "$arg" in
		--dry-run) DRY_RUN=1 ;;
		--yes | -y) ASSUME_YES=1 ;;
		-h | --help) sed -n '2,23p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
		*) echo "unknown argument: $arg" >&2; exit 1 ;;
	esac
done

say() { printf '\n== %s\n' "$*"; }
info() { printf '   %s\n' "$*"; }
warn() { printf '   ! %s\n' "$*" >&2; }

STAMP=$(date +%Y%m%d-%H%M%S)
STATE_DIR="/var/tmp/wifi-drop-iwd-$STAMP"

have_ip() { [ -n "$(ip -4 -o addr show dev "$DEV" 2>/dev/null | awk '{print $4}')" ]; }
iface_exists() { [ -e "/sys/class/net/$DEV" ]; }
link_ok() {
	local gw
	gw=$(ip route show default 2>/dev/null | awk '{print $3}' | head -1)
	[ -n "$gw" ] && ping -c1 -W2 "$gw" >/dev/null 2>&1
}

status_line() {
	info "iface=$(iface_exists && echo sí || echo NO) ip=$(have_ip && ip -4 -o addr show dev "$DEV" | awk '{print $4}' || echo none) gw=$(link_ok && echo ok || echo no)"
}

wait_link() {
	local tries="${1:-10}" i
	for ((i = 0; i < tries; i++)); do
		sleep 2
		status_line
		if iface_exists && have_ip && link_ok; then
			return 0
		fi
	done
	return 1
}

backend() { grep -E '^wifi\.backend=' "$NM_CONF" 2>/dev/null | cut -d= -f2; }

recover() {
	say "RECOVERY: devolviendo la red por la vía que ya funciona (iwd + networkd)"
	systemctl enable --now iwd 2>/dev/null
	systemctl restart systemd-networkd 2>/dev/null
	if wait_link 12; then
		say "recuperado"
		status_line
		return 0
	fi
	warn "no volvió con iwd; corré: sudo ~/.dotfiles/scripts/system/wifi-emergency.sh"
	return 1
}

if [ "$DRY_RUN" = "1" ]; then
	say "dry run — nothing will be changed"
	info "iwd config: $IWD_CONF $([ -f "$IWD_CONF" ] && echo '(existe)' || echo '(no existe)')"
	info "NetworkManager backend: $(backend || echo '(sin conf)')"
	info "plan: escribir [DriverQuirks] DefaultInterface=true -> restart iwd -> verificar"
	info "      -> si el link sigue: disable --now iwd -> verificar otra vez"
	info "      -> si algo se cae: enable --now iwd + restart systemd-networkd (recuperación probada)"
	say "ahora"; status_line
	for u in iwd wpa_supplicant NetworkManager systemd-networkd; do
		info "$u: $(systemctl is-active "$u" 2>&1)/$(systemctl is-enabled "$u" 2>&1)"
	done
	exit 0
fi

[ "$(id -u)" = "0" ] || { echo "run as root: sudo $0" >&2; exit 1; }

if [ "$ASSUME_YES" != "1" ]; then
	printf 'Esto le dice a iwd que no destruya la interfaz, reinicia iwd una vez y después lo\ndesactiva. Cada paso se verifica y, si el link se cae, se recupera por la vía que ya\nequivale a tu configuración actual. Continuar? [y/N] '
	read -r answer
	[[ "$answer" == [yY]* ]] || { echo "aborted"; exit 1; }
fi

# Refuse to run on a backend that needs iwd: stopping it would be the whole problem.
if [ "$(backend)" = "iwd" ]; then
	warn "NetworkManager todavía está en el backend iwd ($NM_CONF)"
	warn "parar iwd con ese backend deja la placa sin supplicant: primero cambiá el backend"
	exit 1
fi

mkdir -p "$STATE_DIR"
[ -f "$IWD_CONF" ] && cp -a "$IWD_CONF" "$STATE_DIR/main.conf.bak"
for unit in iwd wpa_supplicant NetworkManager systemd-networkd; do
	printf '%s %s/%s\n' "$unit" "$(systemctl is-active "$unit" 2>&1)" "$(systemctl is-enabled "$unit" 2>&1)"
done >"$STATE_DIR/units.txt"
info "backup en $STATE_DIR"

say "1/4 iwd deja de ser dueño del netdev"
mkdir -p /etc/iwd
cat >"$IWD_CONF" <<-'CONF'
	# Do not let iwd destroy and re-create the wireless interface. Without this, stopping
	# (or restarting) iwd removes the netdev it created and NetworkManager is left with
	# "Device wlan0 does not exist" -- the modem of every failed attempt to retire iwd
	# on this host. iwd.config(5): "[DriverQuirks] DefaultInterface=true -- Do not allow
	# iwd to destroy / recreate wireless interfaces at startup". The pre-3.x spelling
	# was [General] UseDefaultInterface=true (deprecated).
	[DriverQuirks]
	DefaultInterface=true
CONF
info "wrote $IWD_CONF"

say "2/4 reinicio iwd (la interfaz tiene que sobrevivir)"
systemctl restart iwd
info "iwd: $(systemctl is-active iwd)"
if ! wait_link 8; then
	warn "el link no volvió tras reiniciar iwd"
	recover || exit 3
	exit 2
fi
info "el link sigue vivo después del restart de iwd"

say "3/4 ahora sí: desactivo iwd"
systemctl disable --now iwd
info "iwd: $(systemctl is-active iwd)/$(systemctl is-enabled iwd 2>&1)"

say "4/4 verificando que la red sobreviva a la salida de iwd"
if wait_link 10; then
	say "LISTO — iwd fuera del camino y la red intacta"
	status_line
	info "backend: $(backend)"
	info "wpa_supplicant: $(systemctl is-active wpa_supplicant 2>&1)/$(systemctl is-enabled wpa_supplicant 2>&1)"
	info "backup: $STATE_DIR"
	exit 0
fi

warn "la red no sobrevivió a la salida de iwd"
recover || exit 3
exit 2
