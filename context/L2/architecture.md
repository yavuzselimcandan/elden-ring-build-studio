# Architecture (2026-09-29)

```
chat (skill) --3.0 preset JSON--> Paste JSON / configs/*.json
   BuildStudio.ps1 (WPF, ui/MainWindow.xaml)
     └─ BuildModel.ps1 ── lib/Resolver.cs (Add-Type)      catalog.json (6,352 Hexinton v8.0.1 names/IDs)
          plan: items + notes + issues + loadout (slots)
     └─ backend.ps1 ── save backup ── runtime/request.txt ──► Cheat Engine (elevated, hidden)
                                                              autorun: BuildStudioAutorun.lua (root from %LOCALAPPDATA%)
                                                              bridge.lua: grants (item_adapter.lua), stats, equip (equip_adapter.lua)
          UI polls  ◄── runtime/result.txt + build-ledger-<id>.txt + equip-calibration.txt
```

## Boundaries

- **Preset (3.0)**: user intent. Names, not IDs. Optional `slot` (`R1-3`, `L1-3`, `Arrow1/2`, `Bolt1/2`, `Head`, `Chest`, `Arms`, `Legs`, `Talisman1-4`, `Spell1-14`, `Inventory`) and `affinity`. 2.0 and legacy `equipment` string presets are still read.
- **Plan (3.0)**: resolved, typed rows with `rowIndex` back into the preset, `match` method, `suggestions`, `notes` for every automatic correction, `issues` for anything unresolved, and `loadout` (slot → item). Only plans are sent to the game.
- **Request file**: line protocol `item=category|id|upgrade|qty`, `stat=key|value`, `equip=slot|category|id|upgrade`. The bridge validates every line and never executes preset-supplied code.
- **Receipt**: `result.txt` with the request id; `OK: APPLIED` only when everything requested succeeded, `PARTIAL:` when e.g. equip was skipped, `ERROR:` otherwise. The UI marks nothing applied without a matching receipt.

## Resolver pipeline (per row)

parse string (`+N`, `xN`, `(Ash of War: …)`, `Name (Heavy)`, `Head:` prefix, physick `A + B`) → alias → exact normalised key (case, diacritics, apostrophes, punctuation) → plural folding → category correction (unique) → duplicate policy (lowest ID) → fuzzy (auto-accept only ≥0.90 with ≥0.04 margin) → otherwise unresolved with suggestions. Note-like rows are ignored with a note.

## Equip adapter

PlayerGameData holds two parallel 22-entry arrays (L1 R1 L2 R2 L3 R3, Arrow1 Bolt1 Arrow2 Bolt2 Arrow3 Bolt3, Head Chest Arms Legs Hair, Acc1-5): GaItem handles, then IDs (weapon raw id+upgrade, armor param id, talisman id). Observed id-array base on game 2.2.0.0 is +0x398; CT v8.0.1 (2.7.0.0) uses +0x39C. `calibrate()` tries both and accepts one only when every occupied slot matches an inventory entry by handle and item; `equip()` requires that layout, uses only owned inventory instances not equipped elsewhere, reads back, and rolls back on failure.

## Categories and encodings

Inventory raw id top nibble: weapon 0, armor 1, talisman 2, goods 4, ash 8. Weapon raw id = id + upgrade. Inventory entry stride 0x18: +0 handle, +4 raw id, +8 quantity.
