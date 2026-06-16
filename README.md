# dotfiles — portable Claude Code setup

One source of truth for my Claude Code config across WSL machines (home ⇄ company ⇄ any new box).
Hybrid approach: **dotfiles repo + idempotent `bootstrap.sh`** for personal config and CLI tools,
**declarative plugin re-install** (via `claude/settings.json`) for the shareable extensions.

## New machine — one command

```bash
git clone <this-repo-url> ~/dotfiles
~/dotfiles/bootstrap.sh
source ~/.bashrc        # pick up the cch alias
claude                  # first launch fetches + enables all plugins
```

`bootstrap.sh` is idempotent — safe to re-run any time to converge a machine back to this config.

## What it installs / configures

| Step | Action |
|---|---|
| 1 | `uv` + `headroom-ai`, `markitdown`, `markitdown-mcp` |
| 2 | checks `rtk` (prebuilt binary — copy manually if missing) |
| 3 | checks `fnm`/node |
| 4 | copies `settings.json`, `CLAUDE.md`, `RTK.md`, `hooks/`, `skills/` into `~/.claude` (backs up existing) |
| 4b | repairs the machine-specific fnm node path inside `settings.json` |
| 5 | installs `rtk/filters.toml` → `~/.config/rtk/` |
| 6 | sources `shell/aliases.sh` from `~/.bashrc` (the `cch` alias) |
| 7 | registers MCP servers: context7, markitdown, headroom, serena |
| 8 | plugins re-install declaratively on next `claude` launch |
| 9 | prints a verification checklist |

## Layout

```
bootstrap.sh            idempotent orchestrator
claude/
  settings.json         hooks + 6 enabled plugins + marketplaces + prefs (繁中, xhigh)
  CLAUDE.md  RTK.md      global instructions
  hooks/                caveman-*.js + statusline + rtk wiring
  skills/               find-skills, frontend-workflow, shadcn, vercel-react-best-practices, web-design-guidelines
  re-create-mcp.sh      idempotent MCP registration (called by bootstrap)
rtk/filters.toml        rtk filter rules
shell/aliases.sh        cch wrapper
tools/versions.lock     pinned versions reference
```

## NEVER committed (see `.gitignore`)

`~/.claude/.credentials.json` (OAuth token) · `~/.claude.json` (session + per-project state + local/user MCP) ·
`history.jsonl` · `projects/` transcripts · `.env` · `settings.local.json` · runtime caches.
Re-authenticate per machine instead — run `/mcp` inside claude for any OAuth connector.

## Updating the config

Edit files here (or copy fresh from `~/.claude`), commit, push. On other machines: `git pull && ~/dotfiles/bootstrap.sh`.

## Manual steps bootstrap can't do headlessly

- **rtk binary**: prebuilt, no package index — `scp` it from another machine into `~/.local/bin`.
- **OAuth MCP connectors** (Gmail/Drive/Calendar/Notion): account-managed, run `/mcp` inside claude to auth.
