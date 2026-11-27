#!/usr/bin/env bash
# Build and run the lane dismiss harness.
#
# Like the card harness: the section, the card and the tokens are copied from the
# repo on every run (never edited here), with `import ".."` rewritten to the local
# module and the generated Appearance.qml stripped of `import Quickshell`, which a
# plain QQuickView cannot resolve.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(git -C "$HERE" rev-parse --show-toplevel)"
COMPONENTS="${REPO}/config/quickshell/kanban/components"
TOKENS="${REPO}/config/quickshell/kanban/Appearance.qml"

for name in KanbanSection KanbanCard CategoryChip; do
	sed 's|^import "\.\."$|import "."|' "$COMPONENTS/$name.qml" > "$HERE/$name.qml"
	grep -q '^import "."$' "$HERE/$name.qml"
done

sed -e '/^import Quickshell$/d' "$TOKENS" > "$HERE/Appearance.qml"
grep -q 'readonly property int fieldHeight' "$HERE/Appearance.qml"

cd "$HERE"
defs="-DQML_PATH=\"$HERE/harness.qml\""
/usr/lib/qt6/moc test.cpp -o test.moc
g++ -std=c++17 -fPIC -O0 $defs test.cpp -o test \
	$(pkg-config --cflags --libs Qt6Qml Qt6Quick Qt6Test Qt6Gui) \
	-I"$HERE"

QT_QPA_PLATFORM=offscreen ./test -txt
