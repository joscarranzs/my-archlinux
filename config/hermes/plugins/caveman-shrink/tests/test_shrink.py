"""Tests for the shrink hook. Run: python3 -m unittest discover -s tests"""

from __future__ import annotations

import json
import os
import re
import subprocess
import tempfile
import time
import unittest
import unittest.mock
from pathlib import Path

PLUGIN = Path(__file__).resolve().parent.parent

# Every spill goes to a sandbox home: a suite run must never litter the real
# ~/.hermes/cache/terminal-output with copies of the fixtures.
TEST_HOME = tempfile.mkdtemp(prefix="caveman-shrink-test-")
os.environ["HERMES_HOME"] = TEST_HOME



class Ctx:
    def __init__(self):
        self.hooks = {}

    def register_hook(self, name, fn):
        self.hooks[name] = fn


def load():
    import importlib.util
    import sys

    spec = importlib.util.spec_from_file_location("caveman_shrink", PLUGIN / "__init__.py")
    module = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    ctx = Ctx()
    module.register(ctx)
    return module, ctx


mod, ctx = load()
hook = ctx.hooks["transform_terminal_output"]


def log_sample(levels_and_messages, pad=0):
    lines = []
    for index, (level, message) in enumerate(levels_and_messages):
        lines.append(f"Nov 15 11:34:{index % 60:02d} msi unit[123]: {level} {message}")
    for index in range(pad):
        lines.append(f"Nov 15 11:35:00 msi unit[123]: INFO heartbeat ok {index}")
    return "\n".join(lines)


class TestRegistration(unittest.TestCase):
    def test_registers_the_expected_hook(self):
        self.assertEqual(set(ctx.hooks), {"transform_terminal_output"})


class TestFailOpen(unittest.TestCase):
    def test_small_output_is_untouched(self):
        self.assertIsNone(hook(command="ls", output="a\nb\nc\n", returncode=0))

    def test_unknown_shape_is_untouched(self):
        blob = "\n".join(f"line {i} of prose with no structure at all" for i in range(400))
        self.assertIsNone(hook(command="cat notes.md", output=blob, returncode=0))

    def test_broken_json_is_untouched(self):
        blob = "[" + "x," * 5000
        self.assertIsNone(hook(command="cat x.json", output=blob, returncode=0))

    def test_empty_and_none_are_untouched(self):
        self.assertIsNone(hook(command="true", output="", returncode=0))
        self.assertIsNone(hook(command="true", output=None, returncode=0))

    def test_never_raises_on_hostile_input(self):
        for blob in ("\x00" * 9000, "[" * 9000, "ERROR\n" * 4000, "é" * 9000):
            hook(command="whatever", output=blob, returncode=1)  # must not raise

    def test_single_key_json_wrapper_is_untouched(self):
        # A one-key wrapper means the value is the payload: summarising the key
        # would delete the answer.
        blob = json.dumps({"result": "x" * 6000}, indent=1)
        self.assertIsNone(hook(command="cat r.json", output=blob, returncode=0))

    def test_thin_win_is_refused(self):
        # A log where nearly every line is a keyword: keeping most of it is not
        # worth the risk, so the original must come back.
        blob = "\n".join(f"ERROR failed: problem {i}" for i in range(600))
        self.assertIsNone(hook(command="cat l.log", output=blob, returncode=0))


class TestLogs(unittest.TestCase):
    def sample(self):
        entries = [("INFO", f"routine message {i}") for i in range(200)]
        entries.insert(120, ("ERROR", "connection to db-primary timed out after 30s"))
        entries.insert(60, ("WARNING", "disk usage above 90 percent on /var"))
        return log_sample(entries)

    def test_keeps_errors_and_drops_noise(self):
        out = hook(command="journalctl -n 400", output=self.sample(), returncode=0)
        self.assertIsNotNone(out)
        self.assertIn("connection to db-primary timed out after 30s", out)
        self.assertIn("disk usage above 90 percent on /var", out)
        self.assertNotIn("routine message 7", out)

    def test_reports_counts(self):
        out = hook(command="journalctl", output=self.sample(), returncode=0)
        self.assertIn("202 log lines", out)
        self.assertIn("caveman-shrink: log", out)

    def test_lowercase_error_only_is_not_enough(self):
        # Hermes' own structured logs put "error": null on every line; matching a
        # bare lowercase "error" kept 165 of 400 lines in the real sample.
        entries = [("INFO", f'heartbeat ok {{"error": null, "n": {i}}}') for i in range(300)]
        self.assertIsNone(hook(command="journalctl", output=log_sample(entries), returncode=0))

    def test_traceback_is_kept_with_context(self):
        lines = [f"INFO step {i}" for i in range(150)]
        lines += [
            "Traceback (most recent call last):",
            '  File "/home/u/app/main.py", line 42, in run',
            "    return client.post(url)",
            "httpx.ReadTimeout: The read operation timed out",
        ]
        lines += [f"INFO tail {i}" for i in range(150)]
        out = hook(command="journalctl", output="\n".join(lines), returncode=1)
        self.assertIn("httpx.ReadTimeout: The read operation timed out", out)
        self.assertIn('File "/home/u/app/main.py", line 42', out)

    def test_repeated_lines_are_collapsed(self):
        lines = [f"Nov 15 11:34:00 msi unit[1]: INFO retrying connection" for _ in range(300)]
        lines.insert(150, "Nov 15 11:34:01 msi unit[1]: ERROR gave up after retries")
        out = hook(command="cat retry.log", output="\n".join(lines), returncode=0)
        self.assertIn("(x", out)
        self.assertIn("ERROR gave up after retries", out)


class TestTables(unittest.TestCase):
    def units(self, rows):
        header = "  UNIT" + " " * 100 + "LOAD      ACTIVE   SUB       DESCRIPTION"
        return "\n".join([header] + rows)

    def test_counts_and_keeps_the_odd_rows(self):
        rows = [
            f"  svc-{i}.service{' ' * 90}loaded    active   running   thing {i}" for i in range(60)
        ]
        rows.append(f"  broken.service{' ' * 90}not-found inactive dead      missing unit")
        out = hook(command="systemctl list-units", output=self.units(rows), returncode=0)
        self.assertIsNotNone(out)
        self.assertIn("broken.service", out)
        self.assertNotIn("svc-7.service", out)
        self.assertIn("61 rows", out)

    def test_short_table_is_untouched(self):
        rows = [f"  svc-{i}.service loaded active running x" for i in range(3)]
        self.assertIsNone(hook(command="systemctl", output=self.units(rows), returncode=0))

    def test_footer_is_not_counted_as_a_row(self):
        rows = [f"  svc-{i}.service{' ' * 90}loaded    active   running   thing {i}" for i in range(30)]
        text = self.units(rows) + "\n\n0 loaded units listed.\nTo show all installed unit files use 'systemctl list-unit-files'."
        out = hook(command="systemctl", output=text, returncode=0)
        self.assertIsNotNone(out)
        self.assertIn("30 rows", out)
        self.assertNotIn("units=1", out)


class TestJson(unittest.TestCase):
    def test_array_of_objects_keeps_shape_and_sample(self):
        items = [{"id": i, "name": f"n{i}", "state": "ok"} for i in range(400)]
        out = hook(command="cat data.json", output=json.dumps(items), returncode=0)
        self.assertIsNotNone(out)
        self.assertIn("JSON array of 400 objects", out)
        self.assertIn("id, name, state", out)

    def test_scalar_array(self):
        out = hook(command="cat ids.json", output=json.dumps(list(range(4000))), returncode=0)
        self.assertIsNotNone(out)
        self.assertIn("JSON array of 4000 scalars", out)


class TestProseIsPayload(unittest.TestCase):
    """A document is what the user asked to read. Never summarise it."""

    DOC = "\n".join(
        [
            "# Caveman Compress",
            "",
            "## Purpose",
            "",
            "Compress natural language files into caveman-speak to reduce input tokens.",
            "",
            "- Articles go",
            "- Filler goes",
            "- Hedging goes",
            "",
            "## Boundaries",
            "",
            "If the run had 3 failed assertions, leave the file alone.",
            "```",
            "python3 -m scripts /path/to/file.md",
            "```",
        ]
        + [f"- rule number {i} about preserving code blocks, headings and file paths verbatim" for i in range(70)]
    )

    def test_markdown_is_untouched(self):
        self.assertGreater(len(self.DOC.encode()), 4096)
        self.assertIsNone(hook(command="cat SKILL.md", output=self.DOC, returncode=0))

    def test_a_doc_that_mentions_failures_is_not_a_test_report(self):
        doc = self.DOC + "\n\nRan 12 tests in 0.1s, 3 failed and were reverted.\n"
        self.assertIsNone(hook(command="cat notes.md", output=doc, returncode=0))

    def test_a_dumped_web_page_is_not_a_log(self):
        # The corpus had 275 KB of plugin docs and 74 KB of CSS that the old
        # unconditional log pass happily summarised into losing their content.
        page = "<!doctype html>\n" + '<div class="docs-wrapper plugin-docs">\n' * 400
        self.assertIsNone(hook(command="curl -sL https://example.com/docs", output=page, returncode=0))

    def test_source_listing_is_not_treated_as_a_log(self):
        # A grep of symbols is code, not noise. Before the log compressor needed
        # a positive signal, this shape came back as 4 of 60 lines.
        blob = "\n".join(
            f"    def method_{i}(self, value: int) -> str:  # docstring for method {i}"
            for i in range(60)
        )
        self.assertIsNone(hook(command="grep -rn 'def ' hermes_cli/plugins_context.py", output=blob, returncode=0))

    def test_real_caveman_skill_file_is_untouched(self):
        # The exact file the first version shredded into four lines.
        path = Path("/tmp/caveman-probe/skills/caveman-compress/SKILL.md")
        if not path.exists():
            self.skipTest("reference document not on disk")
        self.assertIsNone(hook(command="cat SKILL.md", output=path.read_text(), returncode=0))


class TestTestOutput(unittest.TestCase):
    def sample(self):
        lines = ["test_a ... ok", "test_b ... ok"] * 400
        lines += ["=" * 60, "FAIL: test_c (tests.test_x.TestCase)", "-" * 60,
                  "Traceback (most recent call last):", "AssertionError: 1 != 2",
                  "-" * 60, "Ran 802 tests in 3.21s", "", "FAILED (failures=1)"]
        return "\n".join(lines)

    def test_keeps_summary_and_failure(self):
        out = hook(command="pytest -v", output=self.sample(), returncode=1)
        self.assertIsNotNone(out)
        self.assertIn("Ran 802 tests in 3.21s", out)
        self.assertIn("FAILED (failures=1)", out)
        self.assertIn("AssertionError: 1 != 2", out)
        self.assertNotIn("test_a ... ok\ntest_a ... ok", out)


class TestSpill(unittest.TestCase):
    """The footer must point at a file that really exists."""

    def sample(self):
        entries = [("INFO", f"routine message {i}") for i in range(200)]
        entries.insert(120, ("ERROR", "connection to db-primary timed out after 30s"))
        return log_sample(entries)

    def spills(self):
        return sorted((Path(TEST_HOME) / "cache" / "terminal-output").glob("caveman-*.log"))

    def test_footer_path_exists_and_holds_the_original(self):
        original = self.sample()
        out = hook(command="journalctl -n 400", output=original, returncode=0)
        self.assertIsNotNone(out)
        match = re.search(r"Full text: (\S+)\]$", out)
        assert match is not None, out
        path = Path(match.group(1))
        self.assertTrue(path.is_file(), path)
        self.assertEqual(path.read_text(), original)

    def test_no_spill_when_the_output_is_untouched(self):
        before = self.spills()
        self.assertIsNone(hook(command="ls", output="a\nb\nc\n", returncode=0))
        doc = "\n".join(f"# heading {i}" for i in range(400))
        self.assertIsNone(hook(command="cat notes.md", output=doc, returncode=0))
        self.assertEqual(self.spills(), before)

    def test_footer_admits_failure_instead_of_lying(self):
        # A regular file where the directory should be: mkdir cannot succeed.
        blocker = Path(tempfile.mkdtemp(prefix="caveman-shrink-block-")) / "not-a-dir"
        blocker.write_text("x")
        with unittest.mock.patch.dict(os.environ, {"HERMES_HOME": str(blocker)}):
            out = hook(command="journalctl", output=self.sample(), returncode=0)
        self.assertIsNotNone(out)
        self.assertIn("NOT saved to disk", out)
        self.assertNotIn("Full text:", out)

    def test_old_spills_are_pruned(self):
        directory = Path(TEST_HOME) / "cache" / "terminal-output"
        hook(command="journalctl", output=self.sample(), returncode=0)
        stale = directory / "caveman-0-0-log.log"
        stale.write_text("old")
        old = time.time() - (mod.SPILL_MAX_AGE_S + 60)
        os.utime(stale, (old, old))
        hook(command="journalctl", output=self.sample(), returncode=0)
        self.assertFalse(stale.exists())


class TestRealHost(unittest.TestCase):
    """The compressor must survive real output from this machine."""

    def test_unittest_run_of_this_plugin(self):
        if os.environ.get("CAVEMAN_SHRINK_NO_SUBPROCESS"):
            self.skipTest("child run of the real-host test")
        # Discovery would re-import this very test and recurse forever, so the
        # child run is told to skip it.
        env = {**os.environ, "CAVEMAN_SHRINK_NO_SUBPROCESS": "1"}
        result = subprocess.run(
            ["python3", "-m", "unittest", "discover", "-s", str(PLUGIN / "tests"), "-v"],
            capture_output=True,
            text=True,
            env=env,
            timeout=120,
        )
        blob = result.stdout + result.stderr
        out = hook(command="python3 -m unittest discover -v", output=blob, returncode=result.returncode)
        if out is not None:
            self.assertLess(len(out.encode()), len(blob.encode()))
            self.assertIn("caveman-shrink:", out)


if __name__ == "__main__":
    unittest.main()
