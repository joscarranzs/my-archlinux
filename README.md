# Hermes user skills

This is an orphan branch: its history contains only the editable skills tree.
It is separate from `development` because skills change more often than the
desktop configuration.

## What is here

- `config/hermes/skills/user/<name>/SKILL.md` — the compact skill body.
- `references/` and `templates/` — depth loaded on demand, never pasted into the body.
- `.bundled_manifest` and `.gitignore` — keep hub caches and runtime locks out of git.

Current skills: `code-security`, `git-github-workflow`, `high-quality-code`,
`how-to-solve-problems`, `kanban`, `my-system`, `software-architecture`.

Hub skill directories are not source. Hermes recreates them on boot and its
curator writes into them, so only `user/` is staged here. The ten legacy
`DESCRIPTION.md` files from those directories were left in the old repository.

## Attach it to Hermes

From a clone of `my-archlinux` checked out on `development`:

```bash
git worktree add ~/.local/share/hermes/skills skills
ln -sfn ~/.local/share/hermes/skills/config/hermes/skills ~/.hermes/skills
```

If `~/.hermes/skills` is already a symlink, replace it with the command above.
Hermes reads skills from `~/.hermes/skills`, so the symlink, not a copy, is what
keeps edits in this branch.

## Edit and verify

- Keep `SKILL.md` bodies short and push depth into `references/` or `templates/`.
- Write in English: descriptions, bodies, support files and commit messages.
- Validate from the `development` worktree:

```bash
python3 scripts/skills/validate-user-skills.py \
  --tree ~/.local/share/hermes/skills/config/hermes/skills
hermes skills list
```

- Commit with Conventional Commits: `feat(skills): ...`, `fix(skills): ...`,
  `docs(skills): ...`.
- Push with `git push origin skills`. The branch is orphan by design; do not
  merge it into `development`.
