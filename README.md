# claude-code-config — portable Claude Code setup

One source of truth for my Claude Code config across machines — WSL/Linux **and native Windows** (home ⇄ company ⇄ any new box).
Hybrid approach: **config repo + idempotent bootstrap** (`bootstrap.sh` for WSL/Linux, `bootstrap.ps1` for native Windows) for personal config and CLI tools,
**declarative plugin re-install** (via `claude/settings.json`) for the shareable extensions.

## New machine — one command

```bash
git clone git@github.com:chuenchen309/claude-code-config.git ~/claude-code-config
~/claude-code-config/bootstrap.sh
source ~/.bashrc        # pick up the cch alias
claude                  # first launch fetches + enables all plugins
```

> Want the repo somewhere else? Clone wherever you like and set `CCC_DIR` to that path
> (default `$HOME/claude-code-config`) — `bootstrap.sh` self-locates, and the `~/.bashrc` block honors the var.
> (The var is deliberately **not** `CLAUDE_CONFIG_DIR` — that is Claude Code's own config-dir
> variable, and pointing it at the repo hijacks claude away from `~/.claude`.)

`bootstrap.sh` is idempotent — safe to re-run any time to converge a machine back to this config.

## Native Windows — one command

For a company box where Claude Code runs on **native Windows** (`%USERPROFILE%\.claude`), not WSL:

```powershell
git clone git@github.com:chuenchen309/claude-code-config.git $HOME\claude-code-config
pwsh -File $HOME\claude-code-config\bootstrap.ps1   # preview first: $env:DRY_RUN=1; pwsh -File ...\bootstrap.ps1
# open a NEW PowerShell, then:
claude                                              # first launch fetches + enables all plugins
```

`bootstrap.ps1` is the Windows port of `bootstrap.sh` — same idempotent, re-runnable contract. It diverges from the Linux flow only where the OS forces it:

| Area | Windows behavior |
|---|---|
| caveman hooks | settings.json `command` rewritten from the Linux fnm node path to portable **exec form** `{"command":"node","args":["C:/Users/<you>/.claude/hooks/…"]}` (forward slashes; works in Git Bash *and* PowerShell). |
| `rtk hook claude` | **dropped** from settings.json — rtk's hook integration is WSL-only (needs a Unix shell); a missing `rtk` would error on every Bash call. |
| MCP servers | registered with `claude mcp add-json` (sidesteps the Windows `-- cmd /c` / `--from` arg-parsing bugs); context7 via `cmd /c npx`, markitdown via absolute `%USERPROFILE%\.local\bin\markitdown-mcp.exe`, serena via `uv tool run` (no separate `uvx.exe` needed). |
| headroom | best-effort — its sdist needs Rust/maturin to build on Windows; if the build fails, the headroom MCP server **and** `cch` are skipped (non-fatal). |
| `cch` alias | installed as a PowerShell `$PROFILE` function (no `~/.bashrc`), only when headroom is present. |
| rtk / filters.toml | skipped (rtk ships a Linux binary). |

**Prereqs on the Windows box:** Node.js on PATH (Claude Code + caveman hooks need it), Git for Windows (enables the Bash tool + Git Bash hook execution), and PowerShell 7 recommended (`winget install Microsoft.PowerShell`). `bootstrap.ps1` installs `uv` itself if missing.

## What it installs / configures

| Step | Action |
|---|---|
| 1 | `uv` + `headroom-ai`, `markitdown`, `markitdown-mcp` |
| 2 | checks `rtk` (prebuilt binary — copy manually if missing) |
| 3 | checks `fnm`/node |
| 4 | copies `settings.json`, `CLAUDE.md`, `RTK.md`, `hooks/`, `skills/` into `~/.claude` (backs up existing) |
| 4b | repairs the machine-specific fnm node path inside `settings.json` |
| 5 | installs `rtk/filters.toml` → `~/.config/rtk/` |
| 5b | installs `ccstatusline/settings.json` → `~/.config/ccstatusline/` |
| 6 | adds a `CCC_DIR` block to `~/.bashrc` that sources `shell/aliases.sh` (the `cch` alias) |
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
ccstatusline/settings.json  statusline display config (powerline nord-aurora)
shell/aliases.sh        cch wrapper
tools/versions.lock     pinned versions reference
```

## NEVER committed (see `.gitignore`)

`~/.claude/.credentials.json` (OAuth token) · `~/.claude.json` (session + per-project state + local/user MCP) ·
`history.jsonl` · `projects/` transcripts · `.env` · `settings.local.json` · runtime caches.
Re-authenticate per machine instead — run `/mcp` inside claude for any OAuth connector.

## Updating the config

Edit files here (or copy fresh from `~/.claude`), commit, push. On other machines: `git pull && ~/claude-code-config/bootstrap.sh`.

## Manual steps bootstrap can't do headlessly

- **rtk binary**: prebuilt, no package index — `scp` it from another machine into `~/.local/bin`.
- **OAuth MCP connectors** (Gmail/Drive/Calendar/Notion): account-managed, run `/mcp` inside claude to auth.
