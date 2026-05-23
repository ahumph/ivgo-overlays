# IVGO overlay tools

Local-only helpers for the OBS overlay. None of these talk to `ivgo-ex`
(Phoenix) — they're entirely standalone.

## `now-playing-watch.ps1`

Bridges the Windows **System Media Transport Controls** (SMTC) API to the
overlay so the `IVGO: Now Playing` browser source can display whatever's
playing in Tidal or YouTube (or any other Chromium / Firefox tab, Spotify,
Apple Music — anything that registers with SMTC).

The script does two things in one process:

1. **Polls SMTC every 2 seconds.** Picks the highest-priority *playing*
   session (Tidal > Chrome / Edge / Firefox > nothing). When everything is
   paused, the panel hides.
2. **Serves an HTTP API on `http://localhost:7779`** so the OBS browser
   source can fetch state without hitting CEF's `file://` CORS restrictions.
   Endpoints:
   - `GET /state` — current track JSON (or `null`).
   - `GET /scenes/09-now-playing.html` — the overlay HTML.
   - `GET /<any-repo-file>` — static-serves any file under the repo root.

### Prerequisites

- **Windows** (uses the Windows.Media.Control WinRT API).
- **Windows PowerShell 5.1** (`powershell.exe`), **NOT** PowerShell 7+
  (`pwsh.exe`). PS7 dropped WinRT projection support. The script will fail
  with an "Unable to find type" error if you run it under pwsh.

### Run

From the repo root:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tools\now-playing-watch.ps1
```

Leave the window open (minimised is fine) while streaming. The script
prints each state change so you can see Tidal/YouTube events landing.

### OBS setup

The `ivgo_obs_setup.lua` installer adds an `IVGO: Now Playing` browser
source to every main scene, configured to load
`http://localhost:7779/scenes/09-now-playing.html` (controlled by the
"Now-Playing HTTP base" field in the Scripts panel — leave blank to skip
the overlay entirely).

If the watch script isn't running, the browser source loads an empty page —
no crash, no console errors. Start the script and refresh the source's
cache to recover.

### Auto-start at login (optional)

Open Task Scheduler → Create Task:

- **Triggers**: At log on (your user)
- **Actions**: Start a program
  - Program: `powershell.exe`
  - Arguments: `-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "C:\path\to\ivgo-overlays\tools\now-playing-watch.ps1"`
- **Settings**: ✅ Allow task to be run on demand. ❌ Stop if running longer than… (uncheck).

### Chat commands

The overlay listens to Twitch IRC directly (anonymous read-only,
`justinfan` pattern) — no backend required. Recognised commands:

- `!np` — reveals the now-playing panel for 30s (configurable via
  `?reveal_ms=` URL param).
- `!playing` — alias for `!np`.

When nothing is playing, the `!PLAYING` label is greyed out and chat
commands are silently ignored.

### URL params on the browser source

- `?reveal_ms=15000` — duration the panel stays revealed after a chat
  command. Default 30000 (30s).
- `?channel=somechannel` — which Twitch channel to listen on. Default
  `irishvideogameorchestra`.
- `?top=200&right=50` — relocate the label-handle.
- `?debug=1` — show a small status pill in the top-left (handy when
  debugging fetch / WebSocket issues).

## Refreshing the BRB "About" video

The 04 Be Right Back scene plays a local copy of the IVGO about-us video.
Download or re-download it with [yt-dlp](https://github.com/yt-dlp/yt-dlp):

```powershell
yt-dlp -f "bestvideo[height<=1080]+bestaudio/best" --merge-output-format mkv `
  -o "media/about.mkv" "https://www.youtube.com/watch?v=<id>"
```

If the resulting file refuses to autoplay in OBS (codec issue), remux to
H.264 + AAC in an `.mp4` container — works everywhere with no quality loss:

```powershell
ffmpeg -i media/about.mkv -c copy media/about.mp4
```

Then update the `src` in `scenes/04-brb.html` accordingly.

## `smtc-test.ps1`

One-shot diagnostic. Prints every SMTC session currently visible to
Windows, marks the "current" one, and shows Title / Artist / Album /
Playback Status. Use it to confirm Tidal / YouTube are exposing metadata
before relying on the watch script.

Same Windows PowerShell 5.1 requirement applies.

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tools\smtc-test.ps1
```
