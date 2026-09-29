# Open work (backlog) — the single list of unfinished and not-started items

Ordered by value to the user. Each item: what is missing, where to start, and how to know it is done.
When you finish or change an item, edit this file in the same commit.

## 1. Ash of War attachment — NOT STARTED (most requested)

- Now: Ashes are granted, weapons are granted/equipped, but the Ash is not attached. The apply receipt says
  "<weapon>: Ash of War not attached".
- Start: search the TGA CT for the gem mounting routine (`gh search code "gem" --repo The-Grand-Archives/Elden-Ring-CT-TGA`,
  look for "Ash of War"/"Gem"/"setGem"/"mount"). Ash handles are 0xC08xxxxx (see context/L2/game-internals.md).
  Plan items already carry `ashOfWarId` (BuildModel.ps1). Unique/somber weapons (no affinity variants) cannot take ashes;
  the resolver already treats their named skill as built-in.
- Affinity follows the ash in-game (Heavy/Keen/...); the catalog has one item id per affinity, so decide whether to grant
  the infused id directly (current behaviour when the preset names "Heavy Claymore") or re-infuse via the routine.
- Done when: a preset with `ashOfWar` applies with the ash shown on the weapon in the Equipment menu (user confirms).

## 2. Remove invisible copies left by the old grant bug — NOT STARTED

- Invisible instances (created before commit e9da453) sit in the inventory list. Harmless, but clutter.
- Start: find the game's remove/discard item routine (TGA CT; look for "removeItem"/"discard"/"ItemRemove").
  Detection: equipping them leaves the ChrAsm id at -1 (see `invalid-instance` in `Equipment.Apply`).
- Done when: a one-off tool (tools/) removes only refused instances, with a save backup, verified by the user.

## 3. Fuzzy matching near-misses — PARTIAL

- "Great Oracle Bubble" → "Great Oracular Bubble" is only a suggestion (score < 0.90 auto-accept threshold in
  `Resolve-CatalogName`, BuildModel.ps1). Gemini also invents non-existent pieces ("Dryleaf Leg Wraps", "Yumi").
- Idea: word-level stemming (oracle/oracular), or accept when the best candidate shares all content-word stems and the
  runner-up is clearly worse. Add cases to `app/test_resolver.ps1` first.

## 4. Quick items / pouch — NOT STARTED

- equipGear handles slots 0–21 only. TGA uses a second routine `equipGoods`
  (AOB `?? FA ?? ?? 0F ?? 81 C1 ?? ?? ?? ?? ?? 8B C1 E9`) for slots 22–38 (quick items/pouch).
  The line format has no key for quick items yet (add e.g. `QUICK:`), and `Get-BuildLoadout` has no quick slots.

## 5. Validation gaps — NOT STARTED

- Somber weapons max +10 (resolver allows up to 25). Derive from the catalog (no affinity variants and not staff/seal)
  or a small table; warn in the resolver.
- Stat totals vs. class minimums / level are not checked (rune level is only displayed).

## 6. UI polish — PARTIAL

- Apply runs on the UI thread (window freezes ~1–5 s during apply). Move `Invoke-BuildPlan` to a runspace.
- No delete/rename preset in the UI (duplicates like "Hydromancer Wade (2)" must be removed in the folder).
- `test_full_plan.ps1` reads a machine-specific preset path; make it skip when absent.

## 7. Repository housekeeping

- PR #1 (`overhaul/v3` → `main`) is open; merge when the user agrees.
- The GitHub repository is **public** (older docs said private). Changing visibility is the user's decision.
- The retired CE autorun `C:/Program Files/Cheat Engine/autorun/zz_EldenRingBuildStudio.lua` is inert; the user may delete it.

## Done (for orientation; details in context/L3/sessions/2026-09-29-overhaul.md)

Resolver rebuild · 3-pane UI with slot board · schema 3.0 · single install + desktop shortcut/icon · Cheat Engine removed ·
elevation handling · item grant fix · equip via game routine with invalid-copy repair · spells via changeMagic ·
Gemini prompt + clipboard import · Turkish-locale regex fix · flask quantities · duplicate paste fix.
