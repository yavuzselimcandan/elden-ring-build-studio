# Current state — 2026-09-29

## Where the app lives

- **The git checkout is the installed app**: `C:/Users/YAVUZ-PC/Documents/GitHub/elden-ring-build-studio/app`. The Desktop shortcut `Elden Ring Build Studio.lnk` (custom icon `app/assets/BuildStudio.ico`) runs `app/Launch.vbs` → `app/BuildStudio.ps1` without a console window; created by `tools/Install.ps1`, which also removed the old `Elden Ring Build Configurator.lnk`.
- **No Cheat Engine** (since 2026-09-29, second change of the day): `app/lib/GameMemory.cs` opens eldenring.exe directly (same user, no admin) and `app/lib/BuildEngine.cs` applies stats, grants (game add-item routine via a remote stub) and equipment. The old CE autorun in Program Files is inert (it only reacts to a boot.flag in the retired folder) and can be deleted manually.
- Retired, left untouched: `Documents/Codex/2026-09-06/.../build_configurator` (canonical until 2026-09-11, holds historical `runtime/` evidence) and `Desktop/Elden Ring Build Configurator` (older copy). Presets were copied from both into `app/configs` (git-ignored) without overwriting.

## Working / verified

- **Live, confirmed in-game by the user (2026-09-29, game 2.2.0.0, Studio elevated because the game runs as admin):** stats; item grants (weapons, armor, talismans, ashes, goods) through the game add-item routine; equipping weapons/armor/talismans through the game equip routine (visible in the Equipment menu); memorising spells through the game changeMagic routine (visible in the spell menu); Gemini line-format import.

- Resolver (`app/lib/Resolver.cs` + `app/BuildModel.ps1`): normalised/alias/plural/fuzzy matching, item-string parsing, duplicate-name policy (lowest ID + note), category correction, unique-weapon built-in skills, Wondrous Physick splitting, note-like rows ignored. On the 7 local presets: 11 unresolved rows before, 1 after (an item that does not exist in the game).
- Plan schema 3.0: `notes`, `match`, `suggestions`, `rowIndex`, and an auto-assigned `loadout` (R1-3, L1-3, ammo, armor, Talisman1-4, Spell1-14). Preset schema 3.0 (`preset.schema.json`) adds optional `slot` / `affinity`.
- UI (`app/BuildStudio.ps1` + `app/ui/MainWindow.xaml`): preset library, one-click Gemini prompt + automatic clipboard import of the line format or JSON (`app/BuildText.ps1`, tested by `test_build_text.ps1`), attribute steppers + rune level, equipment slot board, live fuzzy picker filtered per slot, resolution panel with one-click fixes, connection chip, autosave, auto-apply toggle. Verified by `-CheckOnly` and by screenshots of the running window; no full interactive GUI test suite.
- Live game (from 2026-09-07/11 evidence, previous agents): stat writes with readback and item grants with inventory readback worked on game 2.2.0.0 via the (now removed) CE bridge; the new direct backend reuses the same game routine and offsets.

## Implemented, NOT yet verified in a live game

- **Everything live** (stats, grants, inventory discovery, auto-equip) now runs through the direct backend, which has only been tested against mocked memory (`test_engine.ps1`) and real Win32 calls on a throw-away process (`test_game_memory.ps1`). Run `tools/Probe-Game.ps1` (read-only) with the game open offline before the first apply. Auto-equip calibrates the ChrAsm arrays against live inventory before any write (id-array base 0x398 observed on 2.2.0.0, 0x39C in CT v8.0.1). Whether the game refreshes model/stats right after the write is unknown.
- Weapons with an Ash of War are now granted (the Ash is reported as not attached).

## Not implemented

- Ash of War attachment, affinity changes on owned weapons, memory (spell) slot equipping, quick items/pouch.
- Per-weapon upgrade limits (somber +10), class/level constraints.

## Tests

`app/test_*.ps1` (resolver, model, full plan, legacy normalisation, inventory decode, engine with mocked memory, Win32 plumbing) and `app/BuildStudio.ps1 -CheckOnly`. `test_full_plan.ps1` reads a machine-specific preset path.

## Local machine (never commit)

- Game: `D:/Games/ELDEN RING/Game/eldenring.exe`, FileVersion `2.2.0.0`.
- CT: `C:/Users/YAVUZ-PC/Downloads/eldenring_all-in-one_Hexinton-v8.0.1.CT` (targets 2.7.0.0; its ChrAsm offsets are 4 bytes later than observed on 2.2.0.0).
- Saves: `%APPDATA%/EldenRing/76561197960271872/`; every apply first copies `ER0000.sl2` to `app/runtime/backups/`.
