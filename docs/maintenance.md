# Maintenance backlog

Pending, non-urgent repository work. Nothing here is broken; it is cleanup that
needs a history rewrite or a decision, so it is not part of normal commits.

## Done: shrink `.git` (was ~476 MB)

236 wallpaper assets under `wallpapers/list/` had been committed and later
deleted, so almost the whole weight of the repository was dead history. The
strip was done on `rewriting` and on the local `backup/pre-squash-*` branch
with `git filter-branch` (git-filter-repo was not installed):

```bash
git filter-branch --index-filter \
    'git rm -r --cached --ignore-unmatch wallpapers/list' --prune-empty -- rewriting
git reflog expire --expire=now --all && git gc --prune=now
```

`.git` went from 476 MB to 23 MB. The working tree is byte-identical: both the
branch and the backup kept the same tree hash, and only the dead blobs went
away. Every commit hash changed, so anything else that tracks this branch must
re-clone instead of pull.

The pre-rewrite history stays reachable on the remote as the tags
`archive/2026-09-24-pre-rewrite` and `snapshot/pre-rewrite-config` (the old
`backup/pre-rewrite-20261111` branch was retired in favour of tags); keep them
until no clone is behind, otherwise the old blobs stay served there.

`wallpapers/list/` is gitignored now: image collections live outside the
repository (they are dropped into `~/.wallpapers/current`), because a single
15 MB PNG versioned twice costs more than the rest of the repo together.
