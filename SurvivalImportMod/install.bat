@echo off
setlocal
rem ============================================================
rem  Survival Import Mod - installer (ported to Scrap Mechanic 1.0)
rem  Backs up the vanilla files, then copies the patched ones in.
rem ============================================================

set "GAME=%~dp0.."
set "SG=%GAME%\Survival\Scripts\game\SurvivalGame.lua"
set "CG=%GAME%\Data\Scripts\game\CreativeGame.lua"
set "PATCHED=%~dp0patched"
set "BACKUP=%~dp0backup"

if not exist "%SG%" (
    echo [!] Could not find SurvivalGame.lua - is this folder inside the Scrap Mechanic directory?
    goto :fail
)
if not exist "%PATCHED%\SurvivalGame.lua" (
    echo [!] Missing "%PATCHED%\SurvivalGame.lua" - the patched files are gone.
    goto :fail
)

rem --- check we can write to the game folder ---
copy /y nul "%GAME%\__writetest.tmp" >nul 2>&1
if not exist "%GAME%\__writetest.tmp" (
    echo [!] No write permission in the game folder.
    echo     Right-click install.bat and choose "Run as administrator".
    goto :fail
)
del "%GAME%\__writetest.tmp" >nul 2>&1

rem --- back up vanilla files (only when the live files are unmodded) ---
findstr /L /C:"SurvivalImportMod" "%SG%" >nul 2>&1
if not errorlevel 1 (
    echo [i] Mod already installed - reinstalling patched files.
) else (
    if not exist "%BACKUP%" mkdir "%BACKUP%"
    copy /y "%SG%" "%BACKUP%\SurvivalGame.lua" >nul || goto :fail
    copy /y "%CG%" "%BACKUP%\CreativeGame.lua" >nul || goto :fail
    echo [i] Vanilla files backed up to "%BACKUP%".
)

rem --- install ---
copy /y "%PATCHED%\SurvivalGame.lua" "%SG%" >nul || goto :fail
copy /y "%PATCHED%\CreativeGame.lua" "%CG%" >nul || goto :fail

rem --- CRITICAL: the game executes a compiled bundle, not the .lua files. Editing a
rem     script does nothing until this bundle is deleted; the game then rebuilds it
rem     from the .lua files on the next launch (that launch takes a bit longer).
if exist "%GAME%\Cache\Bundle\core_data.cbo" (
    del /f /q "%GAME%\Cache\Bundle\core_data.cbo" >nul 2>&1
    if exist "%GAME%\Cache\Bundle\core_data.cbo" (
        echo [!] Could not delete Cache\Bundle\core_data.cbo - is the game running?
        echo     Close Scrap Mechanic and run install.bat again, or the mod will NOT load.
        goto :fail
    )
    echo [i] Cleared the compiled script bundle - it rebuilds on next launch.
)

echo.
echo [OK] Survival Import Mod installed!
echo      In survival you now have: /export ^<name^>, /build ^<name^>, /destroy
echo      In creative you now have: /export ^<name^>, /import ^<name^>
echo.
echo      NOTE: a game update or "Verify integrity of game files" in Steam
echo      will restore the vanilla files - just run install.bat again.
echo      (After a game UPDATE, run uninstall.bat first and re-port if the
echo      game scripts changed - see README.md)
pause
exit /b 0

:fail
echo.
echo [!] Installation FAILED - no files were changed beyond what is listed above.
pause
exit /b 1
