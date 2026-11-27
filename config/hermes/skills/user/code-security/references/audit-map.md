# Audit map

## Threat model

Name assets, actors, entry points, trust boundaries, existing controls and attack paths. STRIDE is a prompt, not a ritual:

- Spoofing: identity proof, session handling, credentials.
- Tampering: data integrity, signed or validated inputs, writes.
- Repudiation: audit trails for consequential actions.
- Information disclosure: secrets, personal data, internal details, logs.
- Denial of service: unbounded work, quotas, timeouts.
- Elevation of privilege: role checks, ownership, admin functions.

Keep only threats with a realistic path and an actionable control. Prioritize by likelihood and impact; state the assumption behind each priority.

## Vulnerability checklist

- **Injection:** SQL, NoSQL, command, LDAP, template, XPath, dynamic evaluation. Parameterize or use safe APIs; encode for the output context.
- **Authn/session:** password storage, verification, token validation, expiry, invalidation, recovery. Use vetted libraries; no custom schemes.
- **Authz:** function-level and object-level checks, resource ownership, tenant isolation, admin endpoints, IDOR. Enforce on the trusted side.
- **XSS:** reflected, stored, DOM, unsafe HTML rendering and template interpolation. Context-aware encoding; sanitize only when user HTML is required.
- **CSRF:** state-changing authenticated requests, token, SameSite, Origin/Referer. CORS alone is not CSRF protection.
- **Sensitive data:** keys, tokens, session ids, personal or financial data, internal details in errors and logs. Minimize, encrypt, restrict.
- **Files:** type and size validation, filename handling, path traversal, storage location, executable uploads, permissions. Extensions and client MIME types are not validation.
- **SSRF:** user-controlled URLs, internal networks, cloud metadata, DNS, redirects and protocol restrictions. Validate destinations and restrict network access.
- **Unsafe execution:** deserialization, eval, reflection, object construction, template evaluation, plugin loading. Avoid untrusted code execution.
- **DoS:** large bodies, unbounded queries, recursion, expensive operations, uncontrolled concurrency. Apply limits and timeouts.

## Configuration

Check debug flags, default credentials, excessive permissions, exposed admin interfaces, cookie flags, security headers, CORS, TLS, environment variables and unnecessary network listeners.
