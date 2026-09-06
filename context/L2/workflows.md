# Workflows

## Routine user flow (target)

User sends link in ordinary chat. Skill reads source and local schema/catalog, produces a filled preset. User imports it into native app, edits ordinary controls, and application happens automatically in the offline game. CE remains a background implementation detail. Do not promise ordinary chat can access every video or avoids all platform usage limits.

## Current developer flow

Run Windows PowerShell in STA with `app/BuildStudio.ps1 -CheckOnly` to validate construction. Start without CheckOnly for the visible UI. Do not confuse construction with full GUI testing. `BuildModel.ps1` can be dot-sourced and tested with synthetic presets.

Copy only selected source files to desktop installation after verifying them. Preserve `configs/`, `.previous` files and user changes. Existing shortcut references EldenRingBuildConfigurator.ps1, which forwards to BuildStudio.ps1.

## Handoff flow

Read L0 and L1; inspect only relevant code. State the bounded work item. Execute tests that show outcomes, then record exact evidence in L3 session notes and update L1. Commit source/context only; keep local downloaded CT, saves and game assets outside Git. Publisher uses private GitHub repo and never force pushes.
