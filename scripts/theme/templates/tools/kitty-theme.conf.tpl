# Generated theme: {{palette.name}}
# Colours come from theme/colors.json. The 16 ANSI slots are the palette's own
# terminal colours. The `signal.*` roles are tuned separately to carry text on
# the surfaces, which is why the terminal skips them here.
foreground {{text.ink}}
background {{surface.base}}
selection_foreground {{onAccent.primary}}
selection_background {{accent.primary}}
cursor {{accent.primary}}
cursor_text_color {{onAccent.primary}}
url_color {{accent.primaryInk}}

color0 {{ansi.black}}
color8 {{ansi.brightBlack}}
color1 {{ansi.red}}
color9 {{ansi.brightRed}}
color2 {{ansi.green}}
color10 {{ansi.brightGreen}}
color3 {{ansi.yellow}}
color11 {{ansi.brightYellow}}
color4 {{ansi.blue}}
color12 {{ansi.brightBlue}}
color5 {{ansi.magenta}}
color13 {{ansi.brightMagenta}}
color6 {{ansi.cyan}}
color14 {{ansi.brightCyan}}
color7 {{ansi.white}}
color15 {{ansi.brightWhite}}

# 16-231: the surface -> ink axis, 232-255: the same axis extended past both
# poles. Both are generated from the tokens (theme/apply-theme.py) so they mirror
# with the palette instead of being a hand-written dark ramp that goes invisible
# the day the surfaces turn light.
{{ramp.terminal}}
