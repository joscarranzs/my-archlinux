#!/usr/bin/env bash
# Dejar UN solo dueño de wlan0: NetworkManager, con wpa_supplicant de backend.
#
# El estado que este script arregla (medido en esta máquina):
#   ip route  -> DOS default routes: src .201 (NetworkManager) y src .200 (networkd)
#   networkctl -> State routable, Address .200, Network File 20-wlan.network
#   nmcli      -> wlan0:connected
# O sea: dos clientes DHCP sobre la misma placa. Anda por casualidad y se rompe solo.
#
# No toca la asociación mientras haya una: primero le saca a networkd el derecho a
# configurar wlan0 (NM ya tiene su propia dirección y su ruta), y sólo después retira
# iwd, que ya quedó configurado con [DriverQuirks] DefaultInterface=true para no
# destruir el netdev al salir.
#
# Uso:  sudo wifi-single-owner.sh [--dry-run] [--yes]
# Exit: 0 dueño único y verificado, 1 rechazado, 2 abortado y recuperado, 3 sin red.
set -uo pipefail

readonly NETWORKD_WLAN=/etc/systemd/network/20-wlan.network
readonly NM_CONF=/etc/NetworkManager/conf.d/wifi-backend.conf
readonly DEV=wlan0
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly HERE

DRY_RUN=0
ASSUME_YES=0
for arg in "$@"; do
	case "$arg" in
		--dry-run) DRY_RUN=1 ;;
		--yes | -y) ASSUME_YES=1 ;;
		-h | --help) sed -n '2,16p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
		*) echo "argumento desconocido: $arg" >&2; exit 1 ;;
	esac
done

say() { printf '\n== %s\n' "$*"; }
info() { printf '   %s\n' "$*"; }
warn() { printf '   ! %s\n' "$*" >&2; }

STAMP=$(date +%Y%m%d-%H%M%S)
STATE_DIR="/var/tmp/wifi-single-owner-$STAMP"

nm_connected() { [ "$(nmcli -t -f DEVICE,STATE device 2>/dev/null | awk -F: -v d="$DEV" '$1==d{print $2}')" = "connected" ]; }
have_ip() { [ -n "$(ip -4 -o addr show dev "$DEV" 2>/dev/null | awk '{print $4}')" ]; }
gateway_up() { local gw; gw=$(ip route show default 2>/dev/null | awk '{print $3}' | head -1); [ -n "$gw" ] && ping -c1 -W2 "$gw" >/dev/null 2>&1; }
default_routes() { ip route show default 2>/dev/null | wc -l; }
networkd_owns_wlan() {
	networkctl status "$DEV" 2>/dev/null | grep -qE "Network File:.*20-wlan.network" &&
		networkctl status "$DEV" 2>/dev/null | grep -qE "^ *Address:"
}
ssid() { nmcli -t -f ACTIVE,SSID device wifi 2>/dev/null | awk -F: '$1=="yes"{print $2; exit}'; }

status_block() {
	info "nmcli:      $(nmcli -t -f DEVICE,STATE,CONNECTION device 2>/dev/null | grep "^$DEV:" || echo 'sin dispositivo')"
	info "dirección:  $(ip -4 -o addr show dev "$DEV" 2>/dev/null | awk '{print $4}' | paste -sd' ')"
	info "rutas def:  $(default_routes)"
	info "networkd:   $(networkd_owns_wlan && echo 'maneja wlan0 (NO debería)' || echo 'no maneja wlan0 (correcto)')"
	info "iwd:        $(systemctl is-active iwd 2>&1)/$(systemctl is-enabled iwd 2>&1)"
}

wait_owner() {
	local tries="${1:-15}" i
	for i in $(seq 1 "$tries"); do
		sleep 2
		if nm_connected && gateway_up; then
			return 0
		fi
		info "t+$((i * 2))s nmcli=$(nm_connected && echo connected || echo no) ip=$(have_ip && echo sí || echo no) gw=$(gateway_up && echo ok || echo no)"
	done
	return 1
}

recover() {
	say "RECOVERY — devolviendo la red con el botón de pánico"
	if [ -x "$HERE/wifi-rescue.sh" ]; then
		"$HERE/wifi-rescue.sh"
		return $?
	fi
	warn "no encontré wifi-rescue.sh; a mano: sudo iwctl station $DEV connect '$(ssid)'"
	return 1
}

if [ "$DRY_RUN" = "1" ]; then
	say "dry run — nothing will be changed"
	info "backend NM: $(grep -E '^wifi\.backend=' "$NM_CONF" 2>/dev/null | cut -d= -f2 || echo '?')"
	info "quirk iwd:  $(grep -q DefaultInterface /etc/iwd/main.conf 2>/dev/null && echo 'sí' || echo 'NO (haría falta)')"
	say "ahora"; status_block
	info "plan: mover 20-wlan.network -> verificar que NM sostenga la conexión"
	info "      -> disable --now iwd -> verificar dueño único"
	exit 0
fi

[ "$(id -u)" = "0" ] || { echo "corré: sudo $0" >&2; exit 1; }

if [ "$(grep -E '^wifi\.backend=' "$NM_CONF" 2>/dev/null | cut -d= -f2)" != "wpa_supplicant" ]; then
	warn "el backend de NetworkManager no es wpa_supplicant; corré primero wifi-rescue.sh"
	exit 1
fi
if ! nm_connected; then
	warn "NetworkManager no está conectado; este script asume que NM sostiene el link"
	warn "corré primero: sudo wifi-rescue.sh"
	exit 1
fi
if ! grep -q DefaultInterface /etc/iwd/main.conf 2>/dev/null; then
	warn "falta [DriverQuirks] DefaultInterface=true en /etc/iwd/main.conf"
	warn "sin eso, parar iwd puede destruir la interfaz. Corré: sudo wifi-drop-iwd.sh"
	exit 1
fi

if [ "$ASSUME_YES" != "1" ]; then
	printf 'Va a dejar a NetworkManager como único dueño de wlan0 y a retirar iwd.\nCada paso se verifica; si algo se cae, corre el botón de pánico. Continuar? [y/N] '
	read -r answer
	[[ "$answer" == [yY]* ]] || { echo "aborted"; exit 1; }
fi

say "estado de partida"; status_block
mkdir -p "$STATE_DIR"
[ -f "$NETWORKD_WLAN" ] && cp -a "$NETWORKD_WLAN" "$STATE_DIR/20-wlan.network.bak"
for u in NetworkManager wpa_supplicant iwd systemd-networkd; do
	printf '%s %s/%s\n' "$u" "$(systemctl is-active "$u" 2>&1)" "$(systemctl is-enabled "$u" 2>&1)"
done >"$STATE_DIR/units.txt"
info "backup en $STATE_DIR"

say "1/3 networkd deja de configurar wlan0 (NM ya tiene su dirección)"
if [ -f "$NETWORKD_WLAN" ]; then
	mv -f "$NETWORKD_WLAN" "$STATE_DIR/20-wlan.network.moved"
	info "movido $NETWORKD_WLAN"
else
	info "ya no estaba"
fi
systemctl restart systemd-networkd
sleep 2
status_block

say "2/3 verificando que NetworkManager sostenga la conexión"
if ! wait_owner 15; then
	warn "NM perdió la conexión al soltar networkd"
	TARGET=$(ssid)
	if [ -n "$TARGET" ]; then
		info "levantando el perfil '$TARGET' con NM"
		nmcli connection up "$TARGET" >/dev/null 2>&1
	fi
	if ! wait_owner 15; then
		warn "no se pudo sostener por NM"
		# devolverle networkd su archivo antes de recuperar
		[ -f "$STATE_DIR/20-wlan.network.moved" ] && mv -f "$STATE_DIR/20-wlan.network.moved" "$NETWORKD_WLAN"
		systemctl restart systemd-networkd
		recover || exit 3
		exit 2
	fi
fi
info "NM conectado y con ruta propia"

say "3/3 retirando iwd (ya no es dueño del netdev: quirk aplicado)"
systemctl disable --now iwd 2>/dev/null
info "iwd: $(systemctl is-active iwd 2>&1)/$(systemctl is-enabled iwd 2>&1)"
sleep 2

# Medido en esta máquina: la salida de iwd SIEMPRE tumba la asociación, incluso con el
# quirk y aunque iwd no sea el supplicant conectado -- el quirk salva el netdev, no la
# sesión 802.11. Lo que hay que hacer es volver a activar el perfil enseguida, no esperar
# veinte segundos mirando cómo no vuelve.
if ! wait_owner 3; then
	TARGET=$(ssid)
	if [ -n "$TARGET" ]; then
		info "la salida de iwd cortó el link (esperado); reactivando '$TARGET' con NM"
		nmcli connection up "$TARGET" >/dev/null 2>&1
	fi
	if ! wait_owner 15; then
		warn "no volvió tras reactivar el perfil"
		recover || exit 3
		exit 2
	fi
fi

say "verificación final"
status_block
if nm_connected && gateway_up && ! networkd_owns_wlan && [ "$(default_routes)" -le 1 ]; then
	printf '\n   ✔ DUEÑO ÚNICO: NetworkManager (%s, %s), sin networkd ni iwd en el medio\n\n' \
		"$(ip -4 -o addr show dev "$DEV" | awk '{print $4}')" "$(ssid)"
	info "backup: $STATE_DIR"
	exit 0
fi
warn "el estado final no es el esperado; mirá el bloque de arriba"
exit 2
