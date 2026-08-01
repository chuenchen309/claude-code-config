#!/usr/bin/env pwsh
# re-create-mcp.ps1 — idempotently register user-scoped MCP servers on NATIVE WINDOWS.
# Port of re-create-mcp.sh. None of these carry secrets; OAuth connectors
# (Gmail/Drive/etc.) are account-managed — do NOT add them here.
#
# Uses `claude mcp add-json` (not `claude mcp add -- ...`) on purpose: the `--`
# positional form mangles tokens on Windows — it rewrites `cmd /c` -> `cmd C:/`
# (claude-code #20061). Passing a JSON blob sidesteps that parser.
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

# Resolve the uv tool bin dir (where markitdown-mcp.exe
# lands). PATH inheritance after `uv tool update-shell` is flaky on Windows, so we
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

Write-Host "[mcp] done - run 'claude mcp list' to verify (X/Pending = run /mcp inside claude)."
