#!/usr/bin/env bash
# Install the Arch SDDM theme and its Wayland greeter configuration.
# Run as root: sudo ./scripts/system/install-sddm.sh
#
# The theme is copied, not symlinked: the greeter runs as the `sddm` user and
# cannot traverse a home directory. Re-run this script after every
# `apply-theme.py` run that touches config/sddm/, or the greeter keeps the old
# palette.

set -euo pipefail

if [[ $EUID -ne 0 ]]; then
    echo "This script must run as root (sudo $0)" >&2
    exit 1
fi

# readlink -f: invoked through the ~/.scripts symlink, BASH_SOURCE still carries
# the symlink path, and dirname/../.. would climb to ~ instead of the repo.
REPO="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/../.." && pwd)"
THEME_SRC="$REPO/config/sddm/arch"
THEME_DST="/usr/share/sddm/themes/arch"
GREETER_CONF_SRC="$REPO/config/sddm/hyprland.lua"
GREETER_CONF_DST="/usr/share/sddm/hyprland.lua"
CONF_DIR="/etc/sddm.conf.d"
SYS_FONT_DIR="/usr/share/fonts/TTF"

# Font families the theme renders with: the UI face on the unlock card and the
# icon face for its glyphs. The greeter runs as the `sddm` user, which cannot
# read a home directory, so a family that is not already installed system-wide
# gets mirrored into /usr/share/fonts below. Both of these come from pacman
# (ttf-jetbrains-mono-nerd, ttf-material-symbols-variable) and are visible to the
# greeter as they are; the mirror step is what covers a family that is not.
THEME_FONTS=("JetBrainsMono Nerd Font" "Material Symbols Rounded")

if [[ ! -f "$THEME_SRC/Main.qml" ]]; then
    echo "Missing $THEME_SRC/Main.qml - run ./scripts/theme/apply-theme.py first" >&2
    exit 1
fi

# The generated token file is the theme's palette and ladder. A Main.qml that
# imports it with no file beside it loads as a blank screen.
if [[ ! -f "$THEME_SRC/GreeterAppearance.qml" ]]; then
    echo "Missing $THEME_SRC/GreeterAppearance.qml - run ./scripts/theme/apply-theme.py first" >&2
    exit 1
fi

# Theme
# This is the only recursive delete in the repo: refuse to run it against
# anything but the greeter theme directory, so a bad THEME_DST cannot take
# something else with it.
case "$THEME_DST" in
    /usr/share/sddm/themes/?*) ;;
    *)
        echo "Refusing to replace '$THEME_DST': it is not a greeter theme directory" >&2
        exit 1
        ;;
esac
rm -rf "$THEME_DST"
mkdir -p "$THEME_DST"
cp -r "$THEME_SRC/." "$THEME_DST/"
chmod -R a+rX "$THEME_DST"

# Wayland greeter compositor config
install -Dm644 "$GREETER_CONF_SRC" "$GREETER_CONF_DST"

# SDDM configuration
mkdir -p "$CONF_DIR"

cat >"$CONF_DIR/10-wayland.conf" <<'EOF'
[General]
DisplayServer=wayland

[Wayland]
CompositorCommand=start-hyprland -- --config /usr/share/sddm/hyprland.lua
EOF

# Remove any previously installed autologin drop-in for security.
rm -f "$CONF_DIR/20-autologin.conf"

cat >"$CONF_DIR/30-theme.conf" <<'EOF'
[Theme]
Current=arch
EOF

# Fonts: root's fontconfig does not read the invoking user's local fonts, which
# is exactly what the sddm user sees. Mirror the theme families into
# /usr/share/fonts so the greeter renders with the theme font instead of a
# fallback.
#
# Never skip a family because `fc-match` already finds it system-wide: that
# leaves the mirror at whatever the user-side font was the first time, so
# updating ~/.local/share/fonts/SpaceGrotesk-VF.ttf silently keeps the greeter
# on the old face. Compare content instead and copy only on a real difference.
USER_FONT_DIR=""
if [[ -n ${SUDO_USER:-} ]]; then
    USER_HOME="$(getent passwd "$SUDO_USER" | cut -d: -f6)"
    USER_FONT_DIR="$USER_HOME/.local/share/fonts"
fi

# Names this script mirrored on the previous run. Only entries listed here are
# ever deleted, so a font installed by pacman or by hand is never touched.
MIRROR_MANIFEST="$SYS_FONT_DIR/.mirrored-fonts"
declare -A mirrored=()

fonts_changed=0
for family in "${THEME_FONTS[@]}"; do
    if [[ -z $USER_FONT_DIR || ! -d $USER_FONT_DIR ]]; then
        echo "warning: no user font dir found, cannot mirror '$family'" >&2
        continue
    fi
    # `fc-list FAMILY file` appends ": " to every path, so asking for the "file"
    # format yields strings that never pass `-f`; the copy silently matched
    # nothing while the summary claimed success. Use an explicit format.
    mapfile -t font_files < <(
        sudo -u "$SUDO_USER" env HOME="$USER_HOME" \
            fc-list -f '%{file}\n' "$family" 2>/dev/null | sort -u
    )
    if [[ ${#font_files[@]} -eq 0 ]]; then
        echo "warning: '$family' not found in $USER_FONT_DIR" >&2
        continue
    fi
    mkdir -p "$SYS_FONT_DIR"
    copied=0
    family_changed=0
    sources=()
    for font_file in "${font_files[@]}"; do
        [[ -f $font_file ]] || continue
        # The system dir itself shows up in fc-list: the mirror from a previous
        # run, or a pacman package (Material Symbols). It is never the source --
        # it sorts after $HOME and would clobber the user's newer file.
        [[ $font_file == "$SYS_FONT_DIR"/* ]] && continue
        sources+=("$font_file")
    done
    if [[ ${#sources[@]} -eq 0 ]]; then
        # Every match already lives in the system dir, so there is nothing to
        # mirror: the greeter sees the family without this script doing anything.
        echo "font already system-wide: $family"
        continue
    fi
    for font_file in "${sources[@]}"; do
        font_name="$(basename "$font_file")"
        # Track only files that come from the user's own font dir: a manifest
        # entry is a licence to delete that file on a later run.
        if [[ $font_file == "$USER_FONT_DIR"/* ]]; then
            mirrored["$font_name"]=1
        fi
        if cmp -s "$font_file" "$SYS_FONT_DIR/$font_name"; then
            copied=$((copied + 1))
            continue
        fi
        install -m644 "$font_file" "$SYS_FONT_DIR/"
        copied=$((copied + 1))
        fonts_changed=1
        family_changed=1
    done
    if [[ $family_changed -eq 1 ]]; then
        echo "mirrored system-wide: $family ($copied files)"
    else
        echo "font in sync: $family ($copied files)"
    fi
done

# Drop mirrors an earlier run installed for families the theme has since
# dropped. install-sddm.sh shrinks THEME_FONTS over time and nothing else ever
# removed the leftovers.
if [[ -f $MIRROR_MANIFEST ]]; then
    while read -r font_name; do
        [[ -n $font_name ]] || continue
        # Manifest entries are basenames this script wrote; refuse anything that
        # could climb out of the font dir.
        [[ $font_name == */* ]] && continue
        [[ -n ${mirrored[$font_name]:-} ]] && continue
        rm -f "$SYS_FONT_DIR/$font_name"
        fonts_changed=1
        echo "removed stale mirror: $font_name"
    done <"$MIRROR_MANIFEST"
fi

if [[ -d $SYS_FONT_DIR ]]; then
    if [[ ${#mirrored[@]} -gt 0 ]]; then
        printf '%s\n' "${!mirrored[@]}" | sort >"$MIRROR_MANIFEST"
    else
        # Empty manifest, not a stale one: the next run must not try to remove
        # files that this run already deleted.
        : >"$MIRROR_MANIFEST"
    fi
fi

if [[ $fonts_changed -eq 1 ]]; then
    fc-cache -f >/dev/null
fi

systemctl enable sddm.service

# --- verification -----------------------------------------------------------
fail=0

if diff -r -q "$THEME_SRC" "$THEME_DST" >/dev/null; then
    echo "check: theme files in sync (QML, no raster assets)"
else
    echo "check FAILED: installed theme differs from the repo - re-run this script" >&2
    fail=1
fi

if grep -qx 'QtVersion=6' "$THEME_DST/metadata.desktop"; then
    echo "check: QtVersion=6 present (Qt6 greeter)"
else
    echo "check FAILED: metadata.desktop lacks QtVersion=6 - SDDM would launch the Qt5 greeter" >&2
    fail=1
fi

if grep -qx 'Current=arch' "$CONF_DIR/30-theme.conf"; then
    echo "check: Current=arch"
else
    echo "check FAILED: 30-theme.conf does not select the arch theme" >&2
    fail=1
fi

for family in "${THEME_FONTS[@]}"; do
    if fc-match "$family" 2>/dev/null | grep -qF "$family"; then
        echo "check: font visible to the greeter: $family"
    else
        echo "check FAILED: font not visible to the greeter: $family" >&2
        fail=1
    fi
done

echo
if [[ $fail -eq 0 ]]; then
    echo "All checks passed."
else
    echo "Some checks failed (see above)." >&2
fi

echo "The greeter reads the theme at startup: reboot, or from a TTY run"
echo "  sudo systemctl restart sddm"
echo "Do not restart sddm from inside the graphical session: it kills it."
exit "$fail"
