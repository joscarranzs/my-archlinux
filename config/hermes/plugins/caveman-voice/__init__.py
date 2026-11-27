"""Caveman Voice — terse output mode injected through `pre_llm_call`.

The rules are caveman's idea ("say less"), rewritten to ~220 tokens and injected
once per session instead of once per turn: upstream adds ~1,160 tokens of context
on every turn, and every one of those tokens is re-read on all the following API
calls. This one pays ~220 tokens when the rule is missing from the transcript and
nothing afterwards, so the tax is paid once per session (or again after
compaction drops it) rather than once per turn.

Every rule left here changes the output; the wording around them was cut: the
"user's language wins" and "no closing offer" lines were saying twice what one
line says, and the filler list was eleven examples for one idea.

Payload is never compressed: code, paths, numbers, counts and error text are
copied verbatim, and a negation is never dropped. Terse, not vague.

Kept on `pre_llm_call` on purpose: `register_system_prompt_section` would freeze
the rule at session start, cost ~180 extra bytes of wrapper, and save no tokens
over an injection the prefix cache already covers. Migrating would be churn.
"""

from __future__ import annotations

import json

MARKER = "[terse-output-mode]"

# Budget for the injected block, asserted by the tests: the rule set must stay
# cheap enough to ride every session without becoming context overhead.
MAX_CONTEXT_TOKENS = 400

RULES = f"""{MARKER}
Reply style. Length only: language stays the user's, facts stay unchanged.

- Answer first. No greeting, preamble, recap or closing pleasantry.
- One idea per sentence, <=20 words. Fragments fine. Drop filler.
- Verbatim: code, commands, paths, numbers, units, error text. Never abbreviate a
  path or round a number.
- Never drop a negation: not, never, no, only, except.
- Cut prose, not facts: keep every count, result, caveat and step.
- Terse for a simple task; full detail for a complex, multi-step or risky one.
  Brevity never justifies dropping a step, a caveat or a nuance that changes the
  answer.
- Tool runs: one line before, one line with the result. No narration between calls.
- Full prose instead, then resume: security warnings, irreversible or destructive
  actions, a confused user, any question you ask.
"""


def _already_injected(history) -> bool:
    """True when the rule is still visible in the transcript.

    Cheap check on the serialized history: the marker only ever appears in an
    injected user message, so a substring hit is a real hit.
    """
    if not history:
        return False
    try:
        blob = json.dumps(history, ensure_ascii=False, default=str)
    except Exception:
        return False
    return MARKER in blob


def inject(session_id=None, user_message=None, conversation_history=None, **kwargs):
    """Return the rule block when the transcript has lost it, else None."""
    try:
        if _already_injected(conversation_history):
            return None
        return {"context": RULES}
    except Exception:
        return None


def register(ctx):
    ctx.register_hook("pre_llm_call", inject)
