-- Look and feel that has no theme token. Colors, spacing, radii and opacities
-- come from theme/look.json through scripts/theme/apply-theme.py (rendered into
-- look.lua), and the layout/scrolling setup is declared once, in hyprland.lua.
-- Loaded from hyprland.lua: Hyprland does not auto-load *.lua siblings.

-- Dim inactive windows slightly (0.0 = off, 1.0 = fully dimmed).
hl.config({
  decoration = {
    dim_inactive = true,
    dim_strength = 0.12,
  },
})
