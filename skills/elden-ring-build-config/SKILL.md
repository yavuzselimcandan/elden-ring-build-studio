---
name: elden-ring-build-config
description: Extract an Elden Ring build from a chat-provided link, screenshot or text and produce a concrete Build Studio preset (schema 3.0 JSON with equipment slots) that the desktop app imports with one click.
---

# Build Studio workflow

The user sends source links in chat. Inspect the actual source; never invent video evidence or claim a video was watched when inaccessible. Use provided screenshots/text when available. Write the preset yourself; do not hand the user a blank template.

App (single installed copy, a git checkout): `C:/Users/YAVUZ-PC/Documents/GitHub/elden-ring-build-studio/app`.
Resolve names against `app/catalog.json` (Hexinton v8.0.1 table names/IDs). Never invent IDs — the app resolves names itself and tolerates case, apostrophes, diacritics, plurals and small typos, and offers "did you mean" fixes; still prefer the exact catalog spelling.

Delivery (either works):
1. **Chat-only:** return the JSON in a ```json block. The user copies it; Build Studio imports it automatically when its window is activated (or via **Paste build** / Ctrl+V). For YouTube's Gemini, prefer the line format below.
2. **Local session:** write UTF-8 JSON to `app/configs/<build-name>.json`. Never overwrite an existing preset; pick a new name.

Contract (`app/preset.schema.json`, schemaVersion 3.0):

```json
{"schemaVersion":"3.0","name":"Build name","source":{"url":"source URL","evidence":"Only content actually observed","unresolved":[]},
 "attributes":{"vig":60,"mind":null,"end":null,"str":null,"dex":null,"int":80,"fai":null,"arc":null},
 "items":[
  {"category":"weapon","name":"Magic Claymore","upgrade":25,"ashOfWar":"Carian Sovereignty","slot":"R1"},
  {"category":"weapon","name":"Carian Regal Scepter","upgrade":10,"slot":"L1"},
  {"category":"armor","name":"Spellblade's Pointed Hat","slot":"Head"},
  {"category":"talisman","name":"Shard of Alexander","slot":"Talisman1"},
  {"category":"goods","name":"Terra Magica","slot":"Spell1"},
  {"category":"goods","name":"Starlight Shards","quantity":20,"slot":"Inventory"}
 ]}
```

Rules:
- Categories: `weapon`, `armor`, `talisman`, `goods`, `ash`. Spells, crystal tears, consumables, materials and spirit ashes are `goods`. Arrows/bolts are `weapon`.
- Slots: `R1-R3`, `L1-L3`, `Arrow1/2`, `Bolt1/2`, `Head`, `Chest`, `Arms`, `Legs`, `Talisman1-4`, `Spell1-14`, or `Inventory` (grant only). Omit `slot` to let the app place it (armor by piece, shields/seals/staves left, ammo to quivers, talismans/spells in order). Use explicit slots when the source shows which hand holds what.
- Upgrades are a separate number (weapons only). Infused weapons: use the prefixed name ("Heavy Claymore") or `"affinity":"Heavy"`. Armor/talisman names that contain +1/+2 keep it in the name.
- Unique weapons keep their built-in skill: do not set `ashOfWar` for them (the app ignores it anyway).
- Unknown stats stay `null` (keeps the character's value). Inferred alternatives go in `source.unresolved`, never presented as source facts.

After producing the preset, state which names you could not confirm in the catalog.

Status of game application (be honest): stats, item grants and equipping weapons/armor/talismans into slots are verified live (2026-09-29, game 2.2.0.0, via the game's own add-item and equip routines, with read-back). Not supported yet: Ash of War attachment and memorising spells into slots. Never claim something was applied without the app's receipt.

## Line format (preferred for chat answers, e.g. YouTube "Ask" / Gemini)

The app's **Gemini prompt** button copies a ~500-character prompt that makes the model answer in this format. Build Studio imports it automatically when the user copies the answer and returns to the window (also **Paste build** or Ctrl+V):

```
BUILD: Lifesteal Facetank
STATS: VIG 60, MIND 20, END 30, STR 50, DEX 15, INT 9, FAI 40, ARC 10
R1: Godslayer's Greatsword +10 | Ash: ?
L1: Brass Shield +25 | Ash: Barricade Shield
HEAD: Beast Champion Helm
TALISMAN: Crimson Amber Medallion +3, Shard of Alexander
SPELL: Golden Vow
ITEM: Rowa Raisin x5
```

Keys: BUILD, STATS, R1-R3, L1-L3, HEAD, CHEST, ARMS, LEGS, TALISMAN, SPELL, ITEM (also ARROW/BOLT). Markdown bullets/bold and surrounding chatter are ignored; `?`/unknown values are skipped.
