# Survival Tweaks — for Scrap Mechanic 1.0

Two things, in one mod:

* **Blueprint building** — `/build <name>` places one of your creations and charges the
  parts to your inventory. Started as the Survival Import Mod
  (scrapmechanicmods.com/m=65), ported from 0.6 to 1.0.
* **Fall damage toggle** — `/falldamage`, off by default per world.

The original 0.6 download shipped full copies of `SurvivalGame.lua` / `CreativeGame.lua`
from that era, which reference scripts that moved or were removed in 1.0 (e.g.
`EffectManager.lua` moved to `$GAME_DATA`), so installing them on 1.0 silently breaks.
This port grafts the logic into the **current 1.0 vanilla files** instead. The originals
from the download are untouched in `Data\` and `Survival\` (kept for reference); the
ported files live in `patched\`.

## How Scrap Mechanic handles mods (and why this one patches game files)

The `Mods` folder in your user profile —
`%APPDATA%\Axolot Games\Scrap Mechanic\User\User_<id>\Mods` — is for **Steam Workshop
content**: custom parts, blocks, tiles, worlds. Each mod is a UGC folder the engine
registers under a `$CONTENT_<uuid>` path alias (the same system your lift blueprints
use). The engine's UGC loader looks for `shapesets`, `harvestables`, `assetsets`,
`Prefabs`, `Terrain`, `Effects`, `Nodes` and similar — **there is no entry for
overriding base game scripts**. A Workshop mod can ship scripts for its own new parts,
but nothing lets it replace `SurvivalGame.lua` or `BasePlayer.lua`.

So a mod that changes *game behaviour* has to edit the game's `.lua` files in place,
which is what this one does. Consequences:

* Two such mods **conflict only if they patch the same file**. This mod patches three
  files and keeps them in `patched\`; adding a fourth is one line in `patchset.ps1`.
* **Steam reverts everything** on a game update or *Verify integrity of game files*.
* After a game update, a patched file may be based on an outdated vanilla. `install.bat`
  now detects that and refuses rather than silently reverting part of the update — see
  *Game updates* below.

## Patched files

| Game file | Why |
|---|---|
| `Survival\Scripts\game\SurvivalGame.lua` | the survival chat commands |
| `Data\Scripts\game\CreativeGame.lua` | `/export` + `/import` in creative |
| `Data\Scripts\game\BasePlayer.lua` | one line, for fall damage |
| `Survival\Scripts\util.lua` | the fall damage check itself |

## The gotcha that makes script edits look broken

**Scrap Mechanic 1.0 does not run the loose `.lua` files.** It runs a compiled bundle,
`Cache\Bundle\core_data.cbo`, built from them on first launch. Editing a script has
**zero effect** — no error, no log entry, nothing — until that bundle is deleted, at
which point the game rebuilds it from the `.lua` files on the next launch (that launch
takes noticeably longer).

This is why the original mod appeared "not to enable": the code was never being read.

`install.bat` and `uninstall.bat` delete the bundle for you. Both refuse to run while
the game is open, because the file is locked then. **Always close the game first.**

If you ever edit a script by hand, delete the bundle yourself:

    del "C:\Program Files (x86)\Steam\steamapps\common\Scrap Mechanic\Cache\Bundle\core_data.cbo"

## Install / Uninstall

* Close Scrap Mechanic.
* Run `install.bat` — backs up the vanilla files to `backup\`, installs, clears the bundle.
* Run `uninstall.bat` — restores the vanilla files and clears the bundle again.

If Windows denies access, right-click → *Run as administrator*.

A green `[SurvivalTweaks] ready: ...` line appears in chat when you load a survival
world, listing the commands it bound. No line means the mod is not active — the usual
cause is a stale bundle (rerun `install.bat` with the game closed).

**The first launch after the bundle is cleared sometimes crashes** on the way to the
main menu, while it regenerates ~17,700 caches. This is a cold-cache flake, not the
mod — just launch again and it proceeds. If it crashes twice, delete every `.cbo` in
`Cache\Bundle\` so they all rebuild against the same game version.

## Game updates

**Steam undoes the mod** whenever the game updates or you use *Verify integrity of game
files* — run `install.bat` again.

The dangerous case is an update that *changes a file this mod patches*. Reinstalling
would then overwrite the new version with edits built from the old one, silently
reverting part of the update. (This happened once: an update added the weather system to
`CreativeGame.lua`, and the stale patch would have removed it again.)

To catch it, `install.bat` records the SHA-256 of the vanilla each patch was built from
in `patched\basefiles.sha256`, and **refuses to install** when the vanilla on disk no
longer matches:

    [!] The game has been updated since these patches were made:
          CreativeGame.lua

Re-port the mod onto the new vanilla in `backup\`, then run `install.bat /accept` to
record the new baseline. To re-port: copy the vanilla from `backup\` over the file in
`patched\`, re-apply the `[SurvivalTweaks]` blocks, and confirm with
`diff --strip-trailing-cr -u backup\X.lua patched\X.lua` that nothing vanilla was lost.

## Commands

Survival mode (no dev mode needed):

| Command | Effect |
|---|---|
| `/build <name>` | Builds `<name>` where you are aiming, **consuming the required parts from your inventory** (container contents included). If anything is missing, nothing is built and the missing parts are listed in chat. |
| `/blueprints` | Lists everything `/build` can place. |
| `/export <name>` | Saves the creation you aim at to `Survival\LocalBlueprints\Exported\<name>.blueprint`. An existing export of that name is backed up as `<name>_backup` first. |
| `/destroy` | Destroys the creation you aim at and drops all of its parts as loot bags. The creation is autosaved first, so `/build autosave` puts it back. |
| `/falldamage [on\|off]` | Turns fall damage on or off. With no argument it toggles. **Off by default.** Saved per world, so it survives rejoining. |

### About `/falldamage`

Only *falling* stops hurting. Collision damage is untouched — drive a creation into a
wall, get hit by a spinning sawblade, or have something land on you and you still take
damage as normal. Weapons, drowning, starvation and bots are all unaffected.

Hard landings still **ragdoll** you — only the damage is removed.

The implementation is worth knowing about, because the obvious version does not work.
`CharacterCollision` in `Survival\Scripts\util.lua` ends with:

```lua
local damage = fallDamage > 0 and fallDamage or math.max( collisionDamage, specialCollisionDamage )
```

Landing on the ground is *itself* a collision, and it produces a `collisionDamage` value
too. In vanilla the fall damage simply shadows it. So zeroing `fallDamage` does **not**
disable fall damage — it just uncovers the collision damage underneath, and you keep
taking (smaller) damage on landing. Both terms have to be cleared, and only for a landing
on something that is not itself moving:

```lua
if noFallDamage and fFallImpact > 2.5 and math.abs( velOther.z ) < 0.01 then
    fallDamage = 0
    collisionDamage = 0
end
```

That is the game's own landing test, reused from the block directly above it.
`specialCollisionDamage` — spinning sawblades — is deliberately left alone, as is
`fallTumbleTicks`, which is why the ragdoll survives.

`noFallDamage` is a trailing optional argument on `CharacterCollision`. Only the patched
`BasePlayer.lua` passes it; every bot caller passes fewer arguments, so it is `nil` for
them and their behaviour is untouched.

In multiplayer only the **host** needs the mod — the check runs server-side.

`/import <name>` (free, no materials) is bound **only in dev mode**, so normal survival
play has no way to spawn a creation for free.

Creative mode: `/export <name>` and `/import <name>`, sharing the same blueprints, so
you can design in creative and build it for real in survival.

## What `/build <name>` can find

Two kinds of creation, checked in this order:

1. **Blueprints you saved in-game** — park a creation on a lift, interact with it and
   save. `/build Car mk1` builds the one named *Car mk1*.
2. **`/export` files** — `Survival\LocalBlueprints\Exported\<name>.blueprint`.

If both exist with the same name, the in-game blueprint wins. Names ignore case,
spaces and underscores, so `Car mk1`, `car_mk1` and `CARMK1` are the same thing. A
blueprint's local id (the guid folder name) works as a name too.

### Run `refresh-blueprints.bat` after saving new blueprints

A creation saved on a lift is stored in your user profile in a folder named after its
local id, and the game exposes it to scripts as `$CONTENT_<localId>`. Scripts can read
that path, but Lua in Scrap Mechanic **has no way to list a directory** — so nothing in
the game can turn the name you typed into a folder id on its own.

`refresh-blueprints.bat` scans your profile and writes that name → id map to
`Survival\LocalBlueprints\_userblueprints.json`. `install.bat` runs it for you, but
after you save a *new* blueprint on a lift you have to run it again before `/build`
knows the name. It is safe to run while the game is open; rejoin the world (or use the
guid) to pick up the change. `/blueprints` prints when the index was last built.

Files:

* saved in-game → `%APPDATA%\Axolot Games\Scrap Mechanic\User\User_<id>\Blueprints\`
* `/export`     → `Steam\steamapps\common\Scrap Mechanic\Survival\LocalBlueprints\Exported\`

`Exported\` is a subfolder on purpose: `LocalBlueprints` itself holds ~900 of the
game's own level-decoration blueprints, which would bury your creations in any listing.
They are all still reachable by name if you want to place one.

## Multiplayer note

The world **host** must have the mod installed; commands are executed server-side.
