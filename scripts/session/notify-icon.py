#!/usr/bin/env python3
"""Resolve a notification's source-application icon to a file the desktop can draw.

The toast wears the sender's own icon, and the sender only ever hands over a
string. Quickshell passes it straight to Qt, which resolves that string against
*its* icon theme -- and two things break on the way:

* Qt6 here loads no platform theme at all, because `QT_QPA_PLATFORMTHEME=gtk2`
  is a Qt5 value with no Qt6 plugin behind it. With no platform theme, Qt looks
  in `hicolor` alone and never sees Papirus (the theme GTK is set to), so any
  icon that only a real theme ships comes back empty.
* `Quickshell.iconPath()` never returns an empty string -- it always answers
  `image://icon/<name>`, with or without a `fallback=`. QML therefore cannot
  tell a resolved icon from a missing one, and an unresolvable name paints the
  image provider's broken placeholder instead of letting the card fall back to
  its own glyph.

This helper answers the question QML cannot ask: is there a file behind this
string, and where is it. It prints that absolute path, or nothing at all when
there is none -- which is what makes the toast's glyph fallback reachable.

    notify-icon.py --icon <app_icon> [--app-name <app_name>]

Exit status is always 0. A notification whose icon cannot be found is a fallback,
not a failure, and a non-zero exit here would only make the panel log noise.
"""

import argparse
import configparser
from pathlib import Path

# One answer per string, so the search order is fixed and documented rather than
# whatever the filesystem happens to yield first.
ICON_ROOTS = (
    "~/.local/share/icons",
    "~/.icons",
    "/usr/local/share/icons",
    "/usr/share/icons",
)
EXTENSIONS = (".png", ".svg", ".xpm")
PREFERRED_THEMES = ("hicolor", "Adwaita", "Papirus", "Papirus-Dark", "Papirus-Light")
DESKTOP_DIRS = (
    "~/.local/share/applications",
    "/usr/local/share/applications",
    "/usr/share/applications",
)
GTK_SETTINGS = ("~/.config/gtk-3.0/settings.ini", "~/.config/gtk-4.0/settings.ini")
# A mark is drawn at 18-28 px, so the art that survives the trip is either
# resolution independent or comfortably larger than the mark.
TARGET_PX = 96


def gtk_icon_theme():
    """The icon theme GTK is set to: the one every other toolkit already honours."""
    for path in GTK_SETTINGS:
        settings = Path(path).expanduser()
        if not settings.is_file():
            continue
        parser = configparser.ConfigParser(strict=False, interpolation=None)
        try:
            parser.read(settings, encoding="utf-8")
        except (configparser.Error, UnicodeDecodeError, OSError):
            continue
        if parser.has_section("Settings"):
            name = parser.get("Settings", "gtk-icon-theme-name", fallback="").strip()
            if name:
                return name
    return None


def theme_order():
    """Every installed icon theme, the desktop's own choice first."""
    order = []
    preferred = gtk_icon_theme()
    if preferred:
        order.append(preferred)
    order.extend(PREFERRED_THEMES)
    installed = []
    for root in ICON_ROOTS:
        directory = Path(root).expanduser()
        if not directory.is_dir():
            continue
        for child in sorted(directory.iterdir()):
            if (child / "index.theme").is_file():
                installed.append(child.name)
    for name in installed:
        if name not in order:
            order.append(name)
    return order


def effective_px(size_dir):
    """`48x48@2` is 96 px of art; `scalable` has no size to read."""
    head = size_dir.split("/")[0]
    if head == "scalable":
        return None
    digits = head.split("@")[0].split("x")[0]
    try:
        pixels = int(digits)
    except ValueError:
        return None
    if "@2" in head:
        pixels *= 2
    return pixels


def theme_dirs(theme_dir):
    """The subdirectories the theme declares, ordered best first.

    A theme's own `index.theme` is the manifest, and reading it beats guessing at
    `apps/`, `status/` and the dozen other category folders: the order is the
    theme's, and it costs one file read instead of a walk over the whole theme.
    """
    manifest = theme_dir / "index.theme"
    entries = []
    if manifest.is_file():
        parser = configparser.ConfigParser(strict=False, interpolation=None)
        try:
            parser.read(manifest, encoding="utf-8")
            raw = parser.get("Icon Theme", "Directories", fallback="")
        except (configparser.Error, UnicodeDecodeError, OSError):
            raw = ""
        entries = [entry.strip() for entry in raw.split(",") if entry.strip()]
    if not entries:
        entries = [f"{child.parent.name}/{child.name}" for child in theme_dir.glob("*/*") if child.is_dir()]

    def rank(entry):
        pixels = effective_px(entry)
        if pixels is None:
            return (0, 0)  # scalable: any size, still sharp
        return (1, abs(pixels - TARGET_PX))

    return sorted(entries, key=rank)


def find_in_theme(theme_dir, name):
    for entry in theme_dirs(theme_dir):
        for extension in EXTENSIONS:
            candidate = theme_dir / entry / (name + extension)
            if candidate.is_file():
                return candidate
    return None


def by_name(name):
    """Resolve an icon *name* against every installed theme, in `theme_order`."""
    for theme in theme_order():
        for root in ICON_ROOTS:
            theme_dir = Path(root).expanduser() / theme
            if not (theme_dir / "index.theme").is_file():
                continue
            found = find_in_theme(theme_dir, name)
            if found is not None:
                return found
    return None


def resolve(value):
    """A sender's icon string -- a path, a `file://` URL or a name -- to a file."""
    value = (value or "").strip()
    if not value:
        return None
    if value.startswith("file://"):
        value = value[len("file://"):]
    path = Path(value).expanduser()
    if path.is_absolute():
        return path if path.is_file() else None
    # A name, possibly with the extension the artwork happens to carry.
    for extension in EXTENSIONS:
        if value.endswith(extension):
            value = value[: -len(extension)]
            break
    if "/" in value:
        return None  # a relative path is not a name, and pretending it is finds nothing
    return by_name(value)


def desktop_icon(app_name):
    """The `Icon=` a `.desktop` entry names, matched on the application's display name.

    The last resort, for senders that put a human name in `app_icon` or leave it
    empty: `Google Chrome` is not an icon, it is what the `.desktop` file calls
    itself. Localised `Name[xx]` keys are matched too, because the name the user
    sees is often the localised one.
    """
    wanted = (app_name or "").strip().casefold()
    if not wanted:
        return None
    for root in DESKTOP_DIRS:
        directory = Path(root).expanduser()
        if not directory.is_dir():
            continue
        for entry in sorted(directory.glob("*.desktop")):
            parser = configparser.ConfigParser(strict=False, interpolation=None)
            try:
                parser.read(entry, encoding="utf-8")
            except (configparser.Error, UnicodeDecodeError, OSError):
                continue
            if not parser.has_section("Desktop Entry"):
                continue
            if parser.get("Desktop Entry", "NoDisplay", fallback="false").strip().lower() == "true":
                continue
            names = [parser.get("Desktop Entry", "Name", fallback="")]
            # configparser lowercases keys, so `Name[es]` arrives as `name[es]`.
            names += [value for key, value in parser.items("Desktop Entry") if key.lower().startswith("name[")]
            if any(name.strip().casefold() == wanted for name in names):
                icon = parser.get("Desktop Entry", "Icon", fallback="").strip()
                if icon:
                    return icon
    return None


DESCRIPTION = "Resolve a notification's source-application icon to a file the desktop can draw."


def main(argv=None):
    parser = argparse.ArgumentParser(description=DESCRIPTION)
    parser.add_argument("--icon", default="", help="the sender's app_icon string")
    parser.add_argument("--app-name", dest="app_name", default="", help="the sender's app_name")
    args = parser.parse_args(argv)

    found = resolve(args.icon)
    if found is None and args.app_name:
        found = resolve(desktop_icon(args.app_name))
    if found is not None:
        print(found)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
