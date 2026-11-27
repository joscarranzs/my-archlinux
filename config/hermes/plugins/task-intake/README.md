# task-intake

The agent's door to the Task panel (`~/.config/quickshell/kanban`). One tool,
two verbs, so the board costs a line instead of a page.

| Verb | What it does |
|---|---|
| `action=open` | one line per new/in-progress card: `id status assignee title`. `lane` picks NEW (triage/todo/scheduled/ready), progress (running/review/blocked) or both; `with_body` adds the body preview. |
| `action=file` | files a pending card **after** scoring the request against every open card. |

## Dedupe

The score is the best of four readings, after accent folding, lowercasing and
stopword removal:

1. the folded titles are identical → `1.00` (DUPLICATE);
2. Jaccard over the title words;
3. `0.75 ×` containment of the shorter title in the other — this is what
   catches the same job named with a different verb;
4. `0.6 ×` Jaccard over title **and** body plus `0.4 ×` the title overlap.

Ladder:

- `>= 0.86` → `DUPLICATE <id> (<score>) "<title>" — nothing created`.
- `>= 0.35` → `CANDIDATES` (up to three, with scores). Nothing is written: whether
  the intent matches is a judgement the model makes, then it re-calls with
  `force=true` if none of them is the same thing.
- below → `CREATED <id> "<title>"`.

Only open cards are compared: a `done` card must not block re-filing the same
title, and the plugin never derives an idempotency key from the title for
exactly that reason.

The floor is low on purpose. A missed duplicate leaves two cards for one job; a
spurious candidate costs one short sentence.

## Limits

`title` 1–80 characters, `body` 1–200 — the panel's own creator caps
(`titleLimit` / `descriptionLimit` in `KanbanPanel.qml`). Anything longer is
refused with the actual length, so the model rewrites instead of guessing.

Unassigned by default: the card shows in NEW and the dispatcher never spawns a
worker for it. Pass `assignee` to make it dispatchable.

## Why not the built-in `kanban_*` tools

They are the full board API and stay available; but they are 15 schemas, about
6.6k tokens in every prompt, and `kanban_list` returns every column of every
row. This one schema is ~260 tokens and its read is four fields per card.

## Tests

```
cd ~/.dotfiles/config/hermes/plugins/task-intake
python3 -m unittest discover -s tests -v
```

The suite builds a throwaway board in a sandbox `HERMES_HOME`; it never opens
`~/.hermes/kanban.db`.
