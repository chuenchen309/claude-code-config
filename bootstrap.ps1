#!/usr/bin/env pwsh
# bootstrap.ps1 — idempotently reproduce the Claude Code setup on a NATIVE WINDOWS box.
# Windows port of bootstrap.sh (which targets WSL/Linux). Safe to re-run.
#   real run:  pwsh -File .\bootstrap.ps1
#   preview :  $env:DRY_RUN=1; pwsh -File .\bootstrap.ps1   (prints changes, mutates nothing)
# Repo location is auto-detected from this script's own path.
#
# What this does differently from bootstrap.sh (because the box is native Windows,
# NOT WSL):
#   * registers MCP servers via re-create-mcp.ps1 (claude mcp add-json).
$ErrorActionPreference = 'Stop'
$DRY       = $env:DRY_RUN -eq '1'
$Repo      = Split-Path -Parent $MyInvocation.MyCommand.Path
$ClaudeSrc = Join-Path $Repo 'claude'
$ClaudeDir = Join-Path $HOME '.claude'
$Ts        = Get-Date -Format 'yyyyMMdd-HHmmss'

function Log($m)  { Write-Host "[bootstrap] $m" -ForegroundColor Green }
function Warn($m) { Write-Host "[warn] $m"      -ForegroundColor Yellow }
function Err($m)  { Write-Host "[err] $m"       -ForegroundColor Red }
function Backup($p) {
  if (Test-Path $p) {
    if ($DRY) { Warn "[dry-run] backup $p -> $p.bak-$Ts" }
    else { Copy-Item -LiteralPath $p "$p.bak-$Ts" -Recurse -Force }
  }
}

if ($DRY) { Warn 'DRY-RUN - nothing will be changed.' }

# Require PowerShell 7+ — Windows PowerShell 5.1 mangles the embedded-quote JSON
# argument that re-create-mcp.ps1 hands to `claude mcp add-json`.
if ($PSVersionTable.PSVersion.Major -lt 7) {
  Err 'Run under PowerShell 7+ (pwsh -File bootstrap.ps1). Install: winget install Microsoft.PowerShell'
  exit 1
}
# Don't let a nonzero native exit (uv/claude/node returning non-zero) abort the
# script under Stop on PS 7.4+ — we tolerate/Warn explicitly, matching bootstrap.sh.
$PSNativeCommandUseErrorActionPreference = $false

# ── 1. uv + python CLI tools ────────────────────────────────────────────────
if (-not (Get-Command uv -ErrorAction SilentlyContinue)) {
  Log 'uv missing -> install (astral)'
  if (-not $DRY) { powershell -ExecutionPolicy ByPass -c "irm https://astral.sh/uv/install.ps1 | iex" }
  $env:Path = "$HOME\.local\bin;$env:Path"
}
function Ensure-UvTool($listName, $spec) {
  if ((uv tool list 2>$null) -match "^$listName ") { Log "uv tool $listName present" }
  else { Log "uv tool install $spec"; if (-not $DRY) { uv tool install $spec } }
}
Ensure-UvTool 'markitdown'     'markitdown'
Ensure-UvTool 'markitdown-mcp' 'markitdown-mcp'

# ── 2. node (Claude Code needs it) ──────────────────────────────────────────
if (Get-Command node -ErrorAction SilentlyContinue) { Log "node present: $(node --version)" }
else { Warn 'node MISSING - install Node.js (https://nodejs.org, winget, or fnm). Claude Code needs it.' }

# ── 3. Claude config into ~/.claude ─────────────────────────────────────────
if (-not $DRY) {
  New-Item -ItemType Directory -Force -Path $ClaudeDir, (Join-Path $ClaudeDir 'skills') | Out-Null
}

# settings.json needs no transform on Windows — it carries no hooks/paths, so it
# copies verbatim alongside CLAUDE.md.
foreach ($f in 'CLAUDE.md', 'settings.json') {
  $src = Join-Path $ClaudeSrc $f
  if (-not (Test-Path $src)) { continue }
  $dst = Join-Path $ClaudeDir $f
  Backup $dst
  if (-not $DRY) { Copy-Item -LiteralPath $src $dst -Force }
  Log "install ~/.claude/$f"
}

# skills: additive — keep whatever already resolves; only install missing/empty ones
Get-ChildItem -Directory -Path (Join-Path $ClaudeSrc 'skills') -ErrorAction SilentlyContinue | ForEach-Object {
  $name = $_.Name
  $tgt  = Join-Path $ClaudeDir "skills\$name"
  if ((Test-Path $tgt) -and (Get-ChildItem -Force -ErrorAction SilentlyContinue $tgt)) { Log "skill present: $name (skip)"; return }
  if (Test-Path $tgt) { Backup $tgt; if (-not $DRY) { Remove-Item $tgt -Recurse -Force } }
  if (-not $DRY) { Copy-Item -LiteralPath $_.FullName $tgt -Recurse -Force }
  Log "skill installed: $name"
}

# ── 4. ccstatusline config ──────────────────────────────────────────────────
# ccstatusline reads os.homedir()/.config/ccstatusline/settings.json on ALL OSes
# (hardcoded; no %APPDATA%, no XDG). On Windows that is %USERPROFILE%\.config\...
$ccSrc = Join-Path $Repo 'ccstatusline\settings.json'
if (Test-Path $ccSrc) {
  $ccDir = Join-Path $HOME '.config\ccstatusline'
  if (-not $DRY) { New-Item -ItemType Directory -Force -Path $ccDir | Out-Null }
  $ccDst = Join-Path $ccDir 'settings.json'
  Backup $ccDst
  if (-not $DRY) { Copy-Item -LiteralPath $ccSrc $ccDst -Force }
  Log 'install ~/.config/ccstatusline/settings.json'
}

# ── 5. MCP servers (idempotent; honors DRY_RUN via env) ─────────────────────
if (Get-Command claude -ErrorAction SilentlyContinue) {
  try { & (Join-Path $ClaudeSrc 're-create-mcp.ps1') }
  catch { Warn "re-create-mcp.ps1 error; check 'claude mcp list'" }
}
else { Warn 'claude not found - skip MCP; install Claude Code then run claude\re-create-mcp.ps1' }

# ── 6. plugins: declarative via settings.json (re-clone on next launch) ─────
Log "plugins re-install declaratively from settings.json on next 'claude' start."

# ── 7. verify (read-only) ───────────────────────────────────────────────────
Write-Host ''; Log '-- verify -------------------------------'
# Guard each probe with Get-Command so a tolerated-missing binary prints MISSING
# instead of throwing CommandNotFoundException and aborting the summary.
function Probe($label, $name) {
  if (Get-Command $name -ErrorAction SilentlyContinue) {
    Write-Host ("  {0,-11} {1}" -f "${label}:", (& $name --version 2>&1 | Select-Object -First 1))
  }
  else { Write-Host ("  {0,-11} MISSING" -f "${label}:") }
}
Probe 'claude'     'claude'
Probe 'uv'         'uv'
Probe 'markitdown' 'markitdown'
Probe 'node'       'node'
# the actual .exe files the MCP configs spawn — a naming/install miss here fails
# the server silently while the CLI probes above still report OK.
$binDir = (Get-Command uv -ErrorAction SilentlyContinue).Source
$binDir = if ($binDir) { Split-Path $binDir } else { Join-Path $HOME '.local\bin' }
foreach ($exe in 'markitdown-mcp.exe', 'uv.exe') {   # serena uses uv.exe (uv tool run)
  $p = Join-Path $binDir $exe
  if (Test-Path $p) { Write-Host "  mcp bin:    OK $exe" } else { Warn "MCP server binary missing: $p" }
}
Write-Host ''; Log 'MCP servers:'
if (Get-Command claude -ErrorAction SilentlyContinue) { claude mcp list 2>&1 | ForEach-Object { Write-Host "  $_" } }
Write-Host ''
if ($DRY) { Warn 'DRY-RUN complete - re-run without $env:DRY_RUN to apply.'; exit 0 }
Log "DONE. Open a NEW PowerShell. First 'claude' launch fetches plugins."
Log "Any MCP X/Pending -> run /mcp inside claude to (re)authenticate."
