# Generated config (theme values from theme/*.json)
font_family      {{typography.fonts.mono}}
bold_font        auto
italic_font      auto
bold_italic_font auto
font_size        {{typography.sizes.terminal}}

# Copy on select
copy_on_select clipboard

# Clear scrollback (not just visible screen)
map ctrl+shift+k clear_terminal scrollback active

# Theme (generated)
include theme.conf

# Cursor: block at all times. Shell integration would otherwise switch it to a
# blinking bar at the prompt (its PS1 suffix emits `\e[5 q`), which no
# cursor_shape setting can win against — the shape option only sets the default.
cursor_shape block
shell_integration no-cursor

# Padding
window_padding_width {{look.spacing.sm}}

# Opacity. Fully opaque: a terminal that shows the desktop through its own text
# is harder to read and costs a compositor pass on every frame, and the lightest
# surface the ink was measured against is the palette's, not the wallpaper's.
# dynamic_background_opacity is off on purpose — it is the runtime escape hatch
# that would let a key combo put the transparency back.
background_opacity {{look.opacity.terminal}}
dynamic_background_opacity no
