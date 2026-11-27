#!/usr/bin/env python3
"""Tests for the pure logic in webapp.py.

These cover the parts that need no QML, no network and no desktop entry: the
slug, the URL normalisation, the catalogue name probing and the payload
validation. Run them with:

    python3 -m unittest discover -s scripts/session/tests
"""

import contextlib
import importlib.util
import io
import json
import unittest
from pathlib import Path

WEBAPP = Path(__file__).resolve().parents[1] / "webapp.py"
SPEC = importlib.util.spec_from_file_location("webapp", WEBAPP)
assert SPEC is not None and SPEC.loader is not None
webapp = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(webapp)


def failure(fn, *args):
    """Run fn and return the SystemExit code plus whatever it printed."""
    stderr = io.StringIO()
    with contextlib.redirect_stderr(stderr), contextlib.redirect_stdout(io.StringIO()):
        with unittest.TestCase().assertRaises(SystemExit) as caught:
            fn(*args)
    return caught.exception.code, stderr.getvalue()


class SlugifyTest(unittest.TestCase):
    def test_lowercases_and_joins_words(self):
        self.assertEqual(webapp.slugify("My App"), "my-app")

    def test_strips_punctuation(self):
        self.assertEqual(webapp.slugify("  Hello, World!  "), "hello-world")

    def test_collapses_runs_of_separators(self):
        self.assertEqual(webapp.slugify("a---b   c"), "a-b-c")

    def test_falls_back_when_nothing_is_left(self):
        self.assertEqual(webapp.slugify("!!!"), "webapp")

    def test_empty_name_falls_back(self):
        self.assertEqual(webapp.slugify("   "), "webapp")


class NormalizeUrlTest(unittest.TestCase):
    def test_adds_https_when_missing(self):
        self.assertEqual(webapp.normalize_url("example.com"), "https://example.com")

    def test_keeps_an_existing_scheme(self):
        self.assertEqual(
            webapp.normalize_url("http://example.com/path"), "http://example.com/path"
        )

    def test_trims_surrounding_space(self):
        self.assertEqual(webapp.normalize_url("  example.com  "), "https://example.com")

    def test_rejects_empty(self):
        code, message = failure(webapp.normalize_url, "")
        self.assertEqual(code, 2)
        self.assertIn("url required", message)

    def test_rejects_spaces_inside(self):
        code, message = failure(webapp.normalize_url, "example com")
        self.assertEqual(code, 2)
        self.assertIn("cannot contain spaces", message)

    def test_rejects_a_bare_word(self):
        code, message = failure(webapp.normalize_url, "notadomain")
        self.assertEqual(code, 2)
        self.assertIn("incomplete", message)

    def test_rejects_double_quote(self):
        code, message = failure(webapp.normalize_url, 'https://example.com/a"b')
        self.assertEqual(code, 2)
        self.assertIn("not allowed in a desktop entry", message)

    def test_rejects_backslash(self):
        code, message = failure(webapp.normalize_url, "https://example.com/a\\b")
        self.assertEqual(code, 2)
        self.assertIn("not allowed in a desktop entry", message)

    def test_keeps_percent_encoding(self):
        self.assertEqual(
            webapp.normalize_url("https://example.com/search?q=a%20b"),
            "https://example.com/search?q=a%20b",
        )


class DashboardUrlTest(unittest.TestCase):
    def test_matches_webp_and_extracts_the_name(self):
        match = webapp.DASHBOARD_URL.match(
            "https://cdn.jsdelivr.net/gh/homarr-labs/dashboard-icons/webp/github.webp"
        )
        self.assertIsNotNone(match)
        self.assertEqual(match.group("name"), "github")

    def test_matches_png_and_svg_variants(self):
        for fmt in ("png", "svg"):
            match = webapp.DASHBOARD_URL.match(
                f"https://cdn.jsdelivr.net/gh/homarr-labs/dashboard-icons/{fmt}/github-light.{fmt}"
            )
            self.assertIsNotNone(match)
            self.assertEqual(match.group("name"), "github-light")

    def test_rejects_other_hosts_and_nested_paths(self):
        self.assertIsNone(webapp.DASHBOARD_URL.match("https://example.com/github.png"))
        self.assertIsNone(webapp.DASHBOARD_URL.match(
            "https://cdn.jsdelivr.net/gh/homarr-labs/dashboard-icons/png/nested/github.png"
        ))


class ReadPayloadTest(unittest.TestCase):
    def test_keeps_only_known_keys_as_strings(self):
        payload = webapp.read_payload('{"name":"A","url":"b","icon":"c","extra":1}')
        self.assertEqual(payload, {"name": "A", "url": "b", "icon": "c"})

    def test_missing_keys_become_empty_strings(self):
        self.assertEqual(
            webapp.read_payload('{"name":"A"}'), {"name": "A", "url": "", "icon": ""}
        )

    def test_rejects_invalid_json(self):
        code, message = failure(webapp.read_payload, "{not json")
        self.assertEqual(code, 2)
        self.assertIn("invalid payload", message)

    def test_rejects_a_non_object(self):
        code, message = failure(webapp.read_payload, '["a"]')
        self.assertEqual(code, 2)
        self.assertIn("must be an object", message)


class SandboxedLayoutTest(unittest.TestCase):
    """Shared temporary HOME-side layout: never the real entries or icons."""

    def setUp(self):
        import tempfile

        self.tmp = tempfile.TemporaryDirectory()
        base = Path(self.tmp.name)
        self._saved = (webapp.APPLICATIONS, webapp.ICON_DIR, webapp.DRAFT)
        # setattr: the module is loaded through importlib, so static attribute
        # assignment would trip type checkers that cannot see its namespace.
        setattr(webapp, "APPLICATIONS", base / "applications")
        setattr(webapp, "ICON_DIR", base / "icons")
        setattr(webapp, "DRAFT", base / "draft.json")
        # No desktop database update and no icon download in a unit test.
        self._saved_which = webapp.shutil.which
        webapp.shutil.which = lambda _name: None

    def tearDown(self):
        for name, value in zip(("APPLICATIONS", "ICON_DIR", "DRAFT"), self._saved):
            setattr(webapp, name, value)
        webapp.shutil.which = self._saved_which
        self.tmp.cleanup()


class CreateEntryTest(SandboxedLayoutTest):
    """create_entry against the sandboxed layout."""

    def _create(self, payload):
        with contextlib.redirect_stdout(io.StringIO()):
            webapp.create_entry(payload)

    def test_exec_doubles_percent_signs(self):
        import json

        payload = json.dumps(
            {"name": "Search App", "url": "https://example.com/s?q=a%20b", "icon": ""}
        )
        self._create(payload)
        entry = (webapp.APPLICATIONS / "webapp-search-app.desktop").read_text()
        self.assertIn("Exec=chromium --app=https://example.com/s?q=a%%20b", entry)
        # Comment keeps the original URL: no field-code expansion outside Exec.
        self.assertIn("Comment=https://example.com/s?q=a%20b\n", entry)

    def test_plain_url_unchanged_in_exec(self):
        import json

        payload = json.dumps({"name": "Plain", "url": "https://example.com", "icon": ""})
        self._create(payload)
        entry = (webapp.APPLICATIONS / "webapp-plain.desktop").read_text()
        self.assertIn("Exec=chromium --app=https://example.com --class=webapp-plain", entry)


class ListDeleteTest(SandboxedLayoutTest):
    """list_entries/delete_entry against the sandboxed layout."""

    def _create(self, name, icon=""):
        with contextlib.redirect_stdout(io.StringIO()):
            webapp.create_entry(json.dumps(
                {"name": name, "url": "https://example.com", "icon": icon}
            ))

    def _list(self):
        out = io.StringIO()
        with contextlib.redirect_stdout(out):
            webapp.list_entries()
        return json.loads(out.getvalue())

    def test_lists_created_entries_sorted_by_slug(self):
        self._create("GitHub")
        self._create("Chat GPT")
        apps = self._list()
        self.assertEqual([a["slug"] for a in apps], ["chat-gpt", "github"])
        self.assertEqual(apps[1]["name"], "GitHub")
        self.assertEqual(apps[1]["url"], "https://example.com")

    def test_delete_removes_entry_and_downloaded_icon(self):
        icon = webapp.ICON_DIR / "probe.png"
        icon.parent.mkdir(parents=True, exist_ok=True)
        icon.write_bytes(b"png")
        self._create("Probe", icon=str(icon))
        with contextlib.redirect_stdout(io.StringIO()):
            webapp.delete_entry("probe")
        self.assertFalse((webapp.APPLICATIONS / "webapp-probe.desktop").exists())
        self.assertFalse(icon.exists())
        self.assertEqual(self._list(), [])

    def test_delete_keeps_icons_outside_the_icon_dir(self):
        outside = Path(self.tmp.name) / "elsewhere.png"
        outside.write_bytes(b"png")
        self._create("Probe", icon=str(outside))
        with contextlib.redirect_stdout(io.StringIO()):
            webapp.delete_entry("probe")
        self.assertTrue(outside.exists())

    def test_delete_unknown_slug_fails(self):
        code, message = failure(webapp.delete_entry, "ghost")
        self.assertEqual(code, 2)
        self.assertIn("no web app named ghost", message)

    def test_delete_sanitizes_the_slug(self):
        self._create("Probe")
        code, _ = failure(webapp.delete_entry, "../../etc")
        self.assertEqual(code, 2)
        self.assertTrue((webapp.APPLICATIONS / "webapp-probe.desktop").exists())


if __name__ == "__main__":
    unittest.main()
