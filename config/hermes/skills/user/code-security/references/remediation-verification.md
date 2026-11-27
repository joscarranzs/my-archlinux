# Remediation and verification

## Severity rubric

| Severity | Meaning |
|---|---|
| Critical | trivial exploitation, wide impact, or direct compromise of protected data/system |
| High | realistic exploitation with serious confidentiality, integrity or availability impact |
| Medium | meaningful weakness with preconditions or limited impact |
| Low | narrow impact or strong mitigating conditions |
| Informational | hardening idea, no demonstrated vulnerability |

Use CVSS when applicable, then adjust for exposure, business criticality and exploitability. Explain the reasoning. Label the finding as confirmed, potential, configuration weakness, improvement or false positive.

## Remediation

1. Find the root cause, not just the triggering input.
2. Identify affected components and the attack conditions.
3. Choose an established mechanism at the correct trust boundary.
4. Check compatibility and regression risk before editing.
5. Apply the smallest effective change; preserve legitimate functionality.
6. Add tests for the attack path and for the legitimate path.
7. Verify the original path no longer works and quote the result.

Reject superficial filters, controls that can be bypassed, custom crypto and fixes that move the vulnerability to another layer.

## Verification gates

- Original exploit or failing scenario is no longer reproducible.
- Unauthorized operations are rejected at the trusted boundary.
- Legitimate operations still work.
- Relevant unit, integration and regression tests pass.
- No new secret, dependency or exposure was introduced.
- Tests ran only in authorized environments; production disruption was not attempted.

## Reporting

Report id, title, severity, component, description, root cause, impact, preconditions, attack scenario, evidence, remediation and verification status. Redact secrets and personal data. State what remains unverified and what would prove it.
