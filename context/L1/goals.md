# Goals

The user wants to play Elden Ring builds from videos without collecting gear by hand or touching cheat tools.

1. Find a build video on YouTube, ask YouTube's Gemini ("✦ Ask") with the prompt copied from the app, copy the answer.
   Other chats (ChatGPT/Claude with the `skills/elden-ring-build-config` skill) may produce preset JSON instead.
2. Build Studio (native Windows window, desktop shortcut) imports the copied text automatically, resolves every item name
   against the catalog, and lets the user fix unmatched names and edit stats/slots with normal controls.
3. One click (or auto-apply) applies the build to the running **offline** game: stats, missing items, equipment in the
   right slots, spells in memory slots — with no Cheat Engine and no manual steps beyond a UAC prompt when the game runs elevated.
4. Never damage the save: back up before every apply, read back every change, report failures honestly, never duplicate items.

Style: dark charcoal with restrained gold, serif headings. UI language: English (game item names are English); the user speaks Turkish.

Remaining gaps to the full goal: [next_steps.md](next_steps.md) (Ash of War attachment first).
