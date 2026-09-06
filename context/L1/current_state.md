# Current state — 2026-09-06

## Working/observed

- `app/BuildStudio.ps1`: native WPF app; New/Open/Save, eight attribute inputs, item grid and catalog search. Autosaves/resolves changed values after the grid loses keyboard focus; explicit Save commits edits.
- `app/BuildModel.ps1`: imports both legacy equipment-string presets and v2 item objects. Resolves exact category/name matches; separates weapon upgrades and Ash of War; reports unknown names, invalid quantities and attributes.
- `app/catalog.json`: 6,352 name/ID entries extracted from local Hexinton v8.0.1 dropdowns. These are table IDs, NOT validated against the installed game's live inventory routines.
- `app/preset.schema.json`: v2 contract. `app/build.schema.json` in original source is obsolete v1; installed desktop copy was replaced with v2. Consumers must use preset.schema.json.
- `app/EldenRingBuildConfigurator.ps1` delegates to BuildStudio.ps1. Desktop `.lnk` launches this entry with Windows PowerShell, hidden console, STA. The VBS quoting error was also fixed.
- Local skill and private personal plugin were updated with concrete v2 import instructions. Plugin version at last install: `1.0.0+codex.20260906113616`.

## Missing or unsafe to assume

- `backend.ps1` always returns ready/applied=false. `bridge.lua` raises an explicit unimplemented error. No CE live application, stat write, equipment placement, affinity/Ash installation, backup transaction or inventory readback is implemented.
- BuildStudio displays a hardcoded mismatch message; it does not invoke the backend or monitor game/CE. There is no real-time game synchronization.
- Current resolver only enforces general +0..25, not per-weapon upgrade limits, infusion legality, item stack limits, class minimums or level/stat consistency. Unknown sources and confirmation/evidence are not fully schema-validated. Plan IDs/receipts/deduplication are not implemented.
- Editing creates one `.previous` preset copy; this is not a game-save backup. New editor can still overwrite a same-named preset; naming/collision handling needs improvement.
- Some historical files remain: index.html/app.py/launch.ps1, manifest.json and BUILD_IMPORT.md. They are stale prototypes, not the canonical application contract. Source README may be stale; STATUS.md and this context are authoritative.

## Local machine (do not package these assets)

- Game: `D:/Games/ELDEN RING/Game/eldenring.exe`, observed FileVersion `2.2.0.0`.
- CT: `C:/Users/YAVUZ-PC/Downloads/eldenring_all-in-one_Hexinton-v8.0.1.CT`; SHA256 `D5C5077D6C5753430130DBB9692E933D2E41EDA89ADA3D27DAB5AB96A55D7AAD`; root code targets `2.7.0.0` (1.17).
- Downloaded v5.0 ZIP root code declares `0x2000600010000`, i.e. 2.6.1.0. No compatible write path was tested. A declared-version mismatch alone does not prove failure.
- CE: `C:/Program Files/Cheat Engine/cheatengine-x86_64.exe`; local API reference celua.txt in that folder.
- Desktop app: `C:/Users/YAVUZ-PC/Desktop/Elden Ring Build Configurator`; shortcut same name + `.lnk`.
- User preset `configs/Sovereign Spellblade.json` remains on desktop, excluded from repo. It imports 15 catalog items and one unresolved `Godrick's Great Rune`.
- Saves: `%APPDATA%/EldenRing/76561197960271872/`. Many historic backups exist; inspect before using any. Never assume the active file is the original vanilla save.

## Tests actually run

WPF XAML/control/catalog construction using `BuildStudio.ps1 -CheckOnly`; resolver test on user's existing preset, exact Magic Claymore ID/upgrades/Ash separation, unknown name reporting and VIG=100 rejection. No full GUI interaction test or live-game mutation/readback test passed.
