---
name: how-to-solve-problems
description: Use when diagnosing a problem. Evidence first, verify.
version: 1.0.0
author: joscarranzs
license: MIT
platforms: [linux, macos, windows]
metadata:
  hermes:
    tags: [debugging, diagnosis, evidence, verification, cost]
    category: user
---

# How to Solve Problems

Understand before editing. Diagnose before fixing. Verify before claiming. A resolution is a claim backed by reproduction, source and real output — not an edit that happened to work once.

## When to use

- Behavior contradicts expected behavior, docs or a prior working state.
- An error, a version mismatch, an unfamiliar tool, flag or config key.
- A fix failed, or worked for reasons you cannot state.
- The impulse to change something just to see what happens.

Out of scope: answers already known, and destructive experiments on live systems.

## Triage first

1. State observed vs expected in one sentence. Include the exact command and exact error text.
2. Size the work: small (one known file), medium (several files or a version question), large (architecture, state, live system).
3. Run only the phases that size needs. Name any phase you skip and why.
4. Choose the cheapest sufficient tools and routes. Escalate a model only when the model itself failed, not when the spec was thin.
5. Do not ask for information obtainable by targeted inspection. Ask only for genuinely missing input, a preference you cannot infer, or an irreversible action.

## The seven gates

Each gate closes before the next opens. Recording the gate result is cheaper than rediscovering it later.

1. **Context** — inspect the relevant files, config, versions, callers and execution path. Never edit here. *Gate:* the components and their relationship are stated in two or three lines.
2. **Diagnosis** — reproduce the failure. Split facts, hypotheses and assumptions. Rank causes by evidence and diagnostic cost; eliminate unsupported ones. Keep symptoms separate from root causes. *Gate:* one root cause with supporting evidence.
3. **Research** — read the installed version's own source, changelog and `--help` before the web; then official docs, then maintainer-confirmed issues. Never invent an API, flag, path or config key. *Gate:* a source for the exact version, or an explicitly labelled deduction.
4. **Plan** — pick the simplest change that fully addresses the root cause. List files, edge cases, the verification command and the rollback before editing. One change per hypothesis. *Gate:* success criteria written down in advance.
5. **Implement** — smallest coherent diff, project conventions, no drive-by refactor, no silent loss of existing behavior. *Gate:* the diff contains only planned files.
6. **Verify** — rerun the original reproduction, then project checks and affected neighbors. Quote real before/after output. A failure sends you back to diagnosis with a new hypothesis, never to the same edit. *Gate:* symptom gone, checks executed, regressions checked.
7. **Report** — problem, root cause, solution, files, verification with results, remaining issues. Mark unverified claims explicitly. *Gate:* no claim without evidence.

## Rules that prevent wasted cycles

- Label every claim: **fact** (checked), **hypothesis** (testable), **assumption** (unverified).
- Probe the failure mode itself. A lookup that always answers cannot detect a miss; a guard on it is dead code.
- Treat absent errors as suspicious: undefined config keys, roles and silent defaults can render plausible output while doing nothing.
- One variable per probe. Decide the cheapest falsifying test and its rollback before running it.
- Never repeat an unchanged action. Each iteration must add information or measurable progress.
- Batch independent reads and checks; do not reread unchanged files; push depth into `references/` instead of a fat skill body.
- Stop after two iterations with no new information. Report what is unknown and what artifact would unblock it.
- Ask before irreversible actions: pushes, deletions, force operations, production changes.
- Never fabricate output or report tests as passed unless you ran them.

## Adaptation

Small problem: gates 1, 2, 5, 6. Medium: all seven, research bounded to the exact version. Large: all seven, implement incrementally, verify each step and write a handoff if the session ends mid-work.

## References

- `references/diagnosis.md` — evidence ledger, source trust tiers, first probes by failure surface.
- `references/experiments.md` — bounded probes, silent failures, stop rules.
- `references/verification.md` — verification ladder and the six-field report.
- `templates/investigation-log.md` — fill-in log for medium and large problems.
