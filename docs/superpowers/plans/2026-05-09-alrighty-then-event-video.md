# Alrighty-Then Event Video Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Play `media/alrighty-then.mp4` with audio in a chamfered 480×270 box at the top-left of every IVGO scene whenever a viewer follows, subscribes, or gifts a sub. If multiple events arrive while playing, drain the queue with exactly one follow-up play.

**Architecture:** Self-mounting IIFE `_alrighty` added to `ivgo-shared.js` next to the existing `_toast` singleton; same auto-wire pattern via `DOMContentLoaded`. Two-flag state machine (`playing`, `pending`) gives the "one drain play" semantics.

**Tech Stack:** Plain ES2017 JS, HTML5 `<video>`, existing IVGO design tokens (`T`) and chamfer class (`ovl-chamfer-sm`). No new dependencies.

**Note on testing:** This codebase has no automated test infrastructure — overlays are verified manually via the OBS browser source's devtools and live Twitch events. Each task below ends with concrete manual verification steps that exercise the exact behaviour the spec requires (state machine, drain semantics, scope of triggering events).

---

## File Structure

| File | Status | Responsibility |
|---|---|---|
| `media/alrighty-then.mp4` | New (binary) | The video clip itself, served as `../media/alrighty-then.mp4` from any `scenes/*.html`. |
| `ivgo-shared.js` | Modified | Add `_alrighty` IIFE after `_toast` (~line 250); add three `_bus.on(…)` lines inside the existing `DOMContentLoaded` handler (~line 254); add `alrighty: _alrighty.trigger` to the `window.IVGO` export (~line 636). |

No scene HTML files change. No OBS Lua changes. No backend changes.

---

## Task 1: Add the video asset

**Files:**
- Create: `media/alrighty-then.mp4` (copy from `~/Downloads/alrighty-then.mp4`)

- [ ] **Step 1: Create the `media/` directory and copy the file**

Run:
```bash
mkdir -p media && cp ~/Downloads/alrighty-then.mp4 media/alrighty-then.mp4
```

- [ ] **Step 2: Verify the file landed and is non-empty**

Run:
```bash
ls -lh media/alrighty-then.mp4
```

Expected: file exists, size > 0 bytes (typically 100 KB – 5 MB for a short clip).

- [ ] **Step 3: Sanity-check it's playable in a browser before committing**

Run:
```bash
start media/alrighty-then.mp4
```
(On Windows; `open` on macOS, `xdg-open` on Linux.)

Expected: default video player opens and plays the clip with audio. If it doesn't play, stop here — the file is corrupt or in an unsupported codec, and the rest of the plan won't work.

- [ ] **Step 4: Commit**

Run:
```bash
git add media/alrighty-then.mp4
git commit -m "feat: add alrighty-then video asset"
```

Expected: one commit, one file added.

---

## Task 2: Add the `_alrighty` singleton with manual test hook

**Files:**
- Modify: `ivgo-shared.js` — insert IIFE after line 250 (just after the `_toast` IIFE closes); modify the `window.IVGO` export at lines 630–637.

- [ ] **Step 1: Insert the `_alrighty` IIFE after `_toast`**

Open `ivgo-shared.js`. Find the line `})();` that closes the `_toast` IIFE (line 250 — the one immediately followed by `// Auto-wire Twitch events to toasts`). Insert the following block immediately after that closing line and the blank line that follows it, **before** the `// Auto-wire Twitch events to toasts` comment:

```js
// ── AlrightyBox ───────────────────────────────────────────────────────────
// Top-left video easter egg. Plays media/alrighty-then.mp4 with audio
// whenever channel.follow / channel.subscribe / channel.subscription.gift
// fires. If events arrive while playing, drains them with one follow-up
// play (pending-flag model — N events during one play → exactly 2 plays).

const _alrighty = (function () {
  const SRC = '../media/alrighty-then.mp4';
  let containerEl = null;
  let videoEl = null;
  let playing = false;
  let pending = false;

  function ensureMounted() {
    if (containerEl) return;
    containerEl = document.createElement('div');
    containerEl.className = 'ovl-chamfer-sm';
    containerEl.style.cssText = [
      'position:fixed',
      'top:64px',
      'left:10px',
      'width:480px',
      'height:270px',
      'opacity:0',
      'pointer-events:none',
      'transition:opacity 250ms ease',
      'z-index:9',
      'border:1px solid ' + T.rule2,
      'background:#000',
      'overflow:hidden',
      'box-shadow:0 4px 24px rgba(0,0,0,.5)',
    ].join(';');

    videoEl = document.createElement('video');
    videoEl.src = SRC;
    videoEl.preload = 'auto';
    videoEl.playsInline = true;
    videoEl.style.cssText = 'width:100%;height:100%;object-fit:cover;display:block';
    videoEl.addEventListener('ended', onEnded);
    videoEl.addEventListener('error', onError);

    containerEl.appendChild(videoEl);
    document.body.appendChild(containerEl);
  }

  function hide() {
    if (containerEl) containerEl.style.opacity = '0';
  }

  function onEnded() {
    if (pending) {
      pending = false;
      videoEl.currentTime = 0;
      videoEl.play().catch(onPlayReject);
      return;
    }
    playing = false;
    hide();
  }

  function onError(e) {
    console.warn('[IVGO alrighty] video error', e);
    playing = false;
    pending = false;
    hide();
  }

  function onPlayReject(err) {
    console.warn('[IVGO alrighty] play() rejected:', err);
    playing = false;
    pending = false;
    hide();
  }

  function trigger() {
    ensureMounted();
    if (playing) {
      pending = true;
      return;
    }
    playing = true;
    containerEl.style.opacity = '1';
    videoEl.currentTime = 0;
    videoEl.play().catch(onPlayReject);
  }

  return { trigger };
})();

```

- [ ] **Step 2: Add `alrighty` to the `window.IVGO` export**

In the same file, find the export block at the bottom (lines 630–637 in the current file). Change:

```js
  bus: _bus,
  toast: _toast.toast,
};
```

to:

```js
  bus: _bus,
  toast: _toast.toast,
  alrighty: _alrighty.trigger,
};
```

- [ ] **Step 3: Manual verification — single trigger plays video**

Open `scenes/02-game.html` directly in a Chromium-based browser (Chrome, Edge, or Brave) by opening the file with `start scenes/02-game.html` (Windows) so the relative path `../media/alrighty-then.mp4` resolves. Open devtools (F12) and run in the console:

```js
IVGO.alrighty()
```

Expected:
- A 480×270 chamfered black box fades in at top:64px, left:10px (just below the header bar).
- The video plays with audio.
- When playback ends, the box fades out cleanly.
- No console errors.

If the video plays without audio, autoplay policy may be blocking — note this and proceed; OBS browser sources allow autoplay-with-audio by default, so it'll be fine in production.

- [ ] **Step 4: Manual verification — drain semantics**

In the same console, run:

```js
IVGO.alrighty(); IVGO.alrighty(); IVGO.alrighty(); IVGO.alrighty();
```

Expected:
- Video plays once (the initial trigger), then plays a second time immediately on `ended` (the drain), then stops. Total: exactly **2 plays**, regardless of how many trigger calls were stacked.
- Box fades out only after the second play ends.

This is the core spec requirement — verify it carefully. If you see 3+ plays or only 1 play, the state machine is wrong; do not proceed to Task 3.

- [ ] **Step 5: Manual verification — replay after settled**

Wait until the box has faded out, then run:

```js
IVGO.alrighty()
```

Expected: video plays exactly once and fades out. (Confirms `playing` and `pending` reset cleanly after a settled cycle.)

- [ ] **Step 6: Commit**

Run:
```bash
git add ivgo-shared.js
git commit -m "feat: add alrighty-then video singleton with test hook

Mounts a 480x270 chamfered box at top:64,left:10 and plays
media/alrighty-then.mp4 with audio. Two-flag state machine
(playing, pending) gives one-drain-play semantics for queued
events. Exposed as window.IVGO.alrighty for manual triggering."
```

Expected: one commit modifying `ivgo-shared.js`.

---

## Task 3: Wire the singleton to follow / subscribe / gift bus events

**Files:**
- Modify: `ivgo-shared.js` — add three `_bus.on(…)` lines inside the existing `DOMContentLoaded` handler (currently lines 254–259).

- [ ] **Step 1: Add three bus listeners**

Find the existing block:

```js
// Auto-wire Twitch events to toasts
if (typeof document !== 'undefined') {
  document.addEventListener('DOMContentLoaded', function () {
    _bus.on('channel.follow', p => _toast.toast({ type: 'follow', ...p }));
    _bus.on('channel.subscribe', p => _toast.toast({ type: 'sub', ...p }));
    _bus.on('channel.subscription.gift', p => _toast.toast({ type: 'gift', ...p }));
    _bus.on('channel.cheer', p => _toast.toast({ type: 'cheer', ...p }));
  });
}
```

Replace it with:

```js
// Auto-wire Twitch events to toasts and alrighty video
if (typeof document !== 'undefined') {
  document.addEventListener('DOMContentLoaded', function () {
    _bus.on('channel.follow', p => _toast.toast({ type: 'follow', ...p }));
    _bus.on('channel.subscribe', p => _toast.toast({ type: 'sub', ...p }));
    _bus.on('channel.subscription.gift', p => _toast.toast({ type: 'gift', ...p }));
    _bus.on('channel.cheer', p => _toast.toast({ type: 'cheer', ...p }));

    _bus.on('channel.follow',            () => _alrighty.trigger());
    _bus.on('channel.subscribe',         () => _alrighty.trigger());
    _bus.on('channel.subscription.gift', () => _alrighty.trigger());
  });
}
```

(Note: `channel.cheer` is intentionally NOT wired to alrighty — bits don't trigger the video, per spec.)

- [ ] **Step 2: Manual verification — bus dispatch triggers video**

Reload `scenes/02-game.html` in the browser, open devtools, run:

```js
IVGO.bus.dispatch('channel.follow', { user_name: 'tester' })
```

Expected:
- A toast appears bottom-left ("NEW FOLLOWER · tester")
- The alrighty video fades in top-left and plays with audio
- Both clear cleanly when finished

Repeat with the other two event types:

```js
IVGO.bus.dispatch('channel.subscribe', { user_name: 'tester', tier: '1000' })
IVGO.bus.dispatch('channel.subscription.gift', { user_name: 'tester', total: 5 })
```

Expected for each: corresponding toast appears AND video plays.

- [ ] **Step 3: Manual verification — cheer does NOT trigger video**

Wait until everything has settled, then run:

```js
IVGO.bus.dispatch('channel.cheer', { user_name: 'tester', bits: 100 })
```

Expected:
- A bits toast appears bottom-left.
- The alrighty video does **not** play. (No box fade-in, no audio.)

If the video plays here, Task 3 step 1 was applied incorrectly — recheck the diff.

- [ ] **Step 4: Manual verification — drain semantics via real bus dispatch**

Wait for everything to settle. Run:

```js
IVGO.bus.dispatch('channel.follow', {});
IVGO.bus.dispatch('channel.subscribe', {});
IVGO.bus.dispatch('channel.subscription.gift', {});
```

Expected:
- Three toasts queue up bottom-left (or stagger per existing toast logic).
- The video plays exactly **2 times** total — once for the first event, once to drain the remaining queued events.

- [ ] **Step 5: Commit**

Run:
```bash
git add ivgo-shared.js
git commit -m "feat: wire alrighty video to follow/subscribe/gift bus events

Cheers deliberately not wired — bits don't trigger the video.
Existing ?toasts=0 gate disables the bus on auxiliary sources
(cam-outline, chat), so the video only fires on primary scenes."
```

Expected: one commit modifying `ivgo-shared.js`.

---

## Task 4: End-to-end OBS verification

No code changes; this task confirms the feature works in the actual deployment target.

- [ ] **Step 1: Refresh scenes in OBS**

In OBS, open Tools → Scripts. Select the IVGO installer script. Click **Pull latest & refresh** (the new button added earlier in this session). Watch the Script Log for "[IVGO] Pulling latest…" and "[IVGO] Done — 6 scenes created / refreshed."

Expected: pull completes successfully (or "Already up to date" if already current); scene rebuild logs appear.

- [ ] **Step 2: Verify on Game scene via devtools**

In OBS, switch to **IVGO · 02 Game**. Right-click the **IVGO: Game Overlay** browser source → **Interact** → menu → **Inspect**. In the devtools console:

```js
IVGO.alrighty()
```

Expected:
- Video appears top-left in the OBS preview, just below the header bar (top:64, left:10).
- Plays with audio audible through the OBS audio mixer (the browser source's audio).
- Fades out cleanly on end.

- [ ] **Step 3: Verify on a second scene (Camera or Two-Cam)**

Switch to **IVGO · 03 Camera** and repeat the devtools `IVGO.alrighty()` test on **IVGO: Camera Overlay**.

Expected: same behaviour as Game scene — top-left, plays with audio, fades out.

- [ ] **Step 4: Verify auxiliary sources don't double-fire**

While on the Game scene, inspect the **IVGO: Cam Outline** browser source's devtools and run:

```js
IVGO.alrighty()
```

Expected: video plays in the Cam Outline source too — but this is fine because manually calling `IVGO.alrighty()` bypasses the bus gate. Now run:

```js
IVGO.bus.dispatch('channel.follow', {})
```

Expected: **Nothing happens** on the Cam Outline source (no video, no toast). The `?toasts=0` query param disables the bus connection itself, so dispatched events go nowhere on that source. (Trying it via direct `IVGO.alrighty()` is the only way to trigger it on auxiliary sources — and we wouldn't do that in production.)

- [ ] **Step 5: (Optional) Live Twitch verification**

If a Twitch test account or webhook tester is available, fire a real `channel.follow` event at the channel. Confirm the video plays in OBS exactly once. Otherwise skip.

- [ ] **Step 6: Mark feature complete**

No commit needed; the feature is live on `main` after Tasks 1–3. If everything in this task verified clean, the implementation is complete.

---

## Done criteria

- `media/alrighty-then.mp4` is committed and pulls cleanly on other machines.
- `IVGO.alrighty()` plays the video in a 480×270 chamfered box at top:64, left:10 on every primary scene HTML.
- `channel.follow`, `channel.subscribe`, `channel.subscription.gift` each trigger the video.
- `channel.cheer` does **not** trigger the video.
- N rapid triggers during one playback → exactly 2 total plays.
- Auxiliary browser sources (`?toasts=0`) do not fire the video on real bus events.
- Three commits land on `main`: asset, singleton, bus wiring.
