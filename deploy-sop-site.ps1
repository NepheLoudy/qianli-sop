################################################
# SOP Planet 一键部署脚本（本站点仓库内运行）
#
# 目录约定（所有文件跟本脚本同目录 = site-sop-planet/）：
#   qianli_sop_planet.html  「编辑源」本地用，带编辑面板、contenteditable 标题
#   three.min.js            固定依赖
#   OrbitControls.js        固定依赖
#   qianli_sop_network.html 可选其他页面（同目录放着就自动发布，地址 /qianli_sop_network.html）
#   rm2026_timeline.html    可选其他页面（同目录放着就自动发布，地址 /rm2026_timeline.html）
#   123.html                可选其他页面（同上）
#
# 生成产物：
#   index.html              从 qianli_sop_planet.html 复制并「剥离编辑面板 + 锁定标题只读」
#
# 远程仓库：https://github.com/NepheLoudy/qianli-sop
# Pages 地址（自定义域）：https://sop.cquqianli.cn/
#
# 用法：
#   1) 直接改本目录下的 qianli_sop_planet.html（编辑面板照用，节点/链接随便改）
#   2) 双击本脚本 或 在 PowerShell 中运行:  .\deploy-sop-site.ps1
#   3) 推送完成后约 30-90 秒 GitHub Actions 自动刷新 Pages
################################################
$ErrorActionPreference = "Stop"

# 定位根目录（脚本同目录，兼容 -File 调用与双击）
$Root = Split-Path -Parent $MyInvocation.MyCommand.Path
if (-not $Root) { $Root = Split-Path -Parent $PSCommandPath }
if (-not $Root) { $Root = $PWD.Path }
Set-Location $Root
Write-Host "==> Work dir: $Root" -ForegroundColor Cyan

# 必要文件检查
$srcHtml = Join-Path $Root "qianli_sop_planet.html"
$three   = Join-Path $Root "three.min.js"
$orbit   = Join-Path $Root "OrbitControls.js"
foreach ($p in @($srcHtml,$three,$orbit)) {
    if (!(Test-Path $p)) { Write-Host "[ERR] 缺少文件: $p" -ForegroundColor Red; exit 1 }
}
if (!(Test-Path (Join-Path $Root ".git"))) {
    Write-Host "[ERR] 当前目录还没初始化 git 仓库，先在该目录运行 git init + remote add origin https://github.com/NepheLoudy/qianli-sop.git" -ForegroundColor Red
    exit 1
}

# 1) 从编辑源生成部署版 index.html
Write-Host "==> Build index.html from qianli_sop_planet.html ..." -ForegroundColor Cyan
$content = [System.IO.File]::ReadAllText($srcHtml)
$before  = $content.Length

# 1.1 删除整个编辑面板 HTML（从 <!-- 编辑面板 --> 到 <!-- 3D 场景 --> 之前）
$content = [System.Text.RegularExpressions.Regex]::Replace(
    $content,
    '(?s)\s*<!-- 编辑面板 -->.*?(?=<!-- 3D 场景 -->)',
    "`r`n"
)
# 1.2 去掉"默认展开编辑面板"那行残留 JS
$content = $content -replace 'panel\.classList\.add\(''open''\);', '// (部署版已移除编辑面板)'
# 1.3 锁定顶部标题 / 副标题：禁止编辑
$content = $content -replace 'contenteditable="true"', ''

$outPath = Join-Path $Root "index.html"
[System.IO.File]::WriteAllText($outPath, $content)
Write-Host "    index.html generated ($($before - $content.Length) bytes stripped)" -ForegroundColor Green

# 2) 把其他可选 html 原样保留（本来就在仓库里，直接 add -A 会带上）
$extraPages = @("qianli_sop_network.html","rm2026_timeline.html","123.html")
$inRepo = @()
foreach ($p in $extraPages) {
    if (Test-Path (Join-Path $Root $p)) { $inRepo += $p }
}
if ($inRepo.Count) { Write-Host "    附加页面将一起发布: $($inRepo -join ', ')" -ForegroundColor DarkGray }

# 3) Git 提交 + 推送
Write-Host "==> git status:" -ForegroundColor Cyan
git --no-pager status --short

Write-Host "==> git add -A" -ForegroundColor Cyan
git add -A 2>&1 | Out-Null

$ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
$commitMsg = "deploy: update site at $ts"
Write-Host "==> git commit: $commitMsg" -ForegroundColor Cyan
git commit -m $commitMsg 2>&1 | ForEach-Object { Write-Host "    $_" }
# commit 为空（nothing to commit）不阻塞，继续尝试 push 保证同步

Write-Host "==> git push origin main ..." -ForegroundColor Cyan
git push origin main 2>&1 | ForEach-Object { Write-Host "    $_" }
if ($LASTEXITCODE -ne 0) {
    Write-Host "[ERR] git push 失败（exit=$LASTEXITCODE）。" -ForegroundColor Red
    Write-Host "    常见原因 1) 没有凭据：弹窗填 GitHub 用户名 NepheLoudy，密码填『GitHub Token』" -ForegroundColor Yellow
    Write-Host "             Classic:  https://github.com/settings/tokens       (勾选 repo 全部权限)" -ForegroundColor Yellow
    Write-Host "             Fine:     https://github.com/settings/tokens?type=beta  (给 qianli-sop 仓库 Contents RW)" -ForegroundColor Yellow
    Write-Host "    常见原因 2) GitHub 临时 502：重跑一次脚本即可" -ForegroundColor Yellow
    Write-Host "    常见原因 3) 没设 upstream：先手动运行  git push -u origin main  一次" -ForegroundColor Yellow
    exit $LASTEXITCODE
}

Write-Host ""
Write-Host "==> 同步完成！GitHub Actions 约 30-90 秒后刷新：" -ForegroundColor Green
Write-Host "    SOP 行星:    https://sop.cquqianli.cn/           (index.html)" -ForegroundColor Green
foreach ($p in $inRepo) {
    Write-Host "    $($p.PadRight(22))  https://sop.cquqianli.cn/$p" -ForegroundColor Green
}

