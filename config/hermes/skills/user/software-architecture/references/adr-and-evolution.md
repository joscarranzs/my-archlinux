# Decision records and evolution

## When to write an ADR

Write one for a decision that changes boundaries, data ownership, trust, deployment or a hard-to-reverse contract. Skip trivial implementation choices and style.

One decision per file, append-only. Never rewrite a past ADR: supersede it with a new one that names the old decision.

Fields: status, date, context with facts and numbers, one-sentence decision in active voice, alternatives rejected with concrete reasons, consequences (gains, accepted costs, new constraints), and revisit triggers that are observable events.

In this repo, long-lived decisions belong in `~/.dotfiles/docs/<topic>.md`. Session state and verification numbers belong in `docs/handoff-<date>.md`, which is re-verified by the next session.

## Changing an existing architecture

1. Understand the current design and why it exists.
2. Name the limitation with evidence: a number, a failure, a repeated change cost.
3. Evaluate impact on requirements and affected components.
4. Check backward compatibility and data migration.
5. Propose the smallest justified change with a migration path.
6. Verify behavior and compatibility after the change.

Evolution beats rewrite. A rewrite needs a named limitation that incremental change cannot fix, plus a migration and rollback plan.

## Revisit triggers

Write triggers you can observe: traffic above N, a second consumer, a dependency abandoned, a contract that breaks at version X, an incident trace. "If it ever gets big" is not a trigger.
