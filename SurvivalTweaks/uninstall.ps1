# ============================================================
#  Survival Tweaks - uninstaller
#  Restores the vanilla files from the backup made by install.
# ============================================================

$ErrorActionPreference = 'Stop'
. ( Join-Path $PSScriptRoot 'patchset.ps1' )

$GameRoot = Find-GameRoot $PSScriptRoot
if ( -not $GameRoot ) {
    Write-Host '[!] Could not find the Scrap Mechanic folder above this script.'
    exit 1
}

if ( Get-Process ScrapMechanic -ErrorAction SilentlyContinue ) {
    Write-Host '[!] Scrap Mechanic is running. Close it first, or the mod will stay active.'
    exit 1
}

$backupDir = Join-Path $PSScriptRoot 'backup'
$restored = 0
$skipped  = @()

foreach ( $entry in $PatchSet ) {
    $live   = Join-Path $GameRoot  $entry.Game
    $backup = Join-Path $backupDir $entry.Patched

    if ( -not ( Test-IsModded $live ) ) { continue }

    if ( -not ( Test-Path $backup ) ) {
        $skipped += $entry.Game
        continue
    }

    Copy-Item $backup $live -Force
    Write-Host "[i] Restored $($entry.Game)"
    $restored++
}

if ( $skipped.Count -gt 0 ) {
    Write-Host ''
    Write-Host '[!] No backup found for:'
    foreach ( $name in $skipped ) { Write-Host "      $name" }
    Write-Host '    Restore those with Steam:'
    Write-Host '    Library > Scrap Mechanic > Properties > Installed Files > Verify integrity of game files'
}

if ( $restored -eq 0 -and $skipped.Count -eq 0 ) {
    Write-Host '[i] The mod is not currently installed - nothing to do.'
    exit 0
}

$bundle = Join-Path $GameRoot 'Cache\Bundle\core_data.cbo'
if ( Test-Path $bundle ) {
    Remove-Item $bundle -Force
    Write-Host '[i] Cleared the compiled script bundle - it rebuilds on next launch.'
}

Write-Host ''
Write-Host '[OK] Vanilla files restored. The mod is uninstalled.'
Write-Host '     Your creations in Survival\LocalBlueprints\Exported were left alone.'
exit $( if ( $skipped.Count -gt 0 ) { 1 } else { 0 } )
