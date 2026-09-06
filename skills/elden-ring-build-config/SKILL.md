---
name: elden-ring-build-config
description: Extract an Elden Ring build from a chat-provided link or screenshot and write a concrete preset for the user's desktop Build Studio.
---

# Build Studio workflow

The user sends source links in chat. Inspect the actual source; never invent video evidence or claim a video was watched when inaccessible. Use provided screenshots/text when available. Write the preset yourself; do not hand the user a blank template.

Installed app: `C:/Users/YAVUZ-PC/Desktop/Elden Ring Build Configurator`.
Read `catalog.json` there to resolve canonical English item names and category. IDs are from Hexinton v8.0.1, not verified for the older installed game. Never invent IDs. The app's `BuildModel.ps1` resolves names; do not execute cheat-table Lua while importing.

Write UTF-8 JSON to `configs/<build-name>.json` in the installed app folder. Avoid replacing an existing user preset without preserving its contents. Use this exact contract:

```json
{"schemaVersion":"2.0","name":"Build name","source":{"url":"source URL","evidence":"Only content actually observed","unresolved":[]},"attributes":{"vig":null,"mind":null,"end":null,"str":null,"dex":null,"int":null,"fai":null,"arc":null},"items":[{"category":"weapon","name":"Magic Claymore","upgrade":25,"quantity":1,"ashOfWar":"Carian Sovereignty"}]}
```

Categories: `weapon`, `armor`, `talisman`, `goods`, `ash`. Spells, crystal tears and materials use goods. Upgrades are separate numeric fields; non-weapons use 0. Armor and talismans with +1/+2 in their canonical name retain those suffixes as part of the name. Do not put weapon, upgrade and Ash of War into one string. Unknown attributes stay null; inferred alternatives go in source.unresolved, not presented as source facts.

Compare every name with the local catalog. List unresolved names explicitly. Tell the user the preset filename and that Open preset loads it. UI edits automatically save and resolve into a `.plan.json`.

Current limitation: game file version 2.2.0.0, v8 table targets 2.7.0.0. The live adapter is unimplemented/unverified. Saving or resolving is not applying. Never report items granted, stats changed, auto-equipped or verified without actual backend receipts and game readback. User wants background automatic application once implemented; do not add manual CE steps or repeated compile confirmations to the intended workflow.
