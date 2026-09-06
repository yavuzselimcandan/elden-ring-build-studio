# Goals

The user wants to play Elden Ring builds without manually collecting equipment or manipulating Cheat Engine.

1. Send a social/video build link in ordinary chat. A reusable skill/plugin guides the AI to inspect source material and return a concrete JSON preset. Do not require a Codex coding session for routine imports. Do not claim that a plugin removes normal chat usage limits or grants video access.
2. Open a separate native Windows app via a desktop shortcut. Create a new preset or open an existing one; edit equipment and attributes through normal controls.
3. Automatically resolve and apply changes to the chosen offline Elden Ring session. Discover the game automatically; CE should operate in the background without user-facing CE windows.
4. Preserve saves, avoid repeated item grants, show real application errors and verify successful changes from the game.

Black neumorphism/charcoal with restrained gold was requested. The current WPF grid is an interim implementation, not polished final UX.

Completion requires a demonstrated end-to-end preset -> resolved IDs -> compatible backend -> intended inventory/stat state. Current code stops after ID resolution.
