# Next steps

1. **Install once:** run `powershell -ExecutionPolicy Bypass -File tools/Install.ps1` and approve the UAC prompt, so Cheat Engine's autorun reads the app location from `%LOCALAPPDATA%` (see current_state.md).
2. **First live auto-equip session** (offline game, character loaded, recent manual save backup exists anyway):
   - Apply a small preset (one weapon in R1, one armor piece, one talisman) with the Apply button.
   - Read `app/runtime/equip-calibration.txt`: it must say `result=verified idBase=0x398` (or explain the mismatch). If unverified, do not loosen the check; inspect the dumped rows.
   - Confirm in-game whether the equipment menu, character model and stats reflect the change immediately, after opening the equipment menu, or only after a reload. Record the answer in a session note and in `STATUS.md`. If the game does not refresh, investigate the game's own equip routine rather than stacking memory writes.
3. Memory (spell) slots: calibrate `EquipMagicData` (CT v8: PlayerGameData+0x518 → +0x10 + 8*i) the same way as ChrAsm before enabling `Spell*` equip lines in `backend.ps1`.
4. Ash of War attachment: requires the game's gem-mount routine; the Ash conversion table in `item_adapter.lua` is groundwork only.
5. Upgrade limits: somber weapons cap at +10; derive from catalog (no affinity variants and not staff/seal) or a small table, warn in the resolver.
6. Remove machine-specific paths from `test_full_plan.ps1` / `test_ash_mapping.ps1` (skip when files are absent).
