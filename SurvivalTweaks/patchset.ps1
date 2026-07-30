# ============================================================
#  Survival Tweaks - shared helpers for install / uninstall
#
#  The mod works by replacing game .lua files in place. Scrap Mechanic has no
#  script-override system: the Mods folder in the user profile is for Steam Workshop
#  CONTENT (parts, tiles, worlds), and the engine's UGC loader has no entry for
#  overriding base game scripts. So there is nothing to hook - the files get patched,
#  and Steam reverts them on update or "Verify integrity of game files".
# ============================================================

# Every file this mod patches. Add a line here to patch another file.
#   Patched = path under patched\ , Game = path under the Scrap Mechanic folder
$PatchSet = @(
    [pscustomobject]@{ Patched = 'SurvivalGame.lua'; Game = 'Survival\Scripts\game\SurvivalGame.lua' }
    [pscustomobject]@{ Patched = 'CreativeGame.lua'; Game = 'Data\Scripts\game\CreativeGame.lua' }
    [pscustomobject]@{ Patched = 'BasePlayer.lua';   Game = 'Data\Scripts\game\BasePlayer.lua' }
    [pscustomobject]@{ Patched = 'util.lua';         Game = 'Survival\Scripts\util.lua' }
)

# Any of these in a file means "this is ours, not vanilla". The old name has to stay
# here forever: without it, installing over an older install would read the modded
# files as vanilla and overwrite backup\ with modded copies, destroying the way back.
$ModMarkers = @( 'SurvivalTweaks', 'SurvivalImportMod' )

function Find-GameRoot( [string]$start ) {
    # Release\ScrapMechanic.exe is the marker, not Survival\Scripts: this mod keeps its
    # own copy of the script tree for reference, which would match too.
    $dir = $start
    while ( $dir ) {
        if ( Test-Path ( Join-Path $dir 'Release\ScrapMechanic.exe' ) ) { return $dir }
        $parent = Split-Path -Parent $dir
        if ( $parent -eq $dir ) { break }
        $dir = $parent
    }
    return $null
}

function Test-IsModded( [string]$path ) {
    if ( -not ( Test-Path $path ) ) { return $false }
    $text = Get-Content $path -Raw
    foreach ( $marker in $ModMarkers ) {
        if ( $text -like "*$marker*" ) { return $true }
    }
    return $false
}

function Get-Sha256( [string]$path ) {
    return ( Get-FileHash $path -Algorithm SHA256 ).Hash
}

function Read-Manifest( [string]$path ) {
    # "<sha256>  <patched file name>" per line
    $map = @{}
    if ( Test-Path $path ) {
        foreach ( $line in Get-Content $path ) {
            if ( $line -match '^\s*([0-9A-Fa-f]{64})\s+(.+?)\s*$' ) {
                $map[$matches[2]] = $matches[1].ToUpper()
            }
        }
    }
    return $map
}

function Write-Manifest( [string]$path, [hashtable]$map ) {
    $lines = @( '# sha256 of the vanilla file each patched file was built from.',
                '# install.bat refuses to install when the live vanilla no longer matches,',
                '# which is what stops a game update from being silently reverted.' )
    foreach ( $name in ( $map.Keys | Sort-Object ) ) {
        $lines += "$($map[$name])  $name"
    }
    [System.IO.File]::WriteAllText( $path, ( ( $lines -join "`r`n" ) + "`r`n" ),
        ( New-Object System.Text.UTF8Encoding( $false ) ) )
}
