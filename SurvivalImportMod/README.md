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
| `/export <name>` | Saves the creation you aim at to `Survival\LocalBlueprints\<name>.blueprint`. An existing blueprint of that name is backed up as `<name>_backup` first. |
| `/build <name>` | Imports the blueprint at the spot you aim at, **consuming the required parts from your inventory** (container contents included). If anything is missing, nothing is built and the missing parts are listed in chat. |
| `/destroy` | Destroys the creation you aim at and drops all of its parts as loot bags. The creation is autosaved to `autosave.blueprint` first (`/build autosave` restores it). |

`/import <name>` (free, no materials) is bound **only in dev mode**, so normal survival
play has no way to spawn a creation for free.

Creative mode: `/export <name>` and `/import <name>` (shares the same
`LocalBlueprints` folder, so you can design in creative and build in survival).

Blueprints live in: `Steam\steamapps\common\Scrap Mechanic\Survival\LocalBlueprints\`

## Multiplayer note

The world **host** must have the mod installed; commands are executed server-side.
