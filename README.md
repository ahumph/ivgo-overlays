# IVGO Twitch Overlay Pack

Professional stream overlays for the IVGO Twitch channel. Seven scenes plus a
floating now-playing strip and a chat-triggered fire-effect overlay — all
designed to work together in OBS.

---

## The scenes

| # | Scene | What it's for |
|---|---|---|
| 01 | Starting Soon | Pre-show countdown + full-bleed background video |
| 02 | Game | Main gaming layout — game window, webcam PiP, chat panel |
| 03 | Camera | Full-frame webcam shot for talking direct to viewers |
| 04 | Be Right Back | Interval screen with an embedded "about IVGO" video |
| 05 | Two Camera | Interview / collab — host left, guest right |
| 06 | Ending | Outro screen with full-bleed video |
| 07 | Arranging | Music-arranging coworking layout: display capture, host cam, Pianoteq keyboard band, task list, pomodoro timer, sliding info panel |

Two extras layered on every scene:

- **Now Playing** — a slide-out strip showing what's playing on Tidal / YouTube. Hidden by default; viewers reveal it with `!np` or `!playing` in chat.
- **Fire Overlay** — triggered by the `!fine` chat command (costs 100 Ostis); plays a fire effect over whatever scene you're on.

---

## Before you start

You need:

- **OBS Studio 28+** (any platform — macOS, Windows, Linux).
- This repo cloned to a stable folder. *Don't* leave it in Downloads — OBS will load files from this path every stream.
- A webcam (and a second webcam if you want to do interview streams).
- Optional: **Pianoteq** running, if you want the live keyboard panel on the Arranging scene.
- Optional: **Windows PowerShell 5.1** (built into Windows), if you want the Now Playing strip to read from Tidal/YouTube via SMTC.

---

## 1 — Install the OBS script

This creates all the scenes and their sources automatically. Re-run it any time you change settings or add a new scene.

1. Open **OBS** → menu **Tools** → **Scripts**.
2. Click **+** (bottom-left of the dialog).
3. Navigate to your cloned repo and select **`ivgo_obs_setup.lua`**.
4. The script appears in the list. Click it once — its settings appear on the right.

> Lua scripting is built into OBS. No extra install needed.

---

## 2 — Fill in your details

These appear on the right when the script is selected. All have sensible defaults — change the ones that apply to you, leave the rest.

| Field | What it does |
|---|---|
| **Host name** | Your name. Appears on the Camera and Two-Camera nameplates. Auto-uppercased — type "Adam Humphreys", it'll render "ADAM HUMPHREYS". |
| **Host role** | Your title. Same nameplates. e.g. `Artistic Director`. |
| **Guest name** | Only used on the Two-Camera scene. |
| **Guest role** | Same. |
| **Interview topic** | Strip across the Two-Camera scene. |
| **Countdown (mins)** | How long the Starting Soon countdown starts at when the scene loads. `5` = "STARTING IN 05:00". Set to `0` to hide the countdown box entirely. |
| **Socket URL** | Where the overlay's Phoenix backend lives. Use `wss://ivgorchestra.fly.dev/overlay` for live, `ws://localhost:4000/overlay` for local dev, or leave blank to skip the chat-event integration entirely. |
| **Now-Playing HTTP base** | URL of the local PowerShell watch script. Default `http://localhost:7779`. Leave blank to skip the Now Playing overlay. |
| **Arranging: Piece / Game** | Boot-time defaults only — shown on the Arranging scene's "ON THE DESK" info card on first paint. Change live with `!piece` / `!from` in chat. |
| **Arranging: total sprints / focus mins / break mins** | Pomodoro defaults for the Arranging scene's timer. Chat can override at runtime. |

### Refreshing the scenes after changing settings

After editing any field above, click **Create / Refresh Scenes** at the bottom of the script panel. The script is **idempotent** — re-running it updates existing scenes instead of duplicating them. You can run it as many times as you like; nothing gets clobbered except the bits you explicitly changed.

---

## 3 — Point the sources at your hardware

The installer creates placeholder slots for your devices. You only need to do this once — OBS remembers the device picks across restarts.

In OBS, switch to each scene and right-click the listed source(s) → **Properties**:

### 02 Game scene
| Source | What to pick |
|---|---|
| `IVGO: Game Capture` | The game window or full screen — choose **Capture specific window** or **Capture any fullscreen application**, depending on your setup |
| `IVGO: Host Camera` | Your webcam |

### 03 Camera scene
| Source | What to pick |
|---|---|
| `IVGO: Host Camera` | Your webcam (same one as Game — OBS shares it across scenes) |

### 05 Two Camera scene
| Source | What to pick |
|---|---|
| `IVGO: Host Camera` | Your webcam |
| `IVGO: Guest Camera` | Guest's video input — a second webcam, capture card, or NDI source for remote guests |

### 07 Arranging scene
| Source | What to pick |
|---|---|
| `IVGO: Arranging Screen` | Your notation / DAW screen — pick the **Display** that shows MuseScore, Sibelius, Logic, etc. |
| `IVGO: Host Camera` | Your webcam |
| `IVGO: Pianoteq` (inside the **IVGO: Keyboard** group) | The Pianoteq window. If you don't see it in the dropdown, check **Capture Method → Windows Graphics Capture** |

> The Pianoteq source is pre-cropped (`top=825, bottom=2, left=35, right=41`) to show just the keyboard band. The crop is applied as a **source filter** (not a scene-item crop) so it runs before the chamfer alpha mask. If your Pianoteq window is a different size, right-click `IVGO: Pianoteq` → **Filters** → adjust the "IVGO Keyboard Crop" filter, or change the values in `ivgo_obs_setup.lua` (look for `ensure_crop_filter(kb, ...)`).

### 01 Starting Soon / 04 BRB / 06 Ending
No webcam/game needed. The installer created Media Sources for the background videos already:
- `IVGO: Starting Soon Video` ← `media/buts.mkv`
- `IVGO: Ending Video` ← `media/tetris.webm`

The BRB scene loads `media/about.mkv` directly via its HTML.

---

## 4 — Now Playing (optional but recommended)

The Now Playing overlay reads from Windows SMTC, so it works automatically with Tidal, YouTube (Chrome/Edge/Firefox), Spotify, and most music apps.

### Auto-start (default)

The OBS installer script launches the SMTC watcher (`tools/now-playing-watch.ps1`) hidden in the background each time OBS loads — controlled by the **Auto-start Now Playing watcher with OBS** checkbox in the Scripts panel. It TCP-probes port 7779 first, so re-loading the script or having a leftover watcher from a previous session is a no-op. Nothing else to do — just open OBS.

Toggle the checkbox off if you'd rather run the watcher yourself (e.g. you're driving it from a Task Scheduler entry instead). The **Start Now Playing watcher now** button next to it forces a launch on demand.

### Manual run (if auto-start is off)

In a PowerShell window (**use `powershell.exe`, not `pwsh.exe`** — PS7 lacks the WinRT API needed):

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tools\now-playing-watch.ps1
```

Leave the window running (minimised is fine). It prints each track change so you can confirm it's working.

### How it appears on stream

When the watch script is running and a track is playing, an `!PLAYING` label appears at the top-right of your scene (10px below the pomo timer on the Arranging scene, top-right on other scenes). Viewers type `!np` or `!playing` in chat to slide the panel down for 30 seconds — showing the track title, artist, album, and source (TIDAL/YOUTUBE/etc).

If the script isn't running, the OBS browser source loads an empty page — no crash. Start the script and right-click `IVGO: Now Playing` → **Refresh cache of current page** to recover.

---

## 5 — Chat commands

The Phoenix backend (`ivgo-ex`) listens to chat and broadcasts to the overlays. All overlay state — current piece, current game, task list, pomodoro phase — lives on the server, so chat is the source of truth at runtime. The OBS script's Piece/Game fields are boot defaults only; once Phoenix connects, server state takes over.

### Anyone can use

| Command | What it does |
|---|---|
| `!task <text>` | Append a task to the Arranging task list under your name. Text capped at 80 chars. 10s cooldown per user. |
| `!done` | Tick off your oldest open task (green check). 10s cooldown per user. |
| `!info` | Surface the "ON THE DESK" piece/game card for 10s. 30s global cooldown. |
| `!pomo` | Bot replies with current phase + time remaining + sprint x/y. 30s cooldown per user. |
| `!progress` | Bot replies with current piece, game, and open task count. 60s cooldown per user. |
| `!help` | Bot replies with a one-line command summary. 60s cooldown per user. |
| `!np` / `!playing` | Slide the Now Playing strip down for 30s (shows current Tidal / YouTube / etc. track). |
| `!fine` | Trigger the fire overlay. Costs 100 Ostis. |

### Mods + broadcaster only

| Command | What it does |
|---|---|
| `!piece <text>` | Update the current PIECE. Auto-triggers `!info`, so the card surfaces immediately. |
| `!from <text>` | Update the current GAME / collection. Auto-triggers `!info`. |
| `!pomo focus <mins>` | Set focus length (1–90). |
| `!pomo break <mins>` | Set break length (1–60). |
| `!pomo start` | Start the timer. Enters `:focus` if idle. |
| `!pomo stop` | Pause the timer. Resets the countdown on next start. |
| `!pomo reset` | Restart the current phase's countdown from the top. |
| `!pomo next` | Flip phase focus↔break, reset countdown, increment sprint counter on leaving break. |
| `!task clear` | Wipe all tasks (spam escape hatch). |
| `!task del <id>` | Remove a specific task by id (id shown in the mod-only LiveView control panel). |

> The timer does **not** auto-advance when it hits zero — phase changes only happen on explicit `!pomo start` / `stop` / `reset` / `next`. This is deliberate: keeps the chat in the loop on cadence.

---

## 6 — Re-running and tweaking later

You can re-run the installer at any time. It will:

- **Update** existing scenes with any field changes (countdown, host name, etc.).
- **Preserve** device choices you've made in the Properties dialogs (webcam, game window, Pianoteq).
- **Preserve** any manual scene-item transforms you've adjusted (drag positions, resize).
- **Refresh** browser-source URLs to the latest values.

It won't duplicate scenes or sources. If you want a clean install, delete the scenes manually first and then re-run.

### When to re-run vs when not to

| Change | Re-run? |
|---|---|
| New countdown | Yes |
| New guest name for tonight's interview | Yes |
| Moved a source by dragging in OBS | No — re-running keeps your manual positions |
| Changed your webcam to a new device | No — adjust in the source's Properties |
| Updated a scene's HTML / CSS | Yes — to refresh the browser source's URL cache |
| Edited `ivgo-shared.js` (colours, fonts, ticker text) | No — but you must **right-click each browser source → Refresh cache of current page** so it picks up the change |

---

## 7 — Manual / custom setup (alternative)

If you'd rather build the scenes by hand, here's the source layout per scene. Position and Bounds use the OBS "Stretch to bounding box" mode.

### Common settings for every browser source

| Setting | Value |
|---|---|
| Width | 1920 |
| Height | 1080 |
| **Shutdown source when not visible** | ✅ |
| **Refresh browser when scene becomes active** | ✅ |

### URL pattern

For local files: `file:///C:/path/to/ivgo-overlays/scenes/02-game.html`
For the now-playing source: `http://localhost:7779/scenes/09-now-playing.html?debug=0`

### Per-scene source list (bottom layer first)

**02 Game**
| Source | Type | Position | Size |
|---|---|---|---|
| Game Capture | Game/Screen Capture | 0, 0 | 1920×1080 |
| Host Camera | Video Capture | 1570, 64 | 340×191 |
| Game Overlay | Browser (`02-game.html`) | 0, 0 | 1920×1080 |
| Cam Outline | Browser (`02-cam-outline.html?toasts=0`) | 0, 0 | 1920×1080 |
| Chat | Browser (`02-chat.html?toasts=0`) | 0, 0 | 1920×1080 |
| Now Playing | Browser (`http://localhost:7779/scenes/09-now-playing.html?debug=0`) | 0, 110 | 1920×1080 |
| Fire Overlay | Browser (`10-fire.html`) | 0, 0 | 1920×1080 |

**03 Camera**
| Source | Type | Position | Size |
|---|---|---|---|
| Host Camera | Video Capture | 320, 180 | 1280×720 |
| Camera Overlay | Browser (`03-camera.html?host=...&hostRole=...`) | 0, 0 | 1920×1080 |
| Now Playing | Browser | 0, 0 | 1920×1080 |
| Fire Overlay | Browser | 0, 0 | 1920×1080 |

**05 Two Camera**
| Source | Type | Position | Size |
|---|---|---|---|
| Host Camera | Video Capture | 88, 72 | 904×858 |
| Guest Camera | Video Capture | 1010, 72 | 904×858 |
| Two-Cam Overlay | Browser (`05-two-cam.html?host=...&guest=...&topic=...`) | 0, 0 | 1920×1080 |
| Now Playing | Browser | 0, 0 | 1920×1080 |
| Fire Overlay | Browser | 0, 0 | 1920×1080 |

**07 Arranging**
| Source | Type | Position | Size |
|---|---|---|---|
| Arranging Screen | Monitor / Display Capture | 0, 0 | 1920×1080 |
| Host Camera | Video Capture | 10, 64 | 282×158 |
| Pianoteq (inside Keyboard group) | Window Capture | 266, 842 | 1260×192 |
| Arranging Keyboard Frame (inside Keyboard group) | Browser (`08-keyboard-frame.html?toasts=0`) | 0, 0 | 1920×1080 |
| Arranging Overlay | Browser (`07-arranging.html?piece=...&collection=...&...`) | 0, 0 | 1920×1080 |
| Arranging Cam Outline | Browser (`07-cam-outline.html?toasts=0`) | 0, 0 | 1920×1080 |
| Arranging Chat | Browser (`07-chat.html?toasts=0`) | 0, 0 | 1920×1080 |
| Now Playing | Browser | 0, 0 | 1920×1080 |
| Fire Overlay | Browser | 0, 0 | 1920×1080 |

**01 Starting Soon / 04 BRB / 06 Ending**
| Source | Type | Position | Size |
|---|---|---|---|
| (Video — Media Source for 01 and 06) | Media Source — `media/buts.mkv` or `media/tetris.webm` | 0, 0 | 1920×1080 |
| Scene overlay | Browser (`01-starting-soon.html?mins=5&secs=0` / `04-brb.html` / `06-ending.html`) | 0, 0 | 1920×1080 |
| Now Playing | Browser | 0, 0 | 1920×1080 |
| Fire Overlay | Browser | 0, 0 | 1920×1080 |

> OBS layer order: sources lower in the list appear behind sources higher in the list. Browser overlays must be near the top so chrome (logo, ticker, info panel) draws over cameras and game capture.

---

## 8 — Customising

### Colours, fonts, ticker copy, scene styling

All in **`ivgo-shared.js`** at the repo root. Open in any text editor. Look near the top for `const T = { ... }` (design tokens) and `const TICKER = { ... }` (per-scene ticker text).

After editing, refresh every browser source in OBS that uses the changed file: right-click → **Refresh cache of current page**.

### Per-piece info-panel GIFs (Arranging scene)

Drop a GIF in `media/gifs/` with a filename slug derived from collection + piece. See `media/gifs/README.md` for the exact convention. No code changes needed.

### Background videos (Starting Soon / Ending / BRB)

Replace the file in `media/`. For the Starting Soon and Ending Media Sources, OBS will pick up the new file automatically next time the scene activates. For BRB, the HTML loads `media/about.mkv` directly — just overwrite that file.

To re-download the BRB video from YouTube, see `tools/README.md` for the `yt-dlp` recipe.

### Fire effect (Fire Overlay)

The trigger is server-side: `!fine` chat command, costs 100 Ostis, broadcasts the `overlay.fire` event on Phoenix. Animation is `media/overlay/fire-alpha.webm` — a VP9 video with alpha channel and muxed crackle audio. Replace the file to change the look/sound. Default reveal length is 16s (one full audio play).

---

## Troubleshooting

**The script doesn't appear in OBS / clicking "Create" does nothing.**
Check **Help → Log Files → View Current Log**. Look for `[IVGO]` lines. If you see "Could not place source", a scene name might already be taken by an old install — delete the old scene first and re-run.

**Now Playing label is greyed out / no track shows even when Tidal is playing.**
Confirm the watch script is still running (its console window should still be open). Check it's writing `tools/now-playing.json` with track data. Verify the OBS browser source's URL is `http://localhost:7779/scenes/09-now-playing.html?debug=0` (not `file://`).

**Now Playing label disappears entirely.**
The watch script likely crashed. Restart it. Right-click `IVGO: Now Playing` → **Refresh cache of current page**.

**Arranging info panel shows the wrong GIF or no GIF.**
Filenames need to match the slugify convention exactly. See `media/gifs/README.md` — for `FINAL FANTASY VII REBIRTH` + `AERITH'S SUITE` the file is `final-fantasy-vii-rebirth__aeriths-suite.gif` (double underscore between the two slugs).

**Pianoteq window capture is the wrong part of the screen.**
The crop values in the installer (`top=825, bottom=2, left=35, right=41`) assume a specific Pianoteq window size. Right-click `IVGO: Pianoteq` → **Filters** → select **IVGO Keyboard Crop** → adjust the Left/Right/Top/Bottom fields until you see just the keyboard band. (Don't use Edit Transform's Crop fields — the chamfer alpha mask runs after scene-item crop, so adjusting it there would clip the mask instead of the source.)

**Fire overlay shows but black background isn't transparent.**
You're using `fire.webm` instead of `fire-alpha.webm`. The alpha-channel version is what the overlay loads by default — confirm `scenes/10-fire.html` references `fire-alpha.webm`.

**Animations stutter.**
Right-click the offending browser source → Properties → **FPS** → 60.

**Fonts look wrong on first load.**
The overlays load fonts from Google Fonts on first use. Give the stream a minute — fonts cache locally and look correct from then on.

**Scene switches look rough.**
Settings → Scene Transitions → set **Fade** to 200ms for compositing scenes (Game/Camera/Two-Cam/Arranging). Use **Cut** for switching into Starting Soon/BRB/Ending — those have their own entrance animations.

---

## File layout

```
ivgo-overlays/
├── README.md                       # this file
├── HOWTO.md                        # quick-reference setup notes
├── ivgo-shared.js                  # design tokens + shared React components
├── ivgo_obs_setup.lua              # OBS installer (load via Tools → Scripts)
├── phoenix.min.js                  # Phoenix channel client (for live chat events)
├── index.html                      # in-browser preview of all scenes
├── brand-assets/                   # logos
├── media/
│   ├── about.mkv                   # BRB "about IVGO" video
│   ├── buts.mkv                    # Starting Soon background
│   ├── tetris.webm                 # Ending background
│   ├── gifs/                       # arranging info-panel GIFs (see README inside)
│   └── overlay/
│       └── fire-alpha.webm         # !fine fire effect (VP9 alpha + Opus audio)
├── scenes/
│   ├── 01-starting-soon.html
│   ├── 02-game.html
│   ├── 02-cam-outline.html
│   ├── 02-chat.html
│   ├── 03-camera.html
│   ├── 04-brb.html
│   ├── 05-two-cam.html
│   ├── 06-ending.html
│   ├── 07-arranging.html
│   ├── 07-cam-outline.html
│   ├── 07-chat.html
│   ├── 08-keyboard-frame.html
│   ├── 09-now-playing.html         # served by tools/now-playing-watch.ps1
│   └── 10-fire.html                # !fine reward overlay
└── tools/
    ├── README.md                   # SMTC watch script docs
    ├── now-playing-watch.ps1       # SMTC poller + HTTP server (Windows PS 5.1)
    └── smtc-test.ps1               # one-shot diagnostic
```

---

## Hosting online (optional)

Local files work for solo streaming. If you want to update overlays without touching OBS settings — or share with multiple operators — host the static files on Cloudflare Pages / Netlify / Vercel / your own server, then change the **Overlay base URL** in the installer to the hosted URL.

Things to be aware of when hosting:
- The Now Playing source still needs `http://localhost:7779` (it reads local SMTC). Don't host that one.
- `phoenix.min.js` and the scene HTML can all be hosted together. They reference `../ivgo-shared.js` relatively so as long as the file layout is preserved, it works.

---

## Tech notes

- All scenes are vanilla React (loaded from unpkg) — no build step.
- Live chat events come from a Phoenix backend (`ivgo-ex`, separate repo) over a WebSocket.
- Now Playing reads local Windows SMTC via a PowerShell script that serves both the JSON state and the overlay HTML over `http://localhost:7779`.
- The Fire Overlay listens to `overlay.fire` on the Phoenix `overlay:events` channel — wired in `ivgo-shared.js`.
- Animations use the modern CSS `translate` property; requires Chromium 104+. OBS 28+ satisfies this.
