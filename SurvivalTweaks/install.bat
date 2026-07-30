@echo off
rem ============================================================
rem  Survival Tweaks - installer
rem  Close Scrap Mechanic before running this.
rem  Pass /accept after you have re-ported the mod onto updated game files.
rem ============================================================
set "ACCEPT="
if /i "%~1"=="/accept" set "ACCEPT=-AcceptNewBaseFiles"
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0install.ps1" %ACCEPT%
if errorlevel 1 (
    echo.
    echo [!] Installation FAILED - see the message above.
)
pause
