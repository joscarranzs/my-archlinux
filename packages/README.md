# Package lists

Reproducible list of everything installed on this system.

| File | Manager | Restore |
|------|---------|---------|
| `pacman.txt` | pacman (official repos) | `sudo pacman -S --needed - < packages/pacman.txt` |
| `aur.txt` | AUR (paru/yay) | `paru -S --needed - < packages/aur.txt` |
| `npm.txt` | npm (global) | `npm install -g $(grep -v '^#' packages/npm.txt \| tr '\n' ' ')` |
| `local.txt` | manual (outside package managers) | see per-entry notes |

Notes:
- `paru-bin` is the AUR helper itself; install it first (bootstrap) before restoring `aur.txt`.
- `grim` and `wtype` were added during setup for screenshots/Wayland input.
- Herdr (`hc`, `herdr-app`, `herdr-core`) is installed via the upstream installer, not a package manager.
- Python/Rust toolchains come from `python`/`rust` in `pacman.txt` (no extra pip/cargo packages installed).
