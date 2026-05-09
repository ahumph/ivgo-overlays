# Alrighty-Then Event Video — Design Spec

**Date:** 2026-05-09
**Status:** Approved for implementation
**Scope:** Single-file change to `ivgo-shared.js` plus one new asset.

## Goal

Play a short video clip (`alrighty-then.mp4`) with audio in the top-left of every IVGO overlay scene whenever a viewer follows, subscribes, or gifts a sub. If multiple events arrive while the video is playing, drain the queue with exactly one follow-up play.

## Non-goals

- Bits/cheer events do not trigger the video.
- No per-event customisation of the clip (single asset, fixed duration).
- No counter, badge, or text overlay on the video — toasts already convey the "who and what".
- No interactive controls (mute toggle, replay button, etc.).

## File layout

```
media/alrighty-then.mp4         ← new file, copied from ~/Downloads, committed
ivgo-shared.js                  ← extended with _alrighty singleton + bus wiring
```

The video is committed into the repo so the existing `git pull` flow on each
streaming machine picks it up alongside scene HTML/JS. Browser sources load it
as `../media/alrighty-then.mp4` (sibling-of-`scenes/` URL, identical pattern to
`../brand-assets/IVGO_w.png`).

## Architecture

A self-mounting IIFE named `_alrighty` lives in `ivgo-shared.js` next to the
existing `_toast` singleton. It exposes one public method, `trigger()`, and
holds all state in lexically-scoped locals.

This mirrors the `_toast` pattern exactly: zero changes to the six scene HTML
files, automatic mount on `DOMContentLoaded`, and reuse of the existing
`?toasts=0` query-param gate so auxiliary browser sources (cam-outline, chat)
never fire it.

## State machine

Three local variables: `playing` (bool), `pending` (bool), plus lazy refs to
the container `<div>` and `<video>`.

| Current state         | Event           | Transition                                                   |
|-----------------------|-----------------|--------------------------------------------------------------|
| idle                  | `trigger()`     | `playing=true`; fade container in; `video.play()`            |
| playing               | `trigger()`     | `pending=true`; return                                       |
| playing               | `video.ended`   | if `pending`: clear it, `currentTime=0`, `play()` (no fade)  |
| playing (no pending)  | `video.ended`   | `playing=false`; fade container out                          |
| any                   | `video.error`   | clear both flags; fade out; log warning                      |
| playing               | `play()` reject | clear both flags; fade out; log warning                      |

This produces the exact behaviour the user specified: N events arriving during
one playback → exactly 2 total plays (the initial trigger plus one drain).

## Visual

The container is `position: fixed` so it overlays the scene regardless of any
ancestor stacking context.

| Property      | Value                                                |
|---------------|------------------------------------------------------|
| `top`         | `64px` (54px `HeaderBar` + 10px gap)                 |
| `left`        | `10px`                                               |
| `width`       | `480px`                                              |
| `height`      | `270px` (16:9)                                       |
| `class`       | `ovl-chamfer-sm` (existing corner-clip from shared)  |
| `border`      | `1px solid T.rule2`                                  |
| `background`  | `#000`                                               |
| `box-shadow`  | `0 4px 24px rgba(0,0,0,.5)`                          |
| `pointer-events` | `none`                                            |
| `z-index`     | `9` (above `HeaderBar` at 5 and `Ticker` at 6, below toasts at 9999) |
| `opacity`     | `0` default; `1` while playing; CSS `transition: opacity 250ms ease` |

Inside the container, `<video src="../media/alrighty-then.mp4"
preload="auto" playsinline>` styled `width:100%; height:100%;
object-fit:cover; display:block`. Audio is unmuted (`muted` attribute
deliberately omitted).

## Bus wiring

Inside the existing `DOMContentLoaded` block in `ivgo-shared.js` (the one that
wires `_bus.on(...)` to `_toast.toast(...)`), add three lines:

```js
_bus.on('channel.follow',            () => _alrighty.trigger());
_bus.on('channel.subscribe',         () => _alrighty.trigger());
_bus.on('channel.subscription.gift', () => _alrighty.trigger());
```

`channel.cheer` is deliberately not wired.

The existing `?toasts=0` gate inside `_bus.connect()` returns early before the
socket connects, so any browser source loaded with that flag (cam-outline,
chat) receives no events and `_alrighty.trigger()` is never called there. No
new query param required.

## Public test hook

Extend the `window.IVGO` export with:

```js
window.IVGO.alrighty = _alrighty.trigger;
```

This lets a developer trigger the video manually from the OBS browser
source's devtools (`IVGO.alrighty()`) without firing a real Twitch event.

## Error handling & edge cases

- **Autoplay-with-audio rejection.** `videoEl.play()` returns a Promise. If it
  rejects (browser/CEF autoplay policy), the `.catch` clears `playing` and
  `pending`, fades the container out, and logs a warning. Container never
  gets stuck visible. OBS browser sources allow autoplay with audio by
  default, so this should never fire in production but is handled defensively.
- **Video file missing or codec issue.** `<video>` `error` event handler
  flushes both flags and hides the container. Other overlays continue to
  function.
- **Lazy element creation.** The `<div>` and `<video>` are created inside
  `trigger()` on first call, not on `DOMContentLoaded`. This avoids a wasted
  DOM/buffer on auxiliary sources that will never trigger. After first
  creation `preload="auto"` keeps the file buffered for fast subsequent plays.
- **Scene re-activation.** OBS browser sources have `restart_when_active=true`
  (already set in `ivgo_obs_setup.lua`), so switching away from and back to a
  scene reloads the page, which naturally resets state.
- **Multiple primary scenes mounting at once.** Browser sources are isolated
  iframes — each scene's `_alrighty` is its own state. Two scenes both
  receiving events simultaneously is not a real scenario in OBS (only the
  active scene is composited), and even if it happens visually, the fades
  overlap harmlessly.

## What this does NOT change

- The OBS Lua installer (`ivgo_obs_setup.lua`) — no scene/source changes
  required. The video plays inside the existing browser sources.
- The Phoenix server (`ivgorchestra.fly.dev`) — bus contract is unchanged.
- Toasts — they continue to fire from the same events in parallel with the
  video.
- The other primitives in `ivgo-shared.js` — no shared code is restructured.

## Testing strategy

1. **Manual via devtools hook:** Open the OBS browser source for the Game
   scene, enable the developer tools, run `IVGO.alrighty()` in the console.
   Confirm: container fades in top-left, video plays with audio, container
   fades out, no console errors. Run the call twice rapidly, confirm exactly
   2 total plays (one initial, one drain).
2. **Live trigger:** Use a Twitch test account (or chat-test tooling) to fire
   a follow event. Confirm video plays.
3. **Auxiliary-source check:** Confirm video does NOT play on the Game
   scene's chat or cam-outline browser sources (they'd appear duplicated if
   it did). The existing `?toasts=0` gate handles this.

## Risks

- **Autoplay-with-audio in CEF:** OBS-bundled CEF versions historically
  default to allowing autoplay with audio for browser sources, but this is
  the most likely production failure mode. The `.catch` mitigates the visual
  symptom (stuck-visible container). If it does fail in practice, fix is to
  add `muted=true` and accept a silent video, or play a separate `<audio>`
  unmuted alongside.
- **Repo size:** committing an .mp4 grows the repo. A short clip
  (~1-3 seconds, h264) should be well under 1 MB. If the file ends up larger
  than ~10 MB, revisit with git LFS.
