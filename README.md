# Dotfiles

Personal Arch Linux dotfiles for Hyprland + Quickshell.

## Branches

- `development` — the live desktop tree (this branch).
- `skills` — orphan branch holding only the Hermes user skills.
- `master` — the initial commit, kept untouched.

## Structure

- `config/` — application configuration (symlinked to `~/.config/`)
- `scripts/` — helper scripts and theme generator
- `theme/` — theme tokens (colors, look, animations)
- `wallpapers/` — wallpaper assets
- `etc/` — system configs (copied to `/etc/` by install scripts)
- `hosts/` — host-specific overrides
- `docs/` — notes and guides
  - `wifi-iwd-to-networkmanager.md` — why stopping iwd killed the wifi, and the order
    that hands the radio to NetworkManager without leaving the machine offline
- `packages/` — package lists

## Setup

```bash
git clone git@github.com:joscarranzs/my-archlinux.git ~/.dotfiles
cd ~/.dotfiles
# symlink configs (manual or via stow). config/hermes is skipped by the loop: the
# agent reads it from ~/.hermes, not from ~/.config.
for d in ~/.dotfiles/config/*; do
  [ "$(basename "$d")" = hermes ] && continue
  ln -s "$d" ~/.config/
done
ln -s ~/.dotfiles/scripts ~/.scripts
ln -s ~/.dotfiles/theme ~/.theme
ln -s ~/.dotfiles/wallpapers ~/.wallpapers

# Hermes agent: the two local plugins. Hermes resolves these paths, so the
# symlinks (not copies) are what keeps them editable here.
mkdir -p ~/.hermes/plugins
ln -s ~/.dotfiles/config/hermes/plugins/caveman-shrink ~/.hermes/plugins/caveman-shrink
ln -s ~/.dotfiles/config/hermes/plugins/caveman-voice ~/.hermes/plugins/caveman-voice

# apply theme
./scripts/theme/apply-theme.py
```

## Skills

User skills live on the orphan `skills` branch, not in this tree. They change
often and are kept out of the desktop configuration history on purpose. Attach
that branch as a worktree and point Hermes at the skills directory inside it:

```bash
git worktree add ~/.local/share/hermes/skills skills
ln -sfn ~/.local/share/hermes/skills/config/hermes/skills ~/.hermes/skills
python3 scripts/skills/validate-user-skills.py \
  --tree ~/.local/share/hermes/skills/config/hermes/skills
```

See `README.md` on the `skills` branch for the editing workflow.

Catalog-installed plugins (`advanced-delegation`) are **not** tracked here: their
provenance and update records live in `~/.hermes/plugins/.install-metadata.json`.
Reinstall them with `hermes plugins install advanced-delegation`. The Hermes hub
index cache (`.hub/`, ~52 MB) is ignored on purpose.

The Neovim config is **not** tracked here and is not a submodule: it lives in its
own repository, `joscarranzs/neovim-config`. Clone it separately:

```bash
git clone git@github.com:joscarranzs/neovim-config.git ~/.config/nvim
```

`scripts/theme/apply-theme.py` writes `~/.config/nvim/theme.lua` only when that
directory already exists, so the order of both steps does not matter.

## Theme

Colors, look, and animations are defined in `theme/`. Edit any JSON and run:

```bash
./scripts/theme/apply-theme.py
```

## Hyprland

Config entry point: `config/hypr/hyprland.lua`. Validate with:

```bash
hyprland --verify-config -c ~/.config/hypr/hyprland.lua
```

## Idle / Lock (suspend disabled)

**Suspend is disabled for now** (`etc/systemd/logind.conf.d/00-suspend.conf`):
`HandleLidSwitch`, `HandleLidSwitchExternalPower`, `HandleLidSwitchDocked` and
`HandleSuspendKey` are all `ignore`. The machine lives on AC and the lid/sleep
flow is going to be rebuilt from scratch. Closing the lid does nothing;
`systemctl suspend` still works by hand, only the automatic triggers are off.

Idle is handled by **hypridle** (`config/hypr/hypridle.conf`, user unit
`hypridle.service`), which only locks now:

- Battery: lock after 9 min (`timeout = 540`, conditional on `scripts/session/on-battery.sh`).
- AC power: lock after 24 min (`timeout = 1440`).
- Hibernation is disabled system-wide via `etc/systemd/*` drop-ins.

```bash
sudo pacman -S --needed hypridle
sudo ./scripts/system/install-power-policy.sh
systemctl --user enable --now hypridle.service
```

`install-power-policy.sh` copies the `etc/systemd/*` drop-ins into place. logind
only reads them at start, so **reboot** to apply them. Never
`systemctl restart systemd-logind` on a live graphical session: it terminates the
session and drops you back to the greeter.

## Lockscreen

The Quickshell lockscreen lives in `config/quickshell/lockscreen/` and locks the
session through `ext-session-lock-v1`, authenticating with PAM
(`pam/password.conf`). `hypridle` starts it through `scripts/session/lockscreen.sh`
on idle, and `SUPER + CTRL + L` locks on demand.

Preview it in a floating window without locking the session:

```bash
quickshell -p ~/.config/quickshell/lockscreen/test.qml
```

## App Launcher

The Quickshell app launcher lives in `config/quickshell/launcher/` and opens with `SUPER + SPACE`
(`~/.scripts/session/launcher.sh`). It shows a centered, scrimmed panel with a search field and
a grid of installed applications (Material Symbols Rounded icons, Catppuccin Latte palette).

- Preview in a floating window: `quickshell -p ~/.config/quickshell/launcher/test.qml`
- Launch on demand: `~/.scripts/session/launcher.sh`
- Search filters apps live (name, generic name, keywords, comment).
- `↑↓←→` navigate, `Enter` launches (auto-launches on a single match), `Esc` closes.
- Clicking the scrim also closes the launcher.

Icons use Material Symbols Rounded with `wght 700, GRAD 0, opsz 24, FILL 0`.

## Status bar

A Quickshell bar pinned to the top edge: workspace dots on the left, the date
and clock in the middle, and the system readings on the right.

```bash
quickshell -n -p ~/.config/quickshell/bar/test.qml   # preview over the wallpaper
~/.scripts/session/bar.sh                            # live bar (also starts with the session)
```

Hyprland starts it from `config/hypr/hyprland.lua` as an `exec-once`, right after
the wallpaper. The script waits for the Wayland socket, takes a lock in
`$XDG_RUNTIME_DIR` so a second copy exits instead of stacking a second bar, and
respawns the renderer when it crashes (a clean exit or SIGHUP/SIGINT/SIGTERM is
honoured). To restart it by hand: kill the renderer, or the wrapper and
`~/.scripts/session/bar.sh`.

- `config/quickshell/bar/Bar.qml` — the composition (workspace strip, clock,
  status cluster), reusable by the preview and the live shell.
- `config/quickshell/bar/components/` — `WorkspaceStrip`, `BarClock`,
  `StatusItem`, `StatusCluster`, `BarSeparator`, generated `MaterialIcon`.
- Geometry lives in `theme/look.json` (`bar.height`, `bar.margin`, `bar.padX`,
  `bar.itemGap`, `bar.dotSize`, `bar.dotActiveWidth`, ...) and the type sizes in
  `theme/typography.json` (`sizes.barClock`, `barLabel`, `barValue`); the
  generated `Appearance.qml` is the only place QML reads them from.
- One accent per surface: the active workspace is a gold pill, the clock is
  bone white, everything else is muted ink behind hairlines.
- Wired to live state: workspace strip (Hyprland), clock, volume and backlight
  (`AudioOutput`, `Brightness`), wifi (`NetworkState`), token spend (`TokenUsage`)
  and the pack (`BatteryState`, read from upower). Bluetooth, the monitor glyph and
  notifications are still placeholders.

## Wallpaper

`scripts/session/switch-wallpaper.sh` picks the desktop background: it scans
`~/.wallpapers/current` and copies the chosen image over `default-background`,
which is the file `config/quickshell/wallpaper/shell.qml` renders.

```bash
~/.scripts/session/switch-wallpaper.sh          # cycle to the next image
~/.scripts/session/switch-wallpaper.sh FILE     # jump to a specific image
quickshell -p ~/.config/quickshell/wallpaper/test.qml   # preview, no layer-shell
```

`test.qml` renders the same `default-background` painting in a floating window,
so you can check a wallpaper and its gold hairline frame without touching the
live surface.

## Web app panel

`SUPER + SHIFT + W` opens a Quickshell panel that turns a site into a desktop
application: it asks for a name, a URL and an optional icon, then writes a
freedesktop entry that Chromium opens as its own window.

- **Icon**: a Dashboard Icons name (`youtube`), an image URL, or a local path.
  Names and URLs are downloaded to `~/.local/share/icons/webapps/<slug>.<ext>`,
  because a desktop entry cannot point at the network. Catalogue links in any
  format (png/webp/svg) resolve to the PNG copy of the same name, and the
  variant is yours to pick (`github` vs `github-light`). Leave it empty for the
  generic internet icon.
- **Draft**: the form state is written to
  `$XDG_RUNTIME_DIR/quickshell-webapp-draft.json` while you type. Closing the
  panel keeps the draft, and because the runtime directory is tmpfs it never
  survives a logout or reboot. `DISCARD` clears it.
- **Entries**: `~/.local/share/applications/webapp-<slug>.desktop`, with
  `chromium --app=<url> --class=webapp-<slug>` so window rules can target it.
- **Manage**: the `INSTALLED` button in the header switches the same card to
  the list of installed web apps. Each row shows the icon, name and host with
  a delete action; deleting removes the entry and the icon downloaded for it
  (an icon kept outside the webapps icon dir is left alone).

Keyboard: `Tab` moves between fields, `Enter` creates, `Esc` closes (keeping the
draft); in the installed list `Esc` goes back to the form first.

```bash
~/.scripts/session/webapp.sh                            # open the panel
quickshell -p ~/.config/quickshell/webapp/test.qml      # preview, no layer-shell
~/.scripts/session/webapp.py create '{"name":"Notion","url":"notion.so"}'  # same path, from a shell
~/.scripts/session/webapp.py clear                      # drop the session draft
~/.scripts/session/webapp.py list                       # installed web apps, as JSON
~/.scripts/session/webapp.py delete <slug>              # remove one entry and its icon
```

## Calendar panel

`SUPER + C` opens a month grid on a scrim: the visible month, today marked with
the accent and a dot, a selected day, and the neighbouring months' days dimmed so
the grid never shows holes.

- **Month only, for now.** There are no events on this surface; that is a later
  layer, not a placeholder to be faked with sample data.
- **Fixed 6×7 grid**, so stepping to a month that would fit in five rows does not
  resize the panel and move the frame under the pointer.
- **Monday-first** derived from `Date` (`(getDay() + 6) % 7`), never from the
  locale. The visible month is anchored on the 1st, so stepping back from the
  31st cannot skip a month.
- **One accent**: today owns the gold. A selected day is a raised fill plus a
  hairline, and hover is the neutral state layer (`look.opacity.stateLayer`).

Keyboard: `←` `→` change month, `T` returns to today, `Esc` closes. Clicking a
day selects it; the header chevrons do the same as the arrow keys.

```bash
~/.scripts/session/calendar.sh                        # open the panel
quickshell -p ~/.config/quickshell/calendar/test.qml  # preview, no layer-shell
```

## Volume panel

Click the speaker glyph in the bar to open the output level: current percentage,
a draggable slider, the device name and a `MUTED` flag when the output is silent.

- **Reads PipeWire through Quickshell's service**, not `wpctl`: the value is live,
  a level change costs zero processes, and the panel cannot show a number the
  mixer already moved past. `services/AudioOutput.qml` is the single place that
  reads or writes it.
- **The glyph is the mute button.** It already means "sound" to anyone looking at
  it, and a separate MUTE control on a 300 px plaque is one element too many. It
  turns red when muted, and so does the `MUTED` flag in the header — the
  percentage keeps showing the level while silent, which otherwise reads as a
  broken panel.
- **The slider drags, it does not just click,** and the whole strip is the hit
  area: a 6 px track is not a target.
- Hover is the shared state layer — accent at `look.opacity.stateLayer`, the same
  recipe as the launcher tile.

Keyboard: `↑` `↓` step by `look.volume.step`, `M` toggles mute, `Esc` closes.

```bash
~/.scripts/session/volume.sh                        # open the panel (also a toggle)
quickshell -p ~/.config/quickshell/volume/test.qml  # preview, no layer-shell
```

## Brightness panel

`SUPER + SHIFT + B` (`SUPER + B` is the browser) opens the backlight level:
percentage, a draggable slider and the device node the panel is driving.

- **Writes through logind, not sysfs.** `/sys/class/backlight/*/brightness` is
  `root:root 0644`, so a panel cannot write it, and neither `brightnessctl` nor
  `light` is installed here. `services/Brightness.qml` calls
  `SetBrightness` on `/org/freedesktop/login1/session/auto`, which needs no
  polkit prompt from an active local session. `/session/self` does not exist on
  this host.
- **Reads sysfs, never its own request.** `SetBrightness` returns nothing, so the
  plaque shows what the kernel reports; the write is throttled to one `busctl`
  spawn per 60 ms while dragging instead of one per mouse event.
- **The level has a floor** (`look.brightness.minimum`, 5 %): a screen at 0 % is a
  screen the user cannot see to bring it back up. Both the slider and the arrow
  keys stop there.
- **The glyph is decoration, not a button.** A backlight has no mute, so unlike
  the volume plaque it has no hover state and no click handler.
- The slider is `components/LevelSlider.qml`, a deliberate copy of the volume
  control: a relative import across surface directories does not resolve reliably
  in this build.

Keyboard: `↑` `↓` step by `look.brightness.step`, `Esc` closes. The wheel does
nothing on purpose — layer-shell surfaces do not receive it (verified on the
volume panel).

```bash
~/.scripts/session/brightness.sh                        # open the panel (also a toggle)
quickshell -p ~/.config/quickshell/brightness/test.qml  # preview, no layer-shell
```

## Wifi panel

`SUPER + N` (or a click on the wifi glyph in the bar) opens the wireless panel:
the connection you are on, the networks in range with their signal and security,
and a passphrase field for a network that is not saved yet.

- **Reads through `Quickshell.Networking`**, which is a NetworkManager client.
  That module was useless while iwd ran standalone; the host now runs
  NetworkManager as the only owner of `wlan0` with
  `wifi.backend=wpa_supplicant` (iwd is retired and `disabled`, see
  `docs/wifi-iwd-to-networkmanager.md`), so the panel gets a reactive model
  instead of shelling out to `iwctl`.
- **Connects only on an explicit selection.** A saved network connects straight
  away; a new secured one opens the passphrase field first. There is no
  auto-connect, and **no disconnect or forget action anywhere in the panel** --
  on a machine whose only uplink is wifi, "forget" is one click from a locked door.
- **The connected network is not repeated in the list.** It gets the block above
  it; showing it twice read as a duplicate and there is nothing to connect to.
- **Signal is four drawn bars**, not a Material glyph: the font only publishes
  three wifi steps, so a 42 % and a 64 % link would look identical.
- Scanning runs only while the panel is open (`scannerEnabled` on open, off when
  the process exits), so nothing polls the radio in the background.

Keyboard: `↑` `↓` select, `↵` connect (or submit the passphrase), `R` rescan,
`Esc` closes (and cancels the passphrase field first).

```bash
~/.scripts/session/wifi.sh                        # open the panel (also a toggle)
quickshell -p ~/.config/quickshell/wifi/test.qml  # preview, no layer-shell
```

## Captive portal (networks with a login page)

Open wifi that gates internet behind a student/user login (university, airport,
hotel) now pops the login page automatically, like a phone does.

- **NetworkManager already detects it.** Arch ships
  `/usr/lib/NetworkManager/conf.d/20-connectivity.conf`
  (`uri=http://ping.archlinux.org/nm-check.txt`); when the probe comes back
  hijacked, NM reports connectivity `portal`. No `/etc` change was needed.
- **`scripts/session/captive-portal.sh` watches that state** (`nmcli monitor`,
  line `Connectivity is now 'portal'`), finds where the probe is redirected
  (`curl %{redirect_url}`, fallback `neverssl.com`, then the probe itself for
  transparent interception) and opens it with `xdg-open` (chromium), plus a
  toast. A 60 s cooldown debounces flapping portals, and while the portal holds
  it re-probes every 15 s (bounded) so the state flips to `full` soon after
  login instead of waiting out NM's 300 s interval.
- Autostarts with the session (`hyprland.lua`); the flock makes a second run
  exit, so a manual start never stacks two watchers. The Wayland socket is
  resolved at open time, not at startup, because linger keeps the watcher
  alive across logins.

```bash
~/.scripts/session/captive-portal.sh status  # connectivity + probe + would-open URL
~/.scripts/session/captive-portal.sh open    # force the login page open now
# log: $XDG_RUNTIME_DIR/captive-portal.log
```

Verified with a local fake portal (302 → login page): the browser opened the
redirect target from a systemd user unit with no session env. The live `portal`
transition itself is only provable on the gated network.

## Token panel

`SUPER + T` (or a click on the robot in the bar's status cluster) opens the spend
panel: the prepaid balance, what the wallet has actually spent, and the quota
windows of the coding route.

- **`spent` is `purchased - balance`**, not the portal's `member_spend_usd`
  counter. That field froze at 0.508 404 while the wallet had already lost
  0.752 097, so it under-reports; it is kept as `portal_spent_usd` for diagnosis
  only.
- **`purchased` is derived, not declared.** The first run sets it to
  `round_up(balance + portal_spent)` (19.7563 + 0.5084 -> 20); afterwards it only
  moves when the *balance goes up*, i.e. on a top-up, by that difference.
  Spending never touches it and `spent` never resets.
- **Prepaid vs subscription** is read straight from `balance_usd` and
  `has_subscription`; there is no manual switch to keep in sync.
- `~/.local/state/nous-credits.json` is machine state, not configuration: only
  the helper writes it.
- The feed refreshes on a 60 s TTL. The plaque prints the timestamp of the
  reading (`generated_at`) and prefixes it with `STALE` when the helper could not
  reach the portal, so a cached number never passes for a live one.

Keyboard: `Esc` closes, `R` re-runs the helper instead of waiting for the tick.

```bash
~/.scripts/session/tokens.sh                        # open the panel (also a toggle)
python3 ~/.scripts/session/tokens.py --pretty | head -20
quickshell -p ~/.config/quickshell/tokens/test.qml  # preview, no layer-shell
```

## Battery panel

`SUPER + P` (or a click on the pack glyph in the bar) opens the battery plaque:
level, state, time left or time to full, drain rate, energy and health.

- **Reads upower over D-Bus, not sysfs.** `/sys/class/power_supply/BAT1` on this
  MSI Modern 14 publishes no `power_now` and no `design_capacity`, so a sysfs
  reader cannot report the drain rate or the health. `Quickshell.Services.UPower`
  carries both, plus `timeToEmpty` and `timeToFull` in seconds; a zero means
  "upower is not estimating" and the panel prints a dash instead of a guess.
- **The device is the pack, not `UPower.displayDevice`.** The composite reports
  `healthPercentage` as 0 here while the device behind it reports the measured
  65.65 % of design capacity, so `services/BatteryState.qml` walks
  `UPower.devices` and takes the first battery that is present.
- **It is a component, not a singleton.** Inside a `pragma Singleton` the UPower
  service was created before the D-Bus side existed and every field stayed at
  zero for the life of the process, while the same reads from an ordinary object
  answer within a second and a half.
- **`battery/services/BatteryState.qml` is a deliberate copy of
  `bar/services/BatteryState.qml`.** They import their own `Appearance`, and
  Quickshell does not register a symlinked component in a directory's synthetic
  qmldir. Change one, copy it over the other.
- **One set of thresholds.** `theme/look.json` -> `look.battery` feeds both
  templates, so the bar's glyph turns gold at 20 % and red at 10 % at exactly the
  same level the plaque's bar does.
- The glyph bands are the ones the font publishes: `battery_0_bar` ..
  `battery_6_bar`, `battery_charging_20` .. `_90`, `battery_alert` under the
  critical threshold, `battery_unknown` when upower has no device yet.

Keyboard: `Esc` closes. Nothing here is editable, so there is no second key.

```bash
~/.scripts/session/battery.sh                        # open the panel (also a toggle)
quickshell -p ~/.config/quickshell/battery/test.qml  # preview, no layer-shell
upower -i /org/freedesktop/UPower/devices/battery_BAT1   # the raw reading
```

## Monitor panel

`SUPER + SHIFT + M` opens the monitor plaque: the laptop panel as a locked
readout, then one card per external monitor with a RESOLUTION and a SCALE
dropdown and an APPLY button. `SHIFT` keeps the bind clear of `SUPER + M`
(exit).

- **External monitors only, hot-only.** `services/MonitorState.qml` refuses any
  `eDP-*` / `LVDS-*` / `DSI-*` output before it builds a command, so the eDP-1
  rule in `monitors.lua` cannot be changed from this surface. Applies go through
  `hyprctl eval 'hl.monitor({...})'` — `hyprctl keyword monitor ...` answers
  "unknown request" on a Lua config. Nothing is written to any config file; a
  session restart falls back to `monitors.lua`.
- **The read-back is the proof.** `ok` from `eval` only means the Lua ran; the
  next poll compares the live mode and scale against what was asked. Hyprland
  can snap a scale to its own value (measured on a headless output: asked 1.75,
  got 1.6666666), so the status reports the applied value and adds
  `(asked 1.75×)` when the compositor adjusted it.
- **Menus float, they never stretch the plaque.** `ChoiceMenu` is drawn over the
  plaque content (z 100) anchored under its field, flipping above it when there
  is no room below. The first version expanded the list inline and the plaque
  grew with it — that read as a visual bug. A click outside the menu dismisses
  it; `Esc` closes the menu first, the panel second.
- **A poll that changed nothing must not notify.** Reassigning the model arrays
  rebuilds every card and destroys any open menu or pending pick, so `parse()`
  compares a JSON snapshot and only assigns on a real change (hotplug, mode or
  scale change, layout reflow).
- **Position is preserved.** An apply keeps the output's current `x`/`y`
  (`auto` for a disabled one), so changing a scale does not rearrange the
  desktop on purpose — the compositor may still reflow neighbours when a
  logical size changes.
- Resolution options are the advertised modes deduped to the best refresh rate
  per resolution, biggest first; a live mode outside the advertised list
  (custom modeline) joins at its sorted position. Scale options are
  1 / 1.25 / 1.5 / 1.75 / 2 / 2.5 / 3 plus the live scale when it is off-list.

Keyboard: `↑↓` pick a monitor, `Tab` / `←→` pick a control, `↵` opens a menu or
applies, `Esc` closes. APPLY stays disabled until a pick differs from the live
value; the card shows MODIFIED while it does.

```bash
~/.scripts/session/monitor.sh                        # open the panel (also a toggle)
quickshell -p ~/.config/quickshell/monitor/test.qml  # preview, no layer-shell
hyprctl -j monitors all                              # the raw state the panel polls
hyprctl output create headless                       # fake external for testing
hyprctl output remove HEADLESS-1                     # …and remove it afterwards
```
