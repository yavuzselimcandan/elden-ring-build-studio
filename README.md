# Elden Ring Build Studio — AI handoff

**Incomplete: preset editing/resolution works; live-game application is not implemented or verified.**

Start with [context/00_index.md](context/00_index.md) and [AGENTS.md](AGENTS.md). These explain the intended workflow, actual state, mistakes to avoid, evidence and the next concrete task. Every future agent must log its session.

- `app/`: snapshot of local application source; no saves or downloaded CE/game assets.
- `skills/elden-ring-build-config/`: current chat-side import instructions, copied for continuation; local paths need adaptation on another machine.
- `context/`: L0 index, L1 essentials, L2 domain context, L3 session/archive history.
- `PUBLISH.md`: repository publishing information when supplied by the publishing agent.

On Windows, run `powershell.exe -NoProfile -STA -File app/BuildStudio.ps1`. Use `-CheckOnly` to construct the UI and load its catalog without showing the window. No Python or .NET SDK is required for this WPF editor. Current code does not grant game items.

Canonical schema: `app/preset.schema.json`. Historical files in app/ are documented in the archive and must not override the current context. Table catalog IDs have not been validated for live application on the installed older game.
