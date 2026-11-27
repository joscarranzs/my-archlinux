# Validation

## Evidence ladder

1. Dependency analysis: import/reference graph, direction, cycles, ownership violations.
2. Architecture tests asserting the boundaries that matter, when the project has them.
3. Integration tests across each component boundary and external contract.
4. Failure-scenario analysis: timeouts, absent dependency, bad input, partial write, replay.
5. Security review of trust boundaries and secret handling.
6. Load testing only when a performance or scale requirement exists.
7. Deployment or runtime verification in the real environment.

Different checks prove different things. A dependency graph says nothing about runtime failure behavior; a unit test says nothing about a contract.

## In this repo

From `~/.dotfiles`:

- `python3 -m unittest discover -s scripts/session/tests`
- `bash scripts/session/tests/states/run-all.sh`
- `bash scripts/session/tests/panels/run-all.sh`
- `python3 scripts/theme/contrast-report.py | tail -1` for visible surfaces.

Add architecture-specific checks when a boundary has none. Quote real output.

## Final review

| Axis | Check |
|---|---|
| Structure | responsibilities clear, boundaries justified, coherent shape |
| Dependencies | direction intentional, no cycles, coupling controlled |
| Complexity | a simpler design cannot satisfy the requirements |
| Evolution | migration path understood, expensive choices justified, ADR written |
| Reliability/security | failure scenarios addressed, trust boundaries defined |

Never claim the design is scalable, secure or highly available without evidence. List what remains unverified and what would prove it.
