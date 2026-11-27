# Agent workflow

## File

1. Wait for the explicit request to create a card.
2. Write title <=80 and body <=200 in Spanish.
3. `task_intake action=file` with the right category/priority and no assignee.
4. Handle DUPLICATE by reporting the existing id. Handle CANDIDATES by judging intent; use `force=true` only when it is genuinely a new job.
5. Read back with `task_intake action=open`. No code, no diagnosis, no implementation.

## Authorize

Wait for the user's go-ahead before `hermes kanban assign <id> <profile>` or `claim`. Assignment is what starts a worker and spends credits. Creating a card never implies this step.

## Implement

1. `hermes kanban claim <id> --ttl 28800` before touching code.
2. Do the work with the smallest coherent change and real verification.
3. `hermes kanban comment <id> "<commit sha>; <checks run and result>; <files>"` while the result is fresh.
4. Keep the card `running`; never leave it `ready` while you work.

Useful comment shape:

```
<sha> <subject>. Verified: <exact command> -> <result>. Files: <paths>.
```

## Offer review

1. Confirm tests, checks and commit actually exist.
2. `hermes kanban request-review <id> --summary "<what changed, what to check, evidence>"`.
3. Read back with `hermes kanban show <id>`; if it did not move, comment the exact reason instead of claiming success.
4. Stop. Only the user closes `review` -> `done`.

## Blocked or rejected

- Missing input or capability: `hermes kanban block <id> --kind needs_input|capability "reason"`; leave it there for the user.
- Waiting on a parent: `link` the parent, or record `--kind dependency`; the card waits in `todo`.
- User sends it back from review: `python3 ~/.scripts/session/kanban-feed.py act reopen <id>`, then resume the work.
- Never close a card you could not finish and never write a comment claiming a check you did not run.

## Board check

After every transition: `task_intake action=open` or `hermes kanban show <id>`. The board, not the chat, is the record of what happened.
