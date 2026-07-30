@echo off
setlocal
rem ============================================================
rem  Survival Import Mod - installer (ported to Scrap Mechanic 1.0)
rem  Backs up the vanilla files, then copies the patched ones in.
rem ============================================================

rem --- locate the game folder by walking up from this script ---
rem     Release\ScrapMechanic.exe is the marker, not Survival\Scripts: this mod
rem     keeps its own copy of the script tree, which would match too.
set "GAME=%~dp0."
if exist "%GAME%\Release\ScrapMechanic.exe" goto :gotgame
set "GAME=%~dp0.."
if exist "%GAME%\Release\ScrapMechanic.exe" goto :gotgame
set "GAME=%~dp0..\.."
if exist "%GAME%\Release\ScrapMechanic.exe" goto :gotgame
set "GAME=%~dp0..\..\.."
if exist "%GAME%\Release\ScrapMechanic.exe" goto :gotgame
echo [!] Could not find the Scrap Mechanic folder above this script.
echo     Keep this mod inside the game directory.
goto :fail
:gotgame

set "SG=%GAME%\Survival\Scripts\game\SurvivalGame.lua"
set "CG=%GAME%\Data\Scripts\game\CreativeGame.lua"
set "PATCHED=%~dp0patched"
set "BACKUP=%~dp0backup"
set "EXPORTS=%GAME%\Survival\LocalBlueprints\Exported"

if not exist "%SG%" (
    echo [!] Could not find "%SG%".
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

rem --- /export writes here; keeps player creations out of the ~900 game blueprints ---
if not exist "%EXPORTS%" mkdir "%EXPORTS%"

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

rem --- index the blueprints saved on a lift, so /build can find them by name ---
echo.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0refresh-blueprints.ps1" -GameRoot "%GAME%"

echo.
echo [OK] Survival Import Mod installed!
echo      In survival:  /build ^<name^>, /blueprints, /export ^<name^>, /destroy
echo      In creative:  /export ^<name^>, /import ^<name^>
echo.
echo      After saving new creations on a lift, run refresh-blueprints.bat
echo      so /build can find them by name.
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
