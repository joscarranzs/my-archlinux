#!/usr/bin/env bash
# BOTÓN DE PÁNICO — devolver la wifi con un solo comando, sin pensar.
#
#   sudo ~/.dotfiles/scripts/system/wifi-rescue.sh
#
# No lleva argumentos y no hace preguntas. Intenta dos caminos, en orden, y no dice
# "listo" hasta que hay dirección IP y el gateway responde:
#
#   Fase A (lo moderno, lo que corre hoy): NetworkManager con wpa_supplicant.
#       - reescribe el backend a wpa_supplicant
#       - levanta wpa_supplicant y NetworkManager
#       - si falta el perfil con la contraseña, lo reconstruye con la PSK que guarda iwd
#       - NO toca iwd: en pánico no se limpia nada, solo se recupera
#
#   Fase B (lo histórico, lo que funcionó durante meses): iwd + systemd-networkd.
#       - delega en wifi-emergency.sh, que no depende de NetworkManager ni de nmcli
#
# Si las dos fallan, imprime el estado completo y sale con 2: en ese punto la máquina
# necesita una terminal y manos, no otro script.
set -uo pipefail

readonly NM_CONF=/etc/NetworkManager/conf.d/wifi-backend.conf
readonly DEV=wlan0
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly HERE

say() { printf '\n\033[1m== %s\033[0m\n' "$*"; }
info() { printf '   %s\n' "$*"; }
warn() { printf '   ! %s\n' "$*" >&2; }
ok() { printf '\n\033[1m   ✔ %s\033[0m\n\n' "$*"; }
bad() { printf '\n\033[1m   ✘ %s\033[0m\n\n' "$*"; }

have_ip() { [ -n "$(ip -4 -o addr show dev "$DEV" 2>/dev/null | awk '{print $4}')" ]; }
gateway_up() {
	local gw
	gw=$(ip route show default 2>/dev/null | awk '{print $3}' | head -1)
	[ -n "$gw" ] && ping -c1 -W2 "$gw" >/dev/null 2>&1
}
# La IP puede ser la que dejó systemd-networkd: para cantar "online por
# wpa_supplicant" hay que ver a NetworkManager diciendo que la placa está conectada.
nm_connected() { [ "$(nmcli -t -f DEVICE,STATE device 2>/dev/null | awk -F: -v d="$DEV" '$1==d{print $2}')" = "connected" ]; }

show() {
	info "wlan0: $(ip -br addr show "$DEV" 2>/dev/null | awk '{print $2, $3}')"
	info "ruta:  $(ip route show default 2>/dev/null | head -1)"
	for u in NetworkManager wpa_supplicant iwd systemd-networkd; do
		info "$u: $(systemctl is-active "$u" 2>&1)/$(systemctl is-enabled "$u" 2>&1)"
	done
}

# La SSID y la PSK que ya conocemos: primero el perfil de NM, si no el almacén de iwd.
known_ssid() {
	local s
	s=$(nmcli -t -f ACTIVE,SSID device wifi 2>/dev/null | awk -F: '$1=="yes"{print $2; exit}')
	[ -n "$s" ] && { printf '%s' "$s"; return; }
	s=$(nmcli -t -f NAME,TYPE connection show 2>/dev/null | awk -F: '$2=="802-11-wireless"{print $1; exit}')
	[ -n "$s" ] && { printf '%s' "$s"; return; }
	# iwctl colorea su salida: sin quitar los escapes ANSI, $1 es un código de color y
	# el nombre no aparece nunca.
	iwctl known-networks list 2>/dev/null | sed 's/\x1b\[[0-9;]*m//g' \
		| awk 'NF && $0 !~ /Known Networks|^ *-+|^ *Name/ {print $1; exit}'
}

psk_for() {
	local ssid="$1" psk
	psk=$(nmcli -s -g 802-11-wireless-security.psk connection show "$ssid" 2>/dev/null)
	[ -n "$psk" ] && { printf '%s' "$psk"; return; }
	[ -r "/var/lib/iwd/$ssid.psk" ] && sed -n 's/^PreSharedKey=//p' "/var/lib/iwd/$ssid.psk" | head -1
}

if [ "$(id -u)" != "0" ]; then
	echo "corré: sudo $0" >&2
	exit 1
fi

SSID=$(known_ssid)
say "wifi-rescue — ssid conocido: '${SSID:-ninguno}'"
show

# ------------------------------------------------------------------ fase A
say "FASE A — NetworkManager + wpa_supplicant"
mkdir -p "$(dirname "$NM_CONF")"
cat >"$NM_CONF" <<-'CONF'
	[device]
	wifi.backend=wpa_supplicant
CONF
info "backend escrito: wpa_supplicant"

systemctl enable wpa_supplicant 2>/dev/null
systemctl start wpa_supplicant 2>/dev/null
info "wpa_supplicant: $(systemctl is-active wpa_supplicant 2>&1)"
systemctl enable NetworkManager 2>/dev/null
systemctl restart NetworkManager 2>/dev/null
info "NetworkManager: $(systemctl is-active NetworkManager 2>&1)"

# Si el perfil perdió la contraseña (o el perfil entero falta), se reconstruye
# con la que guarda iwd. nmcli devuelve vacío tanto si el perfil no existe como
# si existe sin PSK: ambos casos deben entrar aquí.
PSK_CURRENT=""
if [ -n "$SSID" ]; then
	PSK_CURRENT=$(nmcli -s -g 802-11-wireless-security.psk connection show "$SSID" 2>/dev/null || true)
fi
if [ -n "$SSID" ] && [ -z "$PSK_CURRENT" ]; then
	PSK=$(psk_for "$SSID")
	if [ -n "$PSK" ]; then
		if nmcli -t -f NAME connection show 2>/dev/null | grep -qxF -- "$SSID"; then
			nmcli connection modify "$SSID" wifi-sec.psk "$PSK" 2>/dev/null
			info "contraseña restaurada en el perfil existente"
		else
			nmcli connection add type wifi con-name "$SSID" ifname "$DEV" ssid "$SSID" \
				wifi-sec.key-mgmt wpa-psk wifi-sec.psk "$PSK" connection.autoconnect yes 2>/dev/null
			info "perfil recreado con la contraseña"
		fi
	fi
fi

info "esperando la conexión (hasta 45s)"
for i in $(seq 1 15); do
	sleep 3
	nm_connected && gateway_up && break
	info "t+$((i * 3))s ip=$(have_ip && echo sí || echo no) gw=$(gateway_up && echo ok || echo no)"
done

if nm_connected && gateway_up; then
	ok "ONLINE por wpa_supplicant — $(ip -4 -o addr show dev "$DEV" | awk '{print $4}')"
	show
	exit 0
fi
warn "la fase A no logró conexión; paso a la fase B"

# ------------------------------------------------------------------ fase B
say "FASE B — iwd + systemd-networkd (el camino histórico)"
if [ -x "$HERE/wifi-emergency.sh" ]; then
	"$HERE/wifi-emergency.sh" ${SSID:+--ssid "$SSID"}
	rc=$?
	if [ "$rc" = "0" ]; then
		ok "ONLINE por iwd + networkd — $(ip -4 -o addr show dev "$DEV" | awk '{print $4}')"
		exit 0
	fi
else
	warn "no encontré $HERE/wifi-emergency.sh"
fi

# --------------------------------------------------------------- sin salida
bad "SIN RED — las dos fases fallaron"
show
[ -n "$SSID" ] && info "red conocida: $SSID"
info "a mano: sudo iwctl station $DEV connect '$SSID'   |   o: sudo wifi-emergency.sh"
exit 2
