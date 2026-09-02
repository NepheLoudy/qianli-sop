@echo off
setlocal
cd /d "%~dp0"
echo ============================================
echo   SOP Planet - Auto Deploy on Save
echo   Folder: %cd%
echo ============================================
echo.
echo Watching qianli_sop_planet.html. Every saved change is auto deployed:
echo   save -^> build index.html -^> git commit/push -^> CI publish (OSS + Pages)
echo Keep this window open while you edit. Close it when done.
echo.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0auto-deploy-watcher.ps1"
echo.
echo Watcher stopped.
pause
