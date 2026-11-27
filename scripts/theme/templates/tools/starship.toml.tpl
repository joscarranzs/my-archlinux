# {{palette.name}}: {{palette.description}}

add_newline = true

# `ip` answers in ~1ms normally, but it can stall for half a second while the
# network stack reconverges (right after a resume, or during a wifi roam) and the
# default 500ms cap then prints a warning on every prompt. Give it headroom: the
# prompt only pays for it when the command is actually slow.
command_timeout = 1500

[character]
success_symbol = "[❯](bold {{accent.primaryInk}})"
error_symbol = "[❯](bold {{signal.red}})"

[directory]
truncation_length = 4
truncate_to_repo = true
style = "bold {{text.ink}}"

[git_branch]
symbol = " "
style = "bold {{accent.primaryInk}}"

[git_status]
style = "bold {{text.inkMuted}}"

# Icons por estado de git (color inline, paleta {{palette.name}})
conflicted = "[bold {{signal.red}}]="
ahead = "[bold {{accent.primaryInk}}]⇡${count}"
behind = "[bold {{accent.primaryInk}}]⇣${count}"
diverged = "[bold {{accent.neutral}}]⇕"
untracked = "[bold {{accent.primaryInk}}]?"
stashed = "[bold {{signal.yellow}}]📦"
modified = "[bold {{signal.red}}]!"
staged = "[bold {{accent.secondary}}]++$count"
renamed = "[bold {{accent.neutral}}]»"
deleted = "[bold {{signal.red}}]✘"

[cmd_duration]
min_time = 500
format = "took [$duration](bold {{accent.primaryInk}}) "

[python]
symbol = " "
style = "bold {{accent.primaryInk}}"

[nodejs]
symbol = " "
style = "bold {{accent.tertiary}}"

[rust]
symbol = " "
style = "bold {{signal.red}}"

[golang]
symbol = " "
style = "bold {{accent.primaryDeep}}"
