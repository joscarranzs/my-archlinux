#!/usr/bin/env bash
# Dejar el arranque de la red coherente antes de reiniciar.
#
# Qué arregla: NetworkManager puede tener un drop-in que lo hace arrancar después de
# iwd y, peor, arrastrarlo (`After=iwd.service` + `Wants=iwd.service`). Con el backend
# en wpa_supplicant, eso pone a iwd y a wpa_supplicant a pelear por la misma placa en
# cada arranque. El drop-in lo escriben los scripts de prueba de backend iwd; sobra en
# un sistema que ya usa wpa_supplicant.
#
# No toca la conexión actual: sólo archivos de configuración de arranque.
#
# Uso: sudo wifi-boot-fix.sh [--dry-run]
set -uo pipefail

readonly DROPIN_DIR=/etc/systemd/system/NetworkManager.service.d
readonly DROPIN=$DROPIN_DIR/10-after-iwd.conf
readonly NETWORKD_WLAN=/etc/systemd/network/20-wlan.network
readonly NM_CONF=/etc/NetworkManager/conf.d/wifi-backend.conf

DRY_RUN=0
[ "${1:-}" = "--dry-run" ] && DRY_RUN=1

say() { printf '\n== %s\n' "$*"; }
info() { printf '   %s\n' "$*"; }
fail=0
check() { # check <descripción> <condición ya evaluada: ok/ko>
	if [ "$2" = "ok" ]; then info "✔ $1"; else info "✘ $1"; fail=$((fail + 1)); fi
}

if [ "$DRY_RUN" = "1" ]; then
	say "dry run — nothing will be changed"
	if [ -f "$DROPIN" ]; then
		info "quitaría $DROPIN ($(systemctl show NetworkManager -p Wants -p After | tr ' ' '\n' | grep -c iwd) referencias a iwd)"
	else
		info "el drop-in ya no está"
	fi
	exit 0
fi

[ "$(id -u)" = "0" ] || { echo "corré: sudo $0" >&2; exit 1; }

say "quitando el drop-in que arrastra iwd al arranque"
if [ -f "$DROPIN" ]; then
	rm -f "$DROPIN"
	info "borrado $DROPIN"
	rmdir "$DROPIN_DIR" 2>/dev/null && info "directorio vacío eliminado"
else
	info "no estaba"
fi
systemctl daemon-reload

say "verificación del camino de arranque"
check "backend de NetworkManager es wpa_supplicant" \
	"$([ "$(grep -E '^wifi\.backend=' "$NM_CONF" 2>/dev/null | cut -d= -f2)" = "wpa_supplicant" ] && echo ok || echo ko)"
check "NetworkManager ya no menciona iwd (Wants/After)" \
	"$([ "$(systemctl show NetworkManager -p Wants -p After | tr ' ' '\n' | grep -c iwd)" = "0" ] && echo ok || echo ko)"
check "iwd deshabilitado (no arranca solo)" \
	"$([ "$(systemctl is-enabled iwd 2>&1)" = "disabled" ] && echo ok || echo ko)"
check "NetworkManager habilitado" \
	"$([ "$(systemctl is-enabled NetworkManager 2>&1)" = "enabled" ] && echo ok || echo ko)"
check "wpa_supplicant habilitado" \
	"$([ "$(systemctl is-enabled wpa_supplicant 2>&1)" = "enabled" ] && echo ok || echo ko)"
check "systemd-networkd no tiene perfil para wlan" \
	"$([ ! -f "$NETWORKD_WLAN" ] && echo ok || echo ko)"
psk=$(nmcli -f 802-11-wireless-security.psk connection show LIB-2396867-5GHz 2>/dev/null | grep -c '<hidden>')
check "el perfil conserva la contraseña" "$([ "$psk" -ge 1 ] && echo ok || echo ko)"
check "el perfil tiene autoconnect" \
	"$([ "$(nmcli -g connection.autoconnect connection show LIB-2396867-5GHz 2>/dev/null)" = "yes" ] && echo ok || echo ko)"

if [ "$fail" = "0" ]; then
	printf '\n   ✔ arranque coherente: NetworkManager + wpa_supplicant, sin iwd en el medio\n\n'
	exit 0
fi
printf '\n   ✘ %s chequeo(s) fallaron: no reinicies todavía\n\n' "$fail"
exit 2
