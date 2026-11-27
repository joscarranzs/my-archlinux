#!/usr/bin/env python3
"""Web app entries and the session draft for the Quickshell web app panel.

The panel processes are short lived (one per open), so the form state cannot
live in QML memory: it is kept in the runtime directory, which is tmpfs and
vanishes on logout. That gives exactly the behaviour the panel promises - a
draft survives closing the panel, never survives a reboot.

Subcommands:
  save <json>    store the draft {"name","url","icon"}
  clear          drop the draft
  create <json>  write a freedesktop entry for the web app and print its path
  list           print the installed web apps as JSON
  delete <slug>  remove a web app entry and the icon downloaded for it
"""

import json
import os
import re
import shutil
import subprocess
import sys
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path
from typing import NoReturn

DRAFT = Path(os.environ.get("XDG_RUNTIME_DIR", "/tmp")) / "quickshell-webapp-draft.json"
APPLICATIONS = Path.home() / ".local" / "share" / "applications"
ICON_DIR = Path.home() / ".local" / "share" / "icons" / "webapps"
BROWSER = os.environ.get("WEBAPP_BROWSER", "chromium")
DEFAULT_ICON = "applications-internet"

# Failures the icon resolver can actually recover from or report. A
# programming error is deliberately left out: it must raise, not turn into
# "your icon name is unknown", which is how a typo in this file would hide.
DOWNLOAD_ERRORS = (urllib.error.URLError, OSError, ValueError)

# Dashboard Icons ships its catalogue as a git repo mirrored by jsDelivr, so a
# bare name like "youtube" is a valid icon reference: it resolves to the PNG.
# The reference is used exactly as typed: the user picks the variant (default
# or "-light") themselves, so no variant probing happens here.
DASHBOARD_CDN = "https://cdn.jsdelivr.net/gh/homarr-labs/dashboard-icons/png/{name}.png"
# The catalogue publishes every entry as png, webp and svg, and links copied
# from its site often point at the webp copy. Qt on this host has no webp image
# plugin, so a catalogue URL in any format resolves to the PNG rendition of the
# same name: same artwork, same variant, a format every surface here renders.
DASHBOARD_URL = re.compile(
    r"^https://cdn\.jsdelivr\.net/gh/homarr-labs/dashboard-icons/"
    r"(?:png|webp|svg)/(?P<name>[A-Za-z0-9._-]+)\.(?:png|webp|svg)$",
    re.IGNORECASE,
)


def fail(message: str) -> NoReturn:
    print(f"webapp: {message}", file=sys.stderr)
    sys.exit(2)


def read_payload(raw):
    try:
        payload = json.loads(raw)
    except json.JSONDecodeError as error:
        fail(f"invalid payload: {error}")
    if not isinstance(payload, dict):
        fail("payload must be an object")
    return {key: str(payload.get(key, "")) for key in ("name", "url", "icon")}


def slugify(name):
    slug = re.sub(r"[^a-z0-9]+", "-", name.strip().lower()).strip("-")
    return slug or "webapp"


def normalize_url(url):
    value = url.strip()
    if not value:
        fail("url required")
    if re.search(r"\s", value):
        fail("url cannot contain spaces")
    # Quotes, backslashes and control characters break the Exec= parsing of a
    # desktop entry; refuse them here instead of writing an entry that will not
    # launch. Percent signs are legal and escaped where Exec is written.
    if re.search(r'["\\\x00-\x1f]', value):
        fail("url contains characters not allowed in a desktop entry")
    if not re.match(r"^https?://", value, re.IGNORECASE):
        value = "https://" + value
    if not re.match(r"^https?://[^\s/]+\.[^\s/]+", value, re.IGNORECASE):
        fail("url looks incomplete")
    return value


def download(url, destination):
    """Fetch an icon. Desktop entries need a local file, not a remote URL."""
    request = urllib.request.Request(url, headers={"User-Agent": "dotfiles-webapp/1.0"})
    with urllib.request.urlopen(request, timeout=12) as response:
        payload = response.read()
    if len(payload) == 0:
        raise ValueError("empty response")
    destination.parent.mkdir(parents=True, exist_ok=True)
    destination.write_bytes(payload)
    return destination


def fetch(url, destination):
    """Download an icon and report a network or filesystem failure as a CLI error."""
    try:
        return str(download(url, destination))
    except DOWNLOAD_ERRORS as error:
        fail(f"could not download the icon: {error}")


def resolve_icon(icon, slug):
    """Turn whatever the user typed into an Icon= value.

    Accepted forms: empty, a Dashboard Icons name, an http(s) URL, a file path.
    Names and URLs are downloaded next to the other web app icons, because a
    freedesktop entry cannot point at the network. The reference is used exactly
    as typed: the user picks the variant (default or "-light") themselves.
    """
    value = icon.strip()
    if not value:
        return DEFAULT_ICON

    if value.startswith("file://"):
        return value[len("file://"):]

    if value.startswith("/") or value.startswith("~"):
        return os.path.expanduser(value)

    if value.lower().startswith(("http://", "https://")):
        catalogue = DASHBOARD_URL.match(value)
        if catalogue:
            name = catalogue.group("name").lower()
            try:
                return str(download(DASHBOARD_CDN.format(name=name), ICON_DIR / f"{slug}.png"))
            except DOWNLOAD_ERRORS as error:
                fail(f"could not download the icon: {error}")
        suffix = Path(urllib.parse.urlparse(value).path).suffix.lower() or ".png"
        return fetch(value, ICON_DIR / f"{slug}{suffix}")

    # Bare word: a Dashboard Icons name, downloaded once so it also works offline.
    name = re.sub(r"[^a-zA-Z0-9._-]+", "-", value).strip("-").lower()
    try:
        return str(download(DASHBOARD_CDN.format(name=name), ICON_DIR / f"{slug}.png"))
    except DOWNLOAD_ERRORS:
        # Not in the catalogue, or the network is down: let the icon theme try
        # the name as typed, which is what happened before the catalogue existed.
        return value


def save_draft(raw):
    payload = read_payload(raw)
    DRAFT.parent.mkdir(parents=True, exist_ok=True)
    tmp = DRAFT.with_name(DRAFT.name + ".tmp")
    tmp.write_text(json.dumps(payload, ensure_ascii=False), encoding="utf-8")
    os.replace(tmp, DRAFT)


def clear_draft():
    try:
        DRAFT.unlink()
    except FileNotFoundError:
        pass


def refresh_desktop_database():
    if shutil.which("update-desktop-database"):
        subprocess.run(["update-desktop-database", str(APPLICATIONS)],
                       check=False, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)


def create_entry(raw):
    payload = read_payload(raw)
    name = payload["name"].strip()
    if not name:
        fail("name required")
    if "\n" in name:
        fail("name cannot contain line breaks")
    url = normalize_url(payload["url"])
    slug = slugify(name)
    icon = resolve_icon(payload["icon"], slug)

    APPLICATIONS.mkdir(parents=True, exist_ok=True)
    entry = APPLICATIONS / f"webapp-{slug}.desktop"
    # Exec= expands %f/%u-style field codes, so a literal percent (common in
    # query strings) must be doubled or the entry fails to parse. Comment keeps
    # the original URL: no expansion happens outside Exec.
    exec_url = url.replace("%", "%%")
    entry.write_text(
        "[Desktop Entry]\n"
        "Type=Application\n"
        "Version=1.5\n"
        f"Name={name}\n"
        f"Comment={url}\n"
        f"Exec={BROWSER} --app={exec_url} --class=webapp-{slug}\n"
        f"Icon={icon}\n"
        "Terminal=false\n"
        "Categories=Network;WebBrowser;\n"
        "StartupNotify=true\n"
        f"StartupWMClass=webapp-{slug}\n",
        encoding="utf-8",
    )
    entry.chmod(0o644)
    refresh_desktop_database()
    clear_draft()
    print(entry)


def entry_fields(path):
    """Read the unlocalized Name/Icon/Comment keys of a desktop entry."""
    fields = {}
    for line in path.read_text(encoding="utf-8").splitlines():
        key, sep, value = line.partition("=")
        if sep and key in ("Name", "Icon", "Comment"):
            fields[key] = value
    return fields


def list_entries():
    """Print every installed web app as JSON, for the panel's manage view."""
    apps = []
    if APPLICATIONS.is_dir():
        for path in sorted(APPLICATIONS.glob("webapp-*.desktop")):
            fields = entry_fields(path)
            slug = path.stem[len("webapp-"):]
            apps.append({
                "slug": slug,
                "name": fields.get("Name", slug),
                "url": fields.get("Comment", ""),
                "icon": fields.get("Icon", ""),
            })
    print(json.dumps(apps, ensure_ascii=False))


def delete_entry(raw_slug):
    """Remove a web app entry and the icon downloaded for it.

    Only icons inside ICON_DIR are removed: an entry may point at a file the
    user keeps elsewhere, and deleting that is not what "delete the app" means.
    """
    slug = slugify(raw_slug)
    entry = APPLICATIONS / f"webapp-{slug}.desktop"
    if not entry.is_file():
        fail(f"no web app named {slug}")
    icon = entry_fields(entry).get("Icon", "")
    entry.unlink()
    if icon.startswith("/"):
        path = Path(icon)
        if path.is_relative_to(ICON_DIR) and path.is_file():
            path.unlink()
    refresh_desktop_database()
    print(entry)


def main(argv):
    if len(argv) < 2:
        print(__doc__)
        return 2
    command = argv[1]
    if command == "save" and len(argv) == 3:
        save_draft(argv[2])
    elif command == "clear":
        clear_draft()
    elif command == "create" and len(argv) == 3:
        create_entry(argv[2])
    elif command == "list" and len(argv) == 2:
        list_entries()
    elif command == "delete" and len(argv) == 3:
        delete_entry(argv[2])
    else:
        print(__doc__)
        return 2
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
