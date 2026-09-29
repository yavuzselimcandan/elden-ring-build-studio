# Current state — 2026-09-29 (end of the overhaul session)

**The product works end to end on the user's machine**: chat/Gemini build text → preset → resolved plan → applied to the
running offline game (stats, items, equipment, spells), each change read back from game memory, confirmed in-game by the user.
Open and half-done work: [next_steps.md](next_steps.md).

## Where things live

- Repository = installed app: `C:/Users/YAVUZ-PC/Documents/GitHub/elden-ring-build-studio`. Run `app/BuildStudio.ps1`.
  Desktop shortcut **Elden Ring Build Studio.lnk** → `app/Launch.vbs` (no console window), icon `app/assets/BuildStudio.ico`,
  created by `tools/Install.ps1`.
- User presets: `app/configs/*.json` (+ generated `*.plan.json`), git-ignored. Runtime output (save backups, apply ledgers,
  calibration reports, settings): `app/runtime/`, git-ignored.
- Branch `overhaul/v3`, PR #1 open against `main`.

## Components (all verified)

| Area | Files | Status |
|---|---|---|
| Resolver | `app/lib/Resolver.cs`, `app/BuildModel.ps1` | normalised/alias/plural/fuzzy match, string parsing, duplicate policy, unique-weapon skills, loadout planning. Tests: `test_resolver.ps1`, `test_build_model.ps1`, `test_luna_normalization.ps1`, `test_full_plan.ps1` |
| Chat import | `app/BuildText.ps1` | Gemini prompt (≈500 chars) + tolerant line-format/JSON parser, invariant culture. Test: `test_build_text.ps1` |
| UI | `app/BuildStudio.ps1`, `app/ui/MainWindow.xaml` | preset library, Gemini prompt button, auto clipboard import (once per text), slot board, fuzzy picker, resolution panel, connection chip, elevation relaunch, autosave |
| Game access | `app/lib/GameMemory.cs` | OpenProcess/RPM/WPM, signature scan, remote call. Test: `test_game_memory.ps1` (throw-away process) |
| Game logic | `app/lib/BuildEngine.cs`, `app/backend.ps1` | stats, grants (AddItem), inventory discovery, equip (game equipGear routine), spells (changeMagic), save backup, ledger. Test: `test_engine.ps1` (mocked memory) |

Live evidence (game 2.2.0.0, user-confirmed in-game): Genuine Tank preset — weapons/talismans equipped and visible in the
Equipment menu; Hydromancer Wade preset — 9/9 slots and 4/4 spells, `applied=True`. Details of offsets and calls:
[../L2/game-internals.md](../L2/game-internals.md).

## Behaviour worth knowing

- The user's game runs as administrator, so the Studio must run elevated to attach; it offers that itself ("Click to connect as admin").
- Every apply: save backup → stats (read back) → grant missing quantities only → equip (calibrated, via game routine,
  invalid copies replaced) → spells (via game routine) → ledger `app/runtime/ledger-*.txt`. Receipt `applied=true` only when nothing failed.
- Flasks count as one item; spells beyond the unlocked memory slots are reported, not forced.

## Not implemented / partial

See [next_steps.md](next_steps.md): Ash of War attachment, removing invisible copies, near-miss fuzzy matches, quick items/pouch,
somber upgrade limits, apply off the UI thread, preset delete/rename.

## Local machine (never commit)

- Game `D:/Games/ELDEN RING/Game/eldenring.exe` FileVersion 2.2.0.0 (runs elevated, offline, EAC off).
- Hexinton CT `C:/Users/YAVUZ-PC/Downloads/eldenring_all-in-one_Hexinton-v8.0.1.CT` (reference only; targets 2.7.0.0).
- Saves `%APPDATA%/EldenRing/76561197960271872/`.
- Retired copies (leave untouched): `Documents/Codex/2026-09-06/.../build_configurator`, `Desktop/Elden Ring Build Configurator`.
