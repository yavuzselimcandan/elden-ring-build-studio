# Agent guide — read this first

Elden Ring Build Studio: a Windows desktop app that turns a build description (from YouTube's Gemini or another chat) into
a preset and applies it to the user's **offline** game — stats, items, equipment, spells — without Cheat Engine.
**It works end to end and was confirmed in-game on 2026-09-29.**

## Read in this order (≈10 minutes)

1. [context/L1/current_state.md](context/L1/current_state.md) — what exists, what is verified, where everything lives.
2. [context/L1/next_steps.md](context/L1/next_steps.md) — **the backlog: every unfinished or half-done item, with leads.**
3. [context/L1/constraints.md](context/L1/constraints.md) — user rules (git discipline, delegation, language) and pitfalls.
4. [context/L2/game-internals.md](context/L2/game-internals.md) — verified offsets, signatures, calling conventions. Required before touching game code.
5. [context/L2/architecture.md](context/L2/architecture.md), [workflows.md](context/L2/workflows.md) (tests, live testing, release), [decisions.md](context/L2/decisions.md).
6. Only if investigating history: [context/L3/sessions/](context/L3/sessions/index.md).

## Rules

- **Version control is a user requirement:** feature branch, small descriptive commits (end with the Co-Authored-By trailer
  your harness specifies), push often, PR into `main`, never force-push. Never commit `app/configs/`, `app/runtime/`,
  cheat tables, saves or binaries.
- **Run the tests before every commit:** `app/test_*.ps1` and `app/BuildStudio.ps1 -CheckOnly` (see workflows.md).
- **Game-facing changes:** use the game's own routines (AddItem, equipGear, changeMagic) rather than writing game structures;
  probe read-only first (`tools/Probe-Game.ps1`); every apply backs up the save; read back every change; and have the user
  confirm the in-game result before calling a new feature done. Never apply offsets from a cheat table without checking
  them against the running game version (they drifted by 4 bytes once).
- The game runs elevated on the user's PC: live helpers must be run elevated (pattern in workflows.md), which shows the
  user a UAC prompt — tell them before you trigger it.
- **Delegation:** only Codex `gpt-6-luna` with reasoning `max`, never astra/sol; simple bounded tasks only; review its diff.
- Be honest about evidence: distinguish "tested with mocks", "read back from memory" and "user saw it in-game".
- Answer the user in Turkish; keep code, commits and docs in English.

## After every work session

Append `context/L3/sessions/YYYY-MM-DD-topic.md` (agent/model, request, files changed, tests and outcomes, external actions,
risks, next step), link it from `context/L3/sessions/index.md`, and update `current_state.md` / `next_steps.md`
(and `decisions.md` for architectural choices) in the same PR.

## Map

```
app/BuildStudio.ps1      UI logic (WPF)          app/ui/MainWindow.xaml   UI layout
app/BuildText.ps1        Gemini prompt + chat text import
app/BuildModel.ps1       preset → plan (resolve, loadout)   app/lib/Resolver.cs   matching/parsing (C#, Add-Type)
app/backend.ps1          plan → game (receipt)   app/lib/GameMemory.cs   process access   app/lib/BuildEngine.cs   game logic
app/catalog.json         6,352 item names/ids    app/preset.schema.json  preset contract
app/test_*.ps1, app/tests/   tests               tools/   Install, Probe-Game, Apply-Preset, New-AppIcon, Test-LiveApply
skills/elden-ring-build-config/SKILL.md   instructions for chat models producing presets
```
