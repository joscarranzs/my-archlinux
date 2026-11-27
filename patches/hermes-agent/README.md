# Hermes Agent patches

Hermes Agent installs from a detached-HEAD git checkout at `~/.hermes/hermes-agent`.
`hermes update` overwrites the working tree, so local fixes live here as patches and
are re-applied by `apply.sh`.

```
patches/hermes-agent/apply.sh          # apply everything, rebuild the TUI bundle
patches/hermes-agent/*.patch           # one file per fix
```

`apply.sh` is idempotent: a patch that applies in reverse is already in place and is
skipped. Run it after every `hermes update`.

## 0001 — Shift+Enter inserts a newline inside Herdr panes

Herdr runs every pane with `TERM_PROGRAM=herdr` and `TERM=xterm-256color`. Neither
value matched the extended-key allowlists in Hermes, so the app never asked the
terminal to report modified keys, and Shift+Enter arrived as a bare `CR` — the
composer submitted instead of breaking the line.

The patch adds `herdr` to both allowlists:

| File | Symbol |
| --- | --- |
| `hermes_cli/cli_terminal_input.py` | `_terminal_supports_extended_enter_keys` |
| `ui-tui/packages/hermes-ink/src/ink/terminal.ts` | `EXTENDED_KEYS_TERMINALS` |

Herdr re-encodes modified keys for the app inside the pane, so the push is safe there.
Verified with the pane's exact environment: the CLI now writes `\x1b[>1u\x1b[>4;2m`,
and neither a bare `xterm-256color` nor Ghostty changed behaviour.

The desktop app needed no patch: `apps/desktop/src/app/chat/composer/index.tsx` already
submits only when `!event.shiftKey`.
