# Session, security and network

## Lock and power

- `hypridle 0.1.8`: `~/.dotfiles/config/hypr/hypridle.conf` sets `lock_cmd = $HOME/.scripts/session/lockscreen.sh`, no unlock command, lock at 540 s only when `on-battery.sh` says battery, and 1440 s on AC. hypridle never suspends. Its arguments run through `/bin/sh -c`, so `$HOME` expands at runtime.
- Lid close is a Hyprland `switch:on:Lid Switch` bind (`hyprland.lua:85-87`) calling `lock-and-suspend.sh`; logind is configured with `HandleLidSwitch=ignore` in `~/.dotfiles/etc/systemd/logind.conf.d/00-suspend.conf`, plus suspend/hibernate/idle ignores. `sleep.conf.d/00-suspend.conf` allows suspend only.
- `lock-and-suspend.sh`: `loginctl lock-session`, wait up to 12 s for `$XDG_RUNTIME_DIR/session-locked`, abort without suspend if absent, then `systemctl suspend`. `--no-suspend` is the safe test. Logs to `$XDG_RUNTIME_DIR/lock-and-suspend.log`.
- Lockscreen: `lockscreen.sh` uses a flock lock, then `quickshell -n -p ~/.config/quickshell/lockscreen/shell.qml`. The QML `WlSessionLock` touches the marker when mapped and removes it on quit.
- PAM lives in `~/.dotfiles/config/quickshell/lockscreen/pam/`: `password.conf` uses `pam_unix.so` and gnome-keyring; `other` is fail-closed deny-all. PAM edits need approval.
- First checks: `$XDG_RUNTIME_DIR/lockscreen.log`, `pgrep -af 'quickshell.*lockscreen'`, `ls $XDG_RUNTIME_DIR/session-locked`, `hyprctl -j binds`, and the logind drop-in. Never remove the marker wait to force a suspend.
- Restart hypridle: `systemctl --user restart hypridle`; logs: `journalctl --user -u hypridle -n 50 --no-pager`.

## Network

- NetworkManager is the only owner of `wlan0`; `/etc/NetworkManager/conf.d/wifi-backend.conf` sets `wifi.backend=wpa_supplicant`.
- iwd is installed but disabled. Stopping it destroyed its netdev; `scripts/system/wifi-drop-iwd.sh` documents the `DefaultInterface=true` quirk and the history in `docs/wifi-iwd-to-networkmanager.md`. Reprocessing scripts: `wifi-single-owner.sh`, `wifi-boot-fix.sh`, `wifi-emergency.sh`, `wifi-rescue.sh`, `nm-iwd-switch.sh`, `nm-wifi-backend.sh`.
- `~/.dotfiles/etc/systemd/resolved.conf.d/00-llmnr.conf` sets `LLM=no`; mDNS is untouched.
- `scripts/session/captive-portal.sh` calls `notify-send`, which is not installed and owned by no package, so that notification never fires. `tokens.py` guards on the same missing binary and skips its alert.

## Qt and GTK

`QT_QPA_PLATFORMTHEME=gtk2` is set in `~/.config/environment.d/wayland.conf` and `~/.config/hypr/hyprland.lua:198`; it is a Qt5 value with no Qt6 plugin, so Qt6 resolves icons only in hicolor. GTK is set to Adwaita with Papirus icons in `gtk-3.0`/`gtk-4.0/settings.ini`; `libqgtk3.so` is installed, so `gtk3` would work, but this is a next-login environment change awaiting the user's decision. The notification icon helper no longer depends on it either way.
