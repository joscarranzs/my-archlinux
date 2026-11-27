# Design system — the light room, in paper

The desktop's visual language, as it stands after the move from a warm gallery
("barro": laid paper, gold leaf, terracotta) to Catppuccin Latte, then to the dark
`warm-charcoal` room, and now to `warm-paper`: the same room as warm-charcoal,
lit from above.

> **Colour: read `theme/colors.json`, not §2.** §2 below records the Latte pass
> and is kept for the reasoning (which hues may carry text, and why). The live
> palette is `warm-paper` — light surfaces (`surface.base #efecef`), ink
> `#2a2222`, emerald accent `#007952` — and `scripts/theme/contrast-report.py`
> checks 91 pairs against it. §2b records how that palette was derived from
> `warm-charcoal` and what the numbers cost. Everything in §3, §5 and §6 still
> holds as written.
> A redesign is in progress (cabinet of curiosities): direction in §10 and
> `docs/redesign-2026-11-23.md`.

This file is the reference for every visual change. Every number in it is either
a token in `theme/*.json` or a measurement taken from the running desktop with
`scripts/theme/contrast-report.py`.

## 1. The pipeline: one source, generated outputs

```
theme/colors.json      palette roles        ─┐
theme/look.json        geometry, opacity     ├─► scripts/theme/apply-theme.py ─► every themed file
theme/typography.json  fonts, sizes, tracking┘
```

`apply-theme.py` renders `scripts/theme/templates/**` into the live configs
(Hyprland, kitty, GTK, Yazi, herdr, starship, SDDM, and one `Appearance.qml` per
Quickshell surface). Two consequences that decide where a change belongs:

- **A colour or metric is changed in the JSON, never in an output.** The next
  generator run overwrites the output.
- **The generator fails fast**: every `{{key}}` in every template must resolve
  before a single file is written, so a renamed token aborts the run instead of
  half-writing the desktop.

Generated outputs (38 files): `~/.config/{hypr/theme.lua,hypr/look.lua,
hypr/animations.lua,gtk-3.0/{settings.ini,gtk.css},gtk-4.0/{settings.ini,gtk.css},
kitty/{kitty.conf,theme.conf},fontconfig/fonts.conf,starship.toml,
yazi/theme.toml,sddm/arch/Main.qml,quickshell/*/Appearance.qml,quickshell/*/
components/MaterialIcon.qml}` plus `herdr-app/themes/<palette>.json` in both
`~/.config/herdr-app/` (the app owns that directory) and the tracked mirror
`config/herdr-app/themes/`. The herdr file is named after `palette.name` and
`config/herdr-app/settings.json` must point at that name; the previous palette's
file is unlinked by the generator so a retired colour set cannot be selected.

`config/nvim/theme.lua` is **not** generated: it lives in the separate
neovim-config repository and is hand-owned, because an editor needs syntax hues
the shell does not (see §2, "The editor is separate").

## 2. Palette

Upstream Catppuccin Latte (`catppuccin/palette` v1.8.0, `catppuccin/kitty`
`latte.conf`). Contrast is measured against `surface.base` (`#eff1f5`), against
`surface.raised` (`#e6e9ef`) for objects on the page, and against the fill for
anything painted *on* a fill. Targets: body ink 7.0, secondary ink 4.5, glyph
accents 2.5–4.5 by job, hairlines 1.15/1.5/2.0.

| token | hex | job | contrast on base / raised |
|---|---|---|---|
| `surface.base` | `#eff1f5` | the page: bar, panel body (Latte `base`) | — |
| `surface.raised` | `#e6e9ef` | panel surface, raised object (`mantle`) | — |
| `surface.raisedHigh` | `#dce0e8` | the object that must differ from the panel, hover (`crust`) | — |
| `surface.line` | `#ccd0da` | interior hairline (`surface0`) | 1.37 / 1.27 : 1 (a line, not text) |
| `surface.border` | `#acb0be` | visible edge: inactive window border, editor splits (`surface2`) | 1.91 / 1.78 : 1 |
| `surface.borderStrong` | `#8c8fa1` | window separator (`overlay1`) | 2.83 / 2.63 : 1 |
| `surface.selection` | `#bcc0cc` | selection wash (`surface1`) | ink on it 5.16 : 1 |
| `surface.cursorline` | `#e6e9ef` | current line (`mantle`) | — |
| `text.ink` | `#42455c` | primary text, clock | 8.30 / 7.72 : 1 |
| `text.inkBright` | `#383b52` | highest-contrast ink (panel headlines, the bar clock) | 9.69 / 9.01 : 1 |
| `text.inkSoft` | `#5c5f77` | secondary text, labels, glyphs (`subtext1`) | 5.53 / 5.14 : 1 |
| `text.inkMuted` | `#606276` | tertiary text | 5.30 / 4.92 : 1 |
| `text.inkFaint` | `#7c7f93` | quiet marks: unlit bars, inactive dots, comments (`overlay2`) | 3.49 / 3.25 : 1 |
| `accent.primary` | `#8839ef` | **fills and strokes only**: plaque edge, window border, slider fill, state layer (`mauve`) | 4.79 / 4.45 : 1 |
| `accent.primaryInk` | `#7f35df` | **accent used as ink**: text and glyphs | 5.34 / 4.97 : 1 |
| `accent.primaryDeep` | `#6b21d4` | pressed accent, strong emphasis | 6.65 / 6.18 : 1 |
| `accent.secondary` | `#168d94` | teal: staged files, node (`teal`) | 3.52 / 3.28 : 1 |
| `accent.tertiary` | `#3a9127` | green: secondary accent (`green`) | 3.53 / 3.28 : 1 |
| `accent.neutral` | `#1e66f5` | blue: diverged-branch marks, ANSI 4 (`blue`) | 4.34 / 4.04 : 1 |
| `accent.quaternary` | `#a16558` | rosewater, declared but unused (`rosewater`) | 4.11 / 3.82 : 1 |
| `signal.red` | `#c60e36` | error, critical, destructive | 5.28 / 4.91 : 1 |
| `signal.orange` / `yellow` / `green` / `purple` | `#aa4307` / `#8a5812` / `#2d711e` / `#924a7f` | warning, pending, ok, special | 5.28 / 5.33 / 5.32 / 5.29 : 1 |
| `onAccent.primary` | `#eff1f5` | ink that sits **on** an accent fill | 4.79 : 1 on the accent |
| `onAccent.signal` | `#eff1f5` | ink that sits **on** a red/green/yellow fill | 5.28–5.33 : 1 on the signals |
| `ansi.*` (16 slots) | upstream Latte | **kitty and herdr ANSI 0–15 only** | not text roles |

**Why some hues are darker than upstream.** Latte's pastels are designed as
*fills under dark ink*, not as text on paper. Measured on `#eff1f5`, upstream
`peach` is 2.64 : 1, `yellow` 2.31 : 1, `pink` 2.34 : 1 — a warning that has to be
read as text disappears. So every role in `accent.*` and `signal.*` keeps its
upstream hue and walks toward black until it clears its target; surfaces, the inks
and `ansi.*` stay exactly upstream. The accent is `mauve`, Catppuccin's own
signature accent, and it is the one hue that passes unchanged (4.79 : 1 as a
fill, which is also why `onAccent.primary` can be the base colour).

**Why the split.** Two jobs, two tokens, same reason as before: `accent.primary`
is a pigment and `accent.primaryInk` is the same hue as ink (5.34 vs 4.79 : 1 —
the fill tone does not clear 4.5:1 on paper). `onAccent.*` is a declared role so
the report checks the ink that sits *on* a fill instead of leaving it to each
template.

**Why `ansi.*` exists.** A terminal that calls itself Catppuccin has to answer
`ls --color` with the colours the flavour is famous for, and those are exactly the
values that fail as UI text. One source, two intents: `signal.*` is the darkened,
text-safe version; `ansi.*` is the upstream 16 for kitty and herdr, including the
odd upstream choice of a *lighter* `brightWhite` (`#bcc0cc`) than `white`
(`#acb0be`).

## 2b. `warm-paper`: the same palette, lit from above

Every hue and saturation in `theme/colors.json` is the one `warm-charcoal` had;
only lightness moved, mirrored around the mid tone and then searched along that
axis until the role cleared the target `contrast-report.py` declares for it. Two
rules did most of the work:

- **Fills get deep, and the ink on them is the page.** A pigment on paper must
  read as a mark *and* carry 4.5:1 under its own label. Both pull toward dark, so
  the fills land in a narrow band and `onAccent.*` is `surface.base` — exactly
  the relation the dark palette had, where `onAccent.primary` was `#292329`.
- **A pastel mirrored down loses its chroma.** The signal hues are near-pastel
  (`#d9aeab`, `#ecd6d5`); mirrored straight to a dark lightness they came out
  brown-black and stopped identifying anything. Saturation is scaled up as the
  lightness drops (×1.45 for `accent.*`, ×1.9 for `signal.*`) so the deep steps
  keep the hue they are named after.

| token | hex | on `surface.base` (`#efecef`) |
|---|---|---|
| `surface.base` / `raised` / `raisedHigh` | `#efecef` / `#e8e5e8` / `#dfdadf` | the paper and its two rungs |
| `surface.line` / `border` / `borderStrong` | `#cfc9cf` / `#ada4ad` / `#958895` | 1.39 / 2.06 / 2.87 : 1 (hairlines) |
| `text.ink` / `inkBright` | `#2a2222` / `#140c0c` | 13.27 / 16.47 : 1 |
| `text.inkSoft` / `inkMuted` / `inkFaint` | `#3e3535` / `#584b4b` / `#897689` | 10.15 / 7.10 / 3.57 : 1 |
| `accent.primary` / `primaryInk` / `primaryDeep` | `#007952` / `#123623` / `#1a5135` | 4.64 / 11.36 / 7.88 : 1 |
| `accent.secondary` / `tertiary` / `tertiaryInk` / `neutral` / `quaternary` | `#40685e` / `#997900` / `#826700` / `#41736b` / `#732a26` | 5.33 / 3.52 / 4.61 / 4.61 / 8.58 : 1 |
| `signal.red` / `orange` / `yellow` / `green` / `purple` | `#d01b31` / `#503d0c` / `#82661a` / `#0f5c35` / `#340b09` | 4.61 / 8.90 / 4.64 / 6.88 / 14.96 : 1 |
| `onAccent.primary` / `signal` | `#efecef` | 4.64 on the accent, 4.61–14.96 on the signals |

`ansi.*` follows the light-terminal convention instead of the mirror: 0 and 8 stay
dark, 1–6 and 9–14 darken until they clear 3.2:1 on the paper, and 7/15 become the
two lightest rungs (a light theme's "white" is a grey, as upstream Latte does).

The bar carries no frame and no hairline, by decision: flush with the screen edge
it is `surface.base` on the paper wallpaper (`#f2eeef`), 1.02:1, and the strip is
meant to dissolve into the top of the screen rather than be outlined onto it.
Anything that needs to read *in* the bar takes a step of ink.

## 2c. The hues come back: a fill sits on its floor, not above it

The mirror cleared every gate and left three roles reading as mud: emerald
`#226844`, gold `#7d6729`, red `#691711`. Each was the right hue in the wrong
place — a hue kept dark enough to carry 4.5:1 under its own label also loses the
chroma that names it, and a red at OKLCH lightness 0.35 reads as brick whatever
its saturation.

The fix is not more contrast; it is no *surplus* contrast. Per role: the hue
angle comes from `warm-charcoal` (that is the identity), the lightness rises
until the ratio lands on the role's declared target — not the target plus a
margin, not the ratio it happened to have — and the chroma is the most that hue
holds inside sRGB at that lightness. The walk is upward, toward the paper, so
nothing needs the saturation compensation the downward mirror needed.

| role | was | now | on `surface.base` | target | OKLCH L / C |
|---|---|---|---|---|---|
| `accent.primary` | `#226844` | `#007952` | 5.72 → 4.64 : 1 | 4.5 | .463/.091 → .509/.111 |
| `accent.tertiary` (gilt) | `#7d6729` | `#997900` | 4.66 → 3.52 : 1 | 3.0 | .522/.085 → .590/.121 |
| `signal.red` | `#691711` | `#d01b31` | 10.35 → 4.61 : 1 | 4.5 | .346/.116 → .550/.209 |

Hue lands on the source angle within half a degree in all three: 162.2 / 90.1 /
22.9 against 162.0 / 90.5 / 22.9.

The red is the loudest move because its surplus was the largest: `#691711` sat at
**10.35:1**, more than twice what the role asks for, and that surplus is what
turned it brown. At its floor it lands on Catppuccin Latte's own red (`#d20f39`:
4.63:1 on this paper, L .550, C .216) — same lightness and chroma band, three
degrees cooler because `warm-charcoal`'s salmon is. `accent.primary` gains the
least chroma (the mint gamut is narrow at L .51) and gains the lightness that
turns pine into emerald.

**Gold is a stroke, so it has two roles.** `accent.tertiary` is the ornament
tone — plaque edges, header rules — and its target is 3.0:1, which is what lets
the gold be gold at 3.52. Gold *text* cannot use it: 11 px at 3.52:1 is under AA.
So the split the accent already had (`accent.primary` / `accent.primaryInk`) is
the gilt's too: `accent.tertiaryInk` `#826700` carries the same hue at 4.61:1 and
reaches QML as `giltInk` in every generated Appearance, required by
`check_gilt_role` and checked at 4.5 in `contrast-report.py`. One consumer today:
the monitor's RESET countdown. The month header keeps the ornament tone on its
rule and draws its title in `text`, which is what it always did.

`signal.yellow` `#82661a` was left alone on purpose: it is a fill as well as a
glyph, so its floor is 4.5 and at 4.64 it already sits on it — there is no
surplus to spend. The pass as a whole: `91 pairs checked, 0 under target`.

## 3. Ink hierarchy: roles, never opacity

**Rule: text and glyphs take their contrast from an ink role, not from an
opacity multiplier. `opacity` is for surfaces, frames, scrims and state layers.**

Measured on this palette, ink dimmed by opacity loses more than it gains — a
light base washes it out faster than near-black did:

| recipe | on `surface.base` |
|---|---|
| ink @ 1.0 | 8.30 : 1 |
| inkSoft @ 0.8 (muted) | 3.63 : 1 |
| inkSoft @ 0.7 (dim) | 2.99 : 1 |
| ink @ 0.55 (disabled) | 2.72 : 1 |
| ink @ 0.32 (faint) | **1.71 : 1 — illegible** |

So `opacityFaint` stays gone from anything meant to be read: an inactive workspace
dot, an unlit signal bar or an out-of-month day is `text.inkFaint` at full
strength (3.49 : 1) instead of ink at 32 % (1.71 : 1), and the difference between
states is a *step of ink* — accent fill, `textMuted`, `textFaint` — not a step of
transparency. `opacityDisabled` survives only where it dims a whole composite
control (a disabled button with its own frame and label).

## 4. Typography

| voice | family | where |
|---|---|---|
| ui | JetBrainsMono Nerd Font | every string this desktop draws: titles, clocks, labels, data, body, buttons, status lines |
| icons | Material Symbols Rounded | every glyph (wght 600, GRAD 0, opsz 24, FILL 0) |
| terminal | JetBrainsMono Nerd Font | kitty, the desktop terminal pane, herdr's editor — the same family, ligatures on |

One UI face, at weight 600: `theme/typography.json` holds `ui`, `mono` and `icons`
and nothing else. `textFont` and `displayFont` survive as *roles* in every
`Appearance.qml` but all three resolve to `JetBrainsMono Nerd Font`, so a surface
that asks for "the display face" gets the same family with a different size — the
hierarchy is carried by size, tracking and ink, not by swapping typefaces.

What left, and why: Fraunces (the display serif) was 11 elements — the two
clocks, month headers, panel headlines — and it made every panel speak in two
accents at once; EB Garamond was declared as a prose voice and rendered nothing;
and the `jp` token (Noto Sans JP) only existed to sit behind the `sans-serif`
alias, which is gone. Those tokens are gone, and so are the files: the retired
families were deleted from `~/.local/share/fonts`, which is empty now, and every
family the theme draws with comes from pacman. The desktop and the terminal are
one family now — a different medium, not a different face — so a panel that
reaches for a second one is drift, and `check_font_roles` is what keeps a family
from being declared and never drawn.

### How 600 reaches an app that is not QML

The family is static and ships a real SemiBold, so there is nothing to cut out of a
variable font and nothing to fake: `font.weight: 600` in QML resolves against the
family's own instances, and fontconfig serves the same face to any toolkit that
asks through it. Proof from the running process, not from the config: the bar has
`/usr/share/fonts/TTF/JetBrainsMonoNerdFont-SemiBold.ttf` mapped and no Space
Grotesk at all.

`fontVariableAxesUi` and `fontVariableAxesDisplay` stay in every `Appearance.qml`
because 51 call sites assign them to `font.variableAxes`, but they emit an empty
map: a static family has no `wght` axis for HarfBuzz to apply. The icon face keeps
its axes (FILL, wght, GRAD, opsz) because Material Symbols Rounded *is* variable.

One rule survives in `fontconfig.conf`: a request for the terminal family that
carries a weight under semibold is raised to 600, so kitty — which asks at weight
normal — does not render at 400 while the panels render at 600. It only matches a
pattern that has a weight, so a bare `fc-match FAMILY` still prints the 400 face.
`apply-theme.py` verifies the 600 face with `fc-match` and warns when a family has
none: that check replaced `scripts/theme/static-instance.py`, deleted along with
the variable UI font it existed for.

### The scale

One ladder, declared in `theme/typography.json` and rendered into every
`Appearance.qml` by `scripts/theme/apply-theme.py`. A surface asks for a role;
it never asks for a size, and no QML file may contain `font.pixelSize: <number>`
— the generator refuses to write the theme if one does.

| step | px | role |
|---|---|---|
| `micro` | 10 | the bar's own labels, where 28 px of height is the budget |
| `small` | 11 | eyebrows (`OUTPUT`, `WIFI`), column headers, keycaps, hints |
| `caption` | 12 | metadata under a value: device name, security, reset countdown |
| `body` | 14 | the content itself: list rows, inputs, card titles, day numbers |
| `title` | 17 | one panel headline, in the UI face at 600 |
| `display` | 26 | the single number a plaque exists to show (`20%`, `98%`) |

Ratios: 11 → 12 → 14 → 17 → 26. `small` and `caption` are one pixel apart on
purpose: the eyebrow carries 1.4 tracking and the caption 0.6, so the tracked
label reads larger than the untracked one at the same size — optical, not
geometric. `display` is the one deliberate jump: a plaque has exactly one hero
number, and it has to beat the body text without a second colour.

Two sizes stay outside the ladder because they belong to another surface, not
to a panel: `clock` (84, the lock-screen time) and `sddm` (24, the greeter).
`terminal` (10) sizes kitty. `editor` is not a token: the Neovim theme lives in
its own repository.

What the ladder replaced: per-panel names (`levelFontSize`, `batteryLevelFontSize`,
`searchIconSize`, `fontSizeClock`, `fontSizeLabel`, `fontSizeButton`) and two
arithmetic one-offs (`fontSizeTitle + 6` for a balance, `fontSizeCaption + 2` for
a glyph). Those were how two surfaces reading the same JSON ended up disagreeing.
The check lives in `apply-theme.py` (`check_type_scale`, `check_no_hardcoded_type`).

## 5. Space, shape, ornament

- Spacing is one 4-based scale (4, 8, 12, 16, 24, 32) named `xs`…`xxl`, plus
  `tight` (6) for the inside of a card, where 8 read as a gap between blocks.
- **One catalogue of control heights**, in `look.controls`, and it is a
  catalogue, not one number: a 56 px password field on the lock screen and a
  32 px secondary field in a form are both correct. What is not allowed is a
  panel inventing its own value. Current roles:

  | role | px | where |
  |---|---|---|
  | `fieldHeightCompact` | 32 | secondary field in a dense form |
  | `fieldHeightDense` | 34 | monitor and wifi rows |
  | `fieldHeight` | 36 | the default text field |
  | `fieldHeightHero` | 52 | the launcher search field, the webapp name |
  | `fieldHeightTall` | 56 | the lock screen, at 400 px wide |
  | `buttonHeight` | 32 | default button |
  | `buttonHeightDense` | 34 | monitor actions |
  | `buttonHeightLarge` | 48 | a primary CTA that spans its card |
  | `rowHeight` / `rowHeightTall` | 46 / 48 | list rows, with and without a preview tile |
  | `cardHeight` | 44 | a single-line card |
  | `iconButtonSize` | 32 | a square glyph button |
  | `chipHeight` | 28 | badge, chip, delete badge |
  | `keycapHeight` | 18 | a key in the legend |
  | `dotSize` | 6 | status pip |
  | `contentPad` / `contentPadTight` | 24 / 20 | panel body; the lock card sits closer |
  | `headerHeight` / `headerHeightTall` | 30 / 32 | panel header |
  | `footerHeight` / `footerHeightTall` | 22 / 28 | key hints; the launcher's footer is a legend |
  | `ruleWidth` / `ruleThickness` | 32 / 1 | the accent rule in every header |
  | `cursorWidth` / `cursorHeight` | 10 / 20 | block caret |
  | `zBadge`…`zModal` | 2 / 20 / 99 / 100 | stacking ladder, named |

  `spacingMedium` in the launcher meant 16 until this pass; it now reads
  `spacingLarge`, which is the same pixel and the same name as everywhere else.
- Radii: `none 0 · xs 2 · sm 4 · md 6 · lg 8 · xl 12 · full 9999`, live in
  `theme/look.json`. The previous pass held every step flat at 5; the redesign
  unflattens it into a deliberate architectural ladder — outer plaques 12,
  cards 6, rows 4 — sharp enough to read as a framed plaque, far from the
  soft-bubble ceiling. See §10.
- One hairline width (`1`), one border per plaque. A plaque's own edge is
  `gilt` (gold, `accent.tertiary`) — the object's frame; interior separators are
  `outline`; a *visible* edge (inactive window, editor split) is `surface.border`.
  `gilt` is a stroke; gold that is drawn as text takes `giltInk`
  (`accent.tertiaryInk`), the same hue at 4.5:1 — see §2c.
  The Hyprland window border stays `accent` (mint): windows signal focus, plaques
  signal ornament. No second inset frame anywhere.
- The bar is the one surface whose shape follows its distance from the display
  edge (`look.bar.inset`). At an inset it is a plaque: radius `md` and the accent
  frame on four sides. At `0` it is a strip: square corners and a single accent
  rule along its content edge, because left, right and bottom would land on the
  screen boundary and enclose nothing. The window gap from the edge is its own
  number, `look.margins.edge` — the bar does not set it.
- Ornament is one gilt rule per header (32 × 1), the gilt plaque edge and the gilt
  hairline the hover ignites; one mint accent action per surface. Nothing
  else: the elegance has to come from proportion and rhythm, not from added
  decoration.
- **A brand mark on a light tile is ink, not white.** Third-party marks ship as
  white artwork because they were drawn for a near-black plate; on the paper tile
  (`surfaceContainerHigh`) that artwork *is* the tile colour. Both marks in the
  token panel measured as gone — `nous.png` 100 % `#ffffff`, the OpenCode frame
  78 % — so each now carries `text.ink` and keeps its geometry and its alpha
  mask. `scripts/icon-contrast.py --background light` is the check: it counts
  "real white" pixels the way the dark direction counts "real black" ones, and it
  is what caught this after every dark-surface check had passed.
- **One legend recipe: a key is drawn as a cap.** `components/LegendRow.qml` is
  generated into every plaque that shows keys — the key in a bordered cap
  (`keycapHeight` 18, radius `shapeSmall`, `outline` at `hairline`) and its label
  beside it in the annotation voice, uppercase and tracked — and entries sit
  `spacingMedium` apart. Seven footers used to spell their hints out as one flat
  string with a hand-made separator, and the only real cap on the desktop lived
  in the kanban. `check_no_flat_hints` refuses a QML string that carries two or
  more key signs; `check_legend_roles` keeps the caps reading `Appearance`.
  The wifi footer carries three entries rather than four: `↑↓ SELECT · ↵ CONNECT ·
  Esc CLOSE` measure 254 px against its 312 px of footer, and adding `R RESCAN`
  makes 336, which would have to elide. `R` still rescans; it is simply not
  advertised by a footer that cannot hold it.
- **The legend band owns the plaque's bottom padding.** The band runs from its
  rule to the plaque's inner bottom edge (`footerHeight + contentPad −
  borderWidth`, pulled down with a negative `Layout.bottomMargin`) and the legend
  centres inside it, horizontally centred in the plaque. Pinned to the content
  margin it sat glued to the rule with a pocket of dead space under it — measured
  on the volume plaque, 4 px above and 24 px below, against 13/13 now.
- **A separator has to separate two different things.** One hairline earns its
  place when it divides a region from a list or a modal (the wifi current-link
  block from the scan list, the kanban board from its creator). It does not when
  it divides two stacked blocks that already carry their own eyebrow label, which
  is what the token panel had five of and the battery panel two. `outline` at
  `hairline`, never `gilt`: the gold is the header rule and the plaque's edge.
- **Enforcement:** `apply-theme.py` refuses to write if a panel Appearance stops
  reading `look.controls`, or if any QML file contains a bare pixel measure
  (`check_metric_roles`, `check_no_hardcoded_geometry`). Only `0`, `1` and
  expressions that divide a width or a height are allowed, because those are
  relations rather than measures. The icon ladder is gated the same way
  (`check_icon_scale`): six steps — `iconSizeXs 16 · Sm 18 · Md 22 · Lg 28 ·
  Xl 40 · Tile 48` — every Appearance carries all six, and a panel picks a rung
  instead of a number. `iconSizeTile` is the app-tile rung; binding an icon to
  `iconSizeXs` inside a 104 px tile is how the launcher shipped a 16 % icon.
  Text is never dimmed with opacity, and that rule is gated rather than trusted
  (`check_no_text_opacity`): the caption ink is composited over the lightest
  surface in the palette at whatever alpha the role asks for, and the result has
  to clear 4.5:1. The numbers come from `theme/`, so the verdict moves with the
  palette: `disabled` at 0.55 reads 3.18:1 and `dim` at 0.7 reads 4.17:1 and are
  refused on a `Text`, while `placeholder` at 0.75 reads 4.54:1 and passes.
  A `0`/`1` ternary is allowed — that is visibility, not dimming. The lock
  surface is checked by the same material and motion gates as the plaques now;
  it used to sit outside both, which is how its only button shipped with no
  hover and nothing failed.

## 6. Interaction

- Motion is four numbers from `animations.json`, all generated into every
  `Appearance.qml`: `motionControlDuration` (110, hover and controls),
  `motionPressDuration` (80, press), `motionEntranceDuration` (200, the plaque
  entrance) and `motionEntranceOffset` (8, the distance that entrance travels).
  Nothing else moves: no scale, no layout animation. The workspace
  pill keeps its own morph (`motionWorkspaceDuration`).
- **The entrance is a fade and a lift, one gesture.** The plaque starts
  transparent and 8 px low, and lands on its anchor over 200 ms, decelerating.
  The offset rides a `Translate` transform, never `y`: every plaque is anchored
  (`anchors.centerIn`) by its shell, and a translate moves the paint without
  fighting the anchor. Both halves are one token pair, and
  `check_entrance_lift` refuses to write when a QML file animates the entrance
  duration without carrying the offset — the first pass shipped the fade alone,
  which is a plaque that pops.
- **The scrim is part of the entrance, not a backdrop.** A scrim painted at full
  strength while its plaque is still at opacity 0 is a black flash with nothing in
  it, and the gap between the two is not constant: the launcher's first polish (18
  app tiles and their icons) lands ~150 ms after the surface maps, which measured
  as a full scrim over 0.5 % of its plate at t+614 ms. Every overlay now *binds*
  the scrim to the plaque — `opacity: panel.opacity` — so there is one driver and
  no second animation to drift out of step; a panel whose first frame lands after
  the fade still arrives whole (the kanban's does: no intermediate frame at all).
  The webapp panel has no entrance, so there the pair is instant together. Verified
  per surface with `grim` in bursts: no panel presents a frame with the scrim up
  and its plate missing.
- **Reduced motion** is a flag in the same JSON (`reducedMotion`). `apply-theme.py`
  is the only thing that honours it: when it is on, every `animations.ui.*Duration`
  *and* every `animations.ui.*Offset` is generated as `0`, so every `Behavior` in
  every panel lands in one frame and no QML file has to branch on the flag. Hyprland's
  own `animations.enabled` stays
  independent — window and workspace motion belong to the compositor.
- **Enforcement:** timing reaches QML through this pipeline and nowhere else.
  `apply-theme.py` refuses to write if a template declares a `motion*` property
  from anything but `animations.ui` (`check_motion_roles`), or if any QML file
  outside a comment mentions the animation JSON (`check_no_runtime_motion`). The
  launcher used to carry its own `Motion.qml` parsing that JSON at run time; when
  the JSON moved to `ui.controlDuration`/`ui.controlEasing` the reader kept asking
  for `durations.short`/`easing` and returned 0, so the launcher's hover was
  instant for weeks while every other panel animated. It now carries the same
  two tokens as the rest, and the file is gone.
- **One hover recipe, everywhere: the object lights up, it does not get tinted.**
  The target paints its *own* fill one rung up the tonal ladder — `hoverFill`
  (`surface.raisedHigh`), or `hoverFillHigh` (`surface.selection`) when it already
  rests at `hoverFill`, which is the launcher tile and the monitor's dropdown box —
  and its edge ignites `gilt`, both wrapped in `ColorAnimation` at
  `motionControlDuration`. Paint it as the target's own background (or as a child
  rectangle with no glyph inside it), never as the item's background under a
  glyph, or the glyph dims with the fill.
- **Press steps the fill back down** to `pressFill` (`surface.base`) at
  `motionPressDuration`, keeping the gilt edge: the click has to land, and 80 ms is
  shorter than the 110 ms hover so the release reads as a separate event. Every
  reworked target exposes `held` (its `MouseArea.pressed`) plus a `forcePressed`
  review hook, because this host has no pointer automation. The same recipe covers
  the lock card's UNLOCK button, which is why its resting fill — `surfaceContainerHigh`,
  which *is* `raisedHigh` — takes `hoverFillHigh` on hover. Its hover comes from a
  `HoverHandler` rather than the `MouseArea`: a disabled `MouseArea` receives no
  mouse events at all, and a button with nothing to do still has a hover state.
- Selection and focus stay the **action accent** (mint): a 2 px accent edge, an
  accent label, the accent bar on a selected network row. Where selection is a
  *surface* change instead — a calendar day, the menu row Enter would take — it
  takes the rung above hover (`hoverFillHigh`), so a hovered object can never be
  mistaken for a chosen one.
- The translucent wash is retired from hover. It survives in exactly two places
  where the state is not a hover: the kanban drop feedback (`dropHot`/`dropCold`,
  which also has to read as danger) and the monitor's filled accent APPLY button,
  which is already the accent and keeps a dark wash so it still reacts.
- **A drop has three verdicts, not two.** While a card is in the air the column
  under it is accent (the move will happen), `warn` (the card is over the lane it
  already lives in — nothing will change, and the chip says "no move") or `danger`
  (the backend would refuse). Releasing over the card's own lane reports
  "Nothing moved - it's already in NEW" in the warn tone and sends nothing;
  a genuine refusal keeps the error tone that matches the red lane. The lane a
  status lives in is not its name: NEW shows `triage`, `todo`, `scheduled` and
  `ready`, and only parked work can "move to NEW" — that is the unblock — so
  dropping a `ready` card back on NEW looked like an illegal move for as long as
  the panel read the lane off the status.
- Keyboard: every panel keeps its existing keys (Esc/click-outside to dismiss,
  Enter to act, arrows to move). Focused fields show an accent border, never a
  glow.

## 7. Application-wide (non-Quickshell) surfaces

- **GTK3/GTK4**: stock Adwaita in light mode (`look.gtk.theme`), Papirus icons,
  `gtk-application-prefer-dark-theme=0`, and a generated `gtk.css` that
  re-defines Adwaita's named colours (`@define-color`) so GTK apps carry this
  palette without replacing the theme. Colours only — geometry stays Adwaita's.
  `gsettings` is written by the generator and read back; `prefer-light` is
  verified, not assumed.
- **kitty**: `foreground`/`background` from the inks and surfaces, ANSI 0–15 from
  `ansi.*` (upstream), and colours 16–255 *generated* as the surface → ink axis
  rather than a hand-written ramp. `selection_background` is `accent.primary`,
  `selection_foreground` is `onAccent.primary`.
- **Hyprland**: `col.active_border` = `accent.primary` (mauve), `col.inactive_border`
  = `surface.border`, windows fully opaque, gaps and rounding from `look.json`.
- **herdr**: theme file named after the palette, `appearance: light`, `hover` stepped
  to `surface.line` (Latte elevates *darker*, so a hover cannot be `raisedHigh` and
  read as a selection), `muted` = `text.inkMuted`, `cursor`/`ring` = `accent.primary`.
- **Yazi / starship / SDDM**: same roles. Starship's prompt uses
  `accent.primaryInk` (it is drawn as text on the terminal background); Yazi's
  mode pills use `onAccent`; SDDM's greeter is drawn, not rasterised — it loads
  `config/sddm/arch/GreeterAppearance.qml` (generated, the same roles as the
  unlock card) and `check_greeter_surface` refuses a colour literal, a font
  family literal, a `.png` or an `Image` in `Main.qml`. There is no second
  palette to recolour and no artwork script: the greeter is the lock surface's
  language, before a session exists.
- **The editor is separate.** `~/.config/nvim/theme.lua` keeps the Latte surfaces
  and the hue roster but walks every syntax hue to 6:1 on `#eff1f5` (upstream
  pastels land at 2.3–3.5 : 1, where a keyword stops reading apart from a number)
  and holds them ≥ 22 CIELAB units apart. `:terminal` uses the same upstream ANSI
  as kitty. `'background'` is `light` — Neovim's defaults and every plugin that
  branches on it follow — and `scripts/check-theme.lua` (in the neovim-config
  repository) fails when any highlight group paints a colour that is not in
  `theme.lua`, which is how flash.nvim's `s` labels were caught pointing at the
  warning hues.

## 8. Verification

```sh
./scripts/theme/apply-theme.py          # regenerate; run twice, git status must not move
./scripts/theme/contrast-report.py      # 91 pairs, exits non-zero under target
                                        # and on a role declared here but missing from colors.json
bash ./scripts/session/tests/states/run-all.sh   # empty/error states, forced offscreen
hyprctl configerrors                    # empty = the Lua side loaded
hyprctl reload                          # verified on 0.57 with a Lua config
```

The states suite exists because "every state exists" was a claim, not a check: no
empty or error state of monitor, wifi, tokens, kanban or webapp had ever been
rendered. Each harness hands its panel a stub (`MonitorPanel.state`,
`WifiPanel.state`, or the `feed`/`apps`/`message` property a panel already took)
and asserts both the sentence and the ink. It found two real defects: a kanban
lane with no cards said nothing at all, and a webapp list with no helper path sat
in `LOADING…` forever because an empty command never starts and never exits. It
found a third when the notifications harness arrived: the toast's app mark came
from `Quickshell.iconPath()`, which answers for *any* string, so an icon no theme
ships painted the image provider's broken placeholder instead of falling back to
the urgency glyph — and no test could see it, because nothing about "resolved"
and "missing" differs in the URL the panel was handed. The mark is resolved by
`scripts/session/notify-icon.py` now, and the harness reads the tile by name
(`mark-image`) because "an image or a glyph" is the one thing that cannot be read
from outside the card.

Pixel checks that cannot lie, on a capture of the running desktop:

- the bar samples `#eff1f5` inside its accent rule, with three distinct ink
  values present (muted label, faint dot, accent-active pill);
- a dark/ink pixel count of 0 inside a tile means an icon that renders
  invisible — count the *darkest* pixel in a text band, never exact colour
  matches: antialiased 10 px type has almost no fully opaque core pixel, and
  exact-match counting under-reports it by an order of magnitude;
- `hyprctl getoption general:col.active_border` returns the accent, which proves
  the reload and not just the file.
- a state is proved by pixels, not by reading the QML: render the component in a
  `Window` under `QT_QPA_PLATFORM=offscreen` with one instance at (0, 0) — the
  platform parks the pointer there, so that instance *is* the hover state — one
  away from the origin (resting) and a third forced with `forcePressed`, then
  `grabToImage` and sample a pixel inside each surface but off the glyph. The
  launcher tile answers `#3e353e` resting, `#453c45` hovered and `#292329`
  pressed, with `#c3b283` on the hovered and pressed edge and `#4a414a` on the
  resting one;
- a transition is timed, not assumed: grab again ~45 ms into it. A duration of 0
  makes that middle frame equal the settled one.

## 9. Open items (decided by the user, not by the theme)

1. **Resolved (2026-11-22): the wallpaper is `wallpapers/current/marble-oracle.jpeg`.**
   A cool, near-monochrome marble bust, so the light paper surfaces sit on a cool
   image instead of the warm `sun-god.jpg` they were designed against. It is still
   a mid-to-dark photograph: the panels read as glass over stone, not as paper on
   white. A true Latte (pale) wallpaper is the obvious next swap if that reads too
   heavy.
2. **Resolved (2026-11-23): the launcher cell is 112 px and the icon is 48.**
   The cell was widened from 96 (panel 632 → 728 logical, 38 % of 1920) and the
   icon moved off `iconSizeXs` (16 — the rung the bar uses for its status glyphs)
   onto a new `iconSizeTile` (48). Measured offscreen: the tile went 88 → 104 px
   and a real icon 14×14 → 46×40 (16 % → 44 % of the tile). One of the three
   truncated names fits now ("Document Viewer"); the rest still elide because
   the 11 px label fits ~15 characters in 104 px, so "Yazi File Manager" (17)
   and "kitty URL Launcher" (18) would need a 128 px cell or a two-line label.
   (Measured while the label was still SpaceMono; the face is JetBrainsMono now, 0.6000 em
   against 0.6120, so the count is if anything a floor.)
3. **Resolved (2026-11-19, webapp pass): webapp icons are the user's pick,
   used verbatim.** A name or URL resolves exactly as typed, catalogue links in
   any format (png/webp/svg) normalise to the PNG copy, and `qt6-imageformats`
   supplies the webp decoder.
   **The tile is paper, so the artwork has to be the dark one.** Dashboard Icons
   names that the opposite way round from how it sounds: `github-light.png` is
   the *white* mark drawn for a dark background, and the plain `github.png` is
   the dark one. On 2026-11-23 both files were replaced by the white variants,
   and on `surfaceContainerHigh` (`#dfdadf`) they measured 100 % `#ffffff` —
   1.1:1, two blank tiles that every dark-surface check passed. Re-pulled on
   2026-11-25: `github.png` is the catalogue default again (sha256 `1ad63489…`)
   and `chatgpt.png` is the green-plate mark (sha256 `4e881a7f…`), which carries
   its own tile. `icon-contrast.py --background light` is what catches the next
   one. The `Icon=` lines in the `.desktop` files never changed.
4. **kitty picks the palette up in new windows only** (a window already open keeps
   the colours it started with; `SIGUSR1` re-reads the config but the theme file
   is included at parse time, so a fresh window is the reliable check).
   `~/.config/nvim/theme.lua` is hand-owned and committed in the neovim-config
   repository — nothing on this side generates it, so a palette change means
   editing it there too.

## 10. Redesign direction (in progress, 2026-11-23)

The desktop is being pulled from "MD3 pastels on dark glass" toward a
contemporary-Renaissance identity — *cabinet of curiosities*: velvet charcoal
panels, gold-leaf rules and inner frames, engraved serif titling, one living
mint accent. The palette is untouched; only jobs and materials move. The full
brief, the rejected candidates and the phase plan live in
`docs/redesign-2026-11-23.md`.

Moved so far (each value consumed immediately — no dead tokens):

- `look.borders.radius` unflattened from all-5 to `0/2/4/6/8/12` (+ `full` 9999).
- `look.opacity.frame` 0.72 -> 0.88: panels read velvet, not glass.
- `gilt` role (`accent.tertiary`, gold) split from the action accent: every
  plaque edge and header rule now reads `gilt`; the mint accent stays for hover,
  selection, focus, sliders and the active pill. Enforced by `check_gilt_role`.

- Signature entrance: the nine opening plaques fade in (200 ms, OutCubic) via
  `animations.ui.entranceDuration`/`entranceEasing`, exposed as
  `motionEntranceDuration`/`motionEntranceEasing`.
- One motion source: the launcher's hand-written `Motion.qml` (a runtime reader of
  `animations.json`) is gone; the launcher reads `motionControlDuration` /
  `motionControlEasing` like the other ten surfaces, and both drift checks
  (`check_motion_roles`, `check_no_runtime_motion`) keep it that way.
- Hover and press stopped being a wash: the hovered object's own fill steps one
  rung up the tonal ladder and its edge ignites gilt, press steps the fill back
  down. Three colour roles (`hoverFill`, `hoverFillHigh`, `pressFill`) carry it in
  every Appearance, enforced by `check_material_roles`; the ten surfaces that had
  the wash were reworked in one pass.
- Reduced motion: `animations.reducedMotion` makes `apply-theme.py` emit `0` for
  every `animations.ui.*Duration`, so every panel lands in one frame without a
  single QML branch.

Not yet moved — they arrive with their consumers in later phases: the
`frameInset` mat, the icon steps (16/22/28) and the launcher cell (96 → 112).

## The task board's own geometry

The kanban is the one surface that owns metrics beyond the shared ladder, and
they live in `theme/look.json` under `kanban` so `apply-theme.py` regenerates
them instead of a hand-edited `Appearance.qml` drifting from its source:

| Token | Value | Job |
| --- | --- | --- |
| `width` | 1240 | plaque width; four lanes of `columnWidth` |
| `columns` | 4 | TO DO, IN PROGRESS, IN REVIEW, DONE |
| `columnGap` | 16 | gutter between lanes, one step of the space scale |
| `maxHeight` | 640 | plaque height on a 1280×720 logical output |
| `cardPadding` | 10 | the card's own inset, both axes |
| `badgeHeight` | 22 | category chip height (was `keycapHeight`, which is the legend's) |
| `taskCardHeight` | 46 | one-line card floor (was `controls.cardHeight`, shared) |

The last three exist because borrowing a shared token made tuning this panel drag
unrelated surfaces: raising `controls.cardHeight` to 48 rewrote eleven other
Appearance files before the split. A board metric now changes here and nowhere
else.
