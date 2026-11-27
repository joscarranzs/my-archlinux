---
name: code-security
description: Use when auditing or fixing security. Evidence, no secrets.
version: 1.0.0
author: joscarranzs
license: MIT
platforms: [linux, macos, windows]
metadata:
  hermes:
    tags: [security, audit, vulnerabilities, secrets, remediation]
    category: user
    related_skills: [high-quality-code, software-architecture, my-system]
---

# Code security

Security is continuous risk reduction, not a state called "secure". Never trust unvalidated input, never assume authorization, never expose sensitive data, never claim security without evidence.

## When to use

- Auditing code, configuration or dependencies for vulnerabilities.
- Fixing a confirmed weakness or reviewing a security-sensitive change.
- Threat modeling a design or significant boundary change.
- Not for style or implementation quality: load `high-quality-code`. Not for system shape: load `software-architecture`. Not for this machine's paths and local decisions: load `my-system`.

## Before auditing

1. Map trust boundaries, identity and permission propagation, untrusted inputs, privileged operations, sensitive data, network exposure, versions and configuration.
2. Never assume a component is secure because it looks clean, and never treat frontend validation as backend security.
3. Use official sources: OWASP, language/framework docs, NIST, CWE, CVE and vendor advisories. Verify the advice applies to the exact version.
4. Label findings: confirmed vulnerability, potential vulnerability, configuration weakness, improvement or false positive. Do not invent exploitability.
5. Never print, log or paste secrets during investigation. On a login, checkout or 2FA form use `browser_vault`; never type a credential supplied in chat.
6. Test only authorized systems. No destructive or disruptive tests against production without explicit approval.

## Non-negotiables

1. Validate untrusted input at the boundary; use parameterized queries and context-aware output encoding. Blacklists alone are not a control.
2. Enforce authentication and authorization on the trusted side, including object-level ownership. Hiding a UI element is not access control.
3. Use established authentication, token and cryptographic libraries. No custom crypto without a reviewed justification.
4. Never hardcode, log, commit or store secrets in cards, handoffs or chat summaries. Minimize sensitive data and encrypt it where required.
5. Apply least privilege and secure defaults: no debug mode in production, no excessive permissions, no unnecessary exposure.
6. Bound resource use: limits, quotas, timeouts and rate limits for expensive or attacker-controlled work.
7. Verify dependency advisories for applicability before upgrading; prefer minimal compatible updates. Never mass-update blindly or add unverified "security" packages.
8. Rank severity by exploitability, impact, exposure and business context, not by the vulnerability's name. Explain significant calls.
9. Fix the root cause with the smallest effective change, add a security test, preserve legitimate behavior and verify the issue is no longer reproducible.
10. Quote real test output. Never fabricate a finding, exploit or verification result, and never claim complete security.

## Workflow

Context -> assets, actors, entry points and boundaries -> threat model (STRIDE when it produces actionable items) -> prioritized findings -> smallest remediation -> tests -> report. Skip speculative threat lists with no control to improve.

This machine already has deliberate security decisions: fail-closed PAM, an unlock marker before suspend, logind lid ignore, NM as sole network owner and LLMNR off. Read `my-system` before changing any of them; never weaken the marker wait.

## Verification

Use what the ecosystem supports and what is installed: SAST, SCA/dependency scanning, secret scanning, configuration audits, input-validation tests, authorization tests and targeted tests. Check availability with `command -v` before relying on a scanner. Confirm the original attack path fails, unauthorized operations are rejected, legitimate ones still work, and regressions pass.

## Report

Every meaningful finding carries an id, title, severity, component, description, root cause, impact, preconditions and attack scenario, evidence, remediation and verification status. Redact secrets and personal data.

## References

- `references/audit-map.md` — threat modeling and the vulnerability-class checklist.
- `references/dependencies-config.md` — supply chain, configuration and secret handling.
- `references/remediation-verification.md` — severity rubric, fixes and verification gates.
- `templates/security-finding.md` — fill-in report.
