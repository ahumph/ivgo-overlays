# Drop-in additions for ahumph/ivgo-overlays

Each path below mirrors where the file belongs in the repo.

## New / modified

| File | Action |
|---|---|
| `ivgo-shared.js` | **Replace** the existing file. Adds `WorkbenchStrip`, `SprintTimer`, `TaskBar`, `TICKER.arranging`. Additive — no breaking changes to the other six scenes. |
| `scenes/07-arranging.html` | New scene chrome. |
| `scenes/07-cam-outline.html` | New cam frame. |
| `scenes/07-chat.html` | New chat panel position for the arranging scene. |
| `docs/README-arranging-section.md` | Merge into the main `README.md` (paste-ready Markdown sections). |
| `docs/installer-additions.lua` | Three patches to apply to `ivgo_obs_setup.lua`. |
| `docs/CLAUDE-CODE-HANDOFF.md` | Brief for Claude Code to wire up chat-driven interactivity. |

## Suggested commit
```
feat: arranging / coworking scene (07)

- New scene chrome + cam outline + chat panel
- WorkbenchStrip, SprintTimer, TaskBar components in shared.js
- TICKER.arranging copy
- README + installer patches + Claude Code handoff for chat interactivity
```
