# Refactor and review

## Refactor protocol

1. Name the quality problem and the exact behavior that must stay identical.
2. Identify public interfaces, callers, tests and generated boundaries.
3. Change one concern at a time; keep the diff reviewable.
4. Remove dead code only after confirming it is unused.
5. Run affected tests, then the wider suite.
6. Compare observable behavior before and after; report any intended difference.

Refactoring is not a redesign. A behavior change belongs in a separate, explicit change.

## Final review

| Axis | Questions |
|---|---|
| Readability | Are names meaningful, flow clear, constants explained? |
| Architecture | Are responsibilities cohesive, coupling controlled, abstractions justified? |
| Maintainability | Is logic duplicated, is the diff small, are dependencies needed? |
| Reliability | Are edge cases and errors handled, contracts preserved? |
| Security | Is external input validated, are secrets protected, no new insecure path? |
| Verification | Which tests ran, what was the output, were regressions checked? |

If a critical criterion fails, fix it before declaring done.

## Before finishing

- Diff contains only the planned files; no generated file was hand-edited.
- Compatibility with existing callers checked.
- Tests and checks were really executed; absent checks are listed.
- Findings that remain unresolved are stated plainly, not smoothed over.
