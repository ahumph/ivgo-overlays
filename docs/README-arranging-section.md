# README section — drop into the main README under the scenes table and under the Manual setup block.
# Below: paste-ready Markdown to append (or merge) into ahumph/ivgo-overlays README.md.

---

## What you'll get — additional scene

Add this row to the scenes table near the top of the README:

| Scene | What it's for |
|---|---|
| Arranging | Coworking / "study with me" layout for arranging streams — small webcam, big screen capture, pomo timer, shared task list, on-demand "on the desk" info card |

---

## Manual setup — Arranging scene

Add this block to the **Compositing scenes** section, after the Two Camera row.

**Arranging scene (`07-arranging.html`)** — coworking layout. Screen capture is the hero; webcam is a small picture-in-picture; chat sits on the right. Add these sources in this order (bottom to top):

| Source | Type | Position | Size |
|---|---|---|---|
| Screen Capture | Display Capture (your notation / DAW screen) | x: 0, y: 0 | 1920 x 1080 |
| Host Camera | Video Capture (webcam) | x: 24, y: 72 | 282 x 158 |
| IVGO: Arranging Overlay | Browser (`07-arranging.html`) | x: 0, y: 0 | 1920 x 1080 |
| IVGO: Arranging Cam Outline | Browser (`07-cam-outline.html`) | x: 0, y: 0 | 1920 x 1080 |
| IVGO: Arranging Chat | Browser (`07-chat.html`) | x: 0, y: 0 | 1920 x 1080 |

The overlay is transparent except for the header bar, the task list under the cam, the pomo timer in the top-right, and the ticker. The "ON THE DESK" workbench strip only appears for 10 seconds when triggered (see `!info` below).

---

## Customising the Arranging scene

Pass URL parameters in OBS to set the boot-time defaults. Once Phoenix is connected and chat commands fire, those values override the URL params.

```
.../07-arranging.html?piece=AERITH%27S%20SUITE&collection=FINAL%20FANTASY%20VII%20REBIRTH&total=4&focus_mins=25&break_mins=5
```

| Parameter | Effect | Example |
|---|---|---|
| `piece` | Title shown in the "ON THE DESK" card when surfaced via `!info` | `AERITH%27S%20SUITE` |
| `collection` | Origin / game name (alias: `from`) | `FINAL%20FANTASY%20VII%20REBIRTH` |
| `total` | Total sprints planned | `4` |
| `focus_mins` | Focus pomo length (alias: `mins`) | `25` |
| `break_mins` | Break pomo length | `5` |

The installer script handles all of these — just fill in the fields and click **Create / Refresh Scenes**.

---

## Chat commands

The arranging scene is driven by Twitch chat (and the LiveView control panel). All commands are case-insensitive; rejected commands drop silently.

### Anyone

| Command | Effect | Cooldown |
|---|---|---|
| `!task <text>` | Append a task for the calling user (text capped at 80 chars). | 10s / user |
| `!done` | Mark the caller's oldest open task done (green tick). | 10s / user |
| `!info` | Show the "ON THE DESK" card for 10 seconds. | 30s global |
| `!pomo` | Bot replies: phase + time remaining + sprint x/y. | 30s / user |
| `!progress` | Bot replies: piece, from, open task count. | 60s / user |
| `!help` | Bot replies: one-line command summary. | 60s / user |

### Mods / broadcaster

| Command | Effect |
|---|---|
| `!piece <text>` | Update PIECE (auto-fires `!info`). |
| `!from <text>` | Update FROM / collection (auto-fires `!info`). |
| `!pomo focus <mins>` | Set focus length (1–90). |
| `!pomo break <mins>` | Set break length (1–60). |
| `!pomo start` | Start the timer (enters FOCUS if idle). |
| `!pomo stop` | Stop / pause the timer. |
| `!pomo reset` | Restart the current phase's countdown. |
| `!pomo next` | Flip focus↔break, advance sprint when leaving break. |
| `!task clear` | Wipe all tasks (spam escape hatch). |

---

## File layout — additions

Append to the file layout tree:

```
scenes/
├── ...
├── 07-arranging.html        # arranging / coworking layout chrome
├── 07-cam-outline.html      # small PiP webcam frame
└── 07-chat.html             # chat panel (right column)
```
