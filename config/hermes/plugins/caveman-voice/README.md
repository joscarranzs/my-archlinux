# Caveman Voice

One job: terse output mode. No extra traffic.

## What it does

`pre_llm_call` injects a compact rule block the first time a session's transcript
lacks it, then stays quiet. Cost: ~220 tokens once per session (or again after
compaction drops the marker), instead of the ~1,160 tokens upstream spends on
every turn — and every one of those tokens is re-read on all the following API
calls.

The marker is `[terse-output-mode]`: its presence in the serialized history is
the whole "already injected" check, and it only ever appears in an injected
message, so a substring hit is a real hit.

## What the rules protect

Code, commands, paths, numbers, units, counts and error text stay verbatim.
Negations (`not`, `never`, `no`, `only`, `except`) are never dropped. Brevity
never justifies losing a step, a caveat or a nuance that changes the answer, and
these switch to full prose: security warnings, irreversible or destructive
actions, a confused user, and any question the agent asks.

Terse, not vague.

## Why `pre_llm_call` and not a system-prompt section

`register_system_prompt_section` would freeze the rule at session start, add
~180 bytes of wrapper, and save no tokens over an injection the prefix cache
already covers. Migrating would be churn.

## Tests

```
python3 -m unittest discover -s tests
```

9 tests: registration, injection on an empty session, not paying twice,
re-injection after compaction drops the marker, bad history, a hook call with no
arguments, the rule budget, payload/negation protection, and the escape hatches.
