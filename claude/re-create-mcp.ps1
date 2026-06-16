#!/usr/bin/env pwsh
# re-create-mcp.ps1 — idempotently register user-scoped MCP servers on NATIVE WINDOWS.
# Port of re-create-mcp.sh. None of these carry secrets; OAuth connectors
# (Gmail/Drive/etc.) are account-managed — do NOT add them here.
#
# Uses `claude mcp add-json` (not `claude mcp add -- ...`) on purpose: the `--`
# positional form mangles tokens on Windows — it rewrites `cmd /c` -> `cmd C:/`
# (claude-code #20061) and drops serena's `--from` (serena #323). Passing a JSON
# blob sidesteps both parsers.
#
# Set $env:DRY_RUN=1 to preview without changing anything.
$ErrorActionPreference = 'Stop'
$DRY = $env:DRY_RUN -eq '1'

# Windows PowerShell 5.1 does NOT round-trip a native-command argument that
# contains embedded double-quotes (our ConvertTo-Json blob), so add-json would
# receive mangled JSON and silently store garbage. Require PowerShell 7+
# (winget install Microsoft.PowerShell), where it can be passed intact.
if ($PSVersionTable.PSVersion.Major -lt 7) {
  Write-Host 'Run under PowerShell 7+ (pwsh) - Windows PowerShell 5.1 mangles the JSON argument to claude mcp add-json.'
  exit 1
}
# Pass embedded quotes through to native commands verbatim (default on 7.3+; set
# explicitly to cover 7.0-7.2). And don't let a nonzero native exit throw under
# Stop - we check $LASTEXITCODE ourselves, mirroring the bash `|| warn` contract.
$PSNativeCommandArgumentPassing = 'Standard'
$PSNativeCommandUseErrorActionPreference = $false

if (-not (Get-Command claude -ErrorAction SilentlyContinue)) {
  Write-Host 'claude not on PATH'; exit 1
}

# Resolve the uv tool bin dir (where uvx.exe / headroom.exe / markitdown-mcp.exe
# land). PATH inheritance after `uv tool update-shell` is flaky on Windows, so we
# bake absolute .exe paths into the MCP configs instead of relying on bare names.
$BinDir = $null
if (Get-Command uv -ErrorAction SilentlyContinue) {
  try { $BinDir = (uv tool dir --bin 2>$null | Select-Object -First 1).Trim() } catch {}
}
if (-not $BinDir) { $BinDir = Join-Path $HOME '.local\bin' }
$BinFwd = ($BinDir -replace '\\', '/')   # forward slashes — safe inside JSON

function Add-Mcp($name, $config) {
  $exists = $false
  try { claude mcp get $name *> $null; if ($LASTEXITCODE -eq 0) { $exists = $true } } catch {}
  if ($exists) { Write-Host "[mcp] $name already exists - skip"; return }
  $json = ($config | ConvertTo-Json -Compress -Depth 6)
  if ($DRY) { Write-Host "[mcp][dry-run] claude mcp add-json $name '$json' -s user"; return }
  Write-Host "[mcp] add $name"
  claude mcp add-json $name $json -s user
  if ($LASTEXITCODE -ne 0) { Write-Host "[mcp] WARN: add $name failed (exit $LASTEXITCODE) - re-run or add manually" }
}

# context7: npx is npx.cmd (a batch shim) — child_process.spawn can't launch it
# directly, so it must go through `cmd /c`. The .exe-based servers below do not.
Add-Mcp 'context7'   @{ command = 'cmd'; args = @('/c', 'npx', '-y', '@upstash/context7-mcp') }
Add-Mcp 'markitdown' @{ command = "$BinFwd/markitdown-mcp.exe" }
# serena via `uv tool run` (= uvx) — uv ships uv.exe but not always a separate
# uvx.exe on Windows, and `uv tool run` is always present.
Add-Mcp 'serena'     @{ command = "$BinFwd/uv.exe"; args = @('tool', 'run', '--from', 'git+https://github.com/oraios/serena', 'serena', 'start-mcp-server', '--project-from-cwd', '--context', 'claude-code') }
# headroom-ai often fails to build on native Windows (sdist needs Rust/maturin, no
# prebuilt wheel) — only register it if its .exe actually installed.
if (Test-Path (Join-Path $BinDir 'headroom.exe')) {
  Add-Mcp 'headroom' @{ command = "$BinFwd/headroom.exe"; args = @('mcp', 'serve') }
}
else { Write-Host '[mcp] headroom skipped - headroom.exe not installed (needs Rust to build on Windows)' }

Write-Host "[mcp] done - run 'claude mcp list' to verify (X/Pending = run /mcp inside claude)."
