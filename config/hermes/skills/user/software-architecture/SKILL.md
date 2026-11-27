---
name: software-architecture
description: Use when designing or changing system structure. Evidence.
version: 1.0.0
author: joscarranzs
license: MIT
platforms: [linux, macos, windows]
metadata:
  hermes:
    tags: [architecture, design, decisions, boundaries, adr]
    category: user
    related_skills: [high-quality-code, how-to-solve-problems, my-system]
---

# Software architecture

Architecture manages complexity; it does not create it. Design the simplest structure that satisfies the actual functional and non-functional requirements, with a credible evolution path.

## When to use

- Designing a new system, service boundary, data flow or integration.
- Changing module boundaries, coupling, ownership or deployment shape.
- Evaluating a pattern, migration or architectural trade-off.
- Not for implementation style: load `high-quality-code`. Not for unknown failures: load `how-to-solve-problems`. Not for this machine's layout: load `my-system`.

## Before designing

1. Inspect the real structure: components, dependencies, data ownership, communication, deployment and constraints. Nothing can be inspected? Say what is unknown.
2. Separate architectural problems from isolated implementation defects.
3. List functional requirements and rank non-functional ones: performance, reliability, security, compatibility, observability, operational cost.
4. Identify existing components and decisions worth reusing. Never replace an approach without naming its real limitation.
5. Read prior decisions in `docs/` and the latest handoff before proposing a new one.

## Non-negotiables

1. No pattern by popularity. Choose the least complex shape that meets the requirement; name the operational cost of anything heavier.
2. No distributed system, microservices or queue without a concrete requirement. A modular monolith usually wins.
3. Boundaries follow responsibility and change rate, with one direction of dependency and no cycles.
4. One owner per piece of data. Define explicit contracts and the failure behavior when a consumer is unavailable.
5. Abstract only where the boundary reduces coupling or clarifies a contract. No generic layers, factories or wrappers for theory.
6. Define trust boundaries, authentication, authorization, secrets handling and least privilege at design time.
7. Reliability mechanisms need understood failure modes: bounded retries, timeouts, graceful degradation and recovery. No retry storms or invented consensus.
8. Design for measured or reasonably anticipated load. No optimization for imaginary traffic; scalability claims need evidence.
9. Prefer incremental evolution and reversibility. A rewrite needs a named limitation, migration path and rollback.
10. Document significant decisions as ADRs; skip trivial implementation details. English documentation.

## Design loop

Context -> requirements and constraints -> at least two alternatives -> decision -> trade-offs -> consequences -> migration -> validation. Write the reason each alternative was rejected; that is what future readers need.

Respect this machine's existing structures: generated files stay generated, Quickshell panels stay one process each, and the lock and network paths have single-owner rules. See `my-system`.

## Validation

Check dependency direction, cycles, responsibility violations, ownership consistency and operational complexity. Exercise integration paths and failure scenarios; run load tests only when the requirement justifies them. In this repo, start with `python3 -m unittest discover -s scripts/session/tests` and the states/panels harnesses, then add architecture-specific checks.

Never claim a design is scalable, secure or highly available without supporting evidence. Report unverified properties explicitly.

## Final review

Structure, dependencies, complexity, evolution, reliability and security. If a critical axis fails, fix the design before presenting it.

## References

- `references/principles-patterns.md` — boundaries, simplicity ladder and pattern costs.
- `references/data-and-trust.md` — ownership, contracts, security and reliability.
- `references/adr-and-evolution.md` — decision records, migration and reversibility.
- `references/validation.md` — evidence and the final review.
- `templates/adr.md` — append-only decision record.
