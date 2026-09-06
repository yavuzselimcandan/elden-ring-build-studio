# Agent handoff contract

Read `context/00_index.md`, then all four L1 files before doing work. Read the relevant L2 files before changing architecture, presets or game integration. Read L3 only when investigating prior attempts.

The project is **incomplete**. Saving a preset, resolving an ID, starting Cheat Engine, or finding a PID does not mean a build was applied. Never report success without evidence of the intended outcome. The current backend deliberately refuses writes.

Respect the user's scarce usage budget. Prefer concise, targeted reads and checks. Do not spawn agents unless authorized. User previously preferred Luna execution and one bounded Astra architecture consultation; those consultations already happened. Do not silently spend another expensive consultation.

Keep the desired workflow: user sends video/link in ordinary chat; AI emits a concrete preset; native desktop app loads it and eventually applies automatically to the user's offline game. A manual JSON editor or requiring the user to operate CE is not the intended final product.

Do not commit game binaries, downloaded CT archives/tables, saves, runtime presets, credentials or logs. Do not initialize or push the enclosing Documents repository. This handoff directory is the repository root.

Preserve existing user saves and presets. No destructive replacement or live-game tests using guessed offsets/IDs. Table record IDs are not memory addresses. Version mismatch is evidence requiring investigation, not proof of incompatibility. Do not disable checks or spoof versions to manufacture success.

After EVERY working session, append `context/L3/sessions/YYYY-MM-DD-description.md` recording agent/model (or unknown), user request, files changed, commands/tests and outcomes, actions on external systems, outstanding risks and exact next step. Update L1 current_state/next_steps and L2 decisions when needed; link the session from L3/sessions/index.md. Distinguish observed facts, hypotheses and untested code. Do not overwrite history or fabricate attribution.

Source edits use apply_patch. Keep the source app and installed desktop copy explicitly distinguished. Deploy only named files and preserve user configs. For Windows GUI launches use hidden helper windows; native UI itself is meant to be visible. No automatic test should modify the user's game just because it happens to be running.
