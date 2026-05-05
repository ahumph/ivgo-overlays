# IVGO Twitch Overlay Pack

Professional stream overlays for IVGO channel streamers. Six scenes — Starting Soon, Game, Camera, Be Right Back, Two-Camera interview, and Ending — all designed to work together in OBS.

---

## What you'll get

Each scene is a 1920x1080 graphic that appears on top of your stream in OBS:

| Scene | What it's for |
|---|---|
| Starting Soon | Pre-show countdown while viewers wait |
| Game | Main gaming layout — shows your game, webcam, and chat |
| Camera | Full-frame webcam shot for talking directly to viewers |
| Be Right Back | Holding screen while you step away |
| Two Camera | Interview layout with host on the left, guest on the right |
| Ending | Outro screen to close the stream |

---

## Quick start — OBS installer script (recommended)

This is the fastest way to get up and running. The installer creates all six OBS scenes automatically. No Python, no coding tools — Lua scripting is built into OBS.

### Step 1 — Download the files

Download or clone this repository to a stable folder on your computer. Keep it somewhere permanent — OBS will need to load files from it every stream.

### Step 2 — Open the OBS Scripts panel

1. Open OBS
2. Click **Tools** in the menu bar
3. Click **Scripts**

### Step 3 — Load the installer

1. In the Scripts panel, click the **+** button (bottom left)
2. Navigate to the folder where you saved these files
3. Select **`ivgo_obs_setup.lua`**
4. The script appears in the list — click it to open its settings on the right

### Step 4 — Fill in your details

| Field | What to enter |
|---|---|
| Overlay base URL | Leave as-is if using local files, or enter your hosted URL |
| Host name | Your name in CAPITALS — e.g. `ADAM HUMPHREYS` |
| Host role | Your role in CAPITALS — e.g. `ARTISTIC DIRECTOR` |
| Guest name | For interview streams — guest's name in CAPITALS |
| Guest role | Guest's role in CAPITALS |
| Interview topic | Topic displayed in the Two-Camera scene |
| Countdown target | When your stream starts — e.g. `2026-06-06T19:00:00Z` (see note below) |

> **Countdown format:** use ISO 8601 format: `YYYY-MM-DDTHH:MM:SSZ` where Z means UTC. For a stream starting 7pm UK time (BST, UTC+1), subtract 1 hour — so 7pm BST = `18:00:00Z`. Clear the field entirely to show a static "Starting Soon" screen with no countdown.

### Step 5 — Create your scenes

Click **Create / Refresh Scenes**. OBS creates all six scenes. You'll see them appear in your Scenes panel.

> Safe to re-run any time — it updates existing scenes rather than creating duplicates. Use this to change the guest name, update the countdown, etc.

### Step 6 — Connect your camera and game capture

The installer creates placeholder slots for your webcam and game capture. You need to point these at your actual devices:

**For the Game scene:**
1. In OBS, switch to the **IVGO · 02 Game** scene
2. In the Sources panel, right-click **IVGO: Game Capture** → Properties → select your game window
3. Right-click **IVGO: Host Camera** → Properties → select your webcam

**For the Camera scene:**
1. Switch to **IVGO · 03 Camera**
2. Right-click **IVGO: Host Camera** → Properties → select your webcam (same one as above)

**For the Two Camera scene:**
1. Switch to **IVGO · 05 Two Camera**
2. Right-click **IVGO: Host Camera** → Properties → select your webcam
3. Right-click **IVGO: Guest Camera** → Properties → select your guest's video input

---

## Manual setup (alternative to the installer)

If you prefer to set things up by hand, or if the installer script doesn't work on your system:

### Add a scene for each overlay

For each scene you want, do the following in OBS:

1. In the **Scenes** panel, click **+** and name your scene (e.g. "IVGO Game")
2. In the **Sources** panel, click **+** → **Browser**
3. Set the URL to the local file path of the scene HTML file, for example:
   - Mac: `file:///Users/yourname/ivgo-overlays/scenes/02-game.html`
   - Windows: `file:///C:/Users/yourname/ivgo-overlays/scenes/02-game.html`
4. Set **Width** to `1920` and **Height** to `1080`
5. Tick **"Shutdown source when not visible"** — saves CPU when this scene isn't active
6. Tick **"Refresh browser when scene becomes active"** — plays the entrance animation every time you switch to this scene

### Full-screen scenes (simple — just the browser source)

These scenes cover the whole screen with their own background:

- `01-starting-soon.html` — Starting Soon countdown
- `04-brb.html` — Be Right Back
- `06-ending.html` — Ending

No game capture or webcam needed. Just add the browser source and you're done.

### Compositing scenes (layered — browser source sits on top of your camera/game)

These scenes are transparent overlays that frame your game capture and webcam. You need to layer sources in the right order:

**Game scene (`02-game.html`)** — add these sources in this order (bottom to top):

| Source | Type | Position | Size |
|---|---|---|---|
| Game Capture | Game/Screen Capture | x: 88, y: 72 | 1452 x 824 |
| Host Camera | Video Capture (webcam) | x: 1570, y: 64 | 340 x 191 |
| IVGO: Game Overlay | Browser (`02-game.html`) | x: 0, y: 0 | 1920 x 1080 |
| IVGO: Cam Outline | Browser (`02-cam-outline.html`) | x: 0, y: 0 | 1920 x 1080 |
| IVGO: Chat | Browser (`02-chat.html`) | x: 0, y: 0 | 1920 x 1080 |

**Camera scene (`03-camera.html`)** — add these sources:

| Source | Type | Position | Size |
|---|---|---|---|
| Host Camera | Video Capture (webcam) | x: 320, y: 180 | 1280 x 720 |
| IVGO: Camera Overlay | Browser (`03-camera.html`) | x: 0, y: 0 | 1920 x 1080 |

**Two Camera scene (`05-two-cam.html`)** — add these sources:

| Source | Type | Position | Size |
|---|---|---|---|
| Host Camera | Video Capture (webcam) | x: 88, y: 72 | 904 x 858 |
| Guest Camera | Video Capture (second webcam/NDI) | x: 1010, y: 72 | 904 x 858 |
| IVGO: Two-Cam Overlay | Browser (`05-two-cam.html`) | x: 0, y: 0 | 1920 x 1080 |

> In OBS, sources listed lower in the Sources panel appear behind sources listed higher. The browser overlay must be at the top of the list so the decorative frame draws over the camera/game feeds.

---

## Previewing in a browser

Open `index.html` in any web browser (Chrome or Firefox) to see all six scenes side by side without opening OBS. Useful for checking what things look like before a stream.

---

## Customising the countdown

To set a specific start time for the Starting Soon scene, add `?target=` to the URL in OBS:

```
file:///path/to/scenes/01-starting-soon.html?target=2026-06-06T19:00:00Z
```

Or to set a duration instead (e.g. 10 minutes):

```
file:///path/to/scenes/01-starting-soon.html?mins=10&secs=00
```

If you used the installer script, update the Countdown Target field and click **Create / Refresh Scenes** again.

---

## Customising the Two Camera scene

To show names and topic in the interview layout, add parameters to the URL:

```
.../05-two-cam.html?host=ADAM%20HUMPHREYS&hostRole=ARTISTIC%20DIRECTOR&guest=NIAMH%20O'CONNOR&guestRole=PRINCIPAL%20VIOLIN&topic=WHY%20VIDEO%20GAME%20MUSIC%20DESERVES%20A%20FULL%20ORCHESTRA
```

The installer handles this for you — just update the fields and re-run it.

---

## Updating the design

Colours, fonts, and the text in the ticker bar and header all live in `ivgo-shared.js`. This file is loaded by every scene, so a change there updates everything at once.

You do not need any coding tools — `ivgo-shared.js` is a plain text file. Open it in any text editor (Notepad, TextEdit, VS Code) and look for the section at the top marked with comments.

---

## File layout

```
ivgo-overlays/
├── README.md                   # this file
├── index.html                  # browser preview of all scenes
├── ivgo-shared.js              # shared design tokens and components
├── ivgo_obs_setup.lua          # OBS auto-installer script (Lua — built into OBS, no install needed)
├── ivgo_obs_setup.py           # OBS auto-installer script (Python — alternative)
├── brand-assets/
│   └── IVGO_w.png              # white IVGO logo — used in the ticker bar on every scene
└── scenes/
    ├── 01-starting-soon.html   # pre-show countdown
    ├── 02-game.html            # game layout chrome (header + ticker)
    ├── 02-cam-outline.html     # decorative frame around the webcam
    ├── 02-chat.html            # chat panel (bottom-right)
    ├── 03-camera.html          # full-frame webcam layout
    ├── 04-brb.html             # be right back
    ├── 05-two-cam.html         # interview / two-camera layout
    └── 06-ending.html          # outro
```

---

## Hosting online (optional)

Local files work perfectly for solo streaming from one machine. If you want to update the overlays without touching the OBS settings on your streaming PC — or if multiple people run streams — host the files online instead.

Drop the contents of this folder onto any static hosting service (Cloudflare Pages, Netlify, Vercel, or your own web server). Then in OBS, replace the `file:///` URLs with your hosted URL:

```
https://your-site.example.com/scenes/02-game.html
```

With hosted files, you can change ticker text or fix a typo and it takes effect the next time OBS refreshes the scene — no need to touch OBS itself.

---

## Troubleshooting

**The overlay shows a white background instead of being transparent**
Right-click the browser source in OBS → Properties → add this to the Custom CSS field:
```css
body { background: transparent; }
```

**Animations stutter**
Right-click the browser source → Properties → change FPS to 60.

**Fonts look wrong on first load**
The overlays load fonts from Google Fonts on first use. Allow the stream to run for a minute — the fonts cache and look correct from then on. For permanently offline use, self-host the font files.

**The installer script doesn't appear or do anything in OBS**
Make sure you loaded `ivgo_obs_setup.lua`, not the `.py` file. Lua is built into OBS — no extra installation needed. If the button does nothing, check the OBS log (Help → Log Files → View Current Log) for any `[IVGO]` error lines.

**Scene switching looks rough**
In OBS, right-click between scenes in the Scene Transitions panel and set Fade to 200ms for Game/Camera/Two-Cam switches. Use Cut for switching into Starting Soon and BRB — those scenes have their own entrance animation that acts as the transition.

---

## Technical notes

The overlays are React applications loaded directly in OBS's built-in browser (Chromium 104+). No build step is needed — React loads from unpkg.com. All six scenes share `ivgo-shared.js` which contains the design system (tokens, components, animations). Edit once, all scenes update.

Animations use the CSS `translate` property (not the legacy `transform` shorthand) so they compose correctly with centred elements. This requires Chromium 104 or newer — OBS satisfies this requirement.
