# Plaque checks

One harness for `config/quickshell/<panel>`, run once per panel. It exists
because two things about a plaque cannot be judged by reading QML: whether its
entrance is a fade *and* a lift (the first pass shipped the fade alone and called
it done), and whether the key hints in its footer actually fit the plaque.

```
./run-all.sh          # every panel, exits non-zero on any failure
```

| Harness | What it proves | How |
|---|---|---|
| `entrance-test.qml` | The plaque starts transparent at `motionEntranceOffset`, decelerates, lands on zero over `motionEntranceDuration`, and `mapToItem` puts the paint back on the anchor with it. Every `LegendRow` in the plaque fits the width its row was given. | `quickshell -p` with the real panel inside a window, offscreen |

## Two traps

- **The harness runs without services.** A panel that binds to a singleton
  (`NetworkState.status`, `MonitorState.status`) sees `undefined` here, so its
  footer falls back to a message branch and the legend does not paint. The
  layout asserts still hold — the row is laid out, only hidden — but the *pixels*
  of those two footers have to be checked live. `run-all.sh` therefore treats
  `TypeError` as expected noise and fails only on hard QML errors.
- **`mapToItem` is the contract, not the token.** Asserting `entranceLift`
  alone would pass a transform that is declared and never applied. Measured
  against a real grab on 2026-11-23: the plaque's top gilt row sits at 40 px at
  rest and 48 px while held at the offset, which is why the harness asserts the
  mapped edge too.

The launcher's plaque lives inside its `shell.qml`, so it needs a PanelWindow
backend to instantiate at all: it is checked live (open it, read the panel log)
rather than here.
