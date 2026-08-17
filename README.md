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

Extras layered on every scene:

- **Now Playing** — a slide-out strip showing what's playing on Tidal / YouTube. Hidden by default; viewers reveal it with `!np` or `!playing` in chat.
- **Fire Overlay** — triggered by the `!fine` chat command (costs 100 Ostis); plays a fire effect over whatever scene you're on.
- **Card Pull** — triggered by the `!pull` chat command (Trading Cards feature); pops bottom-left as a WeeMan card back, flips to reveal the pulled card, holds ~6s.
- **Clip Player** — paste a link to one of this channel's clips in chat and it plays in a panel (centered, or small in the top-left); mods can `!so <user>` to play another streamer's featured clip. Clips from other channels are ignored.
- **WeeMan Avatars** — viewers type `!weeman` to send their own WeeMan walking along the bottom of the stream for 15 minutes, in their chat colour, with their chat messages in speech bubbles above it.
- **Commands card** — `!info` slides up a card listing the chat commands that work on this scene. On 07 Arranging the same command shows the ON THE DESK piece card instead.
- **Raid alerts** — a Twitch raid pops the usual toast + `media/raid.mp4` egg *and* fades in a fullscreen `media/WeeManRaid.mp4` backdrop behind them (black-keyed via an SVG luma filter, with audio).
- **Mic mute indicator** — a small icon at the top-left (`media/mute.png` while the OBS *Mic/Aux* input is muted; `media/microphone.png` flashes for ~2s then fades out on unmute). Reads OBS state over obs-websocket.

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

> **First-time only:** the script writes a default obs-websocket config (port 4455, no auth) so the mic-mute indicator can read OBS state. If you're a fresh OBS install, **restart OBS once** after loading the script for that to activate. If you already have obs-websocket configured (with or without a password), the script leaves your config alone — pass `?obsws_pw=yourpassword` on the overlay browser-source URL if you've set one.

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
| **Twitch channel** | Channel login the Clip Player reads chat from — and the only channel whose clips play from viewer links. |
| **Clip player** | Whether to add the Clip Player source at all. Uncheck and rebuild to remove it. |
| **Clip player size** | *Large* (1280×720, centered) or *Small* (960×540, top-left). |
| **WeeMan avatars** | Whether to add the WeeMan Avatars source. Uncheck and rebuild to remove it. |
| **WeeMan: minutes on screen** | How long a summoned avatar lasts. Default 15. |
| **WeeMan: show chat speech bubbles** | Whether a viewer's chat messages appear above their avatar. Untick to show names only. |
| **Commands card** | Whether `!info` slides up a chat-commands card on the non-Arranging scenes. The card lists only the commands whose feature is enabled above. |
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
| `!info` | On **07 Arranging**, surfaces the "ON THE DESK" piece/game card for 10s. On every other scene, slides up a card listing the chat commands that work there. Either way, 10s on screen, 30s global cooldown. `!commands` is an alias for the command card. |
| `!pomo` | Bot replies with current phase + time remaining + sprint x/y. 30s cooldown per user. |
| `!progress` | Bot replies with current piece, game, and open task count. 60s cooldown per user. |
| `!help` | Bot replies with a one-line command summary. 60s cooldown per user. |
| `!np` / `!playing` | Slide the Now Playing strip down for 30s (shows current Tidal / YouTube / etc. track). |
| `!fine` | Trigger the fire overlay. Costs 100 Ostis. |
| `!weeman` | Sends your own WeeMan walking along the bottom of the stream for 15 minutes, tinted with your chat colour and captioned with your name. While it's out, anything you say appears in a speech bubble above it. Typing it again tops the timer back up. One per viewer, 20 on screen at once. |
| *(paste a clip link)* | Plays the clip in a centered panel — **only** clips from this channel. Any other channel's clip is silently ignored. 60s cooldown per viewer, 15s between clips, same clip won't replay within 30 min. Mods and the broadcaster are exempt from the per-viewer cooldown and the replay block, so they can re-post a clip deliberately. |

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
| `!clipstop` / `!stopclip` / `!skipclip` | Cut off the clip that's playing right now and empty the queue. Instant — video and audio both stop. |
| `!weemanclear` | Send every WeeMan avatar home. They walk off rather than vanishing. |
| `!so <user>` / `!shoutout <user>` | Play one of that streamer's own Featured Clips (picked at random) in the centered panel, styled amber. Falls back to their most-viewed clip if they haven't set a featured shelf; does nothing if they have no clips. Mods are exempt from the per-viewer clip cooldown. |

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
| Commands Card | Browser (`13-help.html?toasts=0&egg_off=1&raid_bg_off=1&help_items=...`) | 0, 0 | 1920×1080 |
| WeeMan Avatars | Browser (`12-weeman.html?toasts=0&egg_off=1&raid_bg_off=1&channel=...`) | 0, 0 | 1920×1080 |
| Clip Player | Browser (`11-clip.html?toasts=0&egg_off=1&raid_bg_off=1&channel=...&clip_size=...`) | 0, 0 | 1920×1080 |
| Fire Overlay | Browser (`10-fire.html?toasts=0&egg_off=1&raid_bg_off=1`) | 0, 0 | 1920×1080 |

**03 Camera**
| Source | Type | Position | Size |
|---|---|---|---|
| Host Camera | Video Capture | 320, 180 | 1280×720 |
| Camera Overlay | Browser (`03-camera.html?host=...&hostRole=...`) | 0, 0 | 1920×1080 |
| Now Playing | Browser | 0, 0 | 1920×1080 |
| Commands Card | Browser | 0, 0 | 1920×1080 |
| WeeMan Avatars | Browser | 0, 0 | 1920×1080 |
| Clip Player | Browser | 0, 0 | 1920×1080 |
| Fire Overlay | Browser | 0, 0 | 1920×1080 |

**05 Two Camera**
| Source | Type | Position | Size |
|---|---|---|---|
| Host Camera | Video Capture | 88, 72 | 904×858 |
| Guest Camera | Video Capture | 1010, 72 | 904×858 |
| Two-Cam Overlay | Browser (`05-two-cam.html?host=...&guest=...&topic=...`) | 0, 0 | 1920×1080 |
| Now Playing | Browser | 0, 0 | 1920×1080 |
| Commands Card | Browser | 0, 0 | 1920×1080 |
| WeeMan Avatars | Browser | 0, 0 | 1920×1080 |
| Clip Player | Browser | 0, 0 | 1920×1080 |
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
| Commands Card | Browser | 0, 0 | 1920×1080 |
| WeeMan Avatars | Browser | 0, 0 | 1920×1080 |
| Clip Player | Browser | 0, 0 | 1920×1080 |
| Fire Overlay | Browser | 0, 0 | 1920×1080 |

**01 Starting Soon / 04 BRB / 06 Ending**
| Source | Type | Position | Size |
|---|---|---|---|
| (Video — Media Source for 01 and 06) | Media Source — `media/buts.mkv` or `media/tetris.webm` | 0, 0 | 1920×1080 |
| Scene overlay | Browser (`01-starting-soon.html?mins=5&secs=0` / `04-brb.html` / `06-ending.html`) | 0, 0 | 1920×1080 |
| Now Playing | Browser | 0, 0 | 1920×1080 |
| Commands Card | Browser | 0, 0 | 1920×1080 |
| WeeMan Avatars | Browser | 0, 0 | 1920×1080 |
| Clip Player | Browser | 0, 0 | 1920×1080 |
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

### Commands card (`!info` off the Arranging scene)

`scenes/13-help.html` — the `IVGO: Commands Card` source. `!info` slides a panel up from the ticker for 10 seconds listing the chat commands that work, then it drops back down. Same gesture, same `!INFO` label handle and same timing as the Arranging scene's info panel, so the two read as one mechanism across the pack.

Added to **every scene except 07 Arranging**, which has its own `!info` that slides the ON THE DESK card up from the same spot — both at once would collide.

**The overlay commands are listed only when they're switched on.** The installer builds the row list from your settings: `!np` appears only if the Now-Playing base URL is set, `!weeman` only if the avatars are enabled, clip links only if the clip player is on, and `!fine` only if a Socket URL is configured (no Phoenix backend means no Ostis). So it can't advertise one of ours that would do nothing.

**`!concerts`, `!socials`, `!discord` and `!x` are answered by Nightbot**, not by this pack — nothing here handles them, they're listed because they work. There's no setting for them for the same reason. If one is renamed or dropped in Nightbot, update the list in `build_help` (`ivgo_obs_setup.lua`) and the `CATALOG` in `scenes/13-help.html` to match; nothing will catch the drift automatically.

The always-present rows (`!concerts`, `!socials`, `!discord`, `!x`, `!info`) are `STATIC_ITEMS` in the page, so editing them only needs a page refresh. The feature-gated ones come from the installer via `help_items`, so changing those needs a scene rebuild. Wording for all of them lives in the `CATALOG` object at the top of the page — edit the wording there, and the installer's `help_items` decides which appear and in what order. Per-source overrides: `help_off=1`, `help_items=np,clip,weeman,fine,info`, `help_secs`, `help_cooldown`, `help_left` / `help_right` (panel insets; the default right inset clears a scene's chat panel).

Preview it with `scenes/13-help.html?help_test=1`.

Like the other chat overlays it reads chat directly rather than going through Phoenix, so it works with the backend offline.

### WeeMan avatars

`scenes/12-weeman.html` — the `IVGO: WeeMan Avatars` source, layered above the scene chrome so the cast walks along the top of the ticker like a ledge, but below the clip player and fire overlay so an alert always wins the foreground.

A viewer types `!weeman` and their WeeMan walks on from the nearest edge, patrols the bottom of the screen for 15 minutes, then walks off and leaves. It's the existing `WeeMan` SVG from `ivgo-shared.js`, tinted with their Twitch chat colour (falling back to a hash of their name), so a given person is the same colour every stream. The name sits above in Courier New.

**The speech bubbles are the point.** While your avatar is out, anything you say in chat appears above it for a few seconds. That's what makes the command worth spending on: it puts the viewer in the scene rather than only on the chat panel. Untick **WeeMan: show chat speech bubbles** if you'd rather show names only — it does put viewer text on the stream.

The cast reacts to the rest of the overlay: follows, subs, gifts and cheers make everyone jump, and a raid sends them all home so they aren't wandering under the raid alert.

Settings: **WeeMan avatars** (on/off), **WeeMan: minutes on screen**, **WeeMan: show chat speech bubbles**. Per-source overrides: `weeman_off=1`, `weeman_mins`, `weeman_max`, `weeman_bubbles=0`, `weeman_base` (px from the bottom, default 26 — lower than the ticker's 36 because the WeeMan artwork has empty space under its feet, so this stands them on the chrome rather than above it), `weeman_size`.

The cast survives a source refresh — names, colours and expiry times are kept in `localStorage`, so a mid-stream refresh doesn't rob 20 people of time they paid for.

To preview without live chat:

```
scenes/12-weeman.html?weeman_test=alice,bob,carol
scenes/12-weeman.html?weeman_test=alice&weeman_test_say=hello
```

**Free to summon as it stands.** Charging Ostis needs `ivgo-ex`, which owns the balances — it would deduct and then broadcast `overlay.weeman` with `{user_name, colour, duration_ms}`, which this page already listens for. Same shape as `!fine` driving the fire overlay.

### Clip player

`scenes/11-clip.html` — a clip panel added to every scene as the `IVGO: Clip Player` browser source. Two sizes, set with **Clip player size** in the script settings:

| Size | Dimensions | Placement |
|---|---|---|
| **Large** (default) | 1280×720 | Centered on the canvas |
| **Small** | 960×540 | Top-left, tucked under the header bar (10, 64) |

Small also pulls the 480p rendition instead of 720p, and scales the header/footer chrome to match. Unlike the rest of the chat features, this one is **entirely client-side**: it opens its own anonymous IRC connection and needs no Phoenix backend, no Twitch app, and no API token.

Two triggers:

- **Anyone pastes a clip link.** All link shapes work (`clips.twitch.tv/<slug>`, `twitch.tv/<channel>/clip/<slug>?filter=...`, `m.twitch.tv/clip/<slug>`, embed URLs). The clip plays **only if it belongs to this channel** — anyone else's clip is dropped with a console note. That filter is the whole safety story: without it, any viewer could put arbitrary video and audio on the stream.
- **A mod types `!so <user>`.** Plays a random clip from that streamer's Featured Clips shelf, falling back to their most-viewed clip. The channel filter is skipped here by design.

Clips play at full volume — ride your own levels. The installer configures the source's audio for you: **Control audio via OBS** (`reroute_audio`) so it lands in the mixer as its own channel, and **Monitor and Output** so you hear it too. Without the first, browser audio bypasses the mixer and only reaches the stream if you happen to capture desktop audio.

Unlike the other overlay sources, the Clip Player is also set to **not** shut down when hidden and **not** refresh on scene activation. It's stateful — an IRC connection plus every cooldown and already-played record — so a restart would kill a playing clip and reset the spam limits on every scene change.

Raid alerts win: a raid pulls the panel off screen immediately, cuts its audio, drops the interrupted clip, and blocks new ones for 10s (the length of `WeeManRaid.mp4`).

#### Cutting a clip short

Clips run up to Twitch's 60s maximum, so there are two ways to pull one:

- **`!clipstop` in chat** (mods and broadcaster) — the everyday lever. Stops playback instantly and empties the queue, so the next clip doesn't just start a second later. Works from a phone. Aliases: `!stopclip`, `!skipclip`.
- **A hotkey** — bind one under OBS → **Settings** → **Hotkeys** → *IVGO: Stop clip player*. No key is bound out of the box. Use this when you're mid-game and typing in chat isn't realistic.

The hotkey works by reloading the Clip Player source, which is blunt but needs no extra plumbing: OBS Lua has no clean channel into a running browser page. The side effect is that per-viewer cooldowns and the already-played list reset, so whoever posted the clip you just pulled could immediately re-post it. `!clipstop` has no such downside — the stopped clip stays on the already-played list and can't come back for 30 minutes. Prefer chat where you can.

An interrupted clip is never resumed, by either route.

There are two more triggers, both live end to end — the overlay side and the `ivgo-ex` broadcasts it depends on (see below):

- **Twitch's native `/shoutout` button** — plays the shouted-at streamer's featured clip, same as `!so`.
- **Starting a raid** — when *we* raid someone, plays the channel we're sending everyone to, labelled `RAIDING · <CHANNEL>` in red. This one preempts: it clears the queue and cuts off anything playing, because the raid fires on its own countdown and won't wait. An *incoming* raid never plays a clip — it pulls the panel instead, and shouting the raider out is the way to show their clip.

#### How ivgo-ex sends these

Neither is detectable client-side. Twitch documents no shoutout `msg-id` for `USERNOTICE` or `NOTICE`, so an anonymous IRC connection cannot see a `/shoutout` at all, and an outgoing raid produces no chat message either. Both are EventSub-only, and EventSub needs a user token — which lives in `ivgo-ex`, where the follow/sub/raid pipeline already runs.

| Event | Subscription | Scope |
|---|---|---|
| `channel.shoutout.create` | `broadcaster_user_id` + `moderator_user_id` = IVGO | `moderator:read:shoutouts` |
| `channel.raid` (outgoing) | `from_broadcaster_user_id` = IVGO | none |

Both are re-broadcast on `overlay:events` under their EventSub names, with the event body intact — the overlay reads `to_broadcaster_user_login` from each. `channel.raid` carries two separate subscriptions in `ivgo-ex` — `to_broadcaster_user_id` for incoming, `from_broadcaster_user_id` for outgoing — since both directions arrive under the same event name and need telling apart by payload, not subscription.

Both event names are in the allowlist in `ivgo-shared.js` (the `_channel.on(type, …)` array) — an event not named there never reaches `bus.on()` listeners.

Because both raid directions arrive on the same event name, the overlay branches on the payload: `from_broadcaster_user_login` matching our channel means outgoing. The raid alerts (toast, egg, WeeMan backdrop) are gated the same way, so they only fire for a raid arriving — a payload with no `from_` field counts as incoming.

To preview the panel without live chat, open the page in any browser with a test param:

```
scenes/11-clip.html?clip_test=<clip-slug>
scenes/11-clip.html?clip_test_so=<streamer-login>
```

Tuning (cooldowns, queue depth, raid block) lives in the constants at the top of `scenes/11-clip.html`. Turn the whole thing off with the **Clip player** checkbox in the script settings, or per-source with `?clip_off=1`.

Per-source URL overrides, if one scene wants different treatment from the rest:

| Param | Effect |
|---|---|
| `clip_size=large` / `small` | The two presets above. |
| `clip_w` / `clip_h` | Explicit video box size, overriding the preset. |
| `clip_top` / `clip_left` | Anchor offset in px. Setting either one anchors the panel instead of centering it — so a large panel can sit in a corner too. |
| `clip_off=1` | Disable on this source. |

#### How clips resolve to video

Twitch's official `clips.twitch.tv/embed` iframe requires a `parent=` domain matching a real HTTP origin, and OBS loads these scenes over `file://` — so the embed is out. Helix returns clip metadata but no playable file (the old "swap the thumbnail suffix for `.mp4`" trick doesn't work on clips hosted under `twitch-video-assets`). So the page queries Twitch's GQL endpoint with the public web Client-Id for a signed, direct MP4, which a plain `<video>` element plays.

That endpoint is undocumented — the same one clip downloaders use. It works today from a `file://` origin (it answers `Access-Control-Allow-Origin: *`), but Twitch owes it no stability. If it ever changes, clips stop resolving and the panel just never appears — nothing else on the overlay is affected, and the reason lands in the browser-source console.

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

**Changed `11-clip.html` but the Clip Player still behaves like the old version.**
The source is serving a cached page. OBS only reloads a browser source when its **URL** changes, and this one deliberately has *refresh on scene activation* off (it's stateful), so an HTML edit that doesn't also change a URL param won't be picked up. Clicking **Create / Refresh Scenes** now forces a no-cache reload of this source, so that's the fix — or right-click `IVGO: Clip Player` → **Refresh cache of current page**.

**Clip plays but you can't hear it (or viewers can't).**
The installer sets this up, so this should only bite a source created before the audio wiring existed — click **Create / Refresh Scenes** to re-apply it. To check by hand: right-click `IVGO: Clip Player` → **Properties** → tick **Control audio via OBS**, then right-click it in the **Audio Mixer** → **Advanced Audio Properties** → set **Audio Monitoring** to *Monitor and Output*. Without the first, browser audio bypasses the mixer entirely and only reaches the stream if you happen to capture desktop audio; without the second, you won't hear it in your own headphones.

**Mic mute icon never appears (or never disappears).**
Check obs-websocket is enabled: OBS → **Tools** → **WebSocket Server Settings** → Server Enabled, port 4455. If you've set a password, append `?obsws_pw=yourpassword` to the overlay browser-source URL. If your mic input isn't called *Mic/Aux*, override with `?mic_input=Your Input Name`. Disable per-source with `?mic_off=1`.

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
│   ├── raid.mp4                    # raid alert egg clip
│   ├── WeeManRaid.mp4              # fullscreen raid backdrop (black-keyed)
│   ├── microphone.png              # mic-unmuted indicator (briefly shown then faded)
│   ├── mute.png                    # mic-muted indicator (persistent while muted)
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
│   ├── 10-fire.html                # !fine reward overlay
│   ├── 11-clip.html                # centered clip player (chat links + !so)
│   ├── 12-weeman.html              # chat-summoned WeeMan avatars (!weeman)
│   └── 13-help.html                # !info commands card (non-Arranging scenes)
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
- The Clip Player is the one chat feature that doesn't go through Phoenix: it reads chat over its own anonymous Twitch IRC socket and resolves clips to signed MP4s via Twitch GQL, so it works with the backend offline. Its native-`/shoutout` and raid-out triggers are the exception — those are EventSub-only, broadcast by `ivgo-ex`.
- `channel.raid` covers raids in both directions. Anything reacting to it should check `from_broadcaster_user_login` against our channel; alerts are a welcome and must not fire when we raid out.
- Every page that connects to the bus mounts toasts, the video egg and the raid backdrop (the auto-wire block in `ivgo-shared.js`). Full-canvas overlay sources stacked on top of a scene must therefore pass `toasts=0&egg_off=1&raid_bg_off=1`, or alerts fire twice with doubled audio.
- Animations use the modern CSS `translate` property; requires Chromium 104+. OBS 28+ satisfies this.
