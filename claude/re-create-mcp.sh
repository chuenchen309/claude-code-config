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

# context7 works anonymously but is rate-limited; export CONTEXT7_API_KEY to get
# your own quota. The key is a secret — it is injected here, never committed.
c7=(npx -y @upstash/context7-mcp)
if [ -n "${CONTEXT7_API_KEY:-}" ]; then
  c7+=(--api-key "$CONTEXT7_API_KEY")
else
  echo "[mcp] note: CONTEXT7_API_KEY unset — registering context7 anonymously (rate-limited)"
fi
add_mcp context7   "${c7[@]}"
add_mcp markitdown "$HOME/.local/bin/markitdown-mcp"

echo "[mcp] done — run 'claude mcp list' to verify (✗/Pending = run /mcp inside claude)."
