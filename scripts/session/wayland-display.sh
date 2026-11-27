#!/usr/bin/env bash
# Resolve the Wayland socket of the compositor that launched this script.
#
# Hyprland writes "<pid>\n<wayland socket>" into its instance lock file, and
# exports HYPRLAND_INSTANCE_SIGNATURE to every child process. Using the instance
# file instead of the first socket on disk keeps the target correct when several
# compositor instances are alive (for example after a TTY login).

resolve_wayland_display() {
	local runtime=${XDG_RUNTIME_DIR:-/run/user/$(id -u)}
	local socket=

	if [[ -n ${HYPRLAND_INSTANCE_SIGNATURE:-} ]]; then
		local lock="$runtime/hypr/$HYPRLAND_INSTANCE_SIGNATURE/hyprland.lock"
		if [[ -f $lock ]]; then
			socket=$(sed -n '2p' "$lock")
			[[ -S $runtime/$socket ]] && { printf '%s\n' "$socket"; return 0; }
		fi
	fi

	if [[ -n ${WAYLAND_DISPLAY:-} && -S $runtime/$WAYLAND_DISPLAY ]]; then
		printf '%s\n' "$WAYLAND_DISPLAY"
		return 0
	fi

	local newest
	newest=$(find "$runtime" -maxdepth 1 -type s -name 'wayland-[0-9]*' -printf '%T@ %f\n' 2>/dev/null \
		| sort -rn | head -n 1 | cut -d' ' -f2-)
	[[ -n $newest ]] && { printf '%s\n' "$newest"; return 0; }

	return 1
}

# Compositors run exec commands before exporting the socket, so retry briefly.
wait_for_wayland_display() {
	local attempt
	for ((attempt = 0; attempt < 100; attempt++)); do
		if resolve_wayland_display; then
			return 0
		fi
		sleep 0.1
	done
	return 1
}
