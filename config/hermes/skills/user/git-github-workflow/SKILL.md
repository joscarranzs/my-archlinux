---
name: git-github-workflow
description: Use for git operations. Verify before pushing.
version: 1.0.0
author: joscarranzs
license: MIT
platforms: [linux, macos, windows]
metadata:
  hermes:
    tags: [git, github, commits, branches, recovery, safety]
    category: user
    related_skills: [my-system, code-security, high-quality-code]
---

# Git and GitHub workflow

Git history is the record of work and decisions. Protect existing work, keep changes traceable, and never perform a destructive operation without understanding and authorization.

## When to use

- Any commit, branch, merge, rebase, tag, push, PR, review or recovery operation.
- Not for task cards: load `kanban`. Not for code quality: load `high-quality-code`. Not for secrets in code: load `code-security`.

## Local rules on this machine

- `~/.dotfiles` is the main repo: work on `rewriting`; `master` receives squashed PRs only. Remote backups are tags, not branches (`docs/maintenance.md`).
- `origin` is `git@github.com:joscarranzs/dotfiles.git`; `rewriting` tracks `origin/rewriting`. `~/.config/nvim` is a separate repo on `main`.
- Commit messages are English, Conventional Commits, with a clear description. Code, comments and docs are English.
- Push only on the user's explicit word. A local commit is not a remote update.
- Never hand-edit generated files, and never commit secrets, temporary files or unrelated changes.

## Before any operation

```bash
git status --short
git branch --show-current
git diff --stat && git diff --cached --stat
git log --oneline -8
git remote -v
git rev-list --left-right --count origin/<branch>...HEAD
```

Never assume a clean tree, the intended branch, synchronized remotes or an absent merge/rebase state. Identify the repository root first: this machine has more than one repo.

## Risk classes

- Low risk: `status`, `diff`, `log`, `branch`, `show`, `fetch`.
- State-changing: `add`, `commit`, `switch`, `merge`, `rebase`, `cherry-pick`, `stash`, `tag`, `push`. Verify target and expected effect first.
- Destructive or high impact: `reset --hard`, `clean -fd`, force push, branch deletion, published-history rewrite, repository settings, releases. Explicit authorization required.

Never overwrite uncommitted work, discard changes because they look unrelated, or force-switch branches when work could be lost or obscured. A general "fix the repo" request is not authorization to destroy anything.

## Commits and branches

- One logical change per commit, imperative English subject, Conventional Commit prefix.
- Review `git diff --cached` before committing. Do not amend published commits without a coordinated reason.
- Respect the existing branch strategy. No Git Flow by default; keep branches focused and short-lived.
- Merge preserves integration context; rebase gives linear history only for local, unpublished commits. Inspect divergence before choosing.
- Conflicts: read both sides, understand intended behavior, preserve valid work, inspect the diff, run tests, check for conflict markers. Never pick `ours`/`theirs` blindly; ask when intent is unclear.

## Remote, GitHub and recovery

Fetch before assuming remote state. Inspect divergence and the exact target before pushing. Prefer `--force-with-lease` over `--force` only when a rewrite is explicitly authorized. Never claim a PR is approved, merged or green without checking its real state.

Review PRs for correctness, architecture, security, regressions and tests; skip style comments that automation enforces. Keep Actions least-privilege, pin critical third-party actions, and never deploy to production without authorization. Treat an exposed credential as compromised: rotate it; deleting the line does not remove it from history.

On failure: read the exact error, inspect state, check `git reflog`, choose the least destructive recovery, then verify integrity. No destructive recovery from guesswork.

## Verification and report

Confirm branch, working tree, staged changes, history, tracking, synchronization, PR and CI state. Report objective, operations performed, affected commits/files/branches, verification, resulting state and remaining issues. Separate local results from what is actually on GitHub.

## References

- `references/commands-and-safety.md` — operation effects and inspection commands.
- `references/branching-commits.md` — local conventions, PRs and code review.
- `references/recovery-github.md` — recovery, remotes, Actions and releases.
- `templates/change-report.md` — final report shape.
