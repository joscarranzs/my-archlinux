# Lifecycle

## Statuses

| Status | Lane | Meaning |
|---|---|---|
| `triage` | TO DO | waiting to be specified |
| `todo` | TO DO | waiting on a parent dependency |
| `scheduled` | TO DO | parked on time, not human input |
| `ready` | TO DO | fresh work, dispatchable only with an assignee |
| `running` | IN PROGRESS | claimed by a worker or by you |
| `blocked` | IN PROGRESS | waiting on a human or capability |
| `review` | IN REVIEW | implementation done, awaiting the user |
| `done` | DONE | closed by the user |
| `archived` | hidden | removed from the active board |

## Forward moves

- `ready` -> `running`: `hermes kanban claim <id> --ttl 28800`. The CLI default is 900 s; the panel uses 28,800 s. Nothing heartbeats a manual claim, so the dispatcher returns the card to `ready` when the lease expires.
- `running` -> `review`: `hermes kanban request-review <id> --summary "..."`. It refuses while a parent dependency is not `done`; keep working or block with that reason instead of forcing it.
- `review` -> `done`: `hermes kanban complete <id> --result "..."`. User-only in this workflow. `--force` exists for a live claim but does not transfer the decision to close.
- `running`/`ready` -> `blocked`: `hermes kanban block <id> --kind <kind> "reason"`. The reason is also appended as a comment.
- `running` -> `scheduled`: `hermes kanban schedule <id>` for a time wait.

## Reverse and recovery

- `blocked`/`scheduled` -> `ready`/`todo`: `hermes kanban unblock <id>`. It lands in `todo` while parents are open. A repeated same-kind re-block after unblock routes to `triage` to break loops.
- `review` -> `running`: `python3 ~/.scripts/session/kanban-feed.py act reopen <id>`, which runs `reopen-review` (lands in `ready`) then `claim` with the panel TTL. This is the only way back into IN PROGRESS.
- `review` -> changes: `hermes kanban request-changes <id>` records what must change; `reopen-review` sends it back to work.
- `todo`/`blocked` -> `ready`: `hermes kanban promote <id> "reason"`; `--dry-run` validates first.
- `running` with a dead claim: `hermes kanban reclaim <id>` returns it for another worker.

## Actors and gates

- Dispatcher skips unassigned cards every tick. No assignee means no worker and no spend.
- `hermes kanban link <parent> <child>` holds the child in `todo` until the parent is `done`; `unlink` removes it.
- `hermes kanban assign <id> <profile>` is the authorization to dispatch. `assign <id> none` unassigns.
- `hermes kanban show <id>` shows the comment and event trail. Verify the resulting status after every mutation.
