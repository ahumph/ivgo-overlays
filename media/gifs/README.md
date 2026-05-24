# Arranging-scene GIFs

The 07 Arranging scene's info panel (`!info` reveal) shows a GIF in the
right half of the chamfered strip when one matches the currently-active
piece. The lookup is convention-based — no JSON, no config, no code edits:

```
media/gifs/<collection-slug>__<piece-slug>.gif
```

Both `collection` and `piece` are slugified:

- lowercased
- apostrophes stripped (`AERITH'S` → `aeriths`)
- any other non-alphanumeric run collapsed to a single `-`
- leading/trailing `-` trimmed

The two slugs are joined with **a double-underscore**.

## Examples

| collection                       | piece                  | filename                                                  |
|----------------------------------|------------------------|-----------------------------------------------------------|
| `FINAL FANTASY VII REBIRTH`      | `AERITH'S SUITE`       | `final-fantasy-vii-rebirth__aeriths-suite.gif`            |
| `THE LEGEND OF ZELDA: WIND WAKER`| `DRAGON ROOST ISLAND`  | `the-legend-of-zelda-wind-waker__dragon-roost-island.gif` |
| `FINAL FANTASY XVI`              | `FIND THE FLAME`       | `final-fantasy-xvi__find-the-flame.gif`                   |

## Behaviour

- If the file exists, it auto-loads on the next `!piece` change.
- If the file doesn't exist, the panel renders without a gif (no error, no
  broken-image flash) — verified via an `Image()` preload before the
  panel updates its `gif` state.
- A `!gif <url>` chat command (server-side, when wired) can still
  override the convention. The override persists until the next
  `!piece` change, which re-runs the convention lookup.

## Tips

- Keep GIFs under ~2 MB if possible — bigger ones pop in late on OBS
  scene switch since browser sources don't preload aggressively.
- For long action loops, prefer a **WebM** or **MP4** in the same path
  (just change the extension in `scenes/07-arranging.html` if you want
  to support video here too — currently it's `.gif` only).
- Animations look best in the 480×270 → 720×405 range; the panel
  renders them at 62.5% width with a left-edge fade mask.
