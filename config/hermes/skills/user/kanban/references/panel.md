# Panel internals

## Files

- `~/.config/quickshell/kanban/` — Quickshell plaque. `shell.qml`, `components/KanbanPanel.qml`, `components/KanbanCard.qml`, `components/KanbanSection.qml`, `services/KanbanFeed.qml`.
- `~/.scripts/session/kanban-feed.py` — readout and mutation helper. Symlinked into place from `~/.dotfiles/scripts/session/kanban-feed.py`.
- `~/.hermes/kanban.db` — the board. `HERMES_KANBAN_DB` can pin a different file.
- `~/.dotfiles/config/hermes/plugins/task-intake/` — the compact agent tool.
- `~/.dotfiles/scripts/session/tests/states/kanban-test.qml` — state harness. Run with `bash scripts/session/tests/states/run-all.sh` from `~/.dotfiles`.

## Feed contract

- No args: runs `hermes kanban list --json`, joins the `category` column from SQLite and prints `{"tasks": [...], "error": null}`. Each task is slimmed to `id, title, body, status, priority, category`.
- `act <args...>`: runs `hermes kanban <args...>` and prints `{"ok": bool, "error": str|null, "output": str}`. Helper-only verbs: `reopen <id>` (`reopen-review` then `claim`) and `categorize <id> C<n>` (writes the column the CLI does not own). A `--category C<n>` on `create` is stripped, the CLI call runs, then the id from `--json` is pinned.
- The helper always exits 0. The JSON `ok`/`error` fields decide success.
- The panel refreshes every 30 s. Mutations are serialized; a second `act` while one is in flight joins a queue capped at 8. A helper that dies without answering still releases the queue.
- A broken readout keeps the previous snapshot on screen instead of blanking the panel.

## Panel rules encoded in QML

- Four visual lanes; `blocked` sits under IN PROGRESS with its own header. Lane is computed from status, never from the status name.
- The IN PROGRESS lease is `claimTtlSeconds: 28800`; the UI says explicitly that a card returns to TO DO when the lease expires and nothing heartbeats it.
- Claims are allowed from TO DO statuses, but the backend only accepts `ready`; `todo`/`triage` are rejected.
- Review -> IN PROGRESS is the one reverse move, done by the helper's `reopen`.
- Editing title/body is allowed only while the card is in the TO DO lane.
- Archive needs the confirmation dialog; there is no delete badge.
