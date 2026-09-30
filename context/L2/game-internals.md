# Game internals (verified)

Everything here was verified **live on eldenring.exe FileVersion 2.2.0.0** on 2026-09-29 unless marked otherwise.
Code: `app/lib/GameMemory.cs` (process access, scans, remote calls) and `app/lib/BuildEngine.cs` (all logic below).
Sources for the routines: [The Grand Archives CT](https://github.com/The-Grand-Archives/Elden-Ring-CT-TGA)
(`MiscWIP/Dependencies/Global Functions/*.cea`) and the local Hexinton v8.0.1 CT (targets 2.7.0.0).

## Access

- The user's game runs **as administrator** → `OpenProcess` from a normal process fails with error 5. The Studio detects
  this (`needsElevation`) and relaunches itself elevated. Command-line helpers must be run elevated too
  (see workflows.md, "Live testing").
- Easy Anti-Cheat must be off (offline). The backend refuses when `EasyAntiCheat_EOS` runs.

## Signatures (all unique on 2.2.0.0)

| Name | Pattern | Resolve |
|---|---|---|
| GameDataMan | `48 8B 05 ?? ?? ?? ?? 48 85 C0 74 05 48 8B 40 58 C3 C3` | rip(+3, len 7) → global; `[global]` = GameDataMan; PlayerGameData = `[GDM+0x8]` |
| AddItem | `40 55 56 57 41 54 41 55 41 56 41 57 48 8D AC 24 ?? ?? ?? ?? 48 81 EC ?? ?? ?? ?? 48 C7 45 C8 ?? ?? ?? ?? 48 89 9C 24 ?? ?? ?? ?? 48 8B 05 ?? ?? ?? ?? 48 33 C4 48 89 85 ?? ?? ?? ?? 44 89 4C 24 ?? 4D 8B F8` | function start |
| item manager global | `44 8B 61 1C 41 8B FC C1 EF 07 40 80 E7 01 41 C1 EC 08 41 80 E4 01 48 8B 0D` | instruction at +0x16, rip(+3, len 7). Same global as the TGA `MapItemMan` AOB (checked) |
| equipGear | `?? 8B F1 ?? 8B D8 ?? 63 EA ?? 8B F9` | match − 0x17 |
| changeMagic | `?? 89 5C ?? ?? ?? 89 74 ?? ?? 57 ?? 83 EC ?? ?? 8B C2 8B F9 ?? 8B C8` | match |

## PlayerGameData (pgd) layout on 2.2.0.0

| Offset | Meaning |
|---|---|
| +0x3C … +0x58 | VIG, MIND, END, STR, DEX, INT, FAI, ARC (int32 each) |
| +0x68 | rune level (never written) |
| +0x2B0 | EquipGameData (embedded) — `rcx` for equipGear |
| +0x340 | ChrAsm **handle** array, 22 × int32 |
| +0x398 | ChrAsm **id** array, 22 × int32 (weapon: id+upgrade; armor: param id; talisman: id; -1 empty) |
| +0x408 | EquipInventoryData (embedded): +0x10 list pointer (= pgd+0x418), +0x18 used count, +0x1C tail index (384) |
| +0x530 | pointer to EquipMagicData: spell ids at +0x10 + 8·i (i = 0..13), -1 = empty |
| +0xA74 | unlocked memory slot count (6 on the user's character) |

Slot index (both arrays and equipGear): L1 0, R1 1, L2 2, R2 3, L3 4, R3 5, Arrow1 6, Bolt1 7, Arrow2 8, Bolt2 9,
(10, 11 unused), Head 12, Chest 13, Arms 14, Legs 15, Hair 16, Talisman1-4 17-20, (21 unused).

**Version drift:** Hexinton v8.0.1 (2.7.0.0) places the ChrAsm id array at +0x39C (4 bytes later). TGA (newer game) uses a
*pointer* to EquipInventoryData at +0x5D0 instead of the embedded block at +0x408. Never trust a table's offsets for this
game version without the calibration in `Equipment.Calibrate` / `Inventory.Discover` / `CheckMagicLayout`.

## Inventory

- Entry stride 0x18: +0 GaItem handle, +4 raw id, +8 quantity, +0xC acquisition/sort number.
- Raw id top nibble = category: weapon 0, armor 1, talisman 2, goods 4, ash 8. Weapon raw = id + upgrade.
- Handles: weapon 0x808xxxxx, armor 0x908xxxxx, talisman 0xA0000000|id, goods 0xB0000000|id, ash 0xC08xxxxx.
- `Inventory.Discover` finds the list without hooks: the array reachable from pgd (≤2 hops) containing the handles of the
  equipped gear. On 2.2.0.0 it is `[pgd+0x418]`.

## Calls (remote stubs built in BuildEngine.cs)

- **AddItem**: `rcx=[item manager global]`, `rdx=&buf+0x20` (`dword 1, dword rawId, dword qty, 0, qword -1 …`),
  `r8=&buf` where **`buf+0` must be 0xFFFFFFFF**, `r9=0`. With 0 at `buf+0` (the old CE adapter) goods still work but
  weapons/armor/ashes become **invisible, unusable instances**. Fixed 2026-09-29.
- **equipGear**: `rcx=pgd+0x2B0, rdx=slot, r8=&handle, r9=row+tailIndex, [rsp+20]=1, [rsp+28]=1, [rsp+30]=0` → returns 1.
  The handle array updates immediately, the id array **one frame later** (poll). If the id stays -1 the game refused the
  instance (an invisible copy from the old grant bug): restore the slot, grant a fresh copy, equip that.
  Writing the ChrAsm arrays directly works in combat but the **Equipment menu does not show it** — never do that live.
- **changeMagic**: `rcx=slot, rdx=mem` with `mem+0x08=slot, +0x48=row+tailIndex-1, +0x4C=0x40000000|id, +0x50=0xB0000000|id`.
  Read back `[EquipMagicData+0x10+8·slot]`.

## Known leftovers in the user's save

Invisible copies created by the old grant bug (e.g. a Poison Spiked Palisade Shield, Ash of War: Cragblade, several
weapons from 2026-09-11) remain in the inventory list. Harmless; the equip code skips refused instances and picks the
newest copy first. Removing them needs the game's remove-item routine (open task).
