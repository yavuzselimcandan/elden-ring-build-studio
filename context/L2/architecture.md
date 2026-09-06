# Architecture

Intended: chat source interpretation -> v2 preset -> desktop editor/resolver -> validated plan -> CE adapter -> game -> receipt/readback -> UI status.

Actual: v2/legacy preset -> BuildStudio -> BuildModel + table catalog -> preset JSON and `.plan.json`. The remaining backend arrow is absent.

```json
{"schemaVersion":"2.0","name":"Example","source":{"url":"","evidence":"Observed facts only","unresolved":[]},"attributes":{"vig":null,"mind":null,"end":null,"str":null,"dex":null,"int":null,"fai":null,"arc":null},"items":[{"category":"weapon","name":"Magic Claymore","upgrade":25,"quantity":1,"ashOfWar":"Carian Sovereignty"}]}
```

Categories: weapon, armor, talisman, goods, ash. Spells/materials/crystal tears use goods. Numeric suffixes in canonical talisman names are retained; weapon upgrades are separate. Unknown attributes should preserve existing stats; source facts must not be invented.

Observed table lookup example: Magic Claymore -> 3180800, upgrade=25; Carian Sovereignty -> 418000. This is NOT a verified instruction to add 25 to an address/ID or directly write those values. A compatible item creation API must encode category, level and variant correctly.

Observed CT record IDs: root Enable 1337092247; ItemType 1337114353; ItemID 1337102251; Num 1337114354; AddItem_ 1337102252. Actual textual addresses seen were ItemCategory, ItemSpawnData+4 and ItemSpawnData+8; AddItem_ is an Auto Assembler script calling a thread, not a writable bool. These details were inspected only. Verify parent activation, dependencies, versions and the concrete function before use.

Cheat Engine bridge should accept only validated data, not arbitrary Lua from a preset. A process being present or a record name existing is not evidence of successful application.
