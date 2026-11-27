# Filing

## Filing is not doing

"Create a card for X" asks you to write X down. Do not open the files it names, reproduce the failure, measure anything or fix it. A card filed after the work is finished lies about the board. If the request needs a diagnosis, the diagnosis is the card's first step or a separate card.

## tool intake

`task_intake action=file` scores the request against every open card before writing. Ignore `done` and `archived` cards in the comparison.

- folded identical titles score `1.00` -> `DUPLICATE`.
- Jaccard over title words.
- `0.75 x` containment of the shorter title in the other.
- `0.6 x` Jaccard over title + body plus `0.4 x` title overlap.
- `>= 0.86` -> `DUPLICATE <id> (<score>) ...`, nothing created.
- `>= 0.35` -> up to three `CANDIDATES`, nothing created. Judge intent; re-call with `force=true` only if none of them is the same job.
- below -> `CREATED <id> ...`.

A batch of siblings trips CANDIDATES from the second card on. The floor is low on purpose: a missed duplicate costs two cards, a false candidate costs one sentence.

Limits: title 1-80 characters, body 1-200. The plugin refuses longer input and reports the actual length; rewrite instead of guessing. Omit `assignee` to leave the card pending and undispatchable.

## Axes

- `category`: C0 none, C1 urgent, C2 important, C3 necessary, C4 optional.
- `priority`: 1-9, the rank inside the category.

`hermes kanban create` has no `--category`; passing it writes nothing. The feed helper strips `--category` before calling the CLI and pins the value on the id parsed from `--json`: `python3 ~/.scripts/session/kanban-feed.py act create --json "Title" --body "..." --category C2`. If the id cannot be parsed, the card exists but is unclassified; re-pin with `act categorize <id> C2`.

## Decomposition

Split non-trivial work into cards ordered by dependency, then priority. Use `hermes kanban link <parent> <child>` for the order; a sentence in the body does not gate anything. Validate each child on its own before it moves.

Card text: Spanish, short, precise. State what has to change and how the result will be recognized. Do not write the solution as a foregone conclusion when the card is a diagnosis.
