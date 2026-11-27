# Dependencies, configuration and secrets

## Supply chain

- Review direct and transitive dependencies, versions, lockfile integrity, provenance and install scripts.
- Check advisories from official sources: GitHub Advisory, OSV, ecosystem scanners, vendor announcements.
- Verify applicability: a CVE in an unused code path or another platform may not affect this system.
- Prefer the smallest compatible security update. Check breaking changes and tests before upgrading.
- Remove unused dependencies; every extra package is attack surface.
- Use only tools applicable to the ecosystem. On this host `npm` is present; `pip-audit`, `trivy` and `gitleaks` are not. Check with `command -v` before planning a scan.

## Secrets

- No secrets in source, tests, fixtures, task cards, handoffs, reports or chat.
- Use environment or a secret manager appropriate to the deployment; restrict file permissions and access.
- Rotate anything that was ever exposed; deleting the line is not rotation.
- On browser login, checkout or 2FA forms use `browser_vault`. Never type a password, card number, CVC or code through the browser tool, and never accept one in chat.
- Keep logs free of credentials, tokens and personal data; redact before sharing output.

## Configuration audit

Compare live configuration against secure defaults: no debug in production, no default credentials, least privilege, bounded exposure, correct cookie flags, headers, CORS, TLS and safe environment handling. Verify the running value, not just the file: a desktop env var here can come from `hl.env()` or `environment.d`.

## Reporting

Describe the exact version, configuration and evidence. Never turn a theoretical advisory into a confirmed vulnerability without a reachable path.
