# Verification and reporting

## Ladder

1. Reproduce the original failure with the exact command.
2. Run the targeted check for the changed behavior, including the failing edge case.
3. Run the project's existing suite for the affected area.
4. Exercise the real environment where the failure was observed: runtime, service, UI or API.
5. Check affected neighbors for regressions.
6. Quote before/after output. Intermittent symptoms need repeated runs, not one lucky pass.

Different layers prove different things. An offscreen render proves geometry and ink, not compositor behavior. A unit test proves the helper, not the wiring.

## If verification fails

Treat it as new evidence. Restate the hypothesis, change one thing, rerun only the affected checks. Do not call the task done to save a round trip.

## Six-field report

1. **Problem** — observed vs expected, with the reproduction.
2. **Root cause** — mechanism and layer, with evidence.
3. **Solution** — what changed and why this option won.
4. **Modified components** — exact paths; separate generated from hand-owned.
5. **Verification** — commands run and their real results.
6. **Remaining issues** — what is unverified, deferred or needs the user's decision.

Never report success without a result you actually produced. List limitations instead of smoothing them over.
