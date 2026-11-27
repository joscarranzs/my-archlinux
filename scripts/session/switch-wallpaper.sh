#!/usr/bin/env bash
# Switch the desktop wallpaper between the images in ~/.wallpapers/current.
#
# Usage: switch-wallpaper.sh [next|FILE]
#   next (default)  cycle to the wallpaper that follows the current one
#   FILE            copy that specific image, by name inside the directory
set -euo pipefail

DIR="${HOME}/.wallpapers/current"
DEFAULT="${DIR}/default-background"

mapfile -t images < <(
    find "${DIR}" -maxdepth 1 -type f \
        \( -name '*.png' -o -name '*.jpg' -o -name '*.jpeg' -o -name '*.webp' \) \
        ! -name 'default-background' | sort
)

if [ "${#images[@]}" -eq 0 ]; then
    echo "switch-wallpaper: no images found in ${DIR}" >&2
    exit 1
fi

target=""
requested="${1:-next}"

if [ "${requested}" != "next" ]; then
    for candidate in "${images[@]}"; do
        if [ "$(basename "${candidate}")" = "${requested}" ]; then
            target="${candidate}"
            break
        fi
    done
    if [ -z "${target}" ]; then
        echo "switch-wallpaper: '${requested}' is not one of: $(basename -a "${images[@]}" | tr '\n' ' ')" >&2
        exit 1
    fi
else
    # Resolve the current image by content: `cmp` follows the symlink, so this
    # also matches a default-background that was copied by hand.
    current=""
    for candidate in "${images[@]}"; do
        if cmp -s "${candidate}" "${DEFAULT}"; then
            current="${candidate}"
            break
        fi
    done

    target="${images[0]}"
    if [ -n "${current}" ]; then
        for index in "${!images[@]}"; do
            if [ "${images[index]}" = "${current}" ]; then
                target="${images[$(((index + 1) % ${#images[@]}))]}"
                break
            fi
        done
    fi
fi

# A symlink, not a copy: the active wallpaper is always one of the pooled
# images, so storing a second copy of it would double its bytes in every commit.
# The Quickshell surface reads this fixed path and follows the link.
ln -sfn -- "$(basename "${target}")" "${DEFAULT}"
echo "wallpaper -> $(basename "${target}")"

# The Quickshell wallpaper surface holds a fixed image path, so it has to be
# restarted to pick up the new content. The wrapper (quickshell-wallpaper.sh)
# treats anything other than a clean exit or SIGHUP/SIGINT/SIGTERM as a crash
# and respawns it, so SIGKILL is the signal that triggers a reload. The PID
# comes from the wrapper's pidfile: the old pgrep -f match also caught commands
# that just mentioned the path.
PIDFILE="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/quickshell-wallpaper.pid"
if [ -r "${PIDFILE}" ]; then
    renderer="$(cat "${PIDFILE}")"
    cmdline=""
    if [ -r "/proc/${renderer}/cmdline" ]; then
        cmdline="$(tr '\0' ' ' <"/proc/${renderer}/cmdline" 2>/dev/null || true)"
    fi
    if [[ "${renderer}" =~ ^[0-9]+$ ]] && [[ "${cmdline}" == *"quickshell/wallpaper/shell.qml"* ]]; then
        kill -9 "${renderer}" 2>/dev/null || true
    fi
fi
