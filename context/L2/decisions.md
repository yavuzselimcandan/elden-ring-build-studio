# Decisions and corrections

- Accepted: native separate window, black/charcoal neumorphism, desktop shortcut, background CE, automatic application after preset edits, chat-side source extraction.
- Accepted: split AI extraction from local execution; routine local execution should not use an LLM.
- Interim: WPF/PowerShell because Windows supports it without Python/SDK installation. It is not a final backend choice.
- 2026-09-29 accepted: keep WPF (native window, zero install) but move XAML to `app/ui/MainWindow.xaml` and design around an equipment slot board + live picker instead of a free-text DataGrid.
- 2026-09-29 accepted: matching/parsing in C# compiled at runtime by Add-Type (`lib/Resolver.cs`); PowerShell loops over 6k entries were too slow for fuzzy search.
- 2026-09-29 accepted: duplicate catalog names resolve to the lowest ID with a visible note instead of failing; fuzzy matches auto-apply only at ≥0.90 with a clear margin, otherwise the user picks from suggestions.
- 2026-09-29 accepted: the git checkout is the only installed copy; app location handed to CE via `%LOCALAPPDATA%/EldenRingBuildStudio/root.txt`.
- 2026-09-29 accepted: auto-equip writes only after live calibration of the slot layout against inventory data (never from a fixed offset table); CT v8 offsets were shown to be 4 bytes off for game 2.2.0.0.
- Corrected: static browser prototype did not satisfy native-window requirement. Plain JSON persistence did not satisfy compile/apply.
- Corrected: a plugin is a packaged instruction/integration surface, not proof of video extraction or live-game capability. Original plugin held an oversimplified paragraph; updated skill specifies concrete contract and limitations.
- Corrected: version mismatch is a warning requiring verification, not conclusive incompatibility. Do not revive an unverified bridge solely by lowering a version check.
- Rejected: interpreting CE record IDs as symbols; writing record ID 1337114353 as item category; claiming stats applied while discarding stat operations. A previous speculative Lua draft did these things and was replaced with an explicit refusal.
- Rejected: status messages claiming CE loaded/attached/applied without receipts, unconditional offline=true, one-time PID gating that ignores later preset edits.
- No requirement for the user to manually manipulate CE. Safety checks should be automatic and factual; authorization should not be repeatedly requested for already authorized routine operations.
