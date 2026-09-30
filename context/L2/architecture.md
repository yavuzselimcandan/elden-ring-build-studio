# Architecture

```
YouTube "Ask" (Gemini) / other chat
        │  line format (BUILD/STATS/R1../TALISMAN/SPELL/ITEM) or preset JSON, via clipboard
        ▼
app/BuildStudio.ps1  (WPF, layout in app/ui/MainWindow.xaml)
  ├─ app/BuildText.ps1      clipboard text → preset object (schema 3.0)
  ├─ app/BuildModel.ps1     preset → plan: resolve names (app/lib/Resolver.cs + app/catalog.json), loadout slots
  └─ app/backend.ps1        plan → game, synchronous, returns a receipt
        ├─ app/lib/GameMemory.cs   open process, read/write, signature scan, remote call (no Cheat Engine)
        └─ app/lib/BuildEngine.cs  stats · AddItem grants · inventory discovery · equip (game equipGear) ·
                                   spells (game changeMagic) · calibration / read-back / repair
        ▼
eldenring.exe (offline, usually elevated)          app/runtime/: save backups, ledger-*.txt, equip-calibration.txt
```

## Data contracts

- **Preset (schema 3.0, `app/preset.schema.json`)**: user intent, item *names*. `items[]` with `category`
  (weapon/armor/talisman/goods/ash), `name`, `upgrade`, `quantity`, optional `ashOfWar`, `affinity`, `slot`
  (`R1-3`, `L1-3`, `Arrow1/2`, `Bolt1/2`, `Head`, `Chest`, `Arms`, `Legs`, `Talisman1-4`, `Spell1-14`, `Inventory`).
  2.0 presets and legacy `equipment` string lists are still read.
- **Plan (schema 3.0, `*.plan.json`)**: resolved rows (`itemId`, `match` method, `suggestions`, `rowIndex` back into the
  preset), `notes` (every automatic correction), `issues` (unresolved/invalid), `loadout` (slot → item).
- **Receipt** from `Invoke-BuildPlan`: `ok`, `applied` (true only if nothing failed), `message`, `lines`, `problems`, `ledger` path.

## Resolver pipeline (per row)

parse string (`+N`, `xN`, `(Ash of War: …)`/`(Ash: …)`, `Name (Heavy)`, `Head:` prefix, physick `A + B`) → alias →
normalised exact key (case, diacritics, apostrophes, punctuation) → plural folding → unique category correction →
duplicate names → lowest id (+note) → fuzzy auto-accept only at ≥0.90 with a ≥0.04 margin → otherwise unresolved with
suggestions. Note-like rows (" / ", "situational"…) are ignored with a note.

## Apply pipeline (backend.ps1)

status/attach (elevation check) → save backup → stats (write, read back, roll back on mismatch) → inventory discovery →
grant only missing quantities (flasks count once) and confirm counts → equipment: calibrate layout, equip via game routine,
wait for the id array, replace refused (invalid) copies with fresh grants, retry items moving between slots → spells:
check layout, plan memory slots, changeMagic, read back → ledger + receipt.

Offsets, signatures and calling conventions: [game-internals.md](game-internals.md).
