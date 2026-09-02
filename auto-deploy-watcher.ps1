################################################
# SOP Planet - Auto Deploy Watcher
# Watches qianli_sop_planet.html for saved changes (any editor, or the
# in-page edit panel writing back through dev-helper) and automatically
# runs deploy-sop-site.ps1: build index.html -> git add/commit -> git push.
# After push, the existing GitHub Actions workflows publish to
# Aliyun OSS (sop.cquqianli.cn) + GitHub Pages. Those workflows are NOT
# touched by this script.
#
# Behavior rules:
#   - Only actual CONTENT changes trigger a deploy (re-save / touch with
#     no changes is ignored).
#   - Waits until the file stops changing (settle window) before deploying,
#     so rapid consecutive saves collapse into ONE deploy.
#   - Saves made while a deploy is running are deployed right after it
#     finishes (nothing overlaps, nothing is lost).
#   - Network-class push failures are auto-retried (30s apart, MaxRetries).
#   - On non-network failure (e.g. bad credentials) it stops retrying:
#     fix the cause, then just save the file again.
#   - Note: deploy sweeps ALL uncommitted changes in this repo (git add -A),
#     not only the html.
#
# Usage:
#   Double click the "start auto deploy" bat in the same folder,
#   or:  powershell -NoProfile -ExecutionPolicy Bypass -File .\auto-deploy-watcher.ps1
#   Close the window (or Ctrl+C) to stop watching.
################################################
param(
    [int]$PollIntervalSec = 2,     # how often to check the file
    [int]$SettleChecks = 2,        # consecutive identical reads before deploying (debounce)
    [int]$MaxRetries = 2,          # extra attempts on network-class push failures
    [int]$RetryDelaySec = 30,      # wait between retry attempts
    [int]$StopAfterSec = 0,        # test hook: auto-exit after N seconds (0 = run forever)
    [string]$WatchFile = "",       # override for tests
    [string]$DeployScript = ""     # override for tests
)
$ErrorActionPreference = "Stop"

$Root = Split-Path -Parent $PSCommandPath
if (-not $Root) { $Root = Split-Path -Parent $MyInvocation.MyCommand.Path }
if (-not $Root) { $Root = (Get-Location).Path }
Set-Location $Root

if (-not $WatchFile)    { $WatchFile    = Join-Path $Root "qianli_sop_planet.html" }
if (-not $DeployScript) { $DeployScript = Join-Path $Root "deploy-sop-site.ps1" }

if (-not (Test-Path -LiteralPath $WatchFile)) {
    Write-Host "[ERR] Cannot find $WatchFile" -ForegroundColor Red
    exit 1
}
if (-not (Test-Path -LiteralPath $DeployScript)) {
    Write-Host "[ERR] Cannot find $DeployScript" -ForegroundColor Red
    exit 1
}

# Matches git/network-class failures worth retrying (auth errors are NOT here on purpose)
$NetworkErrorPattern = 'timed out|timeout|SSL|Could not resolve|Failed to connect|Connection (reset|refused)|unable to access|502|503|Bad Gateway|RPC failed'

function Get-ContentHash([string]$Path) {
    # Returns $null while the file is locked/mid-write so the caller just skips this cycle.
    try { return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash } catch { return $null }
}

function Invoke-DeployOnce {
    # Runs the deploy script as a child process, streaming its output into our window.
    $out = New-Object System.Collections.Generic.List[string]
    & powershell -NoProfile -ExecutionPolicy Bypass -File $DeployScript 2>&1 | ForEach-Object {
        if ($_ -is [System.Management.Automation.ErrorRecord]) { $line = $_.Exception.Message } else { $line = "$_" }
        $out.Add($line)
        if (-not [string]::IsNullOrWhiteSpace($line)) { Write-Host "    $line" -ForegroundColor DarkGray }
    }
    return @{ Code = $LASTEXITCODE; Output = $out }
}

$lastDeployedHash = Get-ContentHash $WatchFile
if (-not $lastDeployedHash) {
    Write-Host "[ERR] Cannot read the watched file right now. Try again." -ForegroundColor Red
    exit 1
}
$lastSeenHash = $lastDeployedHash
$stableCount = 0

Write-Host "============================================" -ForegroundColor Cyan
Write-Host "  SOP Planet - Auto Deploy Watcher started" -ForegroundColor Cyan
Write-Host "  Watch  : $WatchFile"
Write-Host "  Deploy : $DeployScript"
Write-Host "  Poll   : ${PollIntervalSec}s / settle: $SettleChecks checks / retries: $MaxRetries"
Write-Host "  Chain  : save -> build index.html -> git commit/push -> CI (OSS + Pages)"
Write-Host "  Stop   : Close this window or press Ctrl+C"
Write-Host "============================================" -ForegroundColor Cyan
Write-Host "  Editing now... every saved change to the html will be deployed." -ForegroundColor Green
Write-Host ""

$watch = New-Object System.Diagnostics.Stopwatch
$watch.Start()

while ($true) {
    if ($StopAfterSec -gt 0 -and $watch.Elapsed.TotalSeconds -ge $StopAfterSec) {
        Write-Host ""
        Write-Host "[INFO] StopAfterSec ($StopAfterSec s) reached, watcher exits."
        exit 0
    }

    Start-Sleep -Seconds $PollIntervalSec
    $hash = Get-ContentHash $WatchFile
    if (-not $hash) { continue }                                   # mid-write, retry next cycle
    if ($hash -eq $lastDeployedHash) { $lastSeenHash = $hash; $stableCount = 0; continue }

    if ($hash -eq $lastSeenHash) { $stableCount++ } else { $lastSeenHash = $hash; $stableCount = 1 }
    if ($stableCount -lt $SettleChecks) { continue }               # still saving / settling

    # ---- file settled -> deploy (with network retries) ----
    Write-Host ""
    Write-Host "==> [$(Get-Date -Format 'HH:mm:ss')] Saved change detected -> deploying" -ForegroundColor Cyan
    $attempt = 0
    while ($true) {
        $attempt++
        $r = Invoke-DeployOnce
        if ($r.Code -eq 0) { break }
        $joined = ($r.Output -join "`n")
        if ($attempt -le $MaxRetries -and $joined -match $NetworkErrorPattern) {
            Write-Host ""
            Write-Host "[WARN] Network-class push failure (attempt $attempt/$($MaxRetries + 1)). Retrying in $RetryDelaySec s ..." -ForegroundColor Yellow
            Start-Sleep -Seconds $RetryDelaySec
            continue
        }
        Write-Host ""
        Write-Host "[ERR] Deploy failed (exit=$($r.Code)), no more auto-retry." -ForegroundColor Red
        Write-Host "      Fix the problem, then save the html again (or run the deploy bat manually)." -ForegroundColor Red
        break
    }

    # Anchor on the hash that TRIGGERED this deploy, not a re-read. If a save
    # landed mid-deploy (possibly after git add), the next cycle sees the file
    # differ from this anchor and runs another deploy - worst case it is a
    # harmless no-op; re-reading here instead could silently swallow that save.
    $lastDeployedHash = $hash
    $lastSeenHash = $lastDeployedHash
    $stableCount = 0
    if ($r.Code -eq 0) {
        Write-Host ""
        Write-Host "==> [$(Get-Date -Format 'HH:mm:ss')] Deploy done. Site updates after CI finishes (~1-2 min)." -ForegroundColor Green
    }
}
