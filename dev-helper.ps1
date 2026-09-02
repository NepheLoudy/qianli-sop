################################################
# SOP Planet - Dev Helper (local save server)
# Runs a tiny HTTP listener on http://127.0.0.1:7788
#
# Endpoints:
#   GET  /ping            -> returns "pong" (probe)
#   GET  /current-html    -> returns qianli_sop_planet.html source on disk
#   POST /write-html      -> writes request body back to qianli_sop_planet.html
#
# Usage:
#   Double click "启动本地开发助手.bat" in the same folder.
#   Keep this window open while editing. Close it to stop.
################################################
param()
$ErrorActionPreference = "Stop"

# Resolve root folder (this script + qianli_sop_planet.html must be side by side)
$Root = Split-Path -Parent $PSCommandPath
if (-not $Root) { $Root = Split-Path -Parent $MyInvocation.MyCommand.Path }
if (-not $Root) { $Root = (Get-Location).Path }
Set-Location $Root

$TargetHtml = Join-Path $Root "qianli_sop_planet.html"
if (-not (Test-Path -LiteralPath $TargetHtml)) {
    Write-Host "[ERR] Cannot find $TargetHtml" -ForegroundColor Red
    exit 1
}

$Listener = New-Object System.Net.HttpListener
$Prefix = "http://127.0.0.1:7788/"
$Listener.Prefixes.Add($Prefix)
try {
    $Listener.Start()
} catch {
    Write-Host "[ERR] Cannot bind $Prefix : $_" -ForegroundColor Red
    Write-Host "  Make sure port 7788 is free, or run as administrator." -ForegroundColor Yellow
    exit 2
}

Write-Host "============================================" -ForegroundColor Cyan
Write-Host "  SOP Planet Dev Helper - started" -ForegroundColor Cyan
Write-Host "  Listen : $Prefix" -ForegroundColor Cyan
Write-Host "  Target : $TargetHtml" -ForegroundColor Cyan
Write-Host "============================================" -ForegroundColor Cyan
Write-Host "  Edit page (use THIS url, not file://): $Prefixcurrent-html" -ForegroundColor Yellow
Write-Host "  Tip: Click 'Save and Reload' on the page to write back to disk"
Write-Host "  Stop: Close this window or press Ctrl+C"
Write-Host ""

# Auto-open the editor page. Pages opened via file:// cannot reach the helper
# (browser blocks cross-origin reads), which shows the yellow "helper not
# started" badge - so always land the user on the same-origin url.
try { Start-Process "$Prefixcurrent-html" } catch { Write-Host "[WARN] Could not open browser: $_" -ForegroundColor Yellow }

function ReadBody($ctx) {
    $sr = New-Object System.IO.StreamReader($ctx.Request.InputStream, [System.Text.Encoding]::UTF8)
    try { return $sr.ReadToEnd() } finally { $sr.Dispose() }
}

# UTF-8 WITHOUT BOM: the source html on disk has no BOM; emitting one (the plain
# [System.Text.Encoding]::UTF8 default) would add a spurious 1-line diff on the
# first browser save.
$Utf8NoBom = New-Object System.Text.UTF8Encoding($false)

function WriteResp($ctx, $code, $text, $ctype="text/plain; charset=utf-8") {
    $buf = [System.Text.Encoding]::UTF8.GetBytes($text)
    $r = $ctx.Response
    $r.StatusCode = $code
    $r.ContentType = $ctype
    $r.ContentLength64 = $buf.Length
    $r.OutputStream.Write($buf, 0, $buf.Length)
    $r.OutputStream.Close()
}

while ($Listener.IsListening) {
    $ctx = $null
    try {
        $ctx = $Listener.GetContext()
        $path = $ctx.Request.Url.AbsolutePath
        Write-Host "[$(Get-Date -Format 'HH:mm:ss')] $($ctx.Request.HttpMethod) $path"

        switch -Exact ($path) {
            "/ping" {
                WriteResp $ctx 200 "pong"
                continue
            }
            "/current-html" {
                $html = [System.IO.File]::ReadAllText($TargetHtml, [System.Text.Encoding]::UTF8)
                WriteResp $ctx 200 $html "text/html; charset=utf-8"
                Write-Host "  -> 200 source returned ($($html.Length) bytes)" -ForegroundColor DarkGray
                continue
            }
            "/write-html" {
                if ($ctx.Request.HttpMethod -ne "POST") { WriteResp $ctx 405 "Method Not Allowed"; continue }
                $body = ReadBody $ctx
                if ([string]::IsNullOrWhiteSpace($body)) { WriteResp $ctx 400 "Empty body"; continue }
                [System.IO.File]::WriteAllText($TargetHtml, $body, $Utf8NoBom)
                WriteResp $ctx 200 "OK written $($body.Length) chars"
                Write-Host "  -> 200 overwritten on disk ($($body.Length) chars)" -ForegroundColor Green
                continue
            }
            default {
                WriteResp $ctx 404 "Not Found"
                continue
            }
        }
    } catch {
        Write-Host "  !> EXCEPTION: $_" -ForegroundColor Red
        if ($ctx) { try { WriteResp $ctx 500 ("Internal Server Error: " + $_) } catch {} }
    }
}
