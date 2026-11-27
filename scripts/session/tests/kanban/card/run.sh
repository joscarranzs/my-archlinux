#!/usr/bin/env bash
# Build and run the card gesture harness.
#
# Both the card and its tokens are copied from the repo on every run (never
# edited here). The card keeps its `import ".."` rewritten to the local module,
# and the generated Appearance.qml is rendered with its `import Quickshell`
# removed, which a plain QQuickView cannot resolve. Regenerating the token file
# is what keeps the harness honest: a card that starts reading a new role fails
# here instead of passing against a frozen copy of the scale.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(git -C "$HERE" rev-parse --show-toplevel)"
SRC="${REPO}/config/quickshell/kanban/components/KanbanCard.qml"
TOKENS="${REPO}/config/quickshell/kanban/Appearance.qml"

sed 's|^import "\.\."$|import "."|' "$SRC" > "$HERE/KanbanCard.qml"
grep -q '^import "."$' "$HERE/KanbanCard.qml"

# The card draws its category badge through the shared chip; the harness needs
# its own copy for the same reason it needs the card's: nothing here is edited.
CHIP="${REPO}/config/quickshell/kanban/components/CategoryChip.qml"
sed 's|^import "\.\."$|import "."|' "$CHIP" > "$HERE/CategoryChip.qml"
grep -q '^import "."$' "$HERE/CategoryChip.qml"

sed -e '/^import Quickshell$/d' "$TOKENS" > "$HERE/Appearance.qml"
grep -q 'readonly property int fieldHeight' "$HERE/Appearance.qml"

cd "$HERE"
defs="-DQML_PATH=\"$HERE/harness.qml\""
/usr/lib/qt6/moc test.cpp -o test.moc
g++ -std=c++17 -fPIC -O0 $defs test.cpp -o test \
    $(pkg-config --cflags --libs Qt6Qml Qt6Quick Qt6Test Qt6Gui) \
    -I"$HERE"

QT_QPA_PLATFORM=offscreen ./test -txt
