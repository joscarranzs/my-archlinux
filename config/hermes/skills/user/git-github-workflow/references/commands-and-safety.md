# Commands and safety

## Inspect first

```bash
git status --short
git branch -avv
git log --oneline -8
git remote -v
git diff
git diff --cached
git rev-list --left-right --count origin/<branch>...HEAD
git stash list
```

Check for an in-progress merge or rebase before acting: `.git/MERGE_HEAD`, `.git/rebase-merge`, `.git/rebase-apply`.

## Which layer a command touches

| Command | Working tree | Index | Local history | Remote |
|---|---|---|---|---|
| `git restore <file>` | yes | no | no | no |
| `git restore --staged <file>` | no | yes | no | no |
| `git add` | no | yes | no | no |
| `git commit` | no | no | yes | no |
| `git stash` | yes | yes | no | no |
| `git revert` | yes | no | yes (new commit) | no |
| `git reset --soft` | no | yes | yes | no |
| `git reset --mixed` | no | yes | yes | no |
| `git reset --hard` | yes | yes | yes | no |
| `git rebase` | no | no | rewrites commits | no |
| `git push` | no | no | no | yes |

`reset`, `revert` and `restore` are not interchangeable. `revert` is the safe public-history correction: it adds a commit. `reset --hard`, `clean -fd`, force push and branch deletion need explicit authorization when they can discard or hide work.

## Preserve work

- Uncommitted work is the user's work, even when it looks unrelated.
- Prefer a branch, a stash or a separate commit over discarding.
- Before staging, confirm which files belong to the task.
- After any state-changing operation, re-run the inspection block and quote the result.
