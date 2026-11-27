# Handoff — template

Copy to `docs/handoff-YYYY-MM-DD.md`, fill, commit. **Never leave a handoff only
in a chat**: a deleted conversation is a deleted handoff, and the paste that
replaces it arrives truncated exactly where the pending work was.

Rules that make the file worth reading tomorrow:

- **Every number comes from a command run at the close of the session.** If you
  did not run it, do not write it - "I think there were 58 skills" is worse than
  nothing, because it gets quoted next time as fact.
- **State the command next to the value** (section 1). The next session re-runs
  the block instead of trusting the file, and a stale handoff announces itself.
- **Section 6 is never empty.** If nothing is pending, write "nothing" - an empty
  section is indistinguishable from a truncated file.
- **Commit the handoff last**, and let section 1 name the sha the session closed
  on, plus the handoff commit itself.

---

# Handoff - <date> (<one line: what it was about>)

## 1. Exact state at close

Everything below must be reproducible with these commands:

```bash
cd ~/.dotfiles
git log -1 --format='%h %s'; git status --short | wc -l
git rev-list --left-right --count origin/<branch>...HEAD
python3 -m unittest discover -s scripts/session/tests 2>&1 | tail -1
find config/hermes/skills -name SKILL.md | wc -l
hermes plugins list --plain --no-bundled
python3 scripts/session/tokens.py
```

repo:      branch / HEAD / dirty files / ahead-behind
tests:     N/N
skills:    N SKILL.md, symlink target
plugins:   name version + test count
audit:     problems=N warnings=N
tokens:    spent / balance / purchased, portal agrees?

## 2. What was done

One block per change, with the numbers that justify it. Add the diagnosis that
decided the order, and say what was measured versus assumed.

## 3. What was installed and where it lives

Path per artifact, and whether it is versioned, symlinked or hand-maintained.
Anything a restore script would have to recreate goes here.

## 4. Commits

    <sha> <type(scope): subject>

## 5. Traps paid for

One bullet per trap: what looked right, what was actually wrong, what to do
instead. These are the most expensive lines in the file - a trap that is not
written down gets paid for again.

## 6. Pend

- [ ] item - with the file or command that proves it is done
- [ ] item - what blocks it, if anything
