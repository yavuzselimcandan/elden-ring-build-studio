# Runtime status

Build Studio loads the local catalog and resolves preset names to a full typed plan: attributes plus weapons/upgrades, armor, talismans, goods, and Ash IDs. Requests are not marked applied without a matching runtime receipt; unresolved or unsupported rows remain visible and pending.

Verified live, offline-only operations:

- Stats: VIG55 MIND38 END33 STR16 DEX13 INT80 FAI7 ARC9, with backup, pointer/PID checks, readback, and rollback protection. Current level is 173; level is never written.
- Items: Spellblade's Traveling Attire (130100), Cannon of Haima (4080), and Gavel of Haima (4120), each with fresh backup and inventory readback.

Current preset warning: `Godrick's Great Rune` is ambiguous in the catalog and is not auto-selected. A `PARTIAL:` receipt is terminal for the request and leaves unsupported rows visible; only `OK: APPLIED` marks the full plan applied. Equipping/slot placement remains unsupported even when item grants succeed.

The runtime is offline-only and EAC-gated. Game file version is 2.2.0.0; Hexinton table source is v8.0.1 targeting 2.7.0.0. `GrantItem` in the review module is not the general UI path; only the explicitly allowlisted verified item flows are enabled.
