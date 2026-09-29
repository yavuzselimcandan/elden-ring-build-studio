# Current state — 2026-09-29

## Where the app lives

- **The git checkout is the installed app**: `C:/Users/YAVUZ-PC/Documents/GitHub/elden-ring-build-studio/app`. The Desktop shortcut `Elden Ring Build Studio.lnk` (custom icon `app/assets/BuildStudio.ico`) runs `app/Launch.vbs` → `app/BuildStudio.ps1` without a console window; created by `tools/Install.ps1`, which also removed the old `Elden Ring Build Configurator.lnk`.
- The app writes its location to `%LOCALAPPDATA%/EldenRingBuildStudio/root.txt`; the CE autorun (`app/BuildStudioAutorun.lua`) reads it. Until `tools/Install.ps1` is run once with admin approval, the *installed* autorun in `C:/Program Files/Cheat Engine/autorun/zz_EldenRingBuildStudio.lua` is the old copy that hard-codes the retired Documents/Codex path, so live apply from the new location will not be picked up.
- Retired, left untouched: `Documents/Codex/2026-09-06/.../build_configurator` (canonical until 2026-09-11, holds historical `runtime/` evidence) and `Desktop/Elden Ring Build Configurator` (older copy). Presets were copied from both into `app/configs` (git-ignored) without overwriting.

## Visual assets

- Generated icon source: `app/assets/icon-source.png`. The built-in image generator emitted 1254x1254 pixels; the requested exact 1024x1024 dimensions remain unmet. The icon is not wired into packaging or the desktop shortcut.

## Working / verified

- Resolver (`app/lib/Resolver.cs` + `app/BuildModel.ps1`): normalised/alias/plural/fuzzy matching, item-string parsing, duplicate-name policy (lowest ID + note), category correction, unique-weapon built-in skills, Wondrous Physick splitting, note-like rows ignored. On the 7 local presets: 11 unresolved rows before, 1 after (an item that does not exist in the game).
- Plan schema 3.0: `notes`, `match`, `suggestions`, `rowIndex`, and an auto-assigned `loadout` (R1-3, L1-3, ammo, armor, Talisman1-4, Spell1-14). Preset schema 3.0 (`preset.schema.json`) adds optional `slot` / `affinity`.
- UI (`app/BuildStudio.ps1` + `app/ui/MainWindow.xaml`): preset library, clipboard JSON import, attribute steppers + rune level, equipment slot board, live fuzzy picker filtered per slot, resolution panel with one-click fixes, connection chip, autosave, auto-apply toggle. Verified by `-CheckOnly` and by screenshots of the running window; no full interactive GUI test suite.
- Live game (from 2026-09-07/11 evidence, previous agents): stat writes with readback and item grants with inventory readback worked on game 2.2.0.0 via the CE bridge.

## Implemented, NOT yet verified in a live game

- **Auto-equip** (`app/equip_adapter.lua`, wired into `bridge.lua` build mode, fed by `equip=` lines from `backend.ps1`): calibrates the ChrAsm handle/id arrays against live inventory before any write (candidate id-array bases 0x398 = observed on 2.2.0.0, 0x39C = CT v8.0.1), refuses on any inconsistency, equips only owned items, reads back, rolls back on failure. Exercised only against mocked memory (`app/test_equip_adapter.ps1`, CE's lua53-64.dll). Whether the game refreshes model/stats immediately after the write is unknown.
- Weapons with an Ash of War are now granted (the Ash is reported as not attached).

## Not implemented

- Ash of War attachment, affinity changes on owned weapons, memory (spell) slot equipping, quick items/pouch.
- Per-weapon upgrade limits (somber +10), class/level constraints.

## Tests

`app/test_*.ps1` (resolver/model, full plan, legacy normalisation, pending contract, inventory decode, Ash table source, equip adapter spec) and `app/BuildStudio.ps1 -CheckOnly`. `test_full_plan.ps1` and `test_ash_mapping.ps1` read machine-specific paths.

## Local machine (never commit)

- Game: `D:/Games/ELDEN RING/Game/eldenring.exe`, FileVersion `2.2.0.0`.
- CT: `C:/Users/YAVUZ-PC/Downloads/eldenring_all-in-one_Hexinton-v8.0.1.CT` (targets 2.7.0.0; its ChrAsm offsets are 4 bytes later than observed on 2.2.0.0).
- CE: `C:/Program Files/Cheat Engine/cheatengine-x86_64.exe`.
- Saves: `%APPDATA%/EldenRing/76561197960271872/`; every apply first copies `ER0000.sl2` to `app/runtime/backups/`.
