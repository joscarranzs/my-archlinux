#!/usr/bin/env bash
# Assert that the desktop font migration still holds.
#
# Each check below was, at least once, performed by hand in a later session: a
# retired family still resolving through a stale mirror, a dconf key pinned to a
# face that no longer exists, a process drawing with a file that was deleted
# underneath it. Doing that sweep by hand every session is how a clean state
# turns into a TODO list, so it lives here instead.
#
# Exit 0 = clean. Exit 1 = drift, with one FAIL line per broken assertion.
# Usage: scripts/theme/verify-fonts.sh [-v]

set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(git -C "$HERE" rev-parse --show-toplevel)"
VERBOSE=0
[ "${1:-}" = "-v" ] && VERBOSE=1

# Families the desktop dropped in 010fb99. Anything of theirs still resolving,
# mirrored, or mapped into a live process is a leftover.
RETIRED=(
  "Space Grotesk"
  "Space Mono"
  "Fraunces"
  "EB Garamond"
  "Noto Sans JP"
)

pass=0
fail=0

ok()   { pass=$((pass + 1)); [ "$VERBOSE" = 1 ] && printf 'ok   %s\n' "$1"; return 0; }
bad()  { fail=$((fail + 1)); printf 'FAIL %s\n' "$1"; return 0; }
check() { if [ "$1" = 0 ]; then ok "$2"; else bad "$2"; fi; }

# --- the theme itself -------------------------------------------------------
TYPO="$REPO/theme/typography.json"
UI_FAMILY=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["fonts"]["ui"])' "$TYPO" 2>/dev/null)
MONO_FAMILY=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["fonts"]["mono"])' "$TYPO" 2>/dev/null)
MONO_SIZE=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["sizes"]["terminal"])' "$TYPO" 2>/dev/null)

[ -n "$UI_FAMILY" ] && [ "$UI_FAMILY" = "$MONO_FAMILY" ]
check $? "typography.json: ui and mono name the same family"

python3 -c 'import json,sys; sys.exit(1 if "jp" in json.load(open(sys.argv[1]))["fonts"] else 0)' "$TYPO" 2>/dev/null
check $? "typography.json: no jp override left"

# --- nothing of the retired families resolves -------------------------------
FAMILIES=$(fc-list : family 2>/dev/null | tr ',' '\n' | sed 's/^[[:space:]]*//; s/[[:space:]]*$//' | sort -u)
for family in "${RETIRED[@]}"; do
  ! grep -Fxq "$family" <<<"$FAMILIES"
  check $? "fc-list: $family does not resolve"
done

# --- the mirror the greeter reads -------------------------------------------
if [ -d "$HOME/.local/share/fonts" ]; then
  left=$(find "$HOME/.local/share/fonts" -type f \( -name '*.ttf' -o -name '*.otf' -o -name '*.ttc' \) | wc -l)
else
  left=0
fi
[ "$left" = 0 ]
check $? "~/.local/share/fonts holds no font files (found $left)"

MANIFEST=/usr/share/fonts/TTF/.mirrored-fonts
if [ -e "$MANIFEST" ]; then
  mirrored=$(grep -c . "$MANIFEST" 2>/dev/null || true)
  [ "${mirrored:-0}" = 0 ]
  check $? "$MANIFEST is empty (holds ${mirrored:-0} entries)"
else
  ok "$MANIFEST does not exist, nothing was mirrored"
fi

for family in "${RETIRED[@]}"; do
  hits=$(grep -rlF --include='*.ttf' --include='*.otf' --include='*.ttc' "$family" /usr/share/fonts/TTF 2>/dev/null | wc -l)
  [ "$hits" = 0 ]
  check $? "/usr/share/fonts/TTF holds no $family file (found $hits)"
done

# --- what fontconfig answers ------------------------------------------------
face=$(fc-match "$MONO_FAMILY:weight=normal" file 2>/dev/null)
case "$face" in
  *JetBrainsMonoNerdFont-SemiBold.ttf*) ok "fc-match $MONO_FAMILY:weight=normal lands on SemiBold" ;;
  *) bad "fc-match $MONO_FAMILY:weight=normal is $face, not SemiBold" ;;
esac

# fc-match prints every family alias on the same line ("JetBrainsMono Nerd Font,JetBrainsMono NF"),
# so compare the first one only: that is the family a toolkit draws with.
raw=$(fc-match monospace family 2>/dev/null | cut -d, -f1)
[ "$raw" = "$MONO_FAMILY" ]
check $? "fc-match monospace is $MONO_FAMILY (got $raw)"

fc-match "Adwaita Sans" family 2>/dev/null | grep -q 'Adwaita Sans'
check $? "the toolkit default Adwaita Sans is installed"

# --- no pinned UI face, one voice for code ----------------------------------
pinned=$(dconf dump / 2>/dev/null | grep -i 'font' | sort)
want="monospace-font-name='$MONO_FAMILY $MONO_SIZE'"
[ "$pinned" = "$want" ]
check $? "dconf carries exactly one font key, $want"

# --- nothing live still drawing with a deleted face -------------------------
live=0
for proc in /proc/[0-9]*; do
  grep -oE '/[^ ]*\.(ttf|otf|ttc)' "$proc/maps" 2>/dev/null | grep -qF -e 'SpaceGrotesk' -e 'SpaceMono' -e 'Fraunces' -e 'EBGaramond' -e 'NotoSansJP' || continue
  live=$((live + 1))
  [ "$VERBOSE" = 1 ] && printf '     pid %s: %s\n' "${proc#/proc/}" "$(tr '\0' ' ' < "$proc/cmdline" 2>/dev/null)"
done
[ "$live" = 0 ]
check $? "no live process has a retired font mapped (found $live)"

# --- generated files carry the current family -------------------------------
# Only an assignment counts. Historical prose such as ClockLabel.qml's "it used
# to be Fraunces" is the record of an earlier decision and must not fail here.
stale=$(grep -rnE '(fontFamily|font\.family|family).*(Space Grotesk|Space Mono|Fraunces|EB Garamond|Noto Sans JP)' \
  "$HOME/.config/quickshell" "$HOME/.config/sddm" "$HOME/.config/gtk-3.0" \
  "$HOME/.config/gtk-4.0" "$HOME/.config/kitty" 2>/dev/null | wc -l)
[ "$stale" = 0 ]
check $? "no generated config assigns a retired family (found $stale)"

# --- verdict ----------------------------------------------------------------
total=$((pass + fail))
if [ "$fail" = 0 ]; then
  printf 'fonts: %s/%s checks pass\n' "$pass" "$total"
  exit 0
fi
printf 'fonts: %s/%s checks pass, %s failed\n' "$pass" "$total" "$fail"
exit 1
