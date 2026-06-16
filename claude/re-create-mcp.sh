#!/usr/bin/env bash
# Idempotently register user-scoped MCP servers. Safe to re-run.
# None of these carry secrets (env is empty); OAuth connectors (Gmail/Drive/etc.)
# are account-managed and reappear after login — do NOT add them here.
set -euo pipefail
DRY="${DRY_RUN:-0}"

command -v claude >/dev/null || { echo "claude not on PATH"; exit 1; }

add_mcp() {
  local name="$1"; shift
  if claude mcp get "$name" >/dev/null 2>&1; then
    echo "[mcp] $name already exists — skip"
  elif [ "$DRY" = 1 ]; then
    echo "[mcp][dry-run] would add: claude mcp add $name -s user -- $*"
  else
    echo "[mcp] add $name"
    claude mcp add "$name" -s user -- "$@"
  fi
}

add_mcp context7   npx -y @upstash/context7-mcp
add_mcp markitdown "$HOME/.local/bin/markitdown-mcp"
add_mcp headroom   headroom mcp serve
add_mcp serena     uvx --from git+https://github.com/oraios/serena serena start-mcp-server --project-from-cwd --context claude-code

echo "[mcp] done — run 'claude mcp list' to verify (✗/Pending = run /mcp inside claude)."
