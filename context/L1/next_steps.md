# Next steps

1. Ash of War attachment to weapons (find the game's gem-mount routine; TGA CT is the first place to look).
2. Remove invisible item copies left by the pre-fix grant bug (needs the game's own remove-item routine; they are harmless meanwhile, the equip code skips them).
3. Fuzzy matching: consider auto-accepting near-misses like "Great Oracle Bubble" → "Great Oracular Bubble" (currently offered as a suggestion only).
4. Upgrade limits (somber weapons +10) and quick items / pouch.
5. Merge PR #1 (`overhaul/v3`) into `main` once the user is happy.
