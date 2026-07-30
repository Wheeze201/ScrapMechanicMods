# ============================================================
#  Survival Tweaks - installer
#  Backs up the vanilla files, installs the patched ones, clears the script bundle
#  and rebuilds the blueprint index.
# ============================================================

param( [switch]$AcceptNewBaseFiles )

$ErrorActionPreference = 'Stop'
. ( Join-Path $PSScriptRoot 'patchset.ps1' )

$GameRoot = Find-GameRoot $PSScriptRoot
if ( -not $GameRoot ) {
    Write-Host '[!] Could not find the Scrap Mechanic folder above this script.'
    Write-Host '    Keep this mod inside the game directory.'
    exit 1
}

if ( Get-Process ScrapMechanic -ErrorAction SilentlyContinue ) {
    Write-Host '[!] Scrap Mechanic is running. Close it first - the script bundle is locked'
    Write-Host '    while the game is open, and the mod will not load if it cannot be cleared.'
    exit 1
}

$patchedDir   = Join-Path $PSScriptRoot 'patched'
$backupDir    = Join-Path $PSScriptRoot 'backup'
$manifestFile = Join-Path $patchedDir 'basefiles.sha256'
$manifest     = Read-Manifest $manifestFile

# --- write test -------------------------------------------------------------
$probe = Join-Path $GameRoot '__writetest.tmp'
try {
    [System.IO.File]::WriteAllText( $probe, 'x' )
    Remove-Item $probe -Force
} catch {
    Write-Host '[!] No write permission in the game folder.'
    Write-Host '    Right-click install.bat and choose "Run as administrator".'
    exit 1
}

if ( -not ( Test-Path $backupDir ) ) { New-Item -ItemType Directory -Path $backupDir | Out-Null }

# --- back up, and check each patch is still based on the current vanilla -----
$stale = @()
foreach ( $entry in $PatchSet ) {
    $live       = Join-Path $GameRoot   $entry.Game
    $patched    = Join-Path $patchedDir $entry.Patched
    $backup     = Join-Path $backupDir  $entry.Patched

    if ( -not ( Test-Path $live ) )    { Write-Host "[!] Missing game file: $live"; exit 1 }
    if ( -not ( Test-Path $patched ) ) { Write-Host "[!] Missing patched file: $patched"; exit 1 }

    # Back up per file, and only when that file is genuinely vanilla. Backing up a
    # modded file would destroy the only copy of the original.
    if ( Test-IsModded $live ) {
        if ( -not ( Test-Path $backup ) ) {
            Write-Host "[!] $($entry.Game) is already modded and there is no backup of it."
            Write-Host '    Restore it with Steam (Verify integrity of game files), then re-run.'
            exit 1
        }
    } else {
        Copy-Item $live $backup -Force
        Write-Host "[i] Backed up $($entry.Game)"
    }

    # The vanilla the patch was built from, versus the vanilla on disk now.
    $baseHash = Get-Sha256 $backup
    $recorded = $manifest[$entry.Patched]
    if ( $recorded -and $recorded -ne $baseHash ) {
        $stale += $entry.Patched
    }
    $manifest[$entry.Patched] = $baseHash
}

if ( $stale.Count -gt 0 -and -not $AcceptNewBaseFiles ) {
    Write-Host ''
    Write-Host '[!] The game has been updated since these patches were made:'
    foreach ( $name in $stale ) { Write-Host "      $name" }
    Write-Host ''
    Write-Host '    Installing now would overwrite the new versions with edits based on the'
    Write-Host '    old ones, silently reverting part of the update. Re-port the mod onto the'
    Write-Host '    current vanilla files in backup\ first.'
    Write-Host ''
    Write-Host '    If you have already done that, re-run with:  install.bat /accept'
    exit 1
}

# --- install ----------------------------------------------------------------
foreach ( $entry in $PatchSet ) {
    Copy-Item ( Join-Path $patchedDir $entry.Patched ) ( Join-Path $GameRoot $entry.Game ) -Force
    Write-Host "[i] Installed $($entry.Game)"
}
Write-Manifest $manifestFile $manifest

# --- /export writes here; keeps creations out of the ~900 game blueprints ----
$exportDir = Join-Path $GameRoot 'Survival\LocalBlueprints\Exported'
if ( -not ( Test-Path $exportDir ) ) { New-Item -ItemType Directory -Path $exportDir | Out-Null }

# --- clear the compiled bundle ----------------------------------------------
# The game runs a compiled bundle, not the loose .lua files. Editing a script does
# nothing until this is deleted; the game rebuilds it on the next launch, which takes
# noticeably longer. That first rebuild launch is also known to crash occasionally -
# just launch again if it does.
$bundle = Join-Path $GameRoot 'Cache\Bundle\core_data.cbo'
if ( Test-Path $bundle ) {
    Remove-Item $bundle -Force
    Write-Host '[i] Cleared the compiled script bundle - it rebuilds on next launch.'
}

# --- index the blueprints saved on a lift -----------------------------------
Write-Host ''
& ( Join-Path $PSScriptRoot 'refresh-blueprints.ps1' ) -GameRoot $GameRoot

Write-Host ''
Write-Host '[OK] Survival Tweaks installed!'
Write-Host '     Survival:  /build <name>, /blueprints, /export <name>, /destroy, /falldamage'
Write-Host '     Creative:  /export <name>, /import <name>'
Write-Host ''
Write-Host '     Fall damage is OFF by default in each world. Toggle it with /falldamage,'
Write-Host '     or set it explicitly: /falldamage on | /falldamage off'
Write-Host ''
Write-Host '     After saving new creations on a lift, run refresh-blueprints.bat'
Write-Host '     so /build can find them by name.'
Write-Host ''
Write-Host '     A game update or "Verify integrity of game files" restores the vanilla'
Write-Host '     files - run install.bat again. If the update changed a patched script,'
Write-Host '     install.bat will stop and tell you to re-port it.'
exit 0
