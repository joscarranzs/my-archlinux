# Recovery, remotes and GitHub

## Recovery

1. Read the exact error; do not guess from the command name.
2. Inspect branch, status, staged changes and merge/rebase state.
3. Use `git reflog` to find stable recovery points.
4. Choose the least destructive option that preserves work.
5. Verify the tree, history and remotes afterward.

A published-history rewrite requires coordination. Prefer `revert` for shared history. Never run `reset --hard`, `clean -fd` or force push as a blind fix.

## Remotes

Fetch before reasoning about remote state. Check `git rev-list --left-right --count origin/<branch>...HEAD` and the exact target before push. Verify the remote URL before changing it. Use `--force-with-lease` only for an explicitly authorized rewrite. Credentials never go in commands, logs, cards or chat; use the configured credential helpers or `browser_vault` for browser auth.

A successful local operation says nothing about GitHub. Verify the remote branch, PR, checks and release state after the operation.

## GitHub operations

Respect permissions and repository conventions. Do not change settings, branch protection, CODEOWNERS or access without an explicit requirement and authorization. Never claim a PR was approved or merged without checking.

## Actions and CI

Check triggers, jobs, permissions, secrets, caching, deploy conditions and artifact handling. Use least privilege, pin critical third-party actions to verified SHAs, keep secrets out of logs, validate workflow syntax and verify real run results. No production deploy without explicit authorization and safeguards.

## Tags and releases

Respect the project's versioning; never invent a number. Verify the target commit before tagging. Do not move or overwrite a published release tag without authorization. Distinguish a local tag from a published GitHub release, and keep release notes truthful.
