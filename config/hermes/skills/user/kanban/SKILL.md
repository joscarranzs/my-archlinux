---
name: kanban
description: Use when filing, driving or closing Task panel cards.
version: 1.0.0
author: joscarranzs
license: MIT
platforms: [linux]
metadata:
  hermes:
    tags: [kanban, task-panel, cards, transitions, dedupe]
    category: user
---

# Kanban

The Task panel is a view over `~/.hermes/kanban.db`. The board is the source of truth: read it after every transition, never from memory.

## When to use

- The user asks to file, inspect, assign, claim, move, block or close a card.
- A card you own needs a status update, a comment or a follow-up.
- Not for your own internal steps: use `todo_list` for those.

## Lanes and statuses

| Panel lane | Statuses in `tasks.status` |
|---|---|
| TO DO | `triage`, `todo`, `scheduled`, `ready` |
| IN PROGRESS | `running`, `blocked` |
| IN REVIEW | `review` |
| DONE | `done` (`archived` hidden) |

`new` and `progress` are `task_intake` lane names, not statuses. Category and priority are separate axes: C0 none, C1 urgent, C2 important, C3 necessary, C4 optional; P1-P9 rank inside a category. `hermes kanban list` hides category.

## Non-negotiable rules

1. **Create only on explicit request.** "Create a card for X" means file X, not do X. Do not open the code, reproduce the failure or measure anything while filing. Write the card from what the user said; put the diagnosis in the card or in its own card.
2. **A card is not authorization.** Unassigned cards show in TO DO and the dispatcher skips them. Assigning or claiming hands work to a worker and starts spending credits: do it only on the user's go-ahead.
3. **State follows the work, without being asked.** After authorization, claim before touching code; stay `running` while working; comment with the commit and verification numbers; then request review. Only the user closes `review` -> `done`. Never call `complete` yourself. If blocked, use `block` with a reason; never close.
4. **Verify every transition.** Read the board after each move. A refused move gets a comment explaining why; never narrate a transition that did not happen.
5. **Conventions.** Spanish for card titles and bodies; English for code, comments and commits. Title <=80 characters, body <=200. Decompose non-trivial work into dependency-ordered cards with `link`.
6. **Cost.** Cheapest sufficient tools and routes, no premium route by default; batch independent reads.

## Read the board

- `task_intake action=open` prints `id status assignee C<n> P<n> title` per open card. Options: `lane=new|progress|all`, `with_body=true`, `limit`.
- `hermes kanban show <id>` shows body, comments and events; `hermes kanban list --json` gives the full rows.
- Category is not a CLI flag: `sqlite3 ~/.hermes/kanban.db "SELECT id,status,category,priority,title FROM tasks WHERE status NOT IN ('done','archived');"`.

## File a card

- Preferred: `task_intake action=file` with `title`, `body`, `category`, `priority`; omit `assignee` to keep it pending. Dedupe: `>=0.86` DUPLICATE (nothing written), `>=0.35` CANDIDATES (judge intent, then re-call with `force=true` only if the intent differs).
- CLI: `hermes kanban create --json "Title" --body "..." --priority N`. It has no `--category`. Add one with `python3 ~/.scripts/session/kanban-feed.py act categorize <id> C<n>`, or create through the helper: `... act create --json "Title" --category C<n>`.
- `act` belongs to `kanban-feed.py`, not to `hermes kanban`; `hermes kanban act` does not exist.
- Order a batch with `hermes kanban link <parent> <child>`: the child sits in `todo` until the parent is `done`.

## Move a card

| From | To | Command and guard |
|---|---|---|
| `ready` | IN PROGRESS | `hermes kanban claim <id> --ttl 28800`. Only `ready`; `todo`/`triage` are rejected. No heartbeat: expiry returns the card to `ready`. |
| `running` | IN REVIEW | `hermes kanban request-review <id> --summary "..."`. Only from `running`; parent dependencies must be `done`. |
| `blocked`, `scheduled` | TO DO | `hermes kanban unblock <id>`: to `ready`, or `todo` while parents remain open. |
| `review` | IN PROGRESS | `python3 ~/.scripts/session/kanban-feed.py act reopen <id>`: `reopen-review`, then `claim`. The only reverse move. |
| `review` | DONE | User only: `hermes kanban complete <id> --result "..."`. |
| any stuck work | parked | `hermes kanban block <id> --kind <capability|dependency|needs_input|transient> "reason"`. |
| `todo`, `blocked` | `ready` | `hermes kanban promote <id> "reason"` (recovery path). |

`hermes kanban comment <id> "..."` records evidence without moving the card. `archive` is the destructive verb and belongs to the user.

## Panel internals

Quickshell panel under `~/.config/quickshell/kanban/`; helper `~/.scripts/session/kanban-feed.py`. It refreshes every 30 s, serializes mutations with an eight-deep queue, and always answers JSON with `ok`/`error` regardless of exit code. See `references/panel.md` before changing it.

## References

- `references/lifecycle.md` — every status transition, guard and actor.
- `references/filing.md` — dedupe, limits, category/priority, decomposition.
- `references/workflow.md` — file -> authorize -> implement -> review -> user closes.
- `references/panel.md` — panel and helper internals, tests.
