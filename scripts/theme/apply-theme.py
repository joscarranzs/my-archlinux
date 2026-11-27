#!/usr/bin/env python3
import json
import os
import re
import shutil
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
COLORS = ROOT / "theme" / "colors.json"
LOOK = ROOT / "theme" / "look.json"
ANIMATIONS = ROOT / "theme" / "animations.json"
TYPOGRAPHY = ROOT / "theme" / "typography.json"
TEMPLATES = ROOT / "scripts" / "theme" / "templates"

# Flatten colors into a dot-accessible dict: group.key -> value
with COLORS.open() as f:
    data = json.load(f)

flat = {}
for group, values in data.items():
    if isinstance(values, dict):
        for key, val in values.items():
            flat[f"{group}.{key}"] = val
    else:
        flat[f"palette.{group}"] = values

def flatten(prefix, obj):
    if isinstance(obj, dict):
        for k, v in obj.items():
            flatten(f"{prefix}.{k}", v)
    else:
        flat[f"{prefix}"] = obj

with LOOK.open() as f:
    look_data = json.load(f)
with ANIMATIONS.open() as f:
    anim_data = json.load(f)
with TYPOGRAPHY.open() as f:
    typo_data = json.load(f)
flatten("typography", typo_data)

flatten("look", look_data)
flatten("animations", anim_data)

# Reduced motion is a flag in animations.json and this is the only place that
# honours it: a zeroed duration makes every Behavior in every panel land in one
# frame, so no QML file has to branch on the flag. Hyprland's own
# `animations.enabled` stays independent — window and workspace motion belong to
# the compositor, and a panel entrance is a different promise from a window fly.
if anim_data.get("reducedMotion"):
    _ui_durations = [k for k in flat
                     if k.startswith("animations.ui.") and k.endswith("Duration")]
    assert _ui_durations, "animations.ui has no durations to zero"
    for _key in _ui_durations:
        flat[_key] = 0
    # The entrance carries a distance as well as a time: a zeroed duration with a
    # live offset would still land the plaque eight pixels off, one frame later.
    _ui_offsets = [k for k in flat
                   if k.startswith("animations.ui.") and k.endswith("Offset")]
    assert _ui_offsets, "animations.ui has no offsets to zero"
    for _key in _ui_offsets:
        flat[_key] = 0
    assert all(flat[k] == 0 for k in _ui_durations + _ui_offsets), \
        "reduced motion did not zero the ui motion"

# Derived window gaps. The desktop's outer rhythm is its own number now: the bar
# used to own it, but the bar sits edge to edge (look.bar.inset 0) while windows
# keep a margin, so a single value can no longer stand for both. Two corrections:
# Hyprland paints the border outside the client rectangle, so the gap itself is
# what matches (edge = margins.edge), and the scrolling layout adds gaps_in to
# each side of every column, so the side gap is the remainder.
_look_edge_gap = look_data["margins"]["edge"]
_look_inner_gap = look_data["margins"]["gapsIn"]
flat["look.margins.gapsEdge"] = max(0, _look_edge_gap)
flat["look.margins.gapsSide"] = max(0, _look_edge_gap - _look_inner_gap)


# Terminal ramp (kitty colours 16-255). The ramp is the surface -> ink axis: it
# runs dark at the surface end in the dark room and dark at the ink end once the
# surfaces turn light, so it mirrors with the palette instead of being a second
# hand-written ramp that goes invisible on paper. 232-255 continues past both
# poles by a couple of percent, which is how the hand-written ramp bracketed its
# extremes (this derivation reproduces it to within 8/255 per channel).
def _rgb(value: str) -> tuple[int, ...]:
    value = value.lstrip("#")
    return tuple(int(value[i : i + 2], 16) for i in (0, 2, 4))


def _hex(channels) -> str:
    return "#" + "".join(f"{max(0, min(255, round(c))):02x}" for c in channels)


def _mix(a, b, t):
    return tuple(x + (y - x) * t for x, y in zip(a, b))


def _push(color, away_from, t):
    """Move `color` further from `away_from` by the fraction t of the gap."""
    return tuple(c + (c - o) * t for c, o in zip(color, away_from))


def terminal_ramp() -> str:
    base = _rgb(flat["surface.base"])
    raised = _rgb(flat["surface.raised"])
    ink = _rgb(flat["text.ink"])
    ink_bright = _rgb(flat["text.inkBright"])

    lines = ["# 16-231: the surface -> ink axis"]
    for i in range(216):
        lines.append(f"color{i + 16} {_hex(_mix(raised, ink, i / 215))}")
    lines.append("# 232-255: the same axis, extended past both poles")
    low = _push(base, ink_bright, 0.02)
    high = _push(ink_bright, base, 0.03)
    for i in range(24):
        lines.append(f"color{i + 232} {_hex(_mix(low, high, i / 23))}")
    return "\n".join(lines)


flat["ramp.terminal"] = terminal_ramp()


def render(text):
    def repl(m):
        key = m.group(1).strip()
        if key not in flat:
            raise KeyError(f"Unknown key: {key}")
        val = flat[key]
        if isinstance(val, bool):
            return "true" if val else "false"
        return str(val)
    return re.sub(r"\{\{\s*([^}]+?)\s*\}\}", repl, text)

def write_atomic(path: Path, text: str) -> None:
    """Write through a sibling temp file and rename it into place.

    Quickshell (and every other watcher here) reloads the moment the path
    changes. A plain write_text truncates first, so a reload landing in that
    window reads an empty QML file and the whole shell -- the bar included --
    dies with a load error. os.replace is atomic on one filesystem: the watcher
    sees old or new, never a half-written file.
    """
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_name(f".{path.name}.tmp")
    tmp.write_text(text)
    os.replace(tmp, path)


def render_animations(cfg: dict) -> str:
    """Generate the Hyprland animation block from animations.json."""
    lines = ["-- Generated animations"]
    enabled = bool(cfg.get("enabled", False))
    enabled_flag = "true" if enabled else "false"
    lines.append(f"hl.config({{ animations = {{ enabled = {enabled_flag} }} }})")
    for name, points in (cfg.get("curves") or {}).items():
        pts = ", ".join(f"{{{x}, {y}}}" for x, y in points)
        lines.append(f'hl.curve("{name}", {{ type = "bezier", points = {{ {pts} }} }})')

    for leaf in cfg.get("leaves") or []:
        leaf_flag = "true" if leaf.get("enabled") else "false"
        fields = [f'leaf = "{leaf["leaf"]}"', f"enabled = {leaf_flag}"]
        if "speed" in leaf:
            fields.append(f'speed = {leaf["speed"]}')
        if leaf.get("bezier"):
            fields.append(f'bezier = "{leaf["bezier"]}"')
        if leaf.get("style"):
            fields.append(f'style = "{leaf["style"]}"')
        body = ", ".join(fields)
        lines.append(f"hl.animation({{ {body} }})")

    return "\n".join(lines) + "\n"

# Outputs
hypr_color_out = Path.home() / ".config" / "hypr" / "theme.lua"
hypr_look_out = Path.home() / ".config" / "hypr" / "look.lua"
hypr_anim_out = Path.home() / ".config" / "hypr" / "animations.lua"
gtk3_out = Path.home() / ".config" / "gtk-3.0" / "settings.ini"
gtk4_out = Path.home() / ".config" / "gtk-4.0" / "settings.ini"
gtk3_css_out = Path.home() / ".config" / "gtk-3.0" / "gtk.css"
gtk4_css_out = Path.home() / ".config" / "gtk-4.0" / "gtk.css"
sddm_out = Path.home() / ".config" / "sddm" / "arch" / "Main.qml"
# The greeter is a surface of its own (SDDM's QQuickView, no Quickshell), so it
# gets its own generated token file rather than numbers inlined into the QML.
sddm_appearance_out = Path.home() / ".config" / "sddm" / "arch" / "GreeterAppearance.qml"
kitty_main_out = Path.home() / ".config" / "kitty" / "kitty.conf"
kitty_theme_out = Path.home() / ".config" / "kitty" / "theme.conf"
fontconfig_out = Path.home() / ".config" / "fontconfig" / "fonts.conf"
lock_appearance_out = Path.home() / ".config" / "quickshell" / "lockscreen" / "config" / "LockAppearance.qml"
launcher_appearance_out = Path.home() / ".config" / "quickshell" / "launcher" / "Appearance.qml"
lock_materialicon_out = Path.home() / ".config" / "quickshell" / "lockscreen" / "components" / "MaterialIcon.qml"
launcher_materialicon_out = Path.home() / ".config" / "quickshell" / "launcher" / "components" / "MaterialIcon.qml"
bar_appearance_out = Path.home() / ".config" / "quickshell" / "bar" / "Appearance.qml"
bar_materialicon_out = Path.home() / ".config" / "quickshell" / "bar" / "components" / "MaterialIcon.qml"
webapp_appearance_out = Path.home() / ".config" / "quickshell" / "webapp" / "Appearance.qml"
webapp_materialicon_out = Path.home() / ".config" / "quickshell" / "webapp" / "components" / "MaterialIcon.qml"
wallpaper_appearance_out = Path.home() / ".config" / "quickshell" / "wallpaper" / "Appearance.qml"
calendar_appearance_out = Path.home() / ".config" / "quickshell" / "calendar" / "Appearance.qml"
calendar_materialicon_out = Path.home() / ".config" / "quickshell" / "calendar" / "components" / "MaterialIcon.qml"
volume_appearance_out = Path.home() / ".config" / "quickshell" / "volume" / "Appearance.qml"
volume_materialicon_out = Path.home() / ".config" / "quickshell" / "volume" / "components" / "MaterialIcon.qml"
brightness_appearance_out = Path.home() / ".config" / "quickshell" / "brightness" / "Appearance.qml"
brightness_materialicon_out = Path.home() / ".config" / "quickshell" / "brightness" / "components" / "MaterialIcon.qml"
wifi_appearance_out = Path.home() / ".config" / "quickshell" / "wifi" / "Appearance.qml"
wifi_materialicon_out = Path.home() / ".config" / "quickshell" / "wifi" / "components" / "MaterialIcon.qml"
tokens_appearance_out = Path.home() / ".config" / "quickshell" / "tokens" / "Appearance.qml"
tokens_materialicon_out = Path.home() / ".config" / "quickshell" / "tokens" / "components" / "MaterialIcon.qml"
kanban_appearance_out = Path.home() / ".config" / "quickshell" / "kanban" / "Appearance.qml"
battery_appearance_out = Path.home() / ".config" / "quickshell" / "battery" / "Appearance.qml"
battery_materialicon_out = Path.home() / ".config" / "quickshell" / "battery" / "components" / "MaterialIcon.qml"
monitor_appearance_out = Path.home() / ".config" / "quickshell" / "monitor" / "Appearance.qml"
monitor_materialicon_out = Path.home() / ".config" / "quickshell" / "monitor" / "components" / "MaterialIcon.qml"
# herdr keys its themes by filename and config/herdr-app/settings.json points at
# this name, so the file follows the palette instead of keeping the name of the
# palette it used to hold. The previous one is unlinked below: a theme file left
# behind is a colour set that is no longer generated and still selectable.
herdr_theme_out = Path.home() / ".config" / "herdr-app" / "themes" / f"{data['name']}.json"
# ~/.config/herdr-app is a real directory (the app owns it), so the repo keeps a
# tracked copy of the same file. Writing only one of them is how the two drifted
# apart before: the tracked copy is generated here too, never by hand.
herdr_theme_mirror_out = ROOT / "config" / "herdr-app" / "themes" / f"{data['name']}.json"
RETIRED_HERDR_THEMES = ("barro.json", "warm-charcoal.json")
yazi_theme_out = Path.home() / ".config" / "yazi" / "theme.toml"
starship_out = Path.home() / ".config" / "starship.toml"
# The Hermes skin is generated, never hand-written: the TUI/CLI/desktop all read
# one YAML, and that YAML is a function of theme/colors.json like every other
# output here. HERMES_HOME is respected because the agent supports profiles.
hermes_home = Path(os.environ.get("HERMES_HOME") or Path.home() / ".hermes")
hermes_skin_out = hermes_home / "skins" / f"{data['name']}.yaml"
# Marker that lets this script retire skins it generated for a previous palette
# without ever touching one written by hand.
GENERATED_MARKER = "Generated by scripts/theme/apply-theme.py"

hypr_color_tpl = (TEMPLATES / "tools" / "hyprland.lua.tpl").read_text()
hypr_look_tpl = (TEMPLATES / "general" / "look.lua.tpl").read_text()
gtk3_tpl = (TEMPLATES / "tools" / "gtk3.ini.tpl").read_text()
gtk4_tpl = (TEMPLATES / "tools" / "gtk4.ini.tpl").read_text()
gtk3_css_tpl = (TEMPLATES / "tools" / "gtk3-css.tpl").read_text()
gtk4_css_tpl = (TEMPLATES / "tools" / "gtk4-css.tpl").read_text()
sddm_tpl = (TEMPLATES / "tools" / "sddm" / "Main.qml.tpl").read_text()
sddm_appearance_tpl = (TEMPLATES / "tools" / "sddm" / "GreeterAppearance.qml.tpl").read_text()
kitty_main_tpl = (TEMPLATES / "tools" / "kitty-main.conf.tpl").read_text()
kitty_theme_tpl = (TEMPLATES / "tools" / "kitty-theme.conf.tpl").read_text()
fontconfig_tpl = (TEMPLATES / "tools" / "fontconfig.conf.tpl").read_text()
lock_appearance_tpl = (TEMPLATES / "tools" / "quickshell-lock-appearance.qml.tpl").read_text()
launcher_appearance_tpl = (TEMPLATES / "tools" / "quickshell-launcher-appearance.qml.tpl").read_text()
lock_materialicon_tpl = (TEMPLATES / "tools" / "quickshell-lock-materialicon.qml.tpl").read_text()
# The legend row is one recipe in every plaque that shows keys. It is generated
# per panel for the same reason MaterialIcon is -- it reads that panel's
# Appearance -- and it exists because the kanban's footer was the only copy of
# the cap recipe while seven other footers spelled their hints out as one flat
# string. Two recipes for the same object is how surfaces drift apart.
legendrow_tpl = (TEMPLATES / "tools" / "quickshell-legendrow.qml.tpl").read_text()
# The AI plaque's card anatomy, generated per panel for the same reason LegendRow
# is: each copy imports ".." and therefore resolves *that* panel's Appearance, so a
# shared file in one panel's directory is unreachable from the others.
panelcard_tpl = (TEMPLATES / "tools" / "quickshell-panelcard.qml.tpl").read_text()
statuschip_tpl = (TEMPLATES / "tools" / "quickshell-statuschip.qml.tpl").read_text()
usagebar_tpl = (TEMPLATES / "tools" / "quickshell-usagebar.qml.tpl").read_text()
launcher_materialicon_tpl = (TEMPLATES / "tools" / "quickshell-launcher-materialicon.qml.tpl").read_text()
bar_appearance_tpl = (TEMPLATES / "tools" / "quickshell-bar-appearance.qml.tpl").read_text()
# The bar's icons carry optical sizing (status-row glyph variants measured in em);
# the other surfaces' icons stay on the font's own draw, so they keep the shared
# launcher template.
bar_materialicon_tpl = (TEMPLATES / "tools" / "quickshell-bar-materialicon.qml.tpl").read_text()
webapp_appearance_tpl = (TEMPLATES / "tools" / "quickshell-webapp-appearance.qml.tpl").read_text()
wallpaper_appearance_tpl = (TEMPLATES / "tools" / "quickshell-wallpaper-appearance.qml.tpl").read_text()
calendar_appearance_tpl = (TEMPLATES / "tools" / "quickshell-calendar-appearance.qml.tpl").read_text()
volume_appearance_tpl = (TEMPLATES / "tools" / "quickshell-volume-appearance.qml.tpl").read_text()
brightness_appearance_tpl = (TEMPLATES / "tools" / "quickshell-brightness-appearance.qml.tpl").read_text()
wifi_appearance_tpl = (TEMPLATES / "tools" / "quickshell-wifi-appearance.qml.tpl").read_text()
tokens_appearance_tpl = (TEMPLATES / "tools" / "quickshell-tokens-appearance.qml.tpl").read_text()
kanban_appearance_tpl = (TEMPLATES / "tools" / "quickshell-kanban-appearance.qml.tpl").read_text()
battery_appearance_tpl = (TEMPLATES / "tools" / "quickshell-battery-appearance.qml.tpl").read_text()
monitor_appearance_tpl = (TEMPLATES / "tools" / "quickshell-monitor-appearance.qml.tpl").read_text()
herdr_theme_tpl = (TEMPLATES / "tools" / "herdr-theme.json.tpl").read_text()
yazi_theme_tpl = (TEMPLATES / "tools" / "yazi-theme.toml.tpl").read_text()
starship_tpl = (TEMPLATES / "tools" / "starship.toml.tpl").read_text()
hermes_skin_tpl = (TEMPLATES / "tools" / "hermes-skin.yaml.tpl").read_text()

# --- fail fast: every {{key}} in every template must resolve in `flat` ---
def collect_placeholders(text):
    return set(re.findall(r"\{\{\s*([^}]+?)\s*\}\}", text))


def validate_templates(spec):
    missing = []
    for name, content in spec.items():
        for key in collect_placeholders(content):
            if key not in flat:
                missing.append(f"{name}: {key}")
    if missing:
        print("apply-theme.py: aborting — missing theme keys (no files written):")
        for m in sorted(set(missing)):
            print(f"  - {m}")
        sys.exit(1)


# --- one type scale for every surface ---
# The panels used to expose their own subset of sizes under their own names
# (levelFontSize, searchIconSize, fontSizeClock), which is how two surfaces
# drifted apart while reading the same JSON. Every generated Appearance.qml now
# carries the same six steps, and a QML file may not hardcode a pixel size: it
# picks a role. This check is what keeps that true after the next panel lands.
TYPE_SCALE = ("micro", "small", "caption", "body", "title", "display")


def check_type_scale(templates):
    problems = []
    for name, text in templates.items():
        for step in TYPE_SCALE:
            prop = f"fontSize{step[0].upper()}{step[1:]}"
            decl = f"readonly property int {prop}:"
            token = f"typography.sizes.{step}"
            lines = [ln for ln in text.splitlines() if decl in ln]
            if not lines:
                problems.append(f"{name}: {prop} is missing")
            elif not any(token in ln for ln in lines):
                problems.append(f"{name}: {prop} does not read {token}")
    if problems:
        print("apply-theme.py: aborting — type scale drift (no files written):", file=sys.stderr)
        for p in problems:
            print(f"  - {p}", file=sys.stderr)
        sys.exit(1)


def check_no_hardcoded_type(root):
    offenders = []
    for path in root.rglob("*.qml"):
        if path.name in {"Appearance.qml", "MaterialIcon.qml"} or path.name.endswith(".test.qml"):
            continue
        for number, line in enumerate(path.read_text().splitlines(), 1):
            if re.search(r"font\.pixelSize:\s*\d", line):
                offenders.append(f"{path}:{number}: {line.strip()}")
    if offenders:
        print("apply-theme.py: a QML file hardcodes a type size:", file=sys.stderr)
        for o in offenders:
            print(f"  - {o}", file=sys.stderr)
        sys.exit(1)


# --- one set of control heights for every surface ---
# Same reason as the type ladder: five panels used to size a text field 32, 34,
# 36, 52 and 56 px, and an input that tall next to a 32 px button is what reads
# as "unadjusted". The roles live in look.controls; a template may not declare
# them from a literal, and a QML file may not carry a bare pixel measure.
METRIC_ROLES = (
    "contentPad", "headerHeight", "footerHeight",
    "fieldHeight", "fieldHeightHero", "fieldHeightCompact",
    "buttonHeight", "buttonHeightLarge", "rowHeight",
    "iconButtonSize", "chipHeight",
    "ruleWidth", "ruleThickness", "cursorWidth", "cursorHeight",
    "zBadge", "zOverlay", "zPopover", "zModal",
)

GEOMETRY_PROP = re.compile(
    r"^\s*[\w.]*(?:height|Height|width|Width|spacing|Spacing|margins|Margin"
    r"|radius|padding|Pad|gap|Gap|x|y|z)\s*:\s*(?P<val>[^/]+)$"
)


def check_metric_roles(templates):
    problems = []
    for name, text in templates.items():
        for role in METRIC_ROLES:
            decl = f"readonly property int {role}:"
            lines = [ln for ln in text.splitlines() if decl in ln]
            if not lines:
                problems.append(f"{name}: {role} is missing")
            elif not any("look.controls." in ln for ln in lines):
                problems.append(f"{name}: {role} does not read look.controls")
    if problems:
        print("apply-theme.py: aborting — control scale drift (no files written):", file=sys.stderr)
        for p in problems:
            print(f"  - {p}", file=sys.stderr)
        sys.exit(1)


# --- one ornament role for every surface ---
# The gilt (gold) role carries every ornament: the header rule and the plaque
# edge. The accent stays the action colour (hover, selection, focus, sliders).
# Same drift story as the type ladder: if a template drops the role or re-points
# it at the action accent, the desktop loses the gold/or-mint split silently.
def check_gilt_role(templates):
    problems = []
    for name, text in templates.items():
        decl = "readonly property color gilt:"
        ink = "readonly property color giltInk:"
        lines = [ln for ln in text.splitlines() if decl in ln]
        inks = [ln for ln in text.splitlines() if ink in ln]
        if not lines:
            problems.append(f"{name}: gilt role is missing")
        elif not any("accent.tertiary" in ln for ln in lines):
            problems.append(f"{name}: gilt does not read accent.tertiary")
        # The ornament tone clears 3.0:1 as a stroke and only that: gold read as
        # text needs its own deeper step, or a 11 px label in gilt lands at ~3.5:1.
        if not inks:
            problems.append(f"{name}: giltInk role is missing")
        elif not any("accent.tertiaryInk" in ln for ln in inks):
            problems.append(f"{name}: giltInk does not read accent.tertiaryInk")
    if problems:
        print("apply-theme.py: aborting — gilt role drift (no files written):", file=sys.stderr)
        for p in problems:
            print(f"  - {p}", file=sys.stderr)
        sys.exit(1)


# --- one motion source for every surface ---
# Motion enters QML through this pipeline only. The launcher used to carry its own
# Motion.qml that parsed animations.json at run time with keys that no longer
# existed (`durations.short`, `easing`), so its hover silently fell back to 0 ms
# while every other panel animated. A template that declares a motion token must
# read it from animations.ui, and no other QML file may read the animation JSON
# (check_no_runtime_motion). A surface with nothing to animate declares nothing,
# which is why this is a rule about how motion is declared, not how much.
MOTION_PROP = re.compile(r"readonly property int (motion[A-Za-z]*)\s*:\s*(.+?)\s*$")


def check_motion_roles(templates):
    problems = []
    for name, text in templates.items():
        for line in text.splitlines():
            match = MOTION_PROP.search(line)
            if not match:
                continue
            prop, value = match.group(1), match.group(2)
            if "animations.ui." not in value:
                problems.append(f"{name}: {prop} does not read animations.ui")
    if problems:
        print("apply-theme.py: aborting — motion source drift (no files written):", file=sys.stderr)
        for p in problems:
            print(f"  - {p}", file=sys.stderr)
        sys.exit(1)


def check_no_runtime_motion(root):
    offenders = []
    for path in root.rglob("*.qml"):
        if path.name in {"Appearance.qml", "MaterialIcon.qml"} or path.name.endswith("test.qml"):
            continue
        for number, line in enumerate(path.read_text().splitlines(), 1):
            code = line.split("//")[0]
            if "animations.json" in code or "QS_ANIMATIONS_FILE" in code:
                offenders.append(f"{path}:{number}: {line.strip()}")
    if offenders:
        print("apply-theme.py: a QML file reads the animation JSON at run time:", file=sys.stderr)
        for o in offenders:
            print(f"  - {o}", file=sys.stderr)
        sys.exit(1)


# --- the entrance is a fade and a lift, never half of one ---
# The direction line asks for "fade + subtle lift" and the first pass shipped the
# fade alone, which is a plaque that pops. Both halves are one gesture and are
# checked as one: a surface that animates the entrance duration without carrying
# the offset is a regression the eye reads as "abrupt", not as a missing token.
def check_entrance_lift(root):
    offenders = []
    for path in root.rglob("*.qml"):
        if path.name in {"Appearance.qml", "MaterialIcon.qml"} or path.name.endswith("test.qml"):
            continue
        text = path.read_text()
        if "appearance.motionEntranceDuration" in text and \
                "appearance.motionEntranceOffset" not in text:
            offenders.append(str(path))
    if offenders:
        print("apply-theme.py: an entrance animates without its lift:", file=sys.stderr)
        for o in offenders:
            print(f"  - {o}", file=sys.stderr)
        sys.exit(1)


# --- one legend recipe for every surface that shows keys ---
# Seven footers used to spell their hints out as a single string ("↑↓ adjust    M
# mute    esc close"): the keys were ordinary prose, every panel invented its own
# separator, and the one real cap recipe lived in the kanban. The legend row is
# generated into every one of those panels now. This refuses a QML string that
# carries two or more key signs -- the shape the flat footers had -- and the
# template check below keeps the caps reading their roles from Appearance.
HINT_SIGNS = ("esc ", "↑↓", "←→", "↵ ", "tab ")


def check_no_flat_hints(root):
    offenders = []
    for path in root.rglob("*.qml"):
        if path.name in {"Appearance.qml", "MaterialIcon.qml"} or path.name.endswith("test.qml"):
            continue
        for number, line in enumerate(path.read_text().splitlines(), 1):
            code = line.split("//")[0]
            for literal in re.findall(r'"([^"]*)"', code):
                signs = [s for s in HINT_SIGNS if s in literal.lower()]
                if len(signs) >= 2:
                    offenders.append(f"{path}:{number}: {line.strip()}")
    if offenders:
        print("apply-theme.py: a surface still spells its key hints out as prose:",
              file=sys.stderr)
        for o in offenders:
            print(f"  - {o}", file=sys.stderr)
        sys.exit(1)


KEYCAP_ROLES = ("keycapHeight", "shapeSmall", "hairline", "outline", "uiFont", "fontSizeSmall")


# --- a generated Appearance declares each role once ---
# A scripted rewrite of the typography block in the greeter's Appearance left two
# copies of every weight role in the file: the template rendered, the theme
# installed, and the greeter failed with "Duplicate property name" — caught by the
# offscreen suite, not by the generator. Every Appearance is one QtObject, so a
# repeated role name is always a bug, and this is where it is cheap to see.
ROLE_DECL = re.compile(r"^\s*readonly\s+property\s+[\w.]+\s+(\w+)\s*:")


def check_duplicate_roles(templates):
    problems = []
    for name, text in templates.items():
        seen = {}
        for number, line in enumerate(text.splitlines(), 1):
            code = line.split("//")[0]
            match = ROLE_DECL.match(code)
            if not match:
                continue
            role = match.group(1)
            if role in seen:
                problems.append(f"{name}: {role} declared twice (lines {seen[role]} and {number})")
            else:
                seen[role] = number
    if problems:
        print("apply-theme.py: aborting — duplicated role in a generated Appearance:",
              file=sys.stderr)
        for p in problems:
            print(f"  - {p}", file=sys.stderr)
        sys.exit(1)


# --- the greeter is a surface of its own, and it must not grow literals ---
# It used to be a raster theme: a logo, an entry frame, a lock glyph and a bullet
# dot, all PNGs recoloured by sddm-assets.py, with pixel sizes written into the
# QML (640x480, 34x38, 7x7, 5 px of letter spacing). That is a second design
# system, maintained by a script, next to the one every panel reads. The greeter
# now draws the unlock card from its own generated Appearance, so what used to be
# a look can be checked: no colour literal, no font family literal, no raster
# asset, no Image element.
GREETER_LITERAL_COLOR = re.compile(r"#[0-9a-fA-F]{3,8}\b")
GREETER_LITERAL_FONT = re.compile(r'font\.family\s*:\s*"')


def check_greeter_surface(name, text):
    offenders = []
    for number, line in enumerate(text.splitlines(), 1):
        code = line.split("//")[0]
        if GREETER_LITERAL_COLOR.search(code):
            offenders.append(f"{name}:{number}: a colour literal")
        if GREETER_LITERAL_FONT.search(code):
            offenders.append(f"{name}:{number}: a font family literal")
        if ".png" in code:
            offenders.append(f"{name}:{number}: a raster asset")
        if re.match(r"^\s*Image\s*\{", code):
            offenders.append(f"{name}:{number}: an Image element")
    offenders.extend(measure_offenders(name, text))
    if offenders:
        print("apply-theme.py: the greeter carries values that are not tokens:",
              file=sys.stderr)
        for o in offenders:
            print(f"  - {o}", file=sys.stderr)
        sys.exit(1)


def check_legend_roles(templates):
    text = templates.get("quickshell-legendrow.qml.tpl", "")
    problems = [f"legendrow: {role} is not read from appearance"
                for role in KEYCAP_ROLES if f"appearance.{role}" not in text]
    if "cap.implicitWidth" not in text:
        problems.append("legendrow: the cap does not size itself to its key")
    if problems:
        print("apply-theme.py: the legend row drifted from its roles:", file=sys.stderr)
        for p in problems:
            print(f"  - {p}", file=sys.stderr)
        sys.exit(1)


# --- one hover recipe for every surface ---
# Hover stopped being a translucent wash of the action accent: it now lights the
# object — one rung up the tonal ladder plus a gilt hairline — and press steps the
# fill back down. Three colour roles carry that, and they have to read the same
# three palette keys everywhere or the desktop goes back to a hover that is a
# different object on every panel. Same drift story as the type ladder.
MATERIAL_ROLES = (
    ("hoverFill", "surface.raisedHigh"),
    ("hoverFillHigh", "surface.selection"),
    ("pressFill", "surface.base"),
)


def check_material_roles(templates):
    problems = []
    for name, text in templates.items():
        for role, token in MATERIAL_ROLES:
            decl = f"readonly property color {role}:"
            lines = [ln for ln in text.splitlines() if decl in ln]
            if not lines:
                problems.append(f"{name}: {role} is missing")
            elif not any(token in ln for ln in lines):
                problems.append(f"{name}: {role} does not read {token}")
    if problems:
        print("apply-theme.py: aborting — material role drift (no files written):", file=sys.stderr)
        for p in problems:
            print(f"  - {p}", file=sys.stderr)
        sys.exit(1)


# --- one icon ladder for every surface ---
# Same story as the type scale, and it cost real time: the icon steps live in
# typography.json and a panel picks a rung, never a pixel. The launcher's app
# icons were bound to iconXs (16) inside an 88 px tile — a 16 % icon that read as
# a speck — because the ladder had no tile rung and nothing said which rung was
# whose. The ladder is now six steps and every Appearance carries all of them.
ICON_STEPS = ("xs", "sm", "md", "lg", "xl", "tile")


def check_icon_scale(templates):
    problems = []
    for name, text in templates.items():
        for step in ICON_STEPS:
            prop = f"iconSize{step[0].upper()}{step[1:]}"
            token = f"typography.sizes.icon{step[0].upper()}{step[1:]}"
            decl = f"readonly property int {prop}:"
            lines = [ln for ln in text.splitlines() if decl in ln]
            if not lines:
                problems.append(f"{name}: {prop} is missing")
            elif not any(token in ln for ln in lines):
                problems.append(f"{name}: {prop} does not read {token}")
    if problems:
        print("apply-theme.py: aborting — icon scale drift (no files written):", file=sys.stderr)
        for p in problems:
            print(f"  - {p}", file=sys.stderr)
        sys.exit(1)


def measure_offenders(name, text):
    """Lines of `text` that pin a measure instead of reading a role."""
    offenders = []
    number = re.compile(r"(?<![\w.])(\d+(?:\.\d+)?)(?![\w.])")
    relation = re.compile(r"^(parent\.)?(width|height)\s*/\s*\d+$")
    for line_number, line in enumerate(text.splitlines(), 1):
        match = GEOMETRY_PROP.match(line)
        if not match:
            continue
        value = match.group("val").split("//")[0].strip()
        if not number.search(value) or "appearance." in value:
            continue
        if relation.match(value) or "/ 100" in value:
            continue
        # 0 and 1 are structural (no offset, a fraction, a single pixel of
        # border); anything from 2 upwards is a measure somebody chose — unless
        # it only divides a width or a height, which is a proportion.
        measures = [n for n in number.findall(value) if float(n) >= 2]
        if not measures:
            continue
        if all(re.search(r"[/\*]\s*" + re.escape(n) + r"\b", value) for n in measures):
            continue
        offenders.append(f"{name}:{line_number}: {line.strip()}")
    return offenders


def check_no_hardcoded_geometry(root):
    offenders = []
    for path in root.rglob("*.qml"):
        if path.name in {"Appearance.qml", "MaterialIcon.qml", "GreeterAppearance.qml"} or \
                path.name.endswith("test.qml"):
            continue
        if "services/" in str(path):
            continue
        offenders.extend(measure_offenders(str(path), path.read_text()))
    if offenders:
        print("apply-theme.py: a QML file hardcodes a measure:", file=sys.stderr)
        for o in offenders:
            print(f"  - {o}", file=sys.stderr)
        sys.exit(1)


# --- text is never dimmed with opacity ---
# The design system says it plainly: never dim text with opacity, step the ink.
# Three surfaces broke it anyway -- the lock card's PASSWORD label and its status
# line at 0.55, which composited to 3.43:1 over the card they sit on. The check is
# arithmetic rather than taste: take the caption ink, put it over the lightest
# surface in the palette at the alpha the role asks for, and read the contrast. If
# that number is under target the text is not readable at that alpha, so the role
# does not belong on a Text at all. The numbers come from theme/, so retuning
# look.opacity or colors.json moves the verdict with them instead of leaving a
# convention behind.
TEXT_BLOCK = re.compile(r"^\s*(Text|Label)\s*\{")
OPACITY_ROLE = re.compile(r"opacity([A-Z][A-Za-z]*)")
FRACTION = re.compile(r"(?<![\w.])(\d*\.\d+)(?![\w.])")
TEXT_CONTRAST_TARGET = 4.5


def _channel(value):
    value = value / 255
    return value / 12.92 if value <= 0.03928 else ((value + 0.055) / 1.055) ** 2.4


def _luminance(rgb):
    return 0.2126 * _channel(rgb[0]) + 0.7152 * _channel(rgb[1]) + 0.0722 * _channel(rgb[2])


def _contrast(one, two):
    high, low = max(_luminance(one), _luminance(two)), min(_luminance(one), _luminance(two))
    return (high + 0.05) / (low + 0.05)


def check_no_text_opacity(root, colors, opacity):
    ink = _rgb(colors["text"]["inkSoft"])
    surface = _rgb(colors["surface"]["raisedHigh"])
    offenders = []
    for path in root.rglob("*.qml"):
        if path.name in {"Appearance.qml", "MaterialIcon.qml", "LockAppearance.qml"} or \
                path.name.endswith("test.qml"):
            continue
        inside = None
        depth = 0
        for number, line in enumerate(path.read_text().splitlines(), 1):
            code = line.split("//")[0]
            if inside is None:
                if TEXT_BLOCK.match(code):
                    depth = code.count("{") - code.count("}")
                    inside = number if depth > 0 else None
                continue
            depth += code.count("{") - code.count("}")
            if "opacity:" in code:
                expression = code.split("opacity:", 1)[1].strip()
                role = OPACITY_ROLE.search(expression)
                if role:
                    key = role.group(1)[0].lower() + role.group(1)[1:]
                    alpha = opacity.get(key)
                    if alpha is None:
                        offenders.append(
                            f"{path}:{number}: text dimmed with an unknown opacity role ({key})")
                    else:
                        blended = tuple(round(alpha * f + (1 - alpha) * b)
                                        for f, b in zip(ink, surface))
                        read = _contrast(blended, surface)
                        if read < TEXT_CONTRAST_TARGET:
                            offenders.append(
                                f"{path}:{number}: text at opacity:{alpha} reads {read:.2f}:1 "
                                f"over raisedHigh")
                elif FRACTION.findall(expression):
                    offenders.append(f"{path}:{number}: text dimmed by a literal ({expression})")
            if depth <= 0:
                inside = None
    if offenders:
        print("apply-theme.py: text is dimmed with opacity instead of ink:", file=sys.stderr)
        for o in offenders:
            print(f"  - {o}", file=sys.stderr)
        sys.exit(1)


# --- a declared font voice must be a rendered one ---
# `typography.fonts.serif` stood for EB Garamond, documented as the voice for
# "lock-screen prose and notification bodies". No template ever asked for it and
# there is no notification body on this desktop, so the token was a fourth voice
# that only existed to drift -- and it survived a typography pass because nothing
# checks the other direction: every family in the JSON has to be read by some
# template.
def check_font_roles(templates, fonts):
    problems = []
    for key in fonts:
        placeholder = f"typography.fonts.{key}"
        if not any(placeholder in text for text in templates.values()):
            problems.append(f"{key} ({fonts[key]}) is declared but no template renders it")
    if problems:
        print("apply-theme.py: aborting — unused font voice (no files written):",
              file=sys.stderr)
        for p in problems:
            print(f"  - {p}", file=sys.stderr)
        sys.exit(1)


TEMPLATE_SPEC = {
    "hyprland.lua.tpl": hypr_color_tpl,
    "look.lua.tpl": hypr_look_tpl,
    "gtk3.ini.tpl": gtk3_tpl,
    "gtk4.ini.tpl": gtk4_tpl,
    "gtk3-css.tpl": gtk3_css_tpl,
    "gtk4-css.tpl": gtk4_css_tpl,
    "sddm/Main.qml.tpl": sddm_tpl,
    "sddm/GreeterAppearance.qml.tpl": sddm_appearance_tpl,
    "kitty-main.conf.tpl": kitty_main_tpl,
    "kitty-theme.conf.tpl": kitty_theme_tpl,
    "fontconfig.conf.tpl": fontconfig_tpl,
    "quickshell-lock-appearance.qml.tpl": lock_appearance_tpl,
    "quickshell-launcher-appearance.qml.tpl": launcher_appearance_tpl,
    "quickshell-lock-materialicon.qml.tpl": lock_materialicon_tpl,
    "quickshell-launcher-materialicon.qml.tpl": launcher_materialicon_tpl,
    "quickshell-bar-appearance.qml.tpl": bar_appearance_tpl,
    "quickshell-bar-materialicon.qml.tpl": bar_materialicon_tpl,
    "quickshell-webapp-appearance.qml.tpl": webapp_appearance_tpl,
    "quickshell-wallpaper-appearance.qml.tpl": wallpaper_appearance_tpl,
    "quickshell-calendar-appearance.qml.tpl": calendar_appearance_tpl,
    "quickshell-volume-appearance.qml.tpl": volume_appearance_tpl,
    "quickshell-brightness-appearance.qml.tpl": brightness_appearance_tpl,
    "quickshell-wifi-appearance.qml.tpl": wifi_appearance_tpl,
    "quickshell-tokens-appearance.qml.tpl": tokens_appearance_tpl,
    "quickshell-kanban-appearance.qml.tpl": kanban_appearance_tpl,
    "quickshell-battery-appearance.qml.tpl": battery_appearance_tpl,
    "quickshell-monitor-appearance.qml.tpl": monitor_appearance_tpl,
    "herdr-theme.json.tpl": herdr_theme_tpl,
    "yazi-theme.toml.tpl": yazi_theme_tpl,
    "starship.toml.tpl": starship_tpl,
    "quickshell-legendrow.qml.tpl": legendrow_tpl,
    "quickshell-panelcard.qml.tpl": panelcard_tpl,
    "quickshell-statuschip.qml.tpl": statuschip_tpl,
    "quickshell-usagebar.qml.tpl": usagebar_tpl,
    "hermes-skin.yaml.tpl": hermes_skin_tpl,
}
validate_templates(TEMPLATE_SPEC)
check_font_roles(TEMPLATE_SPEC, typo_data["fonts"])

APPEARANCE_TEMPLATES = {
    "bar": bar_appearance_tpl,
    "battery": battery_appearance_tpl,
    "brightness": brightness_appearance_tpl,
    "calendar": calendar_appearance_tpl,
    "kanban": kanban_appearance_tpl,
    "launcher": launcher_appearance_tpl,
    "monitor": monitor_appearance_tpl,
    "tokens": tokens_appearance_tpl,
    "volume": volume_appearance_tpl,
    "webapp": webapp_appearance_tpl,
    "wifi": wifi_appearance_tpl,
}
# Panels whose footer carries key hints. The kanban is in the list because its
# legend is the recipe the others were reworked onto, not because it needed a
# new file.
LEGEND_PANELS = ("launcher", "brightness", "calendar", "kanban", "battery",
                 "monitor", "tokens", "volume", "wifi")
# Panels built out of cards. The launcher is a grid and the kanban's lanes own
# their metric, so neither takes a card; the bar takes one for its toasts.
CARD_PANELS = ("bar", "battery", "brightness", "calendar", "monitor", "tokens",
               "volume", "webapp", "wifi")
check_type_scale(APPEARANCE_TEMPLATES)
check_metric_roles(APPEARANCE_TEMPLATES)
GILT_TEMPLATES = dict(APPEARANCE_TEMPLATES)
GILT_TEMPLATES["lock"] = lock_appearance_tpl
GILT_TEMPLATES["greeter"] = sddm_appearance_tpl
check_gilt_role(GILT_TEMPLATES)
# The lock surface is an Appearance too, and it sat outside both gates: its
# template had no hoverFill/pressFill at all, so its one button shipped with no
# hover while every plaque had the same recipe, and nothing failed. The role
# families it shares with the panels are checked over the same dict now, and the
# greeter joins them: it renders the unlock card's button recipe, so it declares
# the same roles and reads the same motion source.
LOCK_TEMPLATES = dict(APPEARANCE_TEMPLATES)
LOCK_TEMPLATES["lock"] = lock_appearance_tpl
LOCK_TEMPLATES["greeter"] = sddm_appearance_tpl
check_motion_roles(LOCK_TEMPLATES)
check_material_roles(LOCK_TEMPLATES)
# One declaration per role, in every generated Appearance: a duplicated block is
# a QML load error ("Duplicate property name") that renders as a blank surface.
check_duplicate_roles(LOCK_TEMPLATES)
check_duplicate_roles({"greeter": sddm_appearance_tpl})
CARD_ROLES = (
    ("cardFill", "surface.raised", "color"),
    ("cardRadius", "look.borders.radius.lg", "int"),
    ("cardPad", "look.spacing.lg", "int"),
    ("cardGap", "look.spacing.md", "int"),
    ("usageBarHeight", "look.spacing.xs", "int"),
    # The track alpha is read by UsageBar and by the battery's LevelBar. It was
    # referenced by both and declared by neither for exactly one commit: the
    # binding resolved to undefined, and the "14 % track" painted solid ink.
    ("usageBarTrack", "look.opacity.barTrack", "real"),
)


def check_card_roles(templates):
    """Every panel that can hold a card declares the card's four metrics and its bar."""
    problems = []
    for name, text in templates.items():
        for role, token, kind in CARD_ROLES:
            decl = f"readonly property {kind} {role}:"
            lines = [ln for ln in text.splitlines() if decl in ln]
            if not lines:
                problems.append(f"{name}: {role} is missing")
            elif not any(token in ln for ln in lines):
                problems.append(f"{name}: {role} does not read {token}")
    if problems:
        print("apply-theme.py: aborting — card drift (no files written):", file=sys.stderr)
        for p in problems:
            print(f"  - {p}", file=sys.stderr)
        sys.exit(1)


# The greeter is out: SDDM draws a single unlock card, not a stack of them.
CARD_TEMPLATES = dict(APPEARANCE_TEMPLATES)
CARD_TEMPLATES["lock"] = lock_appearance_tpl
check_card_roles(CARD_TEMPLATES)
check_icon_scale(APPEARANCE_TEMPLATES)
check_no_hardcoded_type(ROOT / "config" / "quickshell")
check_no_hardcoded_geometry(ROOT / "config" / "quickshell")
# The greeter has no live output to walk on a first run (its generated QML is
# what this script is about to write), so it is checked as rendered text.
check_greeter_surface("sddm/Main.qml.tpl", render(sddm_tpl))
check_no_text_opacity(ROOT / "config" / "quickshell", data, look_data["opacity"])
check_no_runtime_motion(ROOT / "config" / "quickshell")
check_entrance_lift(ROOT / "config" / "quickshell")
check_no_flat_hints(ROOT / "config" / "quickshell")
check_legend_roles({"quickshell-legendrow.qml.tpl": legendrow_tpl})

write_atomic(hypr_color_out, render(hypr_color_tpl))
write_atomic(hypr_look_out, render(hypr_look_tpl))
write_atomic(hypr_anim_out, render_animations(anim_data))
write_atomic(gtk3_out, render(gtk3_tpl))
write_atomic(gtk4_out, render(gtk4_tpl))
write_atomic(gtk3_css_out, render(gtk3_css_tpl))
write_atomic(gtk4_css_out, render(gtk4_css_tpl))
write_atomic(kitty_theme_out, render(kitty_theme_tpl))
write_atomic(kitty_main_out, render(kitty_main_tpl))
write_atomic(fontconfig_out, render(fontconfig_tpl))
# A fonts.conf that does not parse degrades *every* application at once, silently:
# fontconfig falls back to its built-in defaults and the desktop keeps working with
# the wrong faces. An XML comment with `--` inside is enough to do it, so the file
# is parsed here before anything else runs.
import xml.etree.ElementTree as _ET  # noqa: E402  (local to this check)

try:
    _ET.parse(fontconfig_out)
except _ET.ParseError as exc:
    print(f"apply-theme.py: {fontconfig_out} is not valid XML: {exc}", file=sys.stderr)
    sys.exit(1)
# The panels ask for 600 with font.weight and the fontconfig rule in that file
# raises a weighted request for the terminal family to the same 600. fontconfig
# can only honour that against a face the family really declares, so check it
# instead of assuming: JetBrainsMono Nerd Font ships a real SemiBold, and a
# family that does not would come out at 400 with nothing said. 180 is
# fontconfig's demibold, which is what `weight=demibold` must resolve to.
for _role in ("ui", "mono"):
    _family = typo_data["fonts"][_role]
    _probe = subprocess.run(
        ["fc-match", "-f", "%{style}|%{weight}", f"{_family}:weight=demibold"],
        capture_output=True, text=True)
    _style, _, _weight = _probe.stdout.strip().partition("|")
    if _weight.strip() != "180":
        print(f"apply-theme.py: {_family} ({_role}) has no 600 face -- fontconfig resolves "
              f"weight=demibold to {_style or 'nothing'} (weight {_weight.strip() or 'unknown'}), "
              f"so text below 600 renders at 400", file=sys.stderr)
write_atomic(lock_appearance_out, render(lock_appearance_tpl))
write_atomic(launcher_appearance_out, render(launcher_appearance_tpl))
write_atomic(lock_materialicon_out, render(lock_materialicon_tpl))
write_atomic(launcher_materialicon_out, render(launcher_materialicon_tpl))
write_atomic(bar_appearance_out, render(bar_appearance_tpl))
write_atomic(bar_materialicon_out, render(bar_materialicon_tpl))
write_atomic(webapp_appearance_out, render(webapp_appearance_tpl))
write_atomic(wallpaper_appearance_out, render(wallpaper_appearance_tpl))
write_atomic(webapp_materialicon_out, render(launcher_materialicon_tpl))
write_atomic(calendar_appearance_out, render(calendar_appearance_tpl))
write_atomic(calendar_materialicon_out, render(launcher_materialicon_tpl))
write_atomic(volume_appearance_out, render(volume_appearance_tpl))
write_atomic(volume_materialicon_out, render(launcher_materialicon_tpl))
brightness_appearance_out.parent.mkdir(parents=True, exist_ok=True)
brightness_materialicon_out.parent.mkdir(parents=True, exist_ok=True)
write_atomic(brightness_appearance_out, render(brightness_appearance_tpl))
write_atomic(brightness_materialicon_out, render(launcher_materialicon_tpl))
wifi_appearance_out.parent.mkdir(parents=True, exist_ok=True)
wifi_materialicon_out.parent.mkdir(parents=True, exist_ok=True)
write_atomic(wifi_appearance_out, render(wifi_appearance_tpl))
write_atomic(wifi_materialicon_out, render(launcher_materialicon_tpl))
write_atomic(tokens_appearance_out, render(tokens_appearance_tpl))
write_atomic(tokens_materialicon_out, render(launcher_materialicon_tpl))
kanban_appearance_out.parent.mkdir(parents=True, exist_ok=True)
write_atomic(kanban_appearance_out, render(kanban_appearance_tpl))
battery_appearance_out.parent.mkdir(parents=True, exist_ok=True)
battery_materialicon_out.parent.mkdir(parents=True, exist_ok=True)
write_atomic(battery_appearance_out, render(battery_appearance_tpl))
write_atomic(battery_materialicon_out, render(launcher_materialicon_tpl))
monitor_appearance_out.parent.mkdir(parents=True, exist_ok=True)
monitor_materialicon_out.parent.mkdir(parents=True, exist_ok=True)
write_atomic(monitor_appearance_out, render(monitor_appearance_tpl))
write_atomic(monitor_materialicon_out, render(launcher_materialicon_tpl))
for _legend_panel in LEGEND_PANELS:
    _legend_out = (Path.home() / ".config" / "quickshell" / _legend_panel
                   / "components" / "LegendRow.qml")
    _legend_out.parent.mkdir(parents=True, exist_ok=True)
    write_atomic(_legend_out, render(legendrow_tpl))
for _card_panel in CARD_PANELS:
    _card_dir = Path.home() / ".config" / "quickshell" / _card_panel / "components"
    _card_dir.mkdir(parents=True, exist_ok=True)
    write_atomic(_card_dir / "PanelCard.qml", render(panelcard_tpl))
    write_atomic(_card_dir / "StatusChip.qml", render(statuschip_tpl))
    write_atomic(_card_dir / "UsageBar.qml", render(usagebar_tpl))
write_atomic(herdr_theme_out, render(herdr_theme_tpl))
herdr_theme_mirror_out.parent.mkdir(parents=True, exist_ok=True)
write_atomic(herdr_theme_mirror_out, render(herdr_theme_tpl))
for retired in RETIRED_HERDR_THEMES:
    for directory in (herdr_theme_out.parent, herdr_theme_mirror_out.parent):
        stale = directory / retired
        if stale.name != herdr_theme_out.name and stale.exists():
            stale.unlink()
yazi_theme_out.parent.mkdir(parents=True, exist_ok=True)
write_atomic(yazi_theme_out, render(yazi_theme_tpl))
write_atomic(starship_out, render(starship_tpl))
write_atomic(sddm_out, render(sddm_tpl))
write_atomic(sddm_appearance_out, render(sddm_appearance_tpl))
hermes_skin_out.parent.mkdir(parents=True, exist_ok=True)
write_atomic(hermes_skin_out, render(hermes_skin_tpl))
# A skin generated for an earlier palette is still selectable in /skin and would
# silently point at colours that no longer exist. Retire only our own outputs.
for stale_skin in hermes_skin_out.parent.glob("*.yaml"):
    if stale_skin.name == hermes_skin_out.name or stale_skin.is_symlink():
        continue
    try:
        if GENERATED_MARKER in stale_skin.read_text(errors="ignore"):
            stale_skin.unlink()
    except OSError as exc:
        print(f"apply-theme.py: could not retire {stale_skin}: {exc}", file=sys.stderr)

# The SDDM theme is QML and nothing else now: the greeter draws the unlock card
# from its generated Appearance, so there is no raster artwork left to recolour
# and no second palette to keep in step through a script.

# The Neovim config is a separate repository (joscarranzs/neovim-config), not a
# submodule: clone it on its own. The theme generator only writes `theme.lua`
# when that directory already exists.

print(f"Wrote {hypr_color_out}")
print(f"Wrote {hypr_look_out}")
print(f"Wrote {hypr_anim_out}")
print(f"Wrote {gtk3_out}")
print(f"Wrote {gtk4_out}")
print(f"Wrote {gtk3_css_out}")
print(f"Wrote {gtk4_css_out}")
print(f"Wrote {kitty_theme_out}")
print(f"Wrote {kitty_main_out}")
print(f"Wrote {fontconfig_out}")
print(f"Wrote {lock_appearance_out}")
print(f"Wrote {launcher_appearance_out}")
print(f"Wrote {lock_materialicon_out}")
print(f"Wrote {launcher_materialicon_out}")
print(f"Wrote {wallpaper_appearance_out}")
print(f"Wrote {calendar_appearance_out}")
print(f"Wrote {volume_appearance_out}")
print(f"Wrote {brightness_appearance_out}")
print(f"Wrote {wifi_appearance_out}")
print(f"Wrote {battery_appearance_out}")
print(f"Wrote {monitor_appearance_out}")
for _legend_panel in LEGEND_PANELS:
    print(f"Wrote {Path.home() / '.config' / 'quickshell' / _legend_panel / 'components' / 'LegendRow.qml'}")
for _card_panel in CARD_PANELS:
    for _card_name in ("PanelCard", "StatusChip", "UsageBar"):
        print(f"Wrote {Path.home() / '.config' / 'quickshell' / _card_panel / 'components' / (_card_name + '.qml')}")
print(f"Wrote {herdr_theme_out}")
print(f"Wrote {yazi_theme_out}")
print(f"Wrote {starship_out}")
print(f"Wrote {sddm_out}")
print(f"Wrote {hermes_skin_out}")


def apply_desktop_color_scheme() -> None:
    """Put the desktop-wide appearance keys on the palette too.

    GTK4/libadwaita ignores `gtk-theme-name` in settings.ini and asks the
    desktop for its colour scheme instead — and so does the XDG desktop portal,
    which is what Chromium, Firefox, Electron and every libadwaita app follow.
    A `prefer-dark` key left behind by an earlier dark palette therefore keeps
    those apps dark no matter what the compositor, kitty or the Quickshell
    surfaces do, and `--force-dark-mode` in a browser flags file is not the only
    place the dark can come from.

    The values are read from theme/look.json so the theme owns the system
    appearance instead of a second place to hand-edit, and the write is verified
    by reading the key back: a silent gsettings failure is how this drifted in
    the first place. This used to be gated to a GNOME session, which never ran
    here (the session is Hyprland) while the portal keys stayed dark.
    """
    if shutil.which("gsettings") is None:
        return

    scheme = "prefer-dark" if look_data["gtk"].get("preferDark") else "prefer-light"
    wanted = {
        "color-scheme": scheme,
        "gtk-theme": look_data["gtk"]["theme"],
        "icon-theme": look_data["gtk"]["iconTheme"],
        # Terminal and code: the same mono the theme generates for kitty, so an app
        # that asks GNOME for its monospace face gets this family at the weight the
        # fontconfig rule for that family. It was left on a previous family by hand,
        # which is the same drift as a hand-written Appearance.
        "monospace-font-name": f"{typo_data['fonts']['mono']} {typo_data['sizes']['terminal']}",
    }

    for key, value in wanted.items():
        subprocess.run(
            ["gsettings", "set", "org.gnome.desktop.interface", key, value],
            check=False,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )

    # No UI face is pinned here. font-name and document-font-name are reset so every
    # toolkit keeps its own default (Adwaita Sans 11 and 12 on this install) instead of
    # the hand-set 'Space Grotesk 10' that outlived the family: a GTK or Electron app
    # was still drawing its chrome in a face the theme had already dropped. There is no
    # read-back assertion for these two -- the point is that no value of ours is there.
    for key in ("font-name", "document-font-name"):
        subprocess.run(
            ["gsettings", "reset", "org.gnome.desktop.interface", key],
            check=False,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )

    # Read back. No session bus (a TTY, a build box) is a skip, not a failure;
    # a key that refuses to take is worth a line on stderr.
    for key, value in wanted.items():
        result = subprocess.run(
            ["gsettings", "get", "org.gnome.desktop.interface", key],
            check=False,
            capture_output=True,
            text=True,
        )
        if result.returncode != 0:
            print("apply-theme.py: gsettings not reachable (no session bus): "
                  "GTK/portal appearance left untouched", file=sys.stderr)
            return
        if result.stdout.strip().strip("'") != value:
            print(f"apply-theme.py: org.gnome.desktop.interface {key} is "
                  f"{result.stdout.strip()}, expected '{value}'", file=sys.stderr)


apply_desktop_color_scheme()
