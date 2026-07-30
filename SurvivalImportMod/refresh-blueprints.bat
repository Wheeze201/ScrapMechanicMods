@echo off
rem ============================================================
rem  Survival Import Mod - rebuild the blueprint index
rem  Run this after saving new creations on a lift, so /build can find them.
rem  Safe to run while the game is open.
rem ============================================================
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0refresh-blueprints.ps1"
if errorlevel 1 (
    echo.
    echo [!] The index was NOT written.
)
pause
