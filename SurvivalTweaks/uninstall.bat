@echo off
rem ============================================================
rem  Survival Tweaks - uninstaller
rem  Restores the vanilla game files. Close Scrap Mechanic before running this.
rem ============================================================
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0uninstall.ps1"
if errorlevel 1 (
    echo.
    echo [!] Some files were NOT restored - see the message above.
)
pause
