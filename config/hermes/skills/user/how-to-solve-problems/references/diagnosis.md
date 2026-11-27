# Diagnosis

## Evidence ledger

Keep this in the chat or the investigation log. It prevents arguing from memory.

| Claim | Label | Source or command | What would disprove it |
|---|---|---|---|
| ... | fact / hypothesis / assumption | exact command or doc line | ... |

- **fact**: you ran it or read it in a source for the installed version.
- **hypothesis**: testable, with a named cheapest test.
- **assumption**: unverified. Never use one as the reason for an edit.

## Source trust tiers

| Tier | Source | What it justifies |
|---|---|---|
| T1 | official docs, installed version's source, changelog | the fix, as fact |
| T2 | maintainer-confirmed issue, PR, merged fix | the fix, with version checked |
| T3 | forum or blog reproducible locally | a hypothesis, never a conclusion alone |
| T4 | unverified answer, model output | nothing on its own |

A higher tier wins. A newer T1 beats an older T3. Reproducing a T4 claim locally promotes it to your own T1 evidence; say that you reproduced it.

## First probes by surface

- Runtime: exact command, full error, exit code, verbose flag, version string.
- Build/deps: lockfile, installed version, import or link path, clean rebuild.
- Config: the key the code reads vs the key the file declares; no silent defaults.
- Environment: relevant env vars, shell, user, cwd, service manager, platform.
- Permissions: effective user, file mode, capability, sandbox or namespace.
- Network/service: reachability, DNS, port, listener, logs at the time of failure.
- State/timing: fresh vs warm state, ordering, async arrival, one-frame races.

## Separate the layers

Symptom: what you observe. Root cause: the mechanism that produces it. Contributing factor: makes it worse but does not produce it. Unrelated error: coexists and must not be folded into the fix.
