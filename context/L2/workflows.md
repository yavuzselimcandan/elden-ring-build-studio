# Workflows

## User flow

1. YouTube video → **Gemini prompt** button in Build Studio → paste into YouTube "✦ Ask" → copy the answer.
2. Switch back to Build Studio: the build is imported automatically (or **Paste build** / Ctrl+V), saved to `app/configs`.
3. Fix red (unresolved) rows with the suggestion buttons on the right; adjust stats/slots.
4. Start the game offline, load the character. Click the chip "Click to connect as admin" if the game runs elevated.
5. **Apply to game** (or enable Auto-apply). The status bar shows the receipt; hover it for the full ledger.

## Developer flow

- Tests (no game needed): `cd app; foreach ($t in Get-ChildItem test_*.ps1) { powershell -NoProfile -ExecutionPolicy Bypass -File $t }`
  plus `powershell -NoProfile -ExecutionPolicy Bypass -STA -File BuildStudio.ps1 -CheckOnly`. All must pass before a commit.
- Scripts consumed by Windows PowerShell 5.1 that contain non-ASCII characters need a UTF-8 BOM.
- UI screenshots without a person: launch with `Start-Process` (quote the `-Preset` path), `PrintWindow` the window from a
  DPI-aware process. Keys sent with SendKeys go wherever focus is — prefer testing logic directly.

## Live testing (game running)

Because the game runs elevated, helpers must too. Pattern (one UAC prompt on the user's screen):

```powershell
$out = "$env:TEMP\erbs-out.txt"
$cmd = "& 'C:\...\tools\Probe-Game.ps1' *>&1 | Out-File -Encoding utf8 -Width 250 '$out'"
Start-Process powershell.exe -Verb RunAs -Wait -WindowStyle Hidden -ArgumentList '-NoProfile','-ExecutionPolicy','Bypass','-Command',$cmd
Get-Content $out
```

- `tools/Probe-Game.ps1` — read-only: attach, stats, inventory discovery, equip calibration, signatures. Run this first on any new game version.
- `tools/Apply-Preset.ps1 -Preset <json>` — same code path as the Apply button, prints the ledger.
- `tools/Test-LiveApply.ps1` — small reversible grant/equip test (legacy raw equip path; prefer Apply-Preset now).
- Add a `trap { ... }` to ad-hoc elevated scripts: otherwise terminating errors vanish from the redirected output.
- Tell the user before any write; every apply backs up the save first. Ask the user to confirm visible in-game results —
  memory read-back is not proof the menu/model updated (see game-internals.md).

## Version control (user requirement: strict)

- Work on a feature branch, small commits with explanatory messages ending in the Co-Authored-By trailer, push often,
  PR into `main`. Never force-push. Never commit `app/configs`, `app/runtime`, CT files, saves or binaries.
- After each session append `context/L3/sessions/<date>-<topic>.md`, update L1 (`current_state.md`, `next_steps.md`) and
  L2 decisions when needed.

## Delegation

Simple, well-specified tasks may go to Codex **gpt-6-luna with reasoning max only** (never astra/sol). Close stdin
(`</dev/null`), give an explicit OWNS list, run `git status` afterwards and revert anything outside it; lanes never commit.
