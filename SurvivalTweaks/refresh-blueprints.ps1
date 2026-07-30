# ============================================================
#  Survival Tweaks - blueprint index generator
#
#  Creations saved in-game on a lift live in the user profile, one folder per
#  blueprint named after its local id, and the engine exposes each one to script
#  as the path alias  $CONTENT_<localId>.  Script can READ that path but has no
#  way to list a directory, so it cannot map the name you typed to a folder.
#
#  This writes that map to Survival\LocalBlueprints\_userblueprints.json, which
#  is what /build and /blueprints read.  Re-run it after saving new blueprints.
# ============================================================

param( [string]$GameRoot )

$ErrorActionPreference = 'Stop'

# Release\ScrapMechanic.exe, not Survival\Scripts: this mod keeps its own copy of the
# script tree for reference, so that path matches inside the mod folder too.
function Find-GameRoot( [string]$start ) {
    $dir = $start
    while ( $dir ) {
        if ( Test-Path ( Join-Path $dir 'Release\ScrapMechanic.exe' ) ) { return $dir }
        $parent = Split-Path -Parent $dir
        if ( $parent -eq $dir ) { break }
        $dir = $parent
    }
    return $null
}

if ( -not $GameRoot ) { $GameRoot = Find-GameRoot $PSScriptRoot }
if ( -not $GameRoot ) {
    Write-Host '[!] Could not find the Scrap Mechanic folder above this script.'
    Write-Host '    Keep this script inside the game directory, or pass -GameRoot "<path>".'
    exit 1
}

$outDir  = Join-Path $GameRoot 'Survival\LocalBlueprints'
$outFile = Join-Path $outDir   '_userblueprints.json'
# /export writes here; LocalBlueprints itself holds ~900 of the game's own blueprints
$exportDir = Join-Path $outDir 'Exported'

if ( -not ( Test-Path $outDir ) ) {
    Write-Host "[!] $outDir does not exist - is this really the game folder?"
    exit 1
}
if ( -not ( Test-Path $exportDir ) ) {
    New-Item -ItemType Directory -Path $exportDir | Out-Null
    Write-Host "[i] Created $exportDir"
}

# --- creations saved on a lift ------------------------------------------------
$found = @()
$userRoot = Join-Path $env:APPDATA 'Axolot Games\Scrap Mechanic\User'

if ( Test-Path $userRoot ) {
    foreach ( $user in Get-ChildItem -Path $userRoot -Directory -Filter 'User_*' ) {
        $bpRoot = Join-Path $user.FullName 'Blueprints'
        if ( -not ( Test-Path $bpRoot ) ) { continue }

        foreach ( $folder in Get-ChildItem -Path $bpRoot -Directory ) {
            $descFile = Join-Path $folder.FullName 'description.json'
            $bpFile   = Join-Path $folder.FullName 'blueprint.json'
            if ( -not ( Test-Path $descFile ) ) { continue }
            if ( -not ( Test-Path $bpFile ) )   { continue }

            try { $desc = Get-Content $descFile -Raw | ConvertFrom-Json } catch { continue }
            if ( -not $desc.name ) { continue }

            $name = [string]$desc.name
            $found += [pscustomobject]@{
                name     = $name
                id       = $folder.Name
                # must match blueprintKey() in SurvivalGame.lua
                key      = ( $name.ToLower() -replace '[^a-z0-9]', '' )
                modified = ( Get-Item $bpFile ).LastWriteTimeUtc
            }
        }
    }
} else {
    Write-Host "[i] No user profile found at $userRoot - only /export files will be listed."
}

# two blueprints can share a name; the most recently saved one wins
$blueprints = @(
    $found |
        Where-Object { $_.key -ne '' } |
        Group-Object key |
        ForEach-Object { $_.Group | Sort-Object modified -Descending | Select-Object -First 1 } |
        Sort-Object name
)

# --- creations saved with /export ---------------------------------------------
$exports = @(
    Get-ChildItem -Path $exportDir -Filter '*.blueprint' -File |
        ForEach-Object { $_.BaseName } |
        Sort-Object
)

# --- write the index ----------------------------------------------------------
# Built by hand rather than with ConvertTo-Json: Windows PowerShell 5.1 collapses a
# one-element array into an object, and the game's json parser wants a real array.
function JsonString( [string]$s ) { return ( ConvertTo-Json -InputObject $s -Compress ) }

$lines = @()
$lines += '{'
$lines += "`t""version"" : 1,"
$lines += "`t""generated"" : $( JsonString ( Get-Date ).ToString( 'yyyy-MM-dd HH:mm' ) ),"

$entries = @()
foreach ( $bp in $blueprints ) {
    $entries += "`t`t{ ""name"" : $( JsonString $bp.name ), ""key"" : $( JsonString $bp.key ), ""id"" : $( JsonString $bp.id ) }"
}
$lines += "`t""blueprints"" : ["
if ( $entries.Count -gt 0 ) { $lines += ( $entries -join ",`r`n" ) }
$lines += "`t],"

$entries = @()
foreach ( $name in $exports ) { $entries += "`t`t$( JsonString $name )" }
$lines += "`t""exports"" : ["
if ( $entries.Count -gt 0 ) { $lines += ( $entries -join ",`r`n" ) }
$lines += "`t]"
$lines += '}'

$json = ( $lines -join "`r`n" ) + "`r`n"

# no BOM: the game's parser chokes on one
[System.IO.File]::WriteAllText( $outFile, $json, ( New-Object System.Text.UTF8Encoding( $false ) ) )

Write-Host ''
Write-Host "[OK] Indexed $( $blueprints.Count ) blueprint(s) and $( $exports.Count ) export(s)."
foreach ( $bp in $blueprints ) { Write-Host "     blueprint  $( $bp.name )" }
foreach ( $name in $exports )  { Write-Host "     export     $name" }
Write-Host ''
Write-Host "     Written to $outFile"
Write-Host '     In game: /blueprints to list them, /build <name> to build one.'
exit 0
