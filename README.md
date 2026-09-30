# Elden Ring Build Studio

Turn a build from a YouTube video into your character in the **offline** game: stats, weapons, armor, talismans and
spells — equipped and memorised — in one click. Native Windows app, no Cheat Engine, no installs.

**Status:** working end to end on game version 2.2.0.0 (verified in-game 2026-09-29).
Not yet: Ash of War attachment and a few smaller items — see [the backlog](context/L1/next_steps.md).

## Use

1. Run `tools/Install.ps1` once (creates the **Elden Ring Build Studio** desktop shortcut).
2. In Build Studio press **Gemini prompt**, open the build video on YouTube, press **✦ Ask**, paste, send, copy the answer.
3. Switch back to Build Studio — the build is imported automatically. Fix any red item with the suggestions on the right.
4. Start the game offline (Easy Anti-Cheat off) and load your character. If the chip says *Click to connect as admin*, click it.
5. Press **Apply to game**. Your save is backed up first (`app/runtime/backups/`).

## For developers and AI agents

Start with **[AGENTS.md](AGENTS.md)**. Tests: `app/test_*.ps1`. Game internals: [context/L2/game-internals.md](context/L2/game-internals.md).

Only for your own single-player game, offline. Do not use online.
