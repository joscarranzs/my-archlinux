---
name: high-quality-code
description: Use when writing, fixing or refactoring code. Verify.
version: 1.0.0
author: joscarranzs
license: MIT
platforms: [linux, macos, windows]
metadata:
  hermes:
    tags: [code-quality, refactor, review, testing, conventions]
    category: user
    related_skills: [how-to-solve-problems, my-system]
---

# High-quality code

Write for the next developer who must debug and modify it. The smallest clear implementation that satisfies the real requirement beats a clever one. Correctness first; complexity needs justification.

## When to use

- Creating, fixing, refactoring or reviewing code.
- Maintaining an existing project without widening its surface.
- Not for unknown failures: load `how-to-solve-problems`. Not for this machine's paths and conventions: load `my-system`.

## Before touching code

1. Read project conventions (`~/.dotfiles/AGENTS.md` here) and the neighboring files.
2. Resolve the real path: generated vs hand-owned. Never hand-edit a generated file.
3. Inspect callers, tests, data flow and dependencies. Do not assume an existing abstraction is defective.
4. State the requirement and the failing behavior in one sentence.

## Non-negotiables

1. Smallest coherent diff. No unrelated cleanup, no speculative features, no drive-by refactor.
2. Reuse existing implementations and recipes. Visual consistency beats a tuned-per-panel value.
3. Names communicate intent; control flow stays straightforward; no magic numbers or unexplained constants.
4. One responsibility per function or module. Extract only when clarity, reuse or testability improve.
5. Duplicated business logic is a defect; superficial similarity alone does not justify an abstraction.
6. Apply SOLID only where it pays: contracts, coupling, testability. No ceremony, factories or layers without a reason.
7. Handle errors at boundaries: validate external input, preserve context, never swallow errors, never leak secrets.
8. Prefer explicit types and contracts; represent nullable and optional values accurately.
9. Comments explain non-obvious decisions, constraints and business rules; delete stale ones. Code and comments are English.
10. Security and reliability are requirements: authorization, injection, secrets, races, resource cleanup, recovery.
11. Measure before optimizing. No readability sacrifice for a negligible gain.
12. Never claim tests passed without running them. Report unavailable checks explicitly.

## Create, fix, refactor

- **Create:** requirements -> existing pieces -> responsibilities -> simplest solution -> edge cases -> tests -> review.
- **Fix:** understand original -> root cause -> smallest change -> caller compatibility -> regression test -> verify the symptom is gone.
- **Refactor:** record behavior and public contracts -> change incrementally -> remove dead code only when proven unused -> run tests -> compare behavior.

## Verification in this repo

Run from `~/.dotfiles`:

```bash
python3 -m unittest discover -s scripts/session/tests
python3 scripts/theme/contrast-report.py | tail -1
bash scripts/session/tests/states/run-all.sh
bash scripts/session/tests/panels/run-all.sh
```

State harnesses render components, not `shell.qml`; open a real shell once and read its log for QML errors. Quote real output. If a check cannot run, say so. Never push without the user's word.

## Definition of done

- Requirement met, root cause addressed, diff contains only planned files.
- Tests and relevant checks executed with output quoted; regressions checked.
- No generated file hand-edited, no unrelated refactor, no fabricated result.
- Conventional English commit only when requested; pushing asks first.

## References

- `references/design-rules.md` — naming, functions, abstraction, SOLID, errors and comments.
- `references/security-reliability.md` — boundaries, secrets, concurrency, resources and recovery.
- `references/refactor-and-review.md` — refactor protocol and the six-axis review.
- `references/testing.md` — verification ladder and reporting.
