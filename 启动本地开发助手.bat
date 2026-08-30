@echo off
setlocal
cd /d "%~dp0"
echo ============================================
echo   SOP Planet - Dev Helper
echo   Folder: %cd%
echo ============================================
echo.
echo Starting local HTTP helper on http://127.0.0.1:7788 ...
echo Keep this window open while you edit. Close it when done.
echo.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0dev-helper.ps1"
pause
