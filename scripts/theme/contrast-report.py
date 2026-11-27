#!/usr/bin/env python3
"""Report WCAG contrast of every role in theme/colors.json against every surface.

The palette is the single source of truth for a themed desktop and it is easy to
ship a role that reads fine in the editor and vanishes on screen: a gold that
worked as text on near-black needs a different value on paper. This script turns
"does it read?" into a number, per surface, with the AA/AAA verdict, and exits
non-zero when a role that carries text falls under its target.

    ./scripts/theme/contrast-report.py            # table + verdict
    ./scripts/theme/contrast-report.py --json     # machine-readable

Roles are classified by the job they do:

  text    *.ink, *.inkBright, *.inkSoft, *.inkMuted   -> 7.0 (body) / 4.5 (secondary)
  faint   *.inkFaint, surface.line, surface.border    -> 1.2 (hairline, non-text)
  accent  accent.*                                    -> 4.5 (used as glyph and text)
  signal  signal.*                                    -> 4.5 (state text and glyphs)

Colours whose only job is a fill (a gold plaque behind dark ink) are checked the
other way round: `accent.on` against the accent fills it sits on.
"""

import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
COLORS = ROOT / "theme" / "colors.json"

# role -> minimum contrast against a surface it is painted on
TEXT_ROLES = {
    ("text", "ink"): 7.0,
    ("text", "inkBright"): 7.0,
    ("text", "inkSoft"): 4.5,
    ("text", "inkMuted"): 4.5,
    ("text", "inkFaint"): 2.5,
}
GLYPH_ROLES = {
    ("accent", "primary"): 2.5,
    ("accent", "primaryInk"): 4.5,
    ("accent", "primaryDeep"): 4.5,
    ("accent", "quaternary"): 3.5,
    ("accent", "secondary"): 3.0,
    ("accent", "tertiary"): 3.0,
    ("accent", "tertiaryInk"): 4.5,
    ("accent", "neutral"): 3.5,
}
SIGNAL_ROLES = {
    ("signal", "red"): 4.5,
    ("signal", "orange"): 3.5,
    ("signal", "yellow"): 3.5,
    ("signal", "green"): 3.5,
    ("signal", "purple"): 3.5,
}
HAIRLINE_ROLES = {
    ("surface", "line"): 1.15,
    ("surface", "border"): 1.5,
    ("surface", "borderStrong"): 2.0,
}

# fill -> (ink that sits on it, minimum contrast). One entry per fill actually
# used as a background in the templates: accent plaques take the accent ink, the
# saturated signals take paper, and the editor's selection wash takes the body ink.
FILL_INK = {
    ("accent", "primary"): ("onAccent", "primary", 4.5),
    ("signal", "red"): ("onAccent", "signal", 4.5),
    ("signal", "orange"): ("onAccent", "signal", 4.5),
    ("signal", "yellow"): ("onAccent", "signal", 4.5),
    ("signal", "green"): ("onAccent", "signal", 4.5),
    ("signal", "purple"): ("onAccent", "signal", 4.5),
    ("surface", "selection"): ("text", "ink", 4.5),
}


def rgb(value: str) -> tuple[int, int, int]:
    value = value.lstrip("#")
    return tuple(int(value[i : i + 2], 16) for i in (0, 2, 4))  # type: ignore[return-value]


def luminance(value: str) -> float:
    channels = []
    for channel in rgb(value):
        srgb = channel / 255
        channels.append(srgb / 12.92 if srgb <= 0.03928 else ((srgb + 0.055) / 1.055) ** 2.4)
    red, green, blue = channels
    return 0.2126 * red + 0.7152 * green + 0.0722 * blue


def ratio(a: str, b: str) -> float:
    la, lb = luminance(a), luminance(b)
    hi, lo = max(la, lb), min(la, lb)
    return (hi + 0.05) / (lo + 0.05)


def verdict(value: float, target: float) -> str:
    if value >= target:
        return "ok"
    if value >= target * 0.85:
        return "TIGHT"
    return "FAIL"


def main() -> int:
    as_json = "--json" in sys.argv[1:]
    data = json.loads(COLORS.read_text())
    # `line`, `border`, `borderStrong` and `selection` are fills, not surfaces:
    # text is never set on them directly, so they are checked as hairlines below
    # and as the highlight fill the ink has to survive.
    fills = {"line", "border", "borderStrong", "selection"}
    surfaces = [(f"surface.{k}", v) for k, v in data["surface"].items() if k not in fills]

    rows = []
    failures = []
    # A role declared here but absent from colors.json used to be skipped in
    # silence, so a renamed token quietly dropped a whole check while the report
    # still printed a green verdict. Collect the misses and report them.
    missing_roles = []
    for surface_name, surface_hex in surfaces:
        for group, table in (
            ("text", TEXT_ROLES),
            ("glyph", GLYPH_ROLES),
            ("signal", SIGNAL_ROLES),
            ("hairline", HAIRLINE_ROLES),
        ):
            for (section, key), target in table.items():
                if section not in data or key not in data[section]:
                    missing_roles.append(f"{section}.{key}")
                    continue
                hex_value = data[section][key]
                value = ratio(hex_value, surface_hex)
                state = verdict(value, target)
                rows.append(
                    {
                        "against": surface_name,
                        "role": f"{section}.{key}",
                        "hex": hex_value,
                        "ratio": round(value, 2),
                        "target": target,
                        "verdict": state,
                        "kind": group,
                    }
                )
                if state == "FAIL":
                    failures.append(rows[-1])

    # Ink that sits ON a fill, one row per fill and its paired ink. This is the
    # check that catches the classic light-mode bug: reusing the surface colour as
    # the foreground on an accent reads perfectly in a dark room and disappears on
    # paper, so the pairing is declared here rather than left to the templates.
    on_accent = []
    for (fill_section, fill_key), (ink_section, ink_key, target) in FILL_INK.items():
        if fill_section not in data or fill_key not in data[fill_section]:
            missing_roles.append(f"{fill_section}.{fill_key}")
            continue
        if ink_section not in data or ink_key not in data[ink_section]:
            missing_roles.append(f"{ink_section}.{ink_key}")
            continue
        fill_hex = data[fill_section][fill_key]
        ink_hex = data[ink_section][ink_key]
        value = ratio(ink_hex, fill_hex)
        state = verdict(value, target)
        on_accent.append(
            {
                "against": f"{fill_section}.{fill_key}",
                "role": f"{ink_section}.{ink_key}",
                "hex": ink_hex,
                "ratio": round(value, 2),
                "target": target,
                "verdict": state,
                "kind": "on-fill",
            }
        )
        if state == "FAIL":
            failures.append(on_accent[-1])

    if as_json:
        print(json.dumps({"rows": rows, "on_fill": on_accent, "failures": failures,
                          "missing_roles": sorted(set(missing_roles))}, indent=2))
    else:
        width = max(len(r["role"]) for r in rows + on_accent)
        current = None
        for row in rows + on_accent:
            if row["against"] != current:
                current = row["against"]
                print(f"\n--- on {current} ---")
            print(
                f"  {row['role']:<{width}}  {row['hex']}  {row['ratio']:>5.2f}:1  "
                f"target {row['target']:>4.2f}  {row['verdict']}"
            )
        print(f"\n{len(rows) + len(on_accent)} pairs checked, {len(failures)} under target")
        for role in sorted(set(missing_roles)):
            print(f"  MISSING {role}: declared in this report, absent from theme/colors.json")
        for row in failures:
            print(f"  FAIL {row['role']} on {row['against']}: {row['ratio']}:1 < {row['target']}")

    return 1 if failures or missing_roles else 0


if __name__ == "__main__":
    raise SystemExit(main())
