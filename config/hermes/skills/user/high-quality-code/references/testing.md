# Testing and reporting

## Ladder

1. Reproduce the original failure with the exact command when feasible.
2. Add or update a targeted test for the changed behavior and its edge cases.
3. Test failure scenarios and compatibility with callers.
4. Run the project's suite for the affected area.
5. Exercise the real environment where the defect appeared: service, runtime or UI.
6. Check affected neighbors for regressions.
7. Quote before/after output. Intermittent symptoms need repeated runs.

Different layers prove different things: a unit test proves a helper, not its wiring; an offscreen render proves geometry and ink, not compositor behavior.

## In this repo

From `~/.dotfiles`:

- `python3 -m unittest discover -s scripts/session/tests`
- `python3 scripts/theme/contrast-report.py | tail -1`
- `bash scripts/session/tests/states/run-all.sh`
- `bash scripts/session/tests/panels/run-all.sh`

State harnesses render components, not `shell.qml`. Open a real shell once and read its log for QML errors the harnesses cannot see.

## Reporting

State the exact commands, their real results and anything that could not be checked. Never say tests passed unless you ran them. Never fabricate output. If verification failed, treat it as new evidence: revise the hypothesis, change one thing, rerun only what the change affects.
