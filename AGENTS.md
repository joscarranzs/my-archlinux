# AGENTS.md — dotfiles

Rules for any agent session working in this repo. They exist to save tokens and
subscription quota, not for decoration.

## Delegation

`delegate_task` exposes six model routes on Nous Portal (pay-per-use). Pick one
per task with `option`:

| option | model | use it for |
|---|---|---|
| `fast` (default) | qwen/qwen3.7-flash | lookups, greps, reading and summarizing, renames |
| `work` | deepseek/deepseek-v4-flash | multi-file edits, features, refactors, running tests |
| `code` | qwen/qwen3-coder-next | implementation where correctness matters, or when `work` failed once |
| `docs` | ~z-ai/glm-flash-latest | long-form prose: READMEs, changelogs, doc pages |
| `heavy` | deepseek/deepseek-v4-pro | hard debugging and architecture — ~12x the cost of `fast` |
| `free` | meituan/longcat-2.5:free | bulk mechanical passes where a mistake is cheap to spot |

- **Default to doing the work yourself.** Delegate only when the task splits
  into independent pieces, or when reading everything would flood this context.
- One artifact built iteratively (a panel, a theme tweak, a lockscreen state) is
  never delegated: the child forks the context and cannot ask anything back.
- A child costs 10k-20k tokens before it does any work (~$0.0005 on `fast`,
  ~$0.001 on `work`). Never delegate a task that is fewer than ~10 tool calls.
- Briefs must be self-contained: exact paths, exact commands, expected output
  shape. A child knows nothing about this conversation.
- Cap what comes back: findings and `file:line` references, never file dumps.
- The tree is flat (`max_spawn_depth=1`): children cannot delegate further.
- Treat child output as a report, not proof. Verify side effects yourself.

## Budget

This account is pay-per-use credits, not a subscription. There is **no premium
route configured on purpose** — a single session on a $2/$10 model would cost
more than $19.50.

- **Context length × turns is the bill, and output is noise.** One measured
  session: 330k fresh input, **24.4M cache-read**, 115k output — output was 0.5%
  of the billable volume. Spend effort shrinking what the agent *reads*, never
  what it writes.
- A heavy week of work costs ~$0.80 on the parent model and ~$9.70 on `heavy`.
  Reach for `heavy` only after `work` and `code` both failed, and never for a
  whole session.
- Actual spend per session is recorded: `hermes insights --days 7` and
  `hermes usage`. Check it before starting anything long.


## Context discipline

- One fresh session per task. `/new` is free; a 200-message session is not.
- Never pull a whole large file into the parent context. Grep, then read the
  range you actually need.
- Load the existing skill (`quickshell-panel`, `hermes-agent`, `wayland-session-lock`,
  ...) instead of re-deriving the conventions from scratch — but only the one this
  task needs. **A loaded body stays in the transcript and is re-read on every
  API call**, so its size is a recurring cost: keep bodies under ~5k tok and push
  the depth into `references/`. Loading a 60 KB skill "por si acaso" cost ~21k
  tokens on every call of the session that did it.
- Check `/usage` once a session passes ~50 turns, or when the monthly quota
  looks like it is draining faster than the work justifies.

## Handoffs

- Work does not end in a chat message. A session that stops mid-task writes
  `docs/handoff-<YYYY-MM-DD>.md` from `docs/handoff-TEMPLATE.md` and commits it.
  A handoff pasted into the chat dies with the chat, and the paste arrives
  truncated exactly where the pending items were.
- Every number in it comes from a command run at the close, with the command
  named next to the value, so the next session re-runs the block instead of
  quoting a stale file.
- Section 6 is never empty: "nada" is an answer, an empty section is
  indistinguishable from a truncated file.

## Visual work

- Reuse the recipe that already exists in another surface instead of tuning a
  new value per panel. Repeated drift between surfaces reads as sloppy.
- All user-facing strings in English, whatever the working language is.
