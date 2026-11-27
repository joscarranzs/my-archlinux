# Kanban panel checks

Four harnesses for `config/quickshell/kanban`. They exist because the gesture
layer cannot be judged by reading QML: the first build looked right and moved
nothing.

```
./run-all.sh          # all four, exits non-zero on any failure
```

| Harness | What it proves | How |
|---|---|---|
| `panel-test.qml` | Drop targets register, `destAt` resolves the five zones, the status×destination matrix matches the backend, a hold-drag produces exactly one action, a refused drop produces none, a drop back on the card's own lane is neither a refusal nor an action, a parked card in its own lane is still the unblock, a `complete` always carries `--result`, the creator refuses an empty title, editing is refused outside TO DO (at the double click and again at the commit) and the sheet's hint says so, the action feedback paints in the header's right corner (right-aligned, elided, above the board) and every lane carries the click-anywhere-else that closes the sheet. | `quickshell -p` over a fake feed, offscreen |
| `feed-test.qml` | The same panel over the real backend: create → claim → complete → archive, with the pending id and the outcome message. | `quickshell -p` with `KanbanFeed`, offscreen. **Writes to the live board**: it creates a task called `Panel e2e` and archives it. |
| `card/run.sh` | QTest against the real card: a 180 ms hold on the body starts a drag, a quick swipe does not, a single click asks for the preview, a right click asks to archive, a drag that ends does NOT open the sheet (hold and sideways path alike), the click after it still does, and the card owns no editor — the sheet does. | `g++` + `moc` + `QT_QPA_PLATFORM=offscreen` |
| `section/run.sh` | QTest against the real lane: a press beside the tasks reaches the panel's `closePreview` (a Flickable would otherwise swallow it), a press on a card asks for the preview instead, and the header band stays silent so the panel's own catcher answers there. | `g++` + `moc` + `QT_QPA_PLATFORM=offscreen` |

`visual.qml` is not a test: it paints the real panel in a layer-shell overlay
and walks it through the drag states so the feedback can be photographed with
`grim`. It never sends an action.

## Three traps

- **Offscreen has no polish pass.** `ColumnLayout`/`Row` never position their
  children without a window, so every section sits at x=0 with height 0. The
  panel harness sets the geometry the live layout produces before asserting
  anything (`place()`). If that geometry changes in `Appearance.qml`, update it
  there or the hit-test asserts will lie.
- **Repeater delegates are not QObject children.** `findChildren<QQuickItem *>()`
  on a lane returns every static item and none of the cards: a delegate's QObject
  parent is the engine, only its visual parent is the lane. Walk `childItems()`
  when a test needs a card.
- **The card and lane harnesses copy the component.** A plain `QQuickView` cannot
  resolve `import Quickshell`, which the generated `Appearance.qml` needs.
  `card/run.sh` and `section/run.sh` copy their component (and everything it
  imports) and rewrite its `import ".."`. Never edit a copy - it is regenerated
  every run.
