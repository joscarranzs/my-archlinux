"""Tests for the terse-output injection. Run: python3 -m unittest discover -s tests"""

from __future__ import annotations

import importlib.util
import sys
import unittest
from pathlib import Path

PLUGIN = Path(__file__).resolve().parent.parent


class Ctx:
    def __init__(self):
        self.hooks = {}

    def register_hook(self, name, fn):
        self.hooks[name] = fn


def load():
    spec = importlib.util.spec_from_file_location("caveman_voice", PLUGIN / "__init__.py")
    module = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    ctx = Ctx()
    module.register(ctx)
    return module, ctx


mod, ctx = load()
hook = ctx.hooks["pre_llm_call"]


class TestRegistration(unittest.TestCase):
    def test_registers_pre_llm_call(self):
        self.assertEqual(set(ctx.hooks), {"pre_llm_call"})


class TestInjection(unittest.TestCase):
    def test_injects_on_an_empty_session(self):
        out = hook(session_id="s", user_message="hi", conversation_history=[])
        self.assertIsInstance(out, dict)
        self.assertIn("[terse-output-mode]", out["context"])

    def test_does_not_pay_twice(self):
        # Once the rule is in the transcript it stays there; re-injecting it on
        # every turn is the tax this plugin exists to avoid.
        history = [
            {"role": "system", "content": "persona"},
            {"role": "user", "content": mod.RULES + "\nhola"},
            {"role": "assistant", "content": "ok"},
        ]
        self.assertIsNone(hook(session_id="s", user_message="otra", conversation_history=history))

    def test_reinjects_after_compaction_drops_it(self):
        history = [
            {"role": "user", "content": "[summary of earlier turns]"},
            {"role": "assistant", "content": "ok"},
        ]
        self.assertIsNotNone(hook(session_id="s", user_message="seguí", conversation_history=history))

    def test_bad_history_does_not_raise(self):
        for bad in (None, "", 42, [object()], {"weird": object()}):
            hook(session_id="s", user_message="x", conversation_history=bad)

    def test_hook_never_raises_with_no_arguments(self):
        hook()


class TestRuleContent(unittest.TestCase):
    def test_rule_block_is_cheap(self):
        tokens = (len(mod.RULES.encode()) + 2) // 3
        self.assertLess(tokens, mod.MAX_CONTEXT_TOKENS, f"{tokens} tokens")

    def test_rule_protects_payload_and_negations(self):
        lowered = mod.RULES.lower()
        for required in ("verbatim", "negation", "paths", "numbers", "error text"):
            self.assertIn(required, lowered)

    def test_rule_has_the_escape_hatches(self):
        lowered = mod.RULES.lower()
        for required in ("security", "irreversible", "confused", "question you"):
            self.assertIn(required, lowered)


if __name__ == "__main__":
    unittest.main()
