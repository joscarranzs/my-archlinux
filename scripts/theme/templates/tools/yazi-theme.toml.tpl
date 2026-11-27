# Generated Yazi theme: {{palette.name}}
# Regenerate with: ./scripts/theme/apply-theme.py

[manager]
cwd = { fg = "{{accent.primary}}" }
hovered = { fg = "{{onAccent.primary}}", bg = "{{accent.primary}}" }
preview_hovered = { underline = true }
find_keyword = { fg = "{{signal.yellow}}", italic = true }
find_position = { fg = "{{signal.purple}}", bg = "reset", italic = true }
marker_copied = { fg = "{{signal.green}}", bg = "{{signal.green}}" }
marker_cut = { fg = "{{signal.red}}", bg = "{{signal.red}}" }
marker_marked = { fg = "{{signal.yellow}}", bg = "{{signal.yellow}}" }
marker_selected = { fg = "{{accent.primary}}", bg = "{{accent.primary}}" }
tab_active = { fg = "{{onAccent.primary}}", bg = "{{accent.primary}}" }
tab_inactive = { fg = "{{text.ink}}", bg = "{{surface.raised}}" }
border_style = { fg = "{{surface.line}}" }

[status]
separator_open = ""
separator_close = ""
mode_normal = { fg = "{{onAccent.primary}}", bg = "{{accent.primary}}", bold = true }
mode_select = { fg = "{{onAccent.signal}}", bg = "{{signal.green}}", bold = true }
mode_unset = { fg = "{{onAccent.signal}}", bg = "{{signal.red}}", bold = true }
progress_label = { fg = "{{text.ink}}", bold = true }
progress_normal = { fg = "{{accent.primary}}", bg = "{{surface.raised}}" }
progress_error = { fg = "{{signal.red}}", bg = "{{surface.raised}}" }
perm_type = { fg = "{{accent.primary}}" }
perm_read = { fg = "{{signal.green}}" }
perm_write = { fg = "{{signal.yellow}}" }
perm_exec = { fg = "{{signal.red}}" }
perm_sep = { fg = "{{surface.line}}" }

[input]
border = { fg = "{{accent.primary}}" }
title = { fg = "{{accent.primary}}" }
value = { fg = "{{text.ink}}" }
selected = { reversed = true }

[select]
border = { fg = "{{accent.primary}}" }
active = { fg = "{{signal.purple}}" }
inactive = { fg = "{{text.ink}}" }

[which]
mask = { bg = "{{surface.raised}}" }
cand = { fg = "{{accent.primary}}" }
rest = { fg = "{{surface.line}}" }
desc = { fg = "{{text.ink}}" }
separator = "  "
separator_style = { fg = "{{surface.line}}" }

[help]
on = { fg = "{{signal.purple}}" }
run = { fg = "{{accent.primary}}" }
desc = { fg = "{{text.ink}}" }
hovered = { bg = "{{surface.raised}}", bold = true }
footer = { fg = "{{surface.raised}}", bg = "{{text.ink}}" }

[filetype]
rules = [
  { url = "*/", fg = "{{accent.primary}}" },
  { mime = "image/*", fg = "{{signal.yellow}}" },
  { mime = "video/*", fg = "{{signal.purple}}" },
  { mime = "audio/*", fg = "{{signal.green}}" },
  { mime = "application/zip", fg = "{{signal.red}}" },
  { mime = "application/gzip", fg = "{{signal.red}}" },
  { mime = "application/x-tar", fg = "{{signal.red}}" },
  { mime = "application/x-bzip", fg = "{{signal.red}}" },
  { mime = "application/x-7z-compressed", fg = "{{signal.red}}" },
  { mime = "application/x-rar", fg = "{{signal.red}}" },
  { mime = "application/pdf", fg = "{{signal.orange}}" },
  { url = "*", fg = "{{text.ink}}" },
  { url = ".*", fg = "{{surface.line}}" },
]
