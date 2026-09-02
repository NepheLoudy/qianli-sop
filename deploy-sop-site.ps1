################################################
# SOP Planet - one-click deploy script
# Run this inside site-sop-planet/ (the Git repo folder).
#
# Folder convention (everything lives beside this script):
#   qianli_sop_planet.html  editor source, DO upload, used locally for editing
#   three.min.js            fixed runtime dependency
#   OrbitControls.js        fixed runtime dependency
#   Misc files qianli_sop_network.html / rm2026_timeline.html / 123.html
#     are intentionally moved out to ../sop-misc/ and are NEVER published.
#
# Produces:
#   index.html  -> copy of qianli_sop_planet.html with edit panel stripped
#                  and page title/subtitle locked to readonly.
#
# Usage:
#   1) Modify qianli_sop_planet.html (use the editor panel on the page if you like).
#   2) Double-click 一键部署.bat next to this file, OR run:  .\deploy-sop-site.ps1
#   3) After push, wait for your server to pull, then refresh https://sop.cquqianli.cn/
################################################
param()
$ErrorActionPreference = "Stop"

# Resolve root (this ps1 folder = repo root)
$Root = Split-Path -Parent $PSCommandPath
if (-not $Root) { $Root = Split-Path -Parent $MyInvocation.MyCommand.Path }
if (-not $Root) { $Root = (Get-Location).Path }
Set-Location $Root

$SrcHtml   = Join-Path $Root "qianli_sop_planet.html"
$OutHtml   = Join-Path $Root "index.html"

if (-not (Test-Path -LiteralPath $SrcHtml)) {
    Write-Host "[ERR] Missing $SrcHtml" -ForegroundColor Red
    exit 2
}
if (-not (Test-Path -LiteralPath (Join-Path $Root ".git"))) {
    Write-Host "[ERR] .git folder not found. This script must run inside the repo folder." -ForegroundColor Red
    exit 3
}

Write-Host "==> Work dir: $Root" -ForegroundColor Cyan

########################################
# 1) Build index.html: copy + strip edit panel + lock contenteditable
########################################
Write-Host "==> Building index.html (strip edit panel + lock title readonly)" -ForegroundColor Cyan
$content = [System.IO.File]::ReadAllText($SrcHtml, [System.Text.Encoding]::UTF8)
$before = $content.Length

# PRIMARY match (100% exact because two Chinese HTML comments are unique block markers in source):
#   from  <!-- 编辑面板 -->   to    <!-- 3D 场景 -->
# and replace both markers + everything between with a small deploy comment.
$stripped = '<!-- Edit panel stripped for public deploy -->' + [Environment]::NewLine + '  <!-- 3D scene -->'
$content = [regex]::Replace(
    $content,
    '(?s)<!-- 编辑面板 -->.*?<!-- 3D 场景 -->',
    $stripped
)
# FALLBACK (English markers, if user ever translated the comments):
#   remove entire .edit-panel block up to the start of .scene-wrap.
if ($content.Length -eq $before) {
    $content = [regex]::Replace(
        $content,
        '(?s)<div\s+class="edit-panel"\s+id="editPanel">.*?<div\s+class="scene-wrap">',
        '<!-- Edit panel stripped for public deploy -->' + [Environment]::NewLine + '  <div class="scene-wrap">'
    )
}
# Strip all contenteditable attributes (titles become readonly on live site)
$content = [regex]::Replace($content, '\s*contenteditable\s*=\s*(?:"true"|''true''|true)', '')

[System.IO.File]::WriteAllText($OutHtml, $content, [System.Text.Encoding]::UTF8)
$after = $content.Length
Write-Host "    index.html generated (stripped $($before - $after) bytes)" -ForegroundColor Green

########################################
# 2) Add files to git (explicitly skip 3 misc html names even if they were put back)
########################################
Write-Host "==> git add (never include 3 misc html files: qianli_sop_network/rm2026_timeline/123)" -ForegroundColor Cyan
$ExcludeMisc = @('qianli_sop_network.html','rm2026_timeline.html','123.html')

# PS5 wraps native stderr (git's CRLF warnings etc.) as ErrorRecords; under
# EAP=Stop those would terminate the script mid-deploy. Relax EAP around every
# git call, then restore - real git failures are still caught via $LASTEXITCODE.
$prevEAP = $ErrorActionPreference
$ErrorActionPreference = 'Continue'

# First, stage modified + new files, then UNSTAGE any of the 3 misc names
& git add -A 2>&1 | Out-Null
foreach ($name in $ExcludeMisc) {
    & git reset --quiet HEAD -- $name 2>&1 | Out-Null
    # Also remove from index if they were tracked deletion previously
    # (no-op if not tracked; we want them to stay as "D" unstaged until user decides)
}

# Count staged non-zero (safety check below)
$staged = @(& git --no-pager diff --cached --name-only 2>&1)
$porcelain = (& git status --porcelain 2>&1) -join "`n"
$ErrorActionPreference = $prevEAP
$stagedCount = 0
foreach ($s in $staged) { if (-not [string]::IsNullOrWhiteSpace($s)) { $stagedCount++ } }
Write-Host "    staged files: $stagedCount" -ForegroundColor DarkGray
if ($stagedCount -gt 0) { $staged | ForEach-Object { if (-not [string]::IsNullOrWhiteSpace($_)) { Write-Host "       + $_" -ForegroundColor DarkGray } } }

########################################
# 3) Commit (skip gracefully when nothing to commit - no error)
########################################
Write-Host "==> git status:" -ForegroundColor Cyan
$prevEAPS = $ErrorActionPreference
$ErrorActionPreference = 'Continue'
& git --no-pager status --short 2>&1 | ForEach-Object {
    if ($_ -is [System.Management.Automation.ErrorRecord]) { $_.Exception.Message } else { "$_" }
} | ForEach-Object { Write-Host "    $_" }
$ErrorActionPreference = $prevEAPS

if ($stagedCount -eq 0) {
    # Nothing new to commit, but a previous run may have committed and then failed
    # to push (e.g. network). In that case still push, otherwise the commit would
    # sit locally forever and re-running this script would no-op without pushing.
    $prevEAP2 = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    $unpushed = (& git --no-pager rev-list --count origin/main..main 2>&1 | Out-String).Trim()
    $ErrorActionPreference = $prevEAP2
    if ("$unpushed" -eq '0') {
        Write-Host "[WARN] Nothing staged, skipping commit & push." -ForegroundColor Yellow
        Write-Host "       (Probably nothing changed from last deploy, or index.html is byte-identical.)"
        Write-Host ""
        Write-Host "==> No-op done. (nothing new to deploy)" -ForegroundColor Green
        exit 0
    }
    Write-Host "[INFO] Nothing new staged, but $unpushed unpushed commit(s) found - pushing them now." -ForegroundColor Cyan
}

$ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
$msg = "deploy: update site at $ts"
Write-Host "==> git commit -m '$msg'" -ForegroundColor Cyan
$prevEAP3 = $ErrorActionPreference
$ErrorActionPreference = 'Continue'
$commitOut = @(& git commit -m $msg 2>&1 | ForEach-Object {
    # Normalize: if this is an ErrorRecord (PS5 wrapper), extract the underlying message.
    if ($_ -is [System.Management.Automation.ErrorRecord]) { $_.Exception.Message } else { "$_" }
})
$commitCode = $LASTEXITCODE
$ErrorActionPreference = $prevEAP3
$commitOut | ForEach-Object { if (-not [string]::IsNullOrWhiteSpace($_)) { Write-Host "    $_" } }
if ($commitCode -ne 0) {
    # Git exit 1 when nothing to commit even if we checked above; treat as soft no-op
    if ($porcelain -match '^\s*$') {
        Write-Host "[WARN] Nothing changed after all - nothing to commit." -ForegroundColor Yellow
        exit 0
    }
    Write-Host "[ERR] git commit failed (exit=$commitCode)" -ForegroundColor Red
    exit $commitCode
}

########################################
# 4) Push origin main (categorized actionable error messages)
########################################
Write-Host "==> git push origin main ..." -ForegroundColor Cyan
# NOTE: git writes informational lines ("To <url>" and "X..Y  main -> main") to stderr.
#       In Windows PowerShell 5 stderr output is wrapped as ErrorRecords and
#       causes red "NativeCommandError" noise even when push actually succeeds.
#       We temporarily suppress this cosmetic noise, keep real exit code check.
$prevEAP = $ErrorActionPreference
$ErrorActionPreference = 'Continue'
$pushOut = @(& git push origin main 2>&1 | ForEach-Object {
    # Normalize: if this is an ErrorRecord (PS5 wraper), extract the underlying message.
    if ($_ -is [System.Management.Automation.ErrorRecord]) { $_.Exception.Message } else { "$_" }
})
$ErrorActionPreference = $prevEAP
$pushOut | ForEach-Object { if (-not [string]::IsNullOrWhiteSpace($_)) { Write-Host "    $_" } }
if ($LASTEXITCODE -ne 0) {
    $joined = ($pushOut -join "`n")
    Write-Host ""
    Write-Host "[ERR] git push failed (exit=$LASTEXITCODE)" -ForegroundColor Red
    if ($joined -match 'Authentication failed|Unauthorized|Support for password authentication') {
        Write-Host "   FIX: Bad credentials." -ForegroundColor Yellow
        Write-Host "   -> Open Windows Credential Manager -> Windows Credentials -> remove any github.com entries"
        Write-Host "   -> Re-run this script, enter username NepheLoudy + GitHub PAT (NOT password):"
        Write-Host "      Classic: https://github.com/settings/tokens                       (check `repo` scope)"
        Write-Host "      Fine   : https://github.com/settings/tokens?type=beta             (repo qianli-sop, Contents R/W)"
    } elseif ($joined -match 'rejected|fetch first|non-fast-forward') {
        Write-Host "   FIX: Remote is ahead of local (your server may have pushed a commit ahead)." -ForegroundColor Yellow
        Write-Host "   -> In an external PowerShell window run:"
        Write-Host "      cd $Root"
        Write-Host "      git pull --rebase origin main"
        Write-Host "      Then re-run this .bat."
    } elseif ($joined -match '502|503|Bad Gateway|timed out|SSL') {
        Write-Host "   FIX: GitHub / network is flaky." -ForegroundColor Yellow
        Write-Host "   -> Simply re-run this bat in 30 seconds."
    } elseif ($joined -match 'The current branch .* has no upstream') {
        Write-Host "   FIX: No upstream set." -ForegroundColor Yellow
        Write-Host "   -> Run once:  git push -u origin main"
    }
    exit $LASTEXITCODE
}

Write-Host ""
Write-Host "==> Deploy pushed! After your server syncs (~30-90s):" -ForegroundColor Green
Write-Host "    SOP Planet : https://sop.cquqianli.cn/  (index.html)" -ForegroundColor Green
Write-Host "    (Misc pages are in ../sop-misc/ and are not published with this repo)" -ForegroundColor DarkGray
exit 0
