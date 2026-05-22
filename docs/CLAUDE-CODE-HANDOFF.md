# Claude Code handoff — Arranging scene interactivity

**Project:** `ahumph/ivgo-overlays` + `ahumph/ivgo-ex` (Phoenix app)
**Target scene:** `scenes/07-arranging.html`
**Goal:** make the arranging scene chat-driven. Twitch commands drive a shared task list under the cam, an on-demand info card, and a pomodoro timer. Mod-only for piece/from + pomo control; open to all viewers for tasks + info + status queries.

Builds on the architecture in `PROJECT_PLAN.md` (Phoenix Channels for transport, GenServer for state, EventSub for Twitch integration). Slot into the existing pattern — don't re-architect.

---

## What's already done (don't redo)

- `scenes/07-arranging.html` is rendered (chrome only). Accepts URL params for boot-time defaults.
- `ivgo-shared.js` exposes `WorkbenchStrip`, `SprintTimer`, `TaskBar`, `TICKER.arranging`.
- `ivgo-shared.js` exposes `window.IVGO.bus` (Phoenix Channels wrapper). Currently auto-joins `overlay:events` and dispatches Twitch events. Reuse — don't invent a new transport.

---

## Component changes (overlay repo)

### `WorkbenchStrip` — becomes ephemeral, shrinks to two cells

Currently a persistent lower-third with five cells (PIECE / FROM / SECTION / BARS / TOOL).

New behaviour:
- Two cells only: **PIECE** and **FROM**. Drop SECTION / BARS / TOOL entirely (state model + URL params + installer fields).
- Hidden by default. Shown for **10 seconds** when an `info_shown` event arrives on `overlay:arranging`, then animates out.
- Entrance: reuse `ovl-toast-in` (250ms cubic-bezier). Exit: mirror the toast dismiss (fade + collapse, 300ms).
- Position unchanged — same lower-third slot. With `TaskBar` gone, can drop to `bottom: 36 + 24`.
- PIECE gets visual weight (display type, ~32–40px). FROM sits as mono caption.

### `TaskList` — new component, replaces `TaskBar`

Sits under the cam. Cam is at `24, 72, 282×158`, so the list anchors around `left:24, top:240, width:282`.

```
TASKS
┌─────────────────────────────┐
│ [ ]  aghumphreys  voicing… │
│ [✓]  viewer_42    scales   │  ← green fill + white check
│ [ ]  mod_kim      brew tea │
│ [ ]  aghumphreys  bars 48… │  ← same user, multiple ok
└─────────────────────────────┘
```

- Checkbox: `12×12`, 1px `T.rule2` border, transparent fill when open.
- On done: fill `#22c55e`, render white ✓ SVG inside (200ms ease swap). First green in the system — add `T.done = '#22c55e'`.
- Don't strikethrough text; the tick is enough signal.
- Sort: open tasks first (oldest → newest), then done tasks (newest done → oldest).
- Visible cap: 6 rows at ~22px each.
- Eviction: new task that would exceed cap drops the **oldest done task**. If no done tasks exist, drop the oldest open task (rare; only happens if everyone's hyperactive).
- Done tasks stay visible as social proof until shouldered out.
- Empty state: faint placeholder `DROP A TASK · !task <thing>`.
- Username swatch uses existing `_chatColor(user_name)` helper.

### `SprintTimer` — minor change, renamed semantics

Internally still works the same; externally referred to as the **pomo timer**.

- Accept `startedAt` (ISO-8601). If present, remaining = `durationMs - (Date.now() - new Date(startedAt))`. Accurate across reconnects.
- New `:idle` phase: chip greys out, `:` blink stops, timer shows full configured `focus_ms` in `T.ink3`.
- `BREAK` chip stays amber (existing behaviour).

### Scene wiring (`scenes/07-arranging.html`)

```js
const channel = window.IVGO.bus.joinChannel('overlay:arranging');

channel.on('state',            s => setState(s));                           // on join
channel.on('workbench_updated', p => setState(prev => ({...prev, ...p})));
channel.on('tasks_updated',    ({tasks}) => setState(prev => ({...prev, tasks})));
channel.on('pomo_updated',     ({pomo})  => setState(prev => ({...prev, pomo})));
channel.on('info_shown',       () => { setInfoVisible(true); setTimeout(() => setInfoVisible(false), 10000); });
```

Render tree:
- `<HeaderBar/>`
- `<TaskList tasks={state.tasks}/>` — under cam slot
- `<SprintTimer {...state.pomo}/>` — top-right
- `{infoVisible && <WorkbenchStrip piece={state.piece} from={state.collection}/>}` — lower-third, on demand
- `<Ticker items={TICKER.arranging}/>`

Drop `<TaskBar/>` entirely.

### Bus addition (`ivgo-shared.js`)

`window.IVGO.bus.joinChannel(topic)` — returns `{on(event, fn)}` so scenes can subscribe to additional topics without tangling the EventBus internals. Keep the existing `.on()` for `overlay:events` listeners working.

---

## Server-side (`ahumph/ivgo-ex`)

### `Ivgo.Arranging.Session` (GenServer, singleton)

```elixir
%Session{
  piece:      "AERITH'S SUITE",
  collection: "FINAL FANTASY VII REBIRTH",
  tasks: [                       # ordered list; sort + cap in client
    %Task{id, user_login, user_name, text, added_at, done_at}
  ],
  pomo: %{
    phase:      :idle,           # :idle | :focus | :break
    focus_ms:   25 * 60_000,
    break_ms:   5  * 60_000,
    started_at: nil,             # nil = paused/idle
    sprint:     1,
    total:      4
  }
}
```

Public API:
- `get/0`
- `set_piece/1`, `set_collection/1` — broadcast `workbench_updated`, then `show_info/0`
- `show_info/0` — broadcast `info_shown` (no payload)
- `add_task/3 (login, name, text)` — append; broadcast `tasks_updated`. Cap text at 80 chars. No per-user cap (users can have multiple open tasks).
- `mark_done/1 (login)` — mark caller's **oldest open** task done. Broadcast.
- `pomo_set_focus_mins/1`, `pomo_set_break_mins/1` — update config. Broadcast `pomo_updated`.
- `pomo_start/0` — `started_at = now`, phase → `:focus` if `:idle`. Broadcast.
- `pomo_stop/0` — `started_at = nil`. Hard pause (resets countdown on next start; no resume). Broadcast.
- `pomo_reset/0` — same phase, fresh `started_at = now`. Broadcast.

Persist to ETS (or `:dets` for crash survival) on every write. On `init/1`, hydrate from snapshot so a Phoenix restart mid-stream doesn't blank the overlay.

### Channel topic `overlay:arranging`

On join, push current state so reconnects re-sync:
```elixir
def join("overlay:arranging", _, socket) do
  {:ok, %{state: Session.get()}, socket}
end
```

Events broadcast:
- `workbench_updated` — `%{piece?, collection?}`
- `tasks_updated` — `%{tasks: [...]}` (full list — cheap)
- `pomo_updated` — `%{pomo: %{...}}` (full struct)
- `info_shown` — no payload

### `Ivgo.Twitch.Commands.Arranging` (chat command handler)

Receives `channel.chat.message` events from the existing EventSub GenServer. Plain regex dispatch. Pulls `is_moderator` + `broadcaster` badge from the event for auth.

Per-user cooldowns stored in ETS keyed by `{user_login, command}`.

---

## Command reference

All commands case-insensitive. Single space separator. Text args may contain spaces and run to end of line. Rejected commands (wrong perms / on cooldown / bad args) drop silently — no error replies.

### Anyone — viewer engagement

| Command | Effect | Cooldown |
|---|---|---|
| `!task <text>` | Append a task for the calling user. Text capped at 80 chars. | 10s / user |
| `!done` | Mark caller's oldest open task done (green tick). | 10s / user |
| `!info` | Show the WorkbenchStrip for 10s. | 30s global |
| `!pomo` (no args) | Bot replies with phase + time remaining + sprint x/y. | 30s / user |
| `!progress` | Bot replies with piece, from, and open task count. | 60s / user |
| `!help` | Bot replies with a one-line command summary. | 60s / user |

### Mod / broadcaster only — state changes

| Command | Effect |
|---|---|
| `!piece <text>` | Update PIECE. Also auto-triggers `!info` (overlay surfaces immediately). |
| `!from <text>` | Update FROM (collection / game). Also auto-triggers `!info`. |
| `!pomo focus <mins>` | Set focus length (1–90). |
| `!pomo break <mins>` | Set break length (1–60). |
| `!pomo start` | Start the timer. If `:idle`, enters `:focus`. |
| `!pomo stop` | Stop / pause the timer (resets countdown on next start). |
| `!pomo reset` | Restart the current phase's countdown. |
| `!pomo next` | Flip phase focus↔break, reset, increment sprint when leaving break. |
| `!task clear` | Wipe all tasks (mod escape hatch for spam). |
| `!task del <id>` | Remove a specific task by id (id shown in mod-only LiveView; not commonly used in chat). |

### Bot replies — format

Replies are sent via the existing Twitch chat send API. One line, no emoji unless the channel already uses them. Examples:

```
!pomo  →  FOCUS · 14:23 left · sprint 2/4
!pomo  →  (when idle)  pomo idle · focus 25m / break 5m
!progress  →  Aerith's Suite · FFVII Rebirth · 3 open tasks
!help  →  commands: !task <thing>  !done  !info  !pomo  !progress
```

Keep the bot terse — it shouldn't fight chat for attention. If the bot is rate-limited by Twitch, drop the reply silently rather than queueing.

---

## Acceptance criteria

Reviewer can do all of this in sequence:

1. Start Phoenix. Open `07-arranging.html`. Scene renders with default state from `Session.get/0`. `WorkbenchStrip` is **not** visible. Task list shows empty placeholder. Timer shows `:idle`.
2. Send `!task voicing horns` from viewer A. Row appears in `TaskList` with empty checkbox, viewer A's username + colour.
3. Send `!task brew tea` and `!task scales` from viewer A. Both append — viewer A has three open tasks visible.
4. Send `!task practice` from viewer B. Appears below viewer A's three.
5. Viewer A sends `!done`. **Oldest** of A's tasks (`voicing horns`) gets a green tick. Stays in list.
6. Send `!info` from any viewer. `WorkbenchStrip` animates in showing default piece/from, sits 10s, animates out.
7. Send `!info` again immediately — nothing happens (30s global cooldown).
8. From broadcaster, send `!piece WIND WAKER OVERTURE`. Strip animates in showing the new piece, sits 10s. (Auto-`!info` behaviour.)
9. From non-mod, send `!piece NOPE`. Nothing changes.
10. Send `!pomo focus 30`, then `!pomo start`. Timer enters `:focus` phase, counts down from 30:00.
11. Send `!pomo` from any viewer. Bot replies `FOCUS · 29:53 left · sprint 1/4` (or close).
12. Send `!pomo stop`. Timer freezes, chip goes grey-idle.
13. Restart Phoenix. Reload overlay. Tasks, piece, from, and pomo config all persist. Timer remains stopped.
14. Fill the task list to 6 rows, mostly done. Send a fresh `!task` from anyone — oldest **done** task drops off; new task appears at the bottom of the open section.

---

## Out of scope — do not build

- Audio reactivity.
- Auto-advance on timer zero (explicit `!pomo start/stop/reset/next` only).
- Per-stream analytics / completed-task history (Phase 10 event log layer).
- New design tokens beyond `T.done = '#22c55e'`.
- A second pomo timer in any other scene.

---

## Stretch (only if time)

1. **"Vibe" dot** — aggregate `!focused` / `!distracted` reactions over a rolling 60s window. Decorative corner indicator. No state effect.
2. **Sound stinger on phase boundary** — WebAudio chime. Off by default; `!pomo sound on` toggles.
3. **Per-user task colour reuse** — if same user appears in list multiple times, render their swatch slightly dimmer on repeat rows so the eye groups them.

---

## Files you'll likely touch

```
# ahumph/ivgo-ex
lib/ivgo/arranging/session.ex                 # NEW — GenServer
lib/ivgo/arranging/persistence.ex             # NEW — ETS/dets snapshot
lib/ivgo/twitch/commands/arranging.ex         # NEW — regex parser + auth + cooldowns
lib/ivgo/twitch/bot.ex                        # ADD reply helpers (or extend existing chat sender)
lib/ivgo_web/channels/overlay_channel.ex      # ADD overlay:arranging topic
lib/ivgo/application.ex                       # supervise Session + Persistence
test/ivgo/arranging/session_test.exs          # NEW
test/ivgo/twitch/commands/arranging_test.exs  # NEW — parser + auth + cooldown matrix
# optional:
lib/ivgo_web/live/control_panel_live.ex       # ADD Arranging tab if Phase 5 LiveView exists

# ahumph/ivgo-overlays
ivgo-shared.js                                # add bus.joinChannel(topic); add TaskList; rework WorkbenchStrip (2 cells, ephemeral-friendly); add T.done; SprintTimer startedAt + :idle
scenes/07-arranging.html                      # channel subscription + state container; drop TaskBar; gate WorkbenchStrip on infoVisible
docs/installer-additions.lua                  # drop arr_section/arr_bars/arr_tool/arr_task fields; add arr_break_mins; rename arr_sprint_mins → arr_focus_mins
docs/README-arranging-section.md              # update params table
```

Keep the chat-command parser test-driven — table-style tests for `{input, badges, user, cooldown_state} → expected_effect` lock the matrix down cheaply.

---

## Notes from the design pass

- The arranging scene is intentionally calmer than the game scene. Resist flashy state-change animations. Toast slide (250ms) and goal-bar transition (800ms) are the upper bound on motion.
- `T.done` (`#22c55e`) is the only new colour. The BREAK amber + this green are the only state-driven colour shifts in the scene; don't add more without checking back.
- Bot replies share a Twitch IRC connection with EventSub; rate-limit awareness lives in `Ivgo.Twitch.Bot`. Don't reinvent.
- The `info_shown` mechanism is deliberately fire-and-forget. The scene owns the 10s timer locally — server doesn't track visibility state. Keeps reconnect logic trivial.

When you're done: one-paragraph summary in chat + a screenshot of `!task`, `!done`, and `!info` landing live, and we ship.
