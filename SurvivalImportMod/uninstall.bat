@echo off
setlocal
rem ============================================================
rem  Survival Import Mod - uninstaller
rem  Restores the vanilla files from the backup made by install.bat
rem ============================================================

set "GAME=%~dp0.."
set "SG=%GAME%\Survival\Scripts\game\SurvivalGame.lua"
set "CG=%GAME%\Data\Scripts\game\CreativeGame.lua"
set "BACKUP=%~dp0backup"

findstr /L /C:"SurvivalImportMod" "%SG%" >nul 2>&1
if errorlevel 1 (
    echo [i] The mod is not currently installed - nothing to do.
    pause
    exit /b 0
)

if not exist "%BACKUP%\SurvivalGame.lua" (
    echo [!] No backup found in "%BACKUP%".
    echo     Restore the vanilla files with Steam instead:
    echo     Library ^> Scrap Mechanic ^> Properties ^> Installed Files ^> Verify integrity of game files
    pause
    exit /b 1
)

copy /y "%BACKUP%\SurvivalGame.lua" "%SG%" >nul || goto :fail
copy /y "%BACKUP%\CreativeGame.lua" "%CG%" >nul || goto :fail

rem --- clear the compiled bundle, otherwise the modded scripts keep running ---
if exist "%GAME%\Cache\Bundle\core_data.cbo" (
    del /f /q "%GAME%\Cache\Bundle\core_data.cbo" >nul 2>&1
    if exist "%GAME%\Cache\Bundle\core_data.cbo" (
        echo [!] Could not delete Cache\Bundle\core_data.cbo - is the game running?
        echo     Close Scrap Mechanic and run uninstall.bat again, or the MOD WILL STAY ACTIVE.
        goto :fail
    )
    echo [i] Cleared the compiled script bundle - it rebuilds on next launch.
)

echo [OK] Vanilla files restored. The mod is uninstalled.
pause
exit /b 0

:fail
echo [!] Restore FAILED. You may need to run as administrator, or use
echo     Steam's "Verify integrity of game files" to restore the originals.
pause
exit /b 1
