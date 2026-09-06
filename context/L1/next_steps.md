# Next steps

1. Do not build another frontend or plugin first. Establish a minimal compatible game connection. Read local CT root/version logic and actual ItemGib/stat APIs; inspect compatible older versions only if needed. First use read-only process/character/version checks. Treat a warning about table version as a hypothesis to test, not a blanket refusal or permission to ignore checks.
2. Document actual CE entry points. Record identifiers in XML are not symbols/addresses. Prove the bootstrap and process attachment; previous `/load /luacall` arguments were guessed from binary strings and never verified. Consult CE's official implementation/docs or locally installed API reference.
3. With a recoverable save checkpoint and the user-authorized offline target established, implement one bounded item operation and one reversible stat operation with readback. Stop on uncertainty; do not replay ambiguous item grants.
4. Only after that evidence, implement the adapter's real capability manifest, per-version catalog validation, category encoding, upgrade/affinity/Ash behavior, deduplication and receipts. Wire UI auto-apply to changed normalized plans and character/session identity.
5. Unify preset.schema.json, model, plugin skill and documentation. Add per-item limits, ambiguity handling and level/class constraints. Existing general 25 cap is insufficient for somber weapons.
6. Test the chat-generated preset end to end; clearly distinguish granting items, equipping them and changing affinities. Finish native UI usability after the backend works.

Publish context and source now as requested. Do not claim the repository is a finished playable tool. Future models must append a session record and update L1 after each work session.
