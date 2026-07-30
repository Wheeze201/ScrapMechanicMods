# Survival Import Mod — ported to Scrap Mechanic 1.0

The original mod (scrapmechanicmods.com/m=65) was built for Scrap Mechanic 0.6 and
shipped full copies of `SurvivalGame.lua` / `CreativeGame.lua` from that era. Those
files reference scripts that moved or were removed in 1.0 (e.g. `EffectManager.lua`
moved to `$GAME_DATA`), so installing them on 1.0 silently breaks.

This port grafts the mod's logic into the **current 1.0 vanilla files** instead.
The originals from the download are untouched in `Data\` and `Survival\` (kept for
reference); the ported files live in `patched\`.

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

A green `[SurvivalImportMod] ready: ...` line appears in chat when you load a survival
world, listing the commands it bound. No line means the mod is not active — the usual
cause is a stale bundle (rerun `install.bat` with the game closed).

**Steam will undo the mod** whenever the game updates or you use *Verify integrity
of game files* — just run `install.bat` again. If a real game update ships, the
patched files are based on the pre-update scripts; if survival behaves oddly after
an update, uninstall and re-do the port against the new files.

## Commands

Survival mode (no dev mode needed):

| Command | Effect |
|---|---|
| `/build <name>` | Builds `<name>` where you are aiming, **consuming the required parts from your inventory** (container contents included). If anything is missing, nothing is built and the missing parts are listed in chat. |
| `/blueprints` | Lists everything `/build` can place. |
| `/export <name>` | Saves the creation you aim at to `Survival\LocalBlueprints\Exported\<name>.blueprint`. An existing export of that name is backed up as `<name>_backup` first. |
| `/destroy` | Destroys the creation you aim at and drops all of its parts as loot bags. The creation is autosaved first, so `/build autosave` puts it back. |

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
