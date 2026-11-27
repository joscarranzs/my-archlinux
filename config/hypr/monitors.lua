-- See https://wiki.hypr.land/Configuring/Basics/Monitors/
-- List current monitors and supported resolutions with: hyprctl monitors all

-- GDK_SCALE=1 keeps XWayland GTK apps from scaling twice; the compositor scale
-- below does the actual work. Mirrored in
-- ~/.config/environment.d/wayland.conf so systemd-started apps see it too.
hl.env("GDK_SCALE", "1")

-- This 1920x1080 panel reports ~157 DPI, so "auto" resolved to 1.5. Keep the
-- value explicit: with no monitor rule at all the desktop silently falls back
-- to scale 1.0 on the next login.
hl.monitor({ output = "eDP-1", mode = "1920x1080@60", position = "auto", scale = 1.5 })

-- Configure a specific monitor.
-- hl.monitor({ output = "DP-2", mode = "2560x1440@144", position = "0x0", scale = 1 })

-- Portrait/rotated secondary monitor (transform: 1 = 90°, 3 = 270°).
-- hl.monitor({ output = "DP-2", mode = "preferred", position = "auto", scale = 1, transform = 1 })
