# Security and reliability

## Boundaries

- Validate all external input: files, env vars, CLI flags, API payloads, database rows, QML properties from services.
- Check authorization and authentication at the boundary, never deep inside a helper that assumes a trusted caller.
- Keep injection in mind for shell commands, SQL, paths and rendered markup.
- Encode paths and arguments safely; no ad-hoc shell quoting where argv works.
- Treat configuration and generated files as input too: a missing role or absent binary can fail silently.

## Sensitive data

- Never print or log passwords, tokens, keys, cards or 2FA codes.
- Use the credential vault on login or payment forms; never type a secret supplied in chat.
- Minimize what is stored; keep secrets out of task cards, handoffs and chat summaries.

## Concurrency and state

- Watch shared mutable state, ordering, async answers and one-frame races.
- Use locks or single-owner rules where two writers can collide; never rely on timing luck.
- Decide failure and rollback behavior before mutating durable state.
- Preserve data consistency across related writes; avoid partial updates.

## Resources and recovery

- Close files, connections and processes on every path, including errors.
- Bound retries and timeouts; every loop must be able to end.
- Plan recovery for partial failure: what is in flight, what can be repeated, what needs a human.
- Check dependency and package vulnerabilities when the change touches supply chain or install steps.
- Never introduce an insecure shortcut for speed.
