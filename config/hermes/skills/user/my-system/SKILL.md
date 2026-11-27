---
name: my-system
description: Use when working on this machine. Map, sources, rules.
version: 1.0.0
author: joscarranzs
license: MIT
platforms: [linux]
metadata:
  hermes:
    tags: [arch, hyprland, quickshell, dotfiles, hermes, system]
    category: user
    related_skills: [kanban, how-to-solve-problems]
---

# My system

Live single-user Arch/Hyprland desktop. `~/.dotfiles` (branch `rewriting`) is the source of truth. This skill is the map, not a snapshot: versions, board state, balances and running panels must be re-read live.

## When to use

- Changes to the desktop, scripts, environment, theme, wallpaper, Hermes config, SDDM, PAM or logind.
- A local failure whose cause may be this install rather than the software.
- Before touching anything outside `$HOME` or any lock/suspend path.
- Not for cards: load `kanban`. Not for generic diagnosis: load `how-to-solve-problems`.

## Authority and layout

- Git repo `~/.dotfiles`: `git -C ~/.dotfiles status` is the undo button. Commit durable changes; pushing is a separate user decision.
- Symlinks into it: `~/.bashrc`, `~/.bash_profile`, `~/.scripts`, `~/.theme`, `~/.wallpapers`, `~/.agents`, `~/.config/{hypr,quickshell,kitty,sddm,yazi,gtk-3.0,gtk-4.0,fontconfig,environment.d}`, `~/.hermes/{skills,skins,SOUL.md}`, and three `~/.hermes/plugins/*` entries.
- Real directories: `~/.config/nvim` (own repo, branch `main`), `~/.config/herdr-app`, `~/.local/bin`, `~/.hermes` runtime state.
- `~/.dotfiles/AGENTS.md` is the operating contract: delegation routes, budget, context discipline, handoffs, English UI strings.
- `~/.config/hyprland.lua` also resolves to the Hyprland entry file; there is no `hyprland.conf`.

## Boot and processes

- SDDM -> `/usr/bin/start-hyprland` -> Hyprland reads `~/.config/hypr/hyprland.lua`. Satellites take effect only through `load("name")`; `monitors` loads first.
- One Quickshell process per panel, started by `~/.scripts/session/<panel>.sh`: `quickshell -n -p <panel>/shell.qml`. Panels: bar, battery, brightness, calendar, kanban, launcher, lockscreen, monitor, tokens, volume, wallpaper, webapp, wifi.
- Bar and wallpaper come from `hl.exec_cmd` in `hyprland.lua`; the bar script has a flock and respawn loop. Other panels are toggled by keybind.
- Environment has two writers: `hl.env()` for Hyprland-spawned processes (immediate) and `~/.config/environment.d/wayland.conf` for systemd services (next login). Keep both in sync.
- Verified 2026-11-27: quickshell 0.3.2-1, hyprland 0.57.2-2, hypridle 0.1.8-2, sddm 0.21.0-7. Re-check with `pacman -Q` before relying on them.

## Non-negotiables

1. Resolve the real path, read the file, identify its owner. Generated files are output, never input. `scripts/theme/apply-theme.py` owns derived files through atomic writes; edit `theme/*.json`, templates and hand-owned QML only. Check `GENERATED_MARKER`.
2. One source per concern: theme JSON -> templates -> generated `Appearance.qml`. Motion, type scale, hover/press and icon rungs are generated; no QML parses theme JSON at runtime. Reuse an existing surface's recipe instead of tuning a new value.
3. A silent failure is not a clean result. Diff the `appearance.*` roles a surface reads against those its `Appearance.qml` declares. `Quickshell.iconPath()` always answers, so use `~/.scripts/session/notify-icon.py` to resolve icons.
4. One Quickshell instance per panel. Use the wrapper or a bracketed `pgrep -f` pattern; never unbracketed `pkill -f`. A panel launched from an agent session dies with it; probe with `systemd-run --user --collect`.
5. The lock is fail-closed. The lid belongs to the Hyprland `switch` bind, logind ignores the lid, and suspend waits up to 12 s for `$XDG_RUNTIME_DIR/session-locked`. A missing marker aborts suspend. Never weaken that wait.
6. NetworkManager is the sole owner of `wlan0` with the `wpa_supplicant` backend. iwd is disabled because it destroys its netdev; LLMNR is off. `notify-send` is absent, so its notifiers are silent.
7. Pay-per-use credits: cheapest sufficient route, no premium by default, one session per task. Grep then read ranges; keep skill bodies under ~5k tokens; check spend with `hermes insights --days 7` and `hermes usage`.
8. English for UI strings, code, comments, docs and commits. Spanish only when explicitly ordered for an artefact; card text follows the board precedent in `kanban`.
9. Verify with real output and quote it. Never invent a result; report unverified items as unverified.
10. SDDM, PAM, logind, system units, packages and compositor restarts need explicit approval.

## Where to look first

| Domain | Reference |
|---|---|
| Symlinks, shell, wrappers, environment, scripts | `references/layout-and-shell.md` |
| Theme pipeline, panels, QML traps, nvim, SDDM, wallpapers | `references/theme-and-ui.md` |
| Lock, PAM, power, network, Qt/GTK, silent notifiers | `references/session-security.md` |
| Hermes config, plugins, skills, gateway, voice, tokens, backups | `references/hermes-runtime.md` |
| Delegation, handoffs, commits, recovery, change checklist | `references/work-conventions.md` |

## Volatile facts

Never memorize git HEAD, board state, token balance, running panels or package versions. Re-run `git -C ~/.dotfiles status`, `task_intake action=open`, `~/.scripts/session/tokens.py`, `pgrep -af 'quickshell -n -p'` and `pacman -Q` as needed.

## References

- `references/layout-and-shell.md` — the verified path map and shell behavior.
- `references/theme-and-ui.md` — generation, panels and visual invariants.
- `references/session-security.md` — lock, power, network and environment traps.
- `references/hermes-runtime.md` — the agent runtime on this host.
- `references/work-conventions.md` — how work is delegated, recorded and recovered.
