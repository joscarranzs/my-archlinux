# Hermes runtime

## Paths and profile

- `~/.hermes/` holds `config.yaml` (~113 KB), `.env`, `state.db`, `kanban.db`, `sessions/`, `memories/`, `cache/`, `logs/`, `backups/`, `gateway.sock`, `gateway.pid`, `gateway.lock` and `plugins/`.
- Symlinks into dotfiles: `skills`, `skins`, `SOUL.md` and the three user plugins. No `profiles/` directory exists at present: the implicit default profile is in use.
- `hermes` is a shim in `~/.hermes/hermes-agent/.hermes/bin/` running a standalone CPython 3.14 from `~/.hermes/tools/`, with the agent checkout on `sys.path`. There is no separate venv site-packages.

## Plugins and skills

- Enabled: official `advanced-delegation` 1.2.0, user `caveman-shrink` 0.1.1, `caveman-voice` 0.3.0, `task-intake` 0.1.0.
- Reload without restart: send `reload-plugins` over `~/.hermes/gateway.sock`. Commands, transforms and hooks go live at once; tools and prompt changes wait for the next session; MCP waits for `mcp.reload`. `hermes plugins install/enable` triggers the same force re-discovery.
- Skill tree: `~/.hermes/skills/` -> `~/.dotfiles/config/hermes/skills/`. Only `user/` is committed; `config/hermes/skills/.gitignore` excludes every other top-level dir. Hub dirs hold only `DESCRIPTION.md`.
- Current user skills: `kanban` and `how-to-solve-problems`; other user skills were deleted at the user's order on 2026-11-27. Recover old ones with `git checkout <sha> -- config/hermes/skills/user`.
- Skill bodies stay under ~5k tokens; depth belongs in `references/`. A loaded body is re-read on every API call.

## Task board and docs

- `~/.hermes/kanban.db` is the board; `task_intake` is the compact read/file tool and `~/.scripts/session/kanban-feed.py` is the panel helper. Full rules live in the `kanban` skill.
- `session_search` searches past conversations in `state.db`; it is not the Task panel. Internal agent steps use `todo_list`.
- Handoffs: `~/.dotfiles/docs/handoff-<YYYY-MM-DD>.md` from `docs/handoff-TEMPLATE.md`. Re-run the verification block at the top before trusting any number; section 6 is never empty.

## Voice, budget, backups

- STT is local (faster-whisper, Silero VAD, Spanish-biased prompt); TTS uses Nous with an Edge fallback. `gateway_voice_mode.json` pins several sessions to voice-only.
- `~/.scripts/session/tokens.py` prints one JSON with Nous balance and OpenCode Go plan windows. It never redeems the rotating refresh token itself: it calls `hermes auth refresh nous`. Balance, spend and renewal dates are volatile; re-run the script.
- Budget: `hermes insights --days 7` and `hermes usage`; check `/usage` past ~50 turns. Cache-read dominates the bill; output is noise.
- Backups under `~/.hermes/backups/`: `webapps-20261125/` (two white icons), kanban and state DB snapshots, config backups. `~/.hermes/` also carries many `config.yaml.bak-*` files.
- Quirks: `vision_analyze` works with small crops, not full screens. Wikimedia downloads return 429 when consecutive; wait 8-10 s. Browser or gateway login walls use `browser_vault`; never type secrets from chat.
