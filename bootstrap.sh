#!/usr/bin/env bash
# bootstrap.sh — idempotently reproduce the Claude Code setup on a fresh WSL/Linux box.
# Safe to re-run: every step is guarded.
#   real run:  ~/claude-code-config/bootstrap.sh
#   preview :  DRY_RUN=1 ~/claude-code-config/bootstrap.sh   (prints every change, mutates nothing)
# Repo location is configurable via $CCC_DIR (default: $HOME/claude-code-config).
# (NOT named CLAUDE_CONFIG_DIR on purpose — that var is Claude Code's own config dir.)
set -euo pipefail

DOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLAUDE_SRC="$DOT/claude"
TS="$(date +%Y%m%d-%H%M%S)"
DRY="${DRY_RUN:-0}"

c_g="\033[1;32m"; c_y="\033[1;33m"; c_r="\033[1;31m"; c_0="\033[0m"
log()  { printf "${c_g}[bootstrap]${c_0} %s\n" "$*"; }
warn() { printf "${c_y}[warn]${c_0} %s\n" "$*"; }
err()  { printf "${c_r}[err]${c_0} %s\n" "$*"; }
# run: execute a mutating command, or just print it in DRY mode
run()  { if [ "$DRY" = 1 ]; then printf "${c_y}[dry-run]${c_0} %s\n" "$*"; else "$@"; fi; }
backup(){ [ -e "$1" ] || return 0; run cp -a "$1" "$1.bak-$TS"; }

[ "$DRY" = 1 ] && warn "DRY-RUN — nothing will be changed."
command -v git >/dev/null || { err "git required"; exit 1; }
export PATH="$HOME/.local/bin:$PATH"

# ── 1. uv + python CLI tools ────────────────────────────────────────────────
if ! command -v uv >/dev/null; then
  log "uv missing -> install (astral)"
  run sh -c 'curl -LsSf https://astral.sh/uv/install.sh | sh'
  export PATH="$HOME/.local/bin:$PATH"
fi
ensure_uv_tool(){ # $1 = package name (as uv lists it), $2 = install spec
  if uv tool list 2>/dev/null | grep -q "^$1 "; then log "uv tool $1 present"
  else log "uv tool install $2"; run uv tool install "$2"; fi
}
ensure_uv_tool "markitdown"     "markitdown"
ensure_uv_tool "markitdown-mcp" "markitdown-mcp"
[ "$DRY" = 1 ] || uv tool update-shell 2>/dev/null || true

# ── 2. node via fnm (Claude Code + npx tools invoke node) ───────────────────
command -v fnm >/dev/null && log "fnm present" \
  || warn "fnm MISSING — curl -fsSL https://fnm.vercel.app/install | bash ; then 'fnm install 24'"

# ── 3. Claude config into ~/.claude ─────────────────────────────────────────
run mkdir -p ~/.claude ~/.claude/skills
for f in settings.json CLAUDE.md; do
  [ -f "$CLAUDE_SRC/$f" ] || continue
  backup ~/.claude/"$f"
  run cp "$CLAUDE_SRC/$f" ~/.claude/"$f"
  log "install ~/.claude/$f"
done
# skills: additive + symlink-safe. Keep whatever already resolves (incl. company's
# symlinks into ~/.agents/skills); only install genuinely missing/broken ones.
# Machine-only skills (not in repo) are never touched.
for sk in "$CLAUDE_SRC"/skills/*/; do
  name="$(basename "$sk")"; tgt="$HOME/.claude/skills/$name"
  if [ -d "$tgt" ] && [ -n "$(ls -A "$tgt" 2>/dev/null)" ]; then log "skill present: $name (skip)"; continue; fi
  if [ -e "$tgt" ] || [ -L "$tgt" ]; then backup "$tgt"; run rm -rf "$tgt"; fi
  run cp -a "$sk" "$tgt"
  log "skill installed: $name"
done

# ── 4. ccstatusline config (the statusLine npx tool's display config) ───────
if [ -f "$DOT/ccstatusline/settings.json" ]; then
  run mkdir -p ~/.config/ccstatusline
  backup ~/.config/ccstatusline/settings.json
  run cp "$DOT/ccstatusline/settings.json" ~/.config/ccstatusline/settings.json
  log "install ~/.config/ccstatusline/settings.json"
fi

# ── 5. shell aliases — source via configurable CCC_DIR ──────────────────────
# CCC_DIR (not CLAUDE_CONFIG_DIR!) locates the repo to source aliases.sh; naming
# it CLAUDE_CONFIG_DIR would hijack Claude Code's own config dir to the repo.
if grep -qE 'CCC_DIR=|CLAUDE_CONFIG_DIR=' ~/.bashrc 2>/dev/null; then
  log "CCC_DIR block already in ~/.bashrc"
elif [ "$DRY" = 1 ]; then
  printf "${c_y}[dry-run]${c_0} append CCC_DIR block to ~/.bashrc\n"
else
  cat >> ~/.bashrc <<'BLOCK'

# claude-code-config (override CCC_DIR to relocate the repo)
export CCC_DIR="${CCC_DIR:-$HOME/claude-code-config}"
[ -f "$CCC_DIR/shell/aliases.sh" ] && . "$CCC_DIR/shell/aliases.sh"
BLOCK
  log "added CCC_DIR block to ~/.bashrc"
fi

# ── 6. MCP servers (idempotent; honors DRY_RUN) ─────────────────────────────
if command -v claude >/dev/null; then
  DRY_RUN="$DRY" bash "$CLAUDE_SRC/re-create-mcp.sh" || warn "re-create-mcp.sh error; check 'claude mcp list'"
else warn "claude not found — skip MCP; install Claude Code then run claude/re-create-mcp.sh"; fi

# ── 7. plugins: declarative via settings.json (re-clone on next launch) ─────
log "plugins re-install declaratively from settings.json on next 'claude' start."

# ── 8. verify (read-only) ───────────────────────────────────────────────────
echo; log "── verify ──────────────────────────────"
printf "  claude:     %s\n" "$(claude --version 2>&1 | head -1)"
printf "  markitdown: %s\n" "$(command -v markitdown || echo MISSING)"
printf "  node:       %s\n" "$(node --version 2>&1 | head -1)"
echo; log "MCP servers:"; claude mcp list 2>&1 | sed 's/^/  /' || true
echo
[ "$DRY" = 1 ] && { warn "DRY-RUN complete — re-run without DRY_RUN=1 to apply."; exit 0; }
log "DONE. New shell: 'source ~/.bashrc'. First 'claude' launch fetches plugins."
log "Any MCP ✗/Pending -> run /mcp inside claude to (re)authenticate."
