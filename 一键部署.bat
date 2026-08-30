@echo off
setlocal
cd /d "%~dp0"
echo ============================================
echo   Deploy SOP Planet to sop.cquqianli.cn
echo   Work dir: %cd%
echo ============================================
echo.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0deploy-sop-site.ps1"
set EXIT=%ERRORLEVEL%
echo.
if %EXIT% EQU 0 (
  echo [OK] Deploy finished. Refresh https://sop.cquqianli.cn/ after ~30s.
) else (
  echo [FAIL] Deploy failed with EXIT=%EXIT%.
  echo.
  echo Quick fixes:
  echo   1) Git auth failed  -> remove github.com entries in Windows Credential Manager, then retry
  echo   2) Remote rejected   -> run:  git pull --rebase origin main   then retry
  echo   3) GitHub 502        -> retry this .bat
  echo.
  echo Copy the red ERROR lines above and send them to me if you're stuck.
)
echo.
pause