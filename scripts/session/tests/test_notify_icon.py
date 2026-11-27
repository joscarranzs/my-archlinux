#!/usr/bin/env python3
"""Tests for the icon resolution in notify-icon.py.

The helper reads the icon themes and the `.desktop` entries installed on this
machine, so every test points its roots at a synthetic tree instead: the contract
under test is *which* file wins, and that is decided by the search order (theme,
then size, then extension), not by what happens to be installed.

The one behaviour worth naming: an icon no theme ships resolves to nothing. That
empty answer is the whole point of the helper -- it is what lets the toast fall
back to its own glyph instead of painting the image provider's broken
placeholder, which is the defect this file exists to keep out.

    python3 -m unittest discover -s scripts/session/tests
"""

import importlib.util
import io
import tempfile
import unittest
from contextlib import redirect_stdout
from pathlib import Path
from unittest import mock

HELPER = Path(__file__).resolve().parents[1] / "notify-icon.py"
SPEC = importlib.util.spec_from_file_location("notify_icon", HELPER)
assert SPEC is not None and SPEC.loader is not None
notify_icon = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(notify_icon)


class IconTreeCase(unittest.TestCase):
    """A synthetic icon and application tree, redirected into a temp directory."""

    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.dir = Path(temporary.name)

        self.icons = self.dir / "icons"
        self.desktop = self.dir / "applications"
        self.gtk = self.dir / "gtk-3.0" / "settings.ini"

        # One theme with a scalable icon and two raster sizes; `48x48@2` is 96 px
        # of art, which is the size the helper aims for.
        self.write("icons/First/index.theme", "[Icon Theme]\nDirectories=scalable/apps,48x48/apps,48x48@2/apps\n")
        self.write("icons/First/scalable/apps/alpha.svg", "<svg/>")
        self.write("icons/First/48x48/apps/alpha.png", "png")
        self.write("icons/First/48x48/apps/beta.png", "png")
        self.write("icons/First/48x48@2/apps/gamma.png", "png")
        self.write("icons/First/48x48/apps/delta.svg", "<svg/>")
        # A second theme that ships the same name, so theme order is observable.
        self.write("icons/Second/index.theme", "[Icon Theme]\nDirectories=48x48/apps\n")
        self.write("icons/Second/48x48/apps/second-only.png", "png")
        self.write("icons/Second/48x48/apps/alpha.png", "png")

        self.write("applications/test.desktop", "[Desktop Entry]\nName=Test App\nIcon=beta\n")
        self.write("applications/localised.desktop", "[Desktop Entry]\nName=Plain\nName[es]=Otro Nombre\nIcon=delta\n")
        self.write("applications/hidden.desktop", "[Desktop Entry]\nName=Hidden App\nIcon=alpha\nNoDisplay=true\n")

        self.patch(notify_icon, "ICON_ROOTS", (str(self.icons),))
        self.patch(notify_icon, "DESKTOP_DIRS", (str(self.desktop),))
        # No GTK settings either: the real file names the theme this machine is
        # set to, and a test must not change its answer with the desktop's.
        self.patch(notify_icon, "GTK_SETTINGS", (str(self.dir / "no-settings.ini"),))

    def write(self, relative, content):
        path = self.dir / relative
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(content, encoding="utf-8")
        return path

    def patch(self, obj, name, value):
        patcher = mock.patch.object(obj, name, value)
        self.addCleanup(patcher.stop)
        patcher.start()

    def set_gtk_theme(self, name):
        self.patch(notify_icon, "GTK_SETTINGS", (str(self.gtk),))
        self.write("gtk-3.0/settings.ini", f"[Settings]\ngtk-icon-theme-name={name}\n")

    def run_main(self, *argv):
        out = io.StringIO()
        with redirect_stdout(out):
            code = notify_icon.main(list(argv))
        return code, out.getvalue().strip()


class ResolveAbsolutePath(IconTreeCase):
    def test_a_path_that_exists_is_its_own_answer(self):
        path = self.dir / "icons" / "First" / "48x48" / "apps" / "beta.png"
        self.assertEqual(notify_icon.resolve(str(path)), path)

    def test_a_path_that_does_not_exist_resolves_to_nothing(self):
        self.assertIsNone(notify_icon.resolve(str(self.dir / "nope.png")))

    def test_a_file_url_is_unwrapped(self):
        path = self.dir / "icons" / "First" / "48x48" / "apps" / "beta.png"
        self.assertEqual(notify_icon.resolve(f"file://{path}"), path)

    def test_a_relative_path_is_not_a_name(self):
        self.assertIsNone(notify_icon.resolve("some/dir/alpha"))


class ResolveName(IconTreeCase):
    def test_an_unknown_name_resolves_to_nothing(self):
        # The regression: no theme ships it, so the toast must fall back.
        self.assertIsNone(notify_icon.resolve("zzz-bogus"))
        self.assertIsNone(notify_icon.resolve(""))

    def test_the_gtk_theme_is_searched_first(self):
        self.set_gtk_theme("Second")
        expected = self.dir / "icons" / "Second" / "48x48" / "apps" / "alpha.png"
        self.assertEqual(notify_icon.resolve("alpha"), expected)

    def test_installed_themes_are_searched_in_a_stable_order(self):
        expected = self.dir / "icons" / "First" / "scalable" / "apps" / "alpha.svg"
        self.assertEqual(notify_icon.resolve("alpha"), expected)

    def test_scalable_art_wins_over_a_raster(self):
        self.assertTrue(str(notify_icon.resolve("alpha")).endswith("scalable/apps/alpha.svg"))

    def test_a_hidpi_directory_counts_as_its_true_size(self):
        expected = self.dir / "icons" / "First" / "48x48@2" / "apps" / "gamma.png"
        self.assertEqual(notify_icon.resolve("gamma"), expected)

    def test_a_name_with_the_extension_the_artwork_carries_still_matches(self):
        expected = self.dir / "icons" / "First" / "scalable" / "apps" / "alpha.svg"
        self.assertEqual(notify_icon.resolve("alpha.svg"), expected)

    def test_an_icon_that_only_a_directory_declares_is_still_found(self):
        # `delta` lives in a raster directory as an SVG: the extension list, not
        # the directory name, decides whether it is readable.
        expected = self.dir / "icons" / "First" / "48x48" / "apps" / "delta.svg"
        self.assertEqual(notify_icon.resolve("delta"), expected)


class DesktopEntries(IconTreeCase):
    def test_the_display_name_is_matched_case_insensitively(self):
        self.assertEqual(notify_icon.desktop_icon("test app"), "beta")

    def test_a_localised_name_is_matched_too(self):
        self.assertEqual(notify_icon.desktop_icon("Otro Nombre"), "delta")

    def test_a_hidden_entry_is_skipped(self):
        self.assertIsNone(notify_icon.desktop_icon("Hidden App"))

    def test_an_unknown_application_resolves_to_nothing(self):
        self.assertIsNone(notify_icon.desktop_icon("No Such App"))


class CommandLine(IconTreeCase):
    def test_a_resolved_icon_is_printed_on_one_line(self):
        code, printed = self.run_main("--icon", "gamma")
        self.assertEqual(code, 0)
        self.assertTrue(printed.endswith("48x48@2/apps/gamma.png"))

    def test_an_unresolvable_icon_prints_nothing_and_still_succeeds(self):
        code, printed = self.run_main("--icon", "zzz-bogus")
        self.assertEqual(code, 0)
        self.assertEqual(printed, "")

    def test_the_application_name_is_the_last_resort(self):
        code, printed = self.run_main("--icon", "Google Chrome", "--app-name", "Test App")
        self.assertEqual(code, 0)
        self.assertTrue(printed.endswith("48x48/apps/beta.png"))

    def test_an_icon_beats_the_application_name(self):
        code, printed = self.run_main("--icon", "gamma", "--app-name", "Test App")
        self.assertTrue(printed.endswith("48x48@2/apps/gamma.png"))


if __name__ == "__main__":
    unittest.main()
