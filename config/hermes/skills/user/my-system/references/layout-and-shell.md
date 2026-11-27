# Layout and shell

## Symlink map (verified 2026-11-27)

Into `~/.dotfiles`:

- `~/.bashrc` -> `config/shell/bashrc`; `~/.bash_profile` -> `config/shell/bash_profile`.
- `~/.scripts` -> `scripts/`; `~/.theme` -> `theme/`; `~/.wallpapers` -> `wallpapers/`; `~/.agents` -> `agents/`.
- `~/.config/hypr`, `kitty`, `quickshell`, `sddm`, `yazi`, `gtk-3.0`, `gtk-4.0`, `fontconfig`, `environment.d`, `chromium-flags.conf`.
- `~/.config/hyprland.lua` -> `~/.config/hypr/hyprland.lua`.
- `~/.hermes/skills`, `skins`, `SOUL.md`; `~/.hermes/plugins/{caveman-shrink,caveman-voice,task-intake}`.

Real directories: `~/.config/nvim`, `~/.config/herdr-app`, `~/.local/bin`, `~/.hermes`. Verify with `find ~ -maxdepth 2 -type l -printf '%p -> %l\n'`.

Top-level repo dirs: `agents/ config/ docs/ etc/ hosts/ packages/ patches/ scripts/ theme/ wallpapers/`. `AGENTS.md` holds the operating rules.

## Shell

- `config/shell/bashrc` (77 lines) prepends `~/.local/bin` and `~/.npm-global/bin` to PATH once, guards non-interactive shells, sets `EDITOR=nvim` and `BAT_THEME="Catppuccin Latte"`, history 100000, and initializes fzf (`fnv`), zoxide and starship.
- `bash_profile` sources `bashrc`; `~/.profile` only adds `~/.local/bin`.

## `~/.local/bin` shadowing trap

Everything here shadows same-named binaries later in PATH. Wrappers in `scripts/system/` include `nvim`, `nautilus`, `powerprofilesctl`, `clean-system`, `optimize-system`, `deckcraft`, `gridcraft`, `pdfcraft`, `wordcraft`.

- The wrapper wins: editing `/usr/bin/<name>` fixes nothing.
- `powerprofilesctl` re-execs `/usr/bin/python3 /usr/bin/powerprofilesctl` for python-gobject, because Hermes' bundled Python is earlier in PATH.
- egui wrappers force `WINIT_X11_SCALE_FACTOR=1.5` under the compositor's 1.5 scale; `nvim` sets `NVIM_TEST=1` to silence a DSR warning.
- Real binaries also live here: `herdr`, `herdr-core`, `hermes*` shims, `jq`, `tree-sitter`; `hc` -> `herdr-core`.

## Environment

`~/.config/environment.d/wayland.conf` sets `GDK_BACKEND=wayland`, `QT_QPA_PLATFORM=wayland`, `ELECTRON_OZONE_PLATFORM_HINT=auto`, `MOZ_ENABLE_WAYLAND=1`, `GDK_SCALE=1`, `GDK_DPI_SCALE=1`, `QT_QPA_PLATFORMTHEME=gtk2`. Hyprland spawns through `hl.env()` in `hyprland.lua`; systemd reads environment.d. Neither reads the other, and environment.d applies only at next login.

## Scripts

- `scripts/session/`: one launcher per panel; helpers `notify-icon.py`, `kanban-feed.py`, `hypr-event-stream.py`, `tokens.py`, `wayland-display.sh`, `lock-and-suspend.sh`, `captive-portal.sh`, `on-battery.sh`, `switch-wallpaper.sh`, `text-scale.sh`, `webapp.py`.
- `scripts/theme/`: `apply-theme.py`, `contrast-report.py`, `verify-fonts.sh`, `templates/`.
- `scripts/system/`: machine and app wrappers.
- Tests: 111 Python unit tests, 7 state harnesses and 8 panel harnesses; run from `~/.dotfiles`.
