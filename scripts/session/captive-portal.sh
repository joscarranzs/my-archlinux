#!/usr/bin/env bash
# Open the captive-portal login page when NetworkManager reports a portal.
#
# University/airport/hotel wifi is often open but gated: DHCP works, every HTTP
# request is hijacked to a login page. Phones pop that page automatically; on
# this desktop nothing did. NetworkManager already probes for it (Arch ships
# /usr/lib/NetworkManager/conf.d/20-connectivity.conf, uri=ping.archlinux.org)
# and reports connectivity 'portal' when the probe comes back wrong. This
# watcher turns that state into a browser tab: it finds where the probe is
# redirected and opens it with xdg-open (chromium).
#
# Safe to run twice: the lock is held for the life of the watcher, so the
# session autostart plus a manual run do not stack two watchers.
#
# Subcommands:
#   (none) | watch   run the watcher (default)
#   open             force the discovery + open path now, ignoring the cooldown
#   status           print connectivity, the probe URI and where it would open
set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/wayland-display.sh"

RUNTIME="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
LOCK="$RUNTIME/captive-portal.lock"
LOG="$RUNTIME/captive-portal.log"
STAMP="$RUNTIME/captive-portal.last"
COOLDOWN=60

log() { printf '%s %s\n' "$(date '+%F %T')" "$*" >>"$LOG"; }

# The probe URI NetworkManager itself uses, read from the effective config so
# this script never drifts from what NM actually checks. CAPTIVE_CHECK_URI
# overrides it (tests point it at a local redirect server).
check_uri() {
	if [[ -n ${CAPTIVE_CHECK_URI:-} ]]; then
		printf '%s\n' "$CAPTIVE_CHECK_URI"
		return
	fi
	NetworkManager --print-config 2>/dev/null | awk -F= '/^uri=/ {print $2; exit}'
}

# Where the login page actually is: the probe's redirect first, then a
# plain-HTTP canary (neverssl.com exists for exactly this), then the probe
# itself -- a transparent interception serves the login page on any URL.
portal_url() {
	local uri redirect
	uri=$(check_uri)
	[[ -n $uri ]] || return 1
	redirect=$(curl -s -o /dev/null -w '%{redirect_url}' --max-time 8 "$uri" || true)
	if [[ -n $redirect ]]; then
		printf '%s\n' "$redirect"
		return
	fi
	redirect=$(curl -s -o /dev/null -w '%{redirect_url}' --max-time 8 http://neverssl.com || true)
	if [[ -n $redirect ]]; then
		printf '%s\n' "$redirect"
		return
	fi
	printf '%s\n' "$uri"
}

# open_portal [force]: discover the URL and hand it to the browser. The stamp
# file debounces flapping portals; 'force' (the manual subcommand) skips it.
# The Wayland socket is resolved HERE, not at startup: with linger enabled the
# watcher outlives the session it started in, and a socket cached at boot would
# point at a dead compositor after the next login.
open_portal() {
	local now last url
	now=$(date +%s)
	if [[ ${1:-} != force ]]; then
		last=$(cat "$STAMP" 2>/dev/null || echo 0)
		if ((now - last < COOLDOWN)); then
			log "cooldown: skip open ($((now - last))s since the last one)"
			return
		fi
	fi
	url=$(portal_url) || { log "no probe uri configured; nothing to open"; return 1; }
	if ! WAYLAND_DISPLAY=$(resolve_wayland_display); then
		log "no Wayland socket; cannot open a browser"
		return 1
	fi
	export WAYLAND_DISPLAY
	printf '%s\n' "$now" >"$STAMP"
	log "opening portal: $url"
	notify-send -a "Captive portal" -i network-wireless \
		"Network login required" "Opening the login page" || true
	xdg-open "$url" >/dev/null 2>&1 || log "xdg-open failed for $url"
	# Re-probe while the portal holds so the state flips to full soon after the
	# user logs in, instead of waiting out NM's 300 s interval. Bounded: 20
	# tries, 15 s apart. fd 9 is closed so this child never holds the lock.
	(
		exec 9>&-
		for ((i = 0; i < 20; i++)); do
			sleep 15
			[[ $(nmcli -t -f CONNECTIVITY general) == portal ]] || exit 0
			nmcli networking connectivity check >/dev/null 2>&1 || true
		done
	) &
}

watch() {
	log "watching (probe: $(check_uri))"
	# NM may already sit behind a portal when the watcher starts (it autostarts
	# with the session, which can be after the wifi connected).
	if [[ $(nmcli -t -f CONNECTIVITY general) == portal ]]; then
		open_portal || true
	fi
	while :; do
		# nmcli monitor prints one line per change; the connectivity line is
		# exactly "Connectivity is now '<state>'". When NM restarts the monitor
		# exits: the outer loop brings it back. pipefail + errexit would kill
		# the watcher on that exit, so the pipeline is guarded.
		nmcli monitor 2>>"$LOG" | while IFS= read -r line; do
			case $line in
			*"Connectivity is now 'portal'"*) open_portal || true ;;
			esac
		done || true
		sleep 2
	done
}

case "${1:-watch}" in
watch)
	exec 9>"$LOCK"
	if ! flock -n 9; then
		exit 0
	fi
	watch
	;;
open)
	open_portal force
	;;
status)
	printf 'connectivity: %s\n' "$(nmcli -t -f CONNECTIVITY general)"
	printf 'probe uri:    %s\n' "$(check_uri)"
	if url=$(portal_url); then
		printf 'would open:   %s\n' "$url"
	fi
	;;
*)
	printf 'usage: %s [watch|open|status]\n' "$0" >&2
	exit 1
	;;
esac
