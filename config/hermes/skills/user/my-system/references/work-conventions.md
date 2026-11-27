# Work conventions

## Delegation

Routes from `~/.dotfiles/AGENTS.md`, chosen with `option`:

| Route | Model | Use |
|---|---|---|
| `fast` (default) | qwen/qwen3.7-flash | lookups, greps, reading, renames |
| `work` | deepseek/deepseek-v4-flash | multi-file edits, tests, refactors |
| `code` | qwen/qwen3-coder-next | correctness-critical implementation, or after `work` fails once |
| `docs` | ~z-ai/glm-flash-latest | long-form prose |
| `heavy` | deepseek/deepseek-v4-pro | hard debugging, ~12x `fast`; only after `work` and `code` fail |
| `free` | meituan/longcat-2.5:free | bulk mechanical passes with cheap-to-spot mistakes |

Default to doing the work yourself. Delegate only independent pieces or context that would flood the session; never a single artifact built iteratively. A child starts blank: give exact paths, commands and output shape. Cap what comes back to findings and `file:line`; treat its report as a claim, not proof. The tree is flat: children cannot delegate. Check side effects yourself.

## Cost and context

- Pay-per-use credits, no premium route configured on purpose: one session on a $2/$10 model costs more than the remaining balance.
- Measured session: 330k fresh input, 24.4M cache-read, 115k output. Shrink what the agent reads, not what it writes.
- One fresh session per task; `/new` is free. Grep, then read only the range needed. Keep skill bodies small.
- Check spend with `hermes insights --days 7` and `hermes usage` before long work.

## Handoffs and commits

- A session stopping mid-task writes `docs/handoff-<date>.md` from `docs/handoff-TEMPLATE.md` and commits it. Every number carries the command that produced it; section 6 is never empty.
- Commits are English, conventional, with clear descriptions. Code and comments are English; user-facing strings too. Spanish only when explicitly ordered for an artefact.
- Durable work is committed in `~/.dotfiles`. Pushing is a separate decision and needs the user's word.
- Only the user closes a review card; filing a card never authorizes its execution. See `kanban`.

## Change checklist

1. Resolve the real path, read the file, identify the owner (repo, generated, runtime).
2. Identify the consumer: Hyprland, systemd, Quickshell, SDDM, PAM, Hermes or a plain app.
3. Change the source, not the generated output.
4. Apply with the narrowest action: a reload, one panel restart, one `systemctl --user restart`.
5. Verify with a command and quote the output.
6. Commit durable changes; never push unasked.
7. Report anything unverified with what would prove it.

## Recovery

| Broken | First move |
|---|---|
| Hyprland will not start | TTY, read compositor log; the Lua entry point prints satellite errors on stdout. Fix in the repo, not in `/usr`. |
| Desktop broken, session alive | New kitty via `Super+Return`; fix and reload; `Super+M` exits the session last. |
| Bar or wallpaper missing | Re-run `~/.scripts/session/bar.sh` or `quickshell-wallpaper.sh`. |
| Theme looks wrong after a run | Fix the JSON or template and re-run `apply-theme.py`; `git -C ~/.dotfiles checkout -- theme/` is the undo. |
| Cannot unlock | TTY, log in, kill the lockscreen process, then audit the PAM files; treat as a security incident. |
| Config tree in doubt | `git -C ~/.dotfiles status`; the repo is the undo button for symlinked config. |
