#!/usr/bin/env python3
"""Build an offscreen-runnable copy of the SDDM theme.

The greeter's QML is written against five objects that only SDDM provides at run
time: `sddm` (the greeter proxy), `userModel`, `sessionModel` and `screenModel`.
Nothing else about the file is special, so the theme renders perfectly well in a
plain window once those four exist -- that is what this script arranges.

It does not fake the layout: Main.qml and its generated GreeterAppearance.qml are
copied verbatim, and only the four context objects are renamed to stubs declared
at the top of the copied root. A test that rewrote the surface would prove
nothing about the surface SDDM will load.

Usage: stub.py <destination-dir>  -> prints the path of the patched Main.qml
"""

import re
import shutil
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[4]
THEME = ROOT / "config" / "sddm" / "arch"

STUBS = """
  // --- harness stubs: the objects SDDM injects into the greeter's context ---
  QtObject {
    id: stubScreens
    readonly property int primary: 0
    function geometry(index) { return { width: 1280, height: 800 } }
  }
  QtObject {
    id: stubUsers
    readonly property string lastUser: "joscarranzs"
  }
  QtObject {
    id: stubSessions
    readonly property int lastIndex: 0
    // The real session names, capitalized, plus an unmatchable extra: the old
    // greeter looked for a lowercase "hyprland", never matched, and fell back to
    // `lastIndex` -- which is Plasma here, so a broken search is visible.
    readonly property var names: ["Plasma (Wayland)", "Hyprland (uwsm-managed)",
                                  "Hyprland", "GNOME"]
    function rowCount() { return names.length }
    function index(i, column) { return i }
    function data(i, role) { return names[i] }
  }
  QtObject {
    id: stubSddm
    signal loginFailed()
    signal loginSucceeded()
    property var attempts: []
    function login(user, password, sessionIndex) {
      attempts = attempts.concat([[user, password, sessionIndex]])
      console.log("ATTEMPT user=" + user + " password=" + password
        + " sessionIndex=" + sessionIndex)
    }
  }
  // The harness has to be able to fail a login on demand, and neither the stub
  // nor the token object is reachable by id from outside the component.
  property QtObject sddmStub: stubSddm
  property QtObject appearanceStub: appearance
"""


def main() -> int:
    if len(sys.argv) != 2:
        print("usage: stub.py <destination-dir>", file=sys.stderr)
        return 2
    destination = Path(sys.argv[1])
    destination.mkdir(parents=True, exist_ok=True)

    for name in ("Main.qml", "GreeterAppearance.qml"):
        source = THEME / name
        if not source.is_file():
            print(f"stub.py: {source} is missing - run apply-theme.py first",
                  file=sys.stderr)
            return 1
        shutil.copy2(source, destination / name)

    main_qml = destination / "Main.qml"
    text = main_qml.read_text()

    # The module only holds SDDM's optional helper components; this theme uses
    # none of them, and the real module is not importable outside a greeter.
    text = text.replace("import SddmComponents 2.0\n", "")

    for stub, real in (("stubScreens", "screenModel"), ("stubUsers", "userModel"),
                       ("stubSessions", "sessionModel")):
        text = re.sub(rf"(?<![\w.]){real}(?![\w])", stub, text)
    text = re.sub(r"(?<![\w.])sddm(?![\w])", "stubSddm", text)

    anchor = "  GreeterAppearance { id: appearance }\n"
    if anchor not in text:
        print("stub.py: Main.qml no longer instantiates GreeterAppearance",
              file=sys.stderr)
        return 1
    text = text.replace(anchor, anchor + STUBS, 1)

    main_qml.write_text(text)
    print(main_qml)
    return 0


if __name__ == "__main__":
    sys.exit(main())
