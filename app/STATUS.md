# Installed behavior

Open the desktop shortcut to Build Studio. Open your existing preset, or create a new one and choose catalog items. Edit attributes, item names, quantities, upgrades and Ash of War in the grid. Changes are saved and resolved automatically after leaving the edited grid. Save commits any active edit immediately.

The 6,352 catalog entries come from the local Hexinton v8.0.1 table. Name resolution writes a companion `.plan.json` containing separate IDs, upgrades and quantities. Unknown names remain explicit issues. This validates the table catalog only, not compatibility with the running game.

LIVE GAME APPLICATION IS NOT IMPLEMENTED/VERIFIED. The installed game is file version 2.2.0.0. Hexinton v8.0.1 targets 2.7.0.0; downloaded v5.0 targets 2.6.1.0. A compatible table/runtime bridge is required for live item/stat changes. The app does not launch CE or claim that saving grants items.

Tested: UI construction, catalog loading, existing Sovereign Spellblade import, Magic Claymore ID/upgrade/Ash separation, unknown-item reporting, invalid-stat rejection. Game item grants, equipment changes, affinities and stat writes have not been tested or implemented.
