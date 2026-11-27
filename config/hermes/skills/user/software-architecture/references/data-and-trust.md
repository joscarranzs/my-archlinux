# Data, trust and reliability

## Data ownership

- Name the owner of every table, file, format and cache. Only that component writes it.
- Define transactions and consistency expectations explicitly. Eventual consistency is a contract, not an accident.
- Validate data at boundaries and at ownership transitions.
- Avoid duplicate sources of truth; a cache must be reconstructible from its owner.
- Define API contracts: fields, types, versioning, error shapes and compatibility rules.

## Integration

- Prefer explicit contracts over shared internal state.
- State delivery guarantees, ordering and idempotency for each message path.
- Handle a consumer's absence deliberately: fail, degrade or queue, with a named owner for each choice.
- Avoid tightly coupled integrations where one side must know the other's internals.

## Trust boundaries

Map where trust changes: user input, network, filesystem, subprocess, configuration, external API, privileged service. At each boundary: authenticate, authorize, validate, isolate data and apply least privilege. Application-level validation alone is not a security architecture.

Manage secrets outside code, docs, cards and logs. Encrypt sensitive data in transit and at rest where the requirement demands it. Keep auditability where actions are consequential.

## Reliability

- Identify single points of failure and dependency failure modes.
- Bound retries with timeouts and backoff; add a circuit breaker only when repeated failure is observable and harmful.
- Prefer graceful degradation over total failure when the requirement allows it.
- Define recovery: what can be replayed, what needs reconciliation, what needs a human.
- Back up durable state and test restoration; a backup that was never restored is a hypothesis.
- Add observability at boundaries: useful logs, metrics and error signals for the failure scenarios you designed for.
