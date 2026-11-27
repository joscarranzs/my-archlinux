# Branching, commits and review

## Local conventions

- `~/.dotfiles`: work on `rewriting`; `master` receives squashed PRs only. Remote tags are the backups; do not recreate branch backups.
- `~/.config/nvim`: separate repo on `main`, remote `joscarranzs/neovim-config`.
- Respect an existing strategy before proposing one. No Git Flow or heavy branch taxonomy without a concrete need.
- Keep a branch to one logical objective; avoid long-lived branches and unrelated changes.

## Conventional Commits

`feat:`, `fix:`, `docs:`, `refactor:`, `test:`, `perf:`, `build:`, `ci:`, `chore:`, `style:`.

Write an imperative English subject that states the effect, not `update` or `changes`. Add a body when the why or the consequence is not obvious. Review `git diff --cached` first. Do not amend published commits without a coordinated reason. Never claim a commit was created without running it.

## Integration

- Merge keeps integration context; rebase linearizes only unpublished local commits.
- Inspect both branches, their divergence and conflicting changes before integration.
- Resolve conflicts from intended behavior, preserving valid work from both sides. Check for conflict markers and run relevant tests after.

## Pull requests and review

A PR states the problem, the change, implementation details, issue references, tests performed, risks and migration notes. Verify the target branch, review the whole diff, remove unrelated changes, check for secrets, and confirm required checks and approvals before merging.

Review for functional correctness, architecture, security, regressions, performance, tests and maintainability. Rank findings by severity and explain impact. Skip stylistic comments when formatting is automated.
