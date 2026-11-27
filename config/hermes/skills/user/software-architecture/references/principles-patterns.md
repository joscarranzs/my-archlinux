# Principles and patterns

## Boundaries

- Split by responsibility and change rate, not by fashion or file count.
- One direction of dependency; no cycles. If two modules need each other, the split or the shared abstraction is wrong.
- Small stable interfaces: minimal public surface, private internals.
- One owner per piece of data: the owner of a table, file or format is the only writer.
- No god module. If one file answers "what does the project do?" with everything, split it.
- Separate presentation, business logic, persistence, infrastructure and cross-cutting concerns only as far as the project's complexity warrants.

## Simplicity ladder

Walk upward only when the requirement forces it:

1. One module with clear functions.
2. A few cohesive modules with explicit boundaries.
3. Layers, only if substitution or isolation has a real use.
4. Hexagonal/clean boundaries, only if the domain must survive infrastructure changes.
5. Separate services, only with independent deployment, ownership or scaling needs.

## Pattern costs

| Pattern | Buys | Costs |
|---|---|---|
| Modular monolith | cohesion, cheap changes, one deployment | shared runtime and deploy unit |
| Layered | separation of concerns | can become ceremony without real boundaries |
| Hexagonal / clean | domain isolation, testability | adapters and indirection |
| Event-driven | decoupling in time, fan-out | eventual consistency, replay and debugging cost |
| Microservices | independent deploy and scale | network failures, distributed data, operations |
| Microkernel | plugin extensibility | plugin contracts and lifecycle management |
| Pipe-and-filter | streaming transformations | error propagation across stages |

SOLID applies at boundaries when it reduces coupling or protects a contract. It never justifies interfaces, factories or dependency injection without a consumer.

## Reversibility

Prefer decisions that can be changed with a small diff. Make the expensive, hard-to-reverse choices only after evidence: data model, API contract, deployment topology, trust boundary.
