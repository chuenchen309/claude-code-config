#!/usr/bin/env pwsh
# bootstrap.ps1 — idempotently reproduce the Claude Code setup on a NATIVE WINDOWS box.
# Windows port of bootstrap.sh (which targets WSL/Linux). Safe to re-run.
#   real run:  pwsh -File .\bootstrap.ps1
#   preview :  $env:DRY_RUN=1; pwsh -File .\bootstrap.ps1   (prints changes, mutates nothing)
# Repo location is auto-detected from this script's own path.
#
# What this does differently from bootstrap.sh (because the box is native Windows,
# NOT WSL):
#   * rewrites the two caveman hooks in settings.json from the hardcoded Linux fnm
#     node path (shell form) to portable exec form  {command:"node", args:[...]}
#     with a Windows hooks path in forward slashes.
#   * DROPS the `rtk hook claude` PreToolUse hook — rtk's hook integration is
#     WSL-only (Unix shell required); a missing rtk would error on every Bash call.
#   * registers MCP servers via re-create-mcp.ps1 (claude mcp add-json).
#   * installs the `cch` helper as a PowerShell $PROFILE function (no ~/.bashrc).
$ErrorActionPreference = 'Stop'
$DRY       = $env:DRY_RUN -eq '1'
$Repo      = Split-Path -Parent $MyInvocation.MyCommand.Path
$ClaudeSrc = Join-Path $Repo 'claude'
$ClaudeDir = Join-Path $HOME '.claude'
$Ts        = Get-Date -Format 'yyyyMMdd-HHmmss'
$HomeFwd   = ($HOME -replace '\\', '/')

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
# headroom needs the '[proxy]' extra (cch wrapper) + the standalone 'mcp' SDK
# ('headroom mcp serve'). On native Windows the sdist often won't build (needs
# Rust/maturin, no prebuilt wheel) — treat failure as non-fatal: cch + the
# headroom MCP server are then simply skipped (like rtk).
Log 'ensure headroom-ai ([proxy] extra + mcp sdk)'
if (-not $DRY) {
  uv tool install 'headroom-ai[proxy]==0.25.0' --with mcp
  if ($LASTEXITCODE -ne 0) { Warn 'headroom-ai install failed (needs Rust/maturin to build on Windows) - skipping; cch + headroom MCP unavailable.' }
}
Ensure-UvTool 'markitdown'     'markitdown'
Ensure-UvTool 'markitdown-mcp' 'markitdown-mcp'

# ── 2. rtk — Linux-only here ─────────────────────────────────────────────────
if (Get-Command rtk -ErrorAction SilentlyContinue) {
  Log "rtk present: $(rtk --version 2>&1 | Select-Object -First 1)"
  Warn "rtk's 'hook claude' is WSL-only (Unix shell); the rtk PreToolUse hook is removed from settings.json below regardless."
}
else {
  Warn "rtk not installed (ships a Linux binary; native-Windows hook integration unsupported). The rtk PreToolUse hook is removed from settings.json below."
}

# ── 3. node (Claude Code + caveman hooks need it) ───────────────────────────
if (Get-Command node -ErrorAction SilentlyContinue) { Log "node present: $(node --version)" }
else { Warn 'node MISSING - install Node.js (https://nodejs.org, winget, or fnm). Claude Code and caveman hooks need it.' }

# ── 4. Claude config into ~/.claude ─────────────────────────────────────────
if (-not $DRY) {
  New-Item -ItemType Directory -Force -Path $ClaudeDir, (Join-Path $ClaudeDir 'hooks'), (Join-Path $ClaudeDir 'skills') | Out-Null
}

foreach ($f in 'CLAUDE.md', 'RTK.md') {
  $src = Join-Path $ClaudeSrc $f
  if (-not (Test-Path $src)) { continue }
  $dst = Join-Path $ClaudeDir $f
  Backup $dst
  if (-not $DRY) { Copy-Item -LiteralPath $src $dst -Force }
  Log "install ~/.claude/$f"
}

# settings.json: transform Linux paths -> Windows + drop the rtk hook, as TEXT
# (never round-trip through ConvertTo-Json — it reorders keys, truncates the
# nested powerline/lines arrays at -Depth 2, and \uXXXX-escapes the 繁體中文 value).
$settingsSrc = Join-Path $ClaudeSrc 'settings.json'
$settingsDst = Join-Path $ClaudeDir 'settings.json'
Backup $settingsDst
$c        = Get-Content -Raw -Path $settingsSrc -Encoding UTF8
$winHooks = "$HomeFwd/.claude/hooks"
# (a) caveman node hooks: Linux fnm node path (shell form) -> exec form. Bare
#     "node" works on every platform (node.exe is a real binary, unlike npx.cmd);
#     exec form needs no shell, so it survives both Git Bash and PowerShell and
#     handles spaces in the username. Forward slashes avoid Git Bash eating "\".
#     The path goes in via a placeholder + literal .Replace so a '$' anywhere in
#     the profile path can't be misread as a .NET regex substitution token.
$c = $c -replace '(?m)^(\s*)"command":\s*"\\".*?node\\"\s*\\".*?/hooks/(caveman-[a-z-]+\.js)\\""', ('${1}"command": "node",' + "`n" + '${1}"args": ["@@WINHOOKS@@/${2}"]')
$c = $c.Replace('@@WINHOOKS@@', $winHooks)
# (b) drop the `rtk hook claude` PreToolUse block (WSL-only; would error per Bash call)
$c = $c -replace '(?s)"PreToolUse"\s*:\s*\[\s*\{\s*"matcher"\s*:\s*"Bash"\s*,\s*"hooks"\s*:\s*\[\s*\{\s*"type"\s*:\s*"command"\s*,\s*"command"\s*:\s*"rtk hook claude"\s*\}\s*\]\s*\}\s*\]\s*,\s*', ''
# guards — fail loud instead of writing a broken config
if ($c -match '/home/')          { Err 'settings.json still has a Linux /home/ path after transform (node-hook regex did not match). NOT written.'; exit 1 }
if ($c -match 'rtk hook claude') { Warn 'rtk PreToolUse hook still present - remove it manually from ~/.claude/settings.json.' }
try { $null = $c | ConvertFrom-Json } catch { Err "transformed settings.json is not valid JSON: $_`nNOT written - the .bak is intact."; exit 1 }
if (-not $DRY) { [IO.File]::WriteAllText($settingsDst, $c, (New-Object Text.UTF8Encoding $false)) }   # UTF-8, no BOM
Log 'install ~/.claude/settings.json (node hooks -> exec form, rtk hook dropped)'

# hooks: copy all (caveman *.js are cross-platform; *.ps1 is the Windows statusline)
if (-not $DRY) { Copy-Item -Path (Join-Path $ClaudeSrc 'hooks\*') -Destination (Join-Path $ClaudeDir 'hooks') -Recurse -Force }
Log 'install hooks'

# skills: additive — keep whatever already resolves; only install missing/empty ones
Get-ChildItem -Directory -Path (Join-Path $ClaudeSrc 'skills') -ErrorAction SilentlyContinue | ForEach-Object {
  $name = $_.Name
  $tgt  = Join-Path $ClaudeDir "skills\$name"
  if ((Test-Path $tgt) -and (Get-ChildItem -Force -ErrorAction SilentlyContinue $tgt)) { Log "skill present: $name (skip)"; return }
  if (Test-Path $tgt) { Backup $tgt; if (-not $DRY) { Remove-Item $tgt -Recurse -Force } }
  if (-not $DRY) { Copy-Item -LiteralPath $_.FullName $tgt -Recurse -Force }
  Log "skill installed: $name"
}

# ── 5. rtk filter config — skipped (rtk is Linux-only on this box) ──────────

# ── 5b. ccstatusline config ─────────────────────────────────────────────────
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

# ── 6. cch helper -> PowerShell $PROFILE (no ~/.bashrc on native Windows) ────
# A function, not Set-Alias (aliases can't carry the 'wrap claude --no-rtk' args).
# Only meaningful if headroom installed (see step 1) — skip otherwise.
$marker = '# >>> cch (claude-code-config) >>>'
$body = @'
function cch { headroom wrap claude --no-rtk @args }
'@
$block = "$marker`n$body`n# <<< cch (claude-code-config) <<<"
if (-not (Get-Command headroom -ErrorAction SilentlyContinue)) {
  Warn 'cch skipped - headroom not installed.'
}
elseif ((Test-Path $PROFILE) -and (Select-String -Path $PROFILE -Pattern ([regex]::Escape($marker)) -Quiet)) {
  Log 'cch block already in $PROFILE'
}
elseif ($DRY) { Warn "[dry-run] append cch function to $PROFILE" }
else {
  New-Item -ItemType File -Path $PROFILE -Force | Out-Null
  Add-Content -Path $PROFILE -Value "`n$block"
  Log "added cch function to $PROFILE (open a new shell to use it)"
}

# ── 7. MCP servers (idempotent; honors DRY_RUN via env) ─────────────────────
if (Get-Command claude -ErrorAction SilentlyContinue) {
  try { & (Join-Path $ClaudeSrc 're-create-mcp.ps1') }
  catch { Warn "re-create-mcp.ps1 error; check 'claude mcp list'" }
}
else { Warn 'claude not found - skip MCP; install Claude Code then run claude\re-create-mcp.ps1' }

# ── 8. plugins: declarative via settings.json (re-clone on next launch) ─────
Log "plugins re-install declaratively from settings.json on next 'claude' start."

# ── 9. verify (read-only) ───────────────────────────────────────────────────
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
Probe 'headroom'   'headroom'
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
if (Test-Path (Join-Path $binDir 'headroom.exe')) { Write-Host '  mcp bin:    OK headroom.exe' } else { Write-Host '  mcp bin:    headroom.exe absent (optional - skipped)' }
# hook health: the script paths baked into settings.json must exist, else the
# SessionStart/UserPromptSubmit (caveman) hooks silently no-op.
$activate = Join-Path $ClaudeDir 'hooks\caveman-activate.js'
if (Test-Path $activate) { Write-Host '  hooks:      OK' } else { Warn "hook script missing: $activate" }
Write-Host ''; Log 'MCP servers:'
if (Get-Command claude -ErrorAction SilentlyContinue) { claude mcp list 2>&1 | ForEach-Object { Write-Host "  $_" } }
Write-Host ''
if ($DRY) { Warn 'DRY-RUN complete - re-run without $env:DRY_RUN to apply.'; exit 0 }
Log "DONE. Open a NEW PowerShell. First 'claude' launch fetches plugins."
Log "Any MCP X/Pending -> run /mcp inside claude to (re)authenticate."
