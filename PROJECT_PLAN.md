# IVGO Twitch Overlays — Project Plan (Phoenix edition)

A phased buildout from "static designs in OBS" to "production-ready overlay
system with live data, alerts, and remote control." This version assumes the
IVGO website is built in Elixir/Phoenix and the overlays will be served from
and integrated with that app.

Estimates are rough and assume evening/weekend chunks alongside Upwind and IVGO
ops. Total: 4–6 evenings end-to-end, plus deferred polish.

---

## What the Phoenix stack changes

The overlay HTML files don't change at all — they're still standalone React
pages that run in OBS browser sources. What changes is everything *behind*
them:

- **One deployment** — overlays serve from the Phoenix app at `/overlays/*`,
  not a separate static host
- **Phoenix Channels replaces a custom websocket layer** — every dynamic data
  source (Twitch events, now-playing, goal totals, control commands) becomes
  a `Phoenix.PubSub` topic that overlays subscribe to
- **LiveView replaces a hand-rolled control panel** — the admin page is
  ~1 day of work instead of 2
- **No StreamElements/Streamlabs dependency** — the same Twitch EventSub
  WebSocket integration that would be heavy in JS is light in Elixir, and
  you keep all the data
- **No separate sponsor JSON file** — sponsors live in the Ecto database the
  website already manages, and the overlay reads them through the same channel

The order of phases shifts too: with Phoenix infrastructure cheap to add,
we front-load the control panel (Phase 5) before the Twitch event stream
(Phase 4), so you can stream with manual control as early as day 3.

---

## Phase 0 — Get pixels into OBS (½ day)

Goal: confirm one scene renders pixel-perfect inside an OBS browser source on
your actual streaming machine, before any further work.

- Drop the `ivgo-overlays/` folder somewhere stable on disk
- Create a new OBS scene called **IVGO · Game**
- Add Browser Source → local file → `scenes/02-game.html`
- Width 1920, Height 1080
- Tick "Refresh browser when scene becomes active"
- Add a Game Capture source *underneath* the browser source
- Add a Video Capture source for your webcam, position it inside the cam cutout
- Confirm: rail visible, header visible, ticker scrolling, chat panel rendering,
  gameplay capture visible through the gameplay cutout, webcam visible through
  the cam cutout

**Done when:** you can hit "Start Streaming" and what you see locally is what's
on the stream.

**Common gotchas:**
- If the browser source shows a white background, right-click → Properties and
  add Custom CSS: `body{background:transparent}`
- If animations stutter, bump the browser source FPS to 60 to match a 60fps stream
- If fonts look wrong, the Google Fonts request might be blocked — let them
  cache after first load, or self-host them in Phoenix's `priv/static`

---

## Phase 1 — All six scenes wired into OBS (½ day)

Goal: every scene is a working OBS scene, switching between them is clean.

- Create six OBS scenes (Starting Soon, Game, Camera, BRB, Two Cam, Ending)
- Each gets its own browser source pointing at the matching `.html`
- For compositing scenes, position your Game/Video Capture sources to match
  the cutout coordinates in the README
- Set up scene-switching hotkeys (OBS Settings → Hotkeys → Switch to scene)
- Test the full transition flow: Starting Soon → Game → BRB → Game → Ending
- Watch for the entrance animations re-firing when you switch in

**Optional polish:**
- OBS scene transitions: Fade 200ms between Game/Camera/Two Cam, Cut for
  entering Starting Soon and BRB (which have their own entrance anim carrying
  the visual transition)

**Done when:** you can drive a full mock stream through all six scenes by
hotkey and it looks production-ready visually.

---

## Phase 2 — Serve overlays from Phoenix (½ day)

Goal: stop pointing OBS at local files; serve the overlays from the IVGO
Phoenix app so updates ship via `git push`.

There are two reasonable patterns. Pick one based on whether you want the
initial state server-rendered.

### Option A — Plain static assets (simplest)

Drop the overlay files into `priv/static/overlays/`:
```
priv/static/overlays/
├── ivgo-shared.js
└── scenes/
    ├── 01-starting-soon.html
    └── ...
```

Phoenix's `Plug.Static` already serves `priv/static/`. URL becomes
`https://ivgorchestra.com/overlays/scenes/02-game.html`.

Update OBS browser sources to point at the hosted URLs. Done.

### Option B — Phoenix-rendered scene templates (recommended)

Convert each scene HTML into a Phoenix controller action that renders an
EEx template. The template emits the same React app, but with a
seeded-state `<script>` block:

```elixir
# in your router
get "/overlays/scenes/:scene", OverlayController, :show

# in OverlayController
def show(conn, %{"scene" => scene}) do
  state = %{
    sponsors: Sponsors.list_active(),
    next_concert: Concerts.next(),
    countdown_target: get_session(conn, :countdown_target),
    socket_token: Phoenix.Token.sign(conn, "overlay socket", :overlay),
  }

  render(conn, "#{scene}.html", state: state)
end
```

The template inlines the state:
```html
<script>window.IVGO_STATE = <%= raw Jason.encode!(@state) %>;</script>
<script src="/overlays/ivgo-shared.js"></script>
<script>...the React app, reads window.IVGO_STATE on boot...</script>
```

**Why bother:** the overlay shows the right ticker copy, sponsor list, and
countdown target on first paint, with no websocket round-trip. OBS's
"Refresh browser when scene becomes active" picks up any changes
automatically without needing a separate update mechanism for slow-changing
data.

**Cost:** 2–3 hours. Worth doing.

### Why not LiveView for the scenes themselves?

Tempting but wrong. LiveView excels at server-rendered interactive UIs
with frequent diff updates. The overlays are mostly visual chrome with a
handful of dynamic data points. Rebuilding the design system (chamfered
chips, audio bars, animated rail) in HEEx components would be significant
work for limited payoff. The cleaner split: **React owns rendering,
Phoenix Channels owns data delivery.**

LiveView *is* the right call for the control panel — see Phase 5.

**Done when:** you can edit ticker copy in the Phoenix repo, push, and see
it on stream within ~60s of the next deploy.

---

## Phase 3 — Layer the chrome (1 day, optional)

Goal: split each monolithic scene into composable layers, so OBS scenes
share the chrome and switching is faster.

**Reconsider this phase given Phoenix.** With server-rendered seed state
from Phase 2, the cost of "monolithic per-scene" drops — each scene loads
instantly with correct data. The motivation for layer splits weakens.

I'd defer this and only do it if you feel the pain of duplicated chrome
across scenes during build, e.g. you want a 7th "Just Chatting" scene that
re-uses the rail/header/ticker without rebuilding them.

If you do split, the breakdown:
- `chrome.html` — rail + header + ticker
- `lower-third.html` — now-playing strip
- `chat.html` — chat panel
- `goal.html` — goal bar
- Per-scene content layers — only the unique stuff

In OBS, compose by toggling sources. Watch RAM — each browser source spawns
a CEF process.

**Done when:** you have a Just-Chatting scene that re-uses chrome without
duplicating React code.

---

## Phase 5 — Control panel as LiveView (1 day) ← moved earlier

Goal: a phone-friendly admin page where you direct the overlay live —
update now-playing, toggle panels, fire toasts, set countdowns.

**This phase moves before Phase 4** because LiveView makes it cheap, and
having manual control means you can stream live with the overlays before
Twitch events are wired.

### Build outline

```elixir
# router.ex
scope "/admin", IvgoWeb do
  pipe_through [:browser, :require_admin]
  live "/overlay-control", OverlayControlLive
end
```

```elixir
defmodule IvgoWeb.OverlayControlLive do
  use IvgoWeb, :live_view

  @overlay_topic "overlay:control"

  def mount(_params, _session, socket) do
    if connected?(socket), do: IvgoWeb.Endpoint.subscribe(@overlay_topic)
    {:ok, assign(socket, state: load_state())}
  end

  def handle_event("set_now_playing", %{"track" => t, "game" => g, "composer" => c}, socket) do
    state = update_state(:now_playing, %{track: t, game: g, composer: c})
    IvgoWeb.Endpoint.broadcast(@overlay_topic, "now_playing_updated", state.now_playing)
    {:noreply, assign(socket, state: state)}
  end

  def handle_event("toggle_chat", _, socket) do ... end
  def handle_event("trigger_toast", %{"username" => u}, socket) do ... end
  # etc
end
```

### Features for the control panel

- Now-playing form (game, track, composer, "set & broadcast")
- Toggle: show/hide chat panel
- Toggle: show/hide goal bar
- Toggle: show/hide lower-third (now-playing strip)
- Countdown target picker for Starting Soon
- "Trigger thank-you toast" with username input
- Manual ticker push: type a message, appears in next ticker rotation
- **Phoenix.Presence**: shows which overlay browser sources are currently
  connected ("Game: 1 connected, BRB: 0 connected") — confirms OBS has
  the overlay loaded before you go live

### Overlay-side wiring

Add a small `OverlaySocket` module to `ivgo-shared.js` that connects to
Phoenix Channel `overlay:control`, listens for events, dispatches to React:

```javascript
// In ivgo-shared.js — add an EventBus that wraps Phoenix.Socket
window.IVGO.bus = (function() {
  const socket = new Phoenix.Socket("/socket", { params: { token: window.IVGO_STATE.socket_token } });
  socket.connect();
  const channel = socket.channel("overlay:control", {});
  channel.join();

  const listeners = {};
  channel.onMessage = (event, payload) => {
    (listeners[event] || []).forEach(fn => fn(payload));
    return payload;
  };
  return {
    on: (event, fn) => { (listeners[event] = listeners[event] || []).push(fn); },
  };
})();
```

Each scene's React components subscribe via `window.IVGO.bus.on("now_playing_updated", ...)`.

**Done when:** between songs you can pull out your phone, type the next
track in the LiveView form, and it appears in the lower-third within
~500ms.

---

## Phase 4 — Twitch events via EventSub GenServer (1–2 days)

Goal: the overlays react to real follows, subs, cheers, and chat messages
instead of showing hardcoded data.

**With Phoenix in the stack, drop StreamElements as a recommendation** — the
glue cost is the same and you keep the data.

### Build outline

```elixir
defmodule Ivgo.Twitch.EventSub do
  use GenServer
  alias IvgoWeb.Endpoint

  # Holds the websocket connection to Twitch's EventSub endpoint,
  # handles OAuth refresh-token dance, reconnects on drops.

  def handle_info({:gun_ws, _, _, {:text, msg}}, state) do
    case Jason.decode!(msg) do
      %{"metadata" => %{"message_type" => "notification"}, "payload" => %{"event" => event, "subscription" => %{"type" => type}}} ->
        Endpoint.broadcast("overlay:events", type, event)
        # Also append to event log table for analytics
        Ivgo.Analytics.record_event(type, event)
      # ... session_welcome, session_keepalive, reconnect handling
    end
    {:noreply, state}
  end
end
```

Subscribe to: `channel.follow`, `channel.subscribe`,
`channel.subscription.gift`, `channel.cheer`, `channel.chat.message`.

### Overlay-side

Same EventBus pattern as Phase 5 — overlays already subscribe to Phoenix
Channels. Just add a second channel `overlay:events`:

- `channel.chat.message` → push to ChatPanel's message buffer
- `channel.follow` → spawn a follow toast (slides in bottom-left, dismisses
  after 5s, blue accent Chip)
- `channel.subscribe` / `channel.subscription.gift` → bigger badge animation,
  optional sound stinger via Web Audio API
- `channel.cheer` → fire goal-bar pulse + toast (Phase 7 hooks in here)

### What Phoenix gives you that StreamElements wouldn't

When you later decide a follow event should also: write to your supporters
DB, append to a Notion page, send a Discord notification, update the OST
2027 sponsor reach dashboard — those are all just additional GenServers
subscribing to `"overlay:events"`. Twelve lines each. With StreamElements
you'd run a separate webhook bridge.

### One-time OAuth cost

Half a day to wire up the Twitch user-token flow, save the refresh token,
handle expiry. After that it's invisible.

### Build order within this phase

1. Connect to EventSub, log raw events to console — confirm plumbing
2. Wire `channel.chat.message` to ChatPanel — most visible payoff
3. Add follow toast
4. Add sub stinger
5. Defer cheer → goal bar to Phase 7

**Done when:** a friend follows your channel and a toast appears on stream
within 2 seconds.

---

## Phase 6 — Track changes & motion polish (½–1 day)

Goal: the overlay feels alive, not just animated.

All client-side, unchanged from the original plan:

**Track-change transition.** When the now-playing changes (via the Phase 5
control panel), slide the old strip out and the new one in. Two strips in
the DOM, animate between them on `now_playing_updated` events. 400ms
cubic-bezier, brief blue-glow pulse on the new strip's border.

**Goal bar pulse.** When a tip lands, animate the bar fill width with a CSS
transition (already in the goal bar component). Add an overshoot glow
(`@keyframes goal-pulse`) triggered by toggling a class for 800ms after
the value updates.

**Idle ambience.** Slow drift on the background:
- 60-second loop translating blue wash gradients by ±10px
- 30-second infinite scroll on the grid (translate Y by -80px to match
  grid spacing)

Both subliminal — the eye barely registers them but the whole scene reads
as "alive" instead of "static."

**Optional: live audio reactivity.** Skip unless you specifically want it.
The decorative bars already read as "live." The robust path (tap OBS's
audio meter via obs-websocket, push RMS through Phoenix Channel) is
straightforward in this stack but the marginal payoff is small.

**Done when:** you watch your own VOD and notice the overlay never stops
moving.

---

## Phase 7 — Goal bar wiring (½ day)

Goal: the season fund / charity goal bar reflects real money raised.

```elixir
defmodule Ivgo.Tiltify.Poller do
  use GenServer
  alias IvgoWeb.Endpoint

  @poll_interval :timer.seconds(30)

  def init(_) do
    schedule_poll()
    {:ok, %{last_total: nil}}
  end

  def handle_info(:poll, state) do
    case Tiltify.Api.fetch_campaign_total(campaign_id()) do
      {:ok, total} when total != state.last_total ->
        Endpoint.broadcast("overlay:goal", "goal_updated", %{value: total, target: target()})
        schedule_poll()
        {:noreply, %{state | last_total: total}}
      _ ->
        schedule_poll()
        {:noreply, state}
    end
  end

  defp schedule_poll, do: Process.send_after(self(), :poll, @poll_interval)
end
```

Same GenServer pattern as EventSub. Cheer events from Phase 4 also broadcast
to `"overlay:goal"`. If/when you add Stripe or Ko-fi, those are webhook
controllers that broadcast to the same topic. Goal bar gets updates from
any source without knowing where they came from.

**Done when:** a £1 test tip lands and within 30 seconds the bar advances
and a toast fires.

---

## Phase 8 — Sponsor integration (½ day)

Goal: persistent sponsor logos / chips for OST London 2027 sponsors visible
across all scenes.

This becomes relevant once you start landing sponsor commitments (Materia
already; Laced as prospect; Devolver via partner; Larian, Bethesda, Sony,
Valve at higher tiers). Visible Twitch presence is a real contractual
asset for some sponsorship tiers.

### Implementation (much simpler with Phoenix)

Sponsors are content the IVGO website already needs to display. They live
in the Ecto database — schema, admin page to manage them. The overlay reads
them through the seeded state from Phase 2 (Option B):

```elixir
# In OverlayController.show/2
state = %{
  sponsors: Sponsors.list_active() |> Enum.map(&%{name: &1.name, logo_url: &1.logo_url, tier: &1.tier}),
  ...
}
```

The React `SponsorRail` component reads from `window.IVGO_STATE.sponsors`
on boot. Tier determines placement:
- Gold sponsors in the chrome, persistent across all scenes
- Silver sponsors in a rotating slot
- Bronze sponsors in the ticker copy

When sponsors change, OBS's "Refresh on active" picks up the new list on
next scene switch. No websocket needed for slow-changing data.

For real-time sponsor "thank you" moments (e.g. a sponsor watch party where
you want to highlight them mid-stream), the control panel from Phase 5 can
push a `sponsor_spotlight` event through the channel.

**Done when:** Materia logo is visible on every stream's overlay, and you
can manage the sponsor list from the existing IVGO admin without touching
the overlay code.

---

## Phase 9 — Stream Deck integration (optional, ½ day)

Goal: physical buttons for common overlay actions.

If you have an Elgato Stream Deck (or use the iOS/Android app), the Stream
Deck just hits HTTP endpoints. Those endpoints are now Phoenix controller
actions that broadcast to channels — same as the LiveView buttons.

Add:
```elixir
post "/admin/overlay/toggle/:panel", OverlayController, :toggle
post "/admin/overlay/toast", OverlayController, :trigger_toast
```

Both auth-gated by API key. Stream Deck plugin sends the requests; Phoenix
broadcasts the events; overlays react.

**Done when:** you can run an entire stream's overlay direction without
touching a keyboard.

---

## Phase 10 — Analytics & event log (deferred, ½ day)

Goal: post-stream analytics from the event stream.

Once Phase 4's `Ivgo.Analytics.record_event/2` is writing every Twitch
event to an Ecto table, you have a queryable record of stream activity.
Build out at leisure:

- Scene-level engagement: which scenes had the most follows/subs/tips?
- Time-of-day patterns
- OST London promotion effectiveness: count of mentions in chat correlated
  with tips or pre-registrations
- Top supporters across multiple streams (already in the Ending scene's
  hardcoded list — make it real)

Connects to your broader IVGO data picture (Notion, fundraising tracker)
once that exists.

**Done when:** you can answer "did the FFVII tribute stream drive more OST
pre-registrations than the Stardew stream?" with a query, not a guess.

---

## Estimated total: 4–6 evenings

Most of the value lands by end of Phase 5 — at that point you can stream
live with manual control of every dynamic element.

## What I'd do this week

If you have one Saturday afternoon, do **Phases 0 + 1** — get all six
scenes working in OBS. That alone is a complete usable overlay pack.

If you have a second session, do **Phase 2 (Option A — plain static)** to
serve from Phoenix at `ivgorchestra.com/overlays/`, then start **Phase 5**
(LiveView control panel). That gets you to "feels live and reactive" with
manual control even before Twitch events are wired.

Phase 4 (Twitch events) is the third session. After that, you have a
complete production-ready system; Phases 6–10 are quality-of-life upgrades
done at leisure.

## Maintenance burden

Once Phase 4 is done, the overlay system is near-zero-maintenance. You'll
update:
- Ticker copy (a couple of times per month, when concerts approach) — via
  control panel or DB seed
- Sponsor list (when you sign sponsors) — via existing admin UI
- Concert dates (rare) — via existing admin UI

The shared bundle (`ivgo-shared.js`) is stable design infrastructure — once
the tokens are dialled in, you almost never touch it.

## Cross-cutting concerns

**Auth.** The control panel and Stream Deck endpoints need protection.
Reuse whatever admin auth you've set up for IVGO admin pages. Don't build
a separate auth domain.

**Phoenix Channel reconnect.** OBS browser sources stay open for hours.
Phoenix's JS client handles reconnects but the React EventBus needs to
re-subscribe and recover state on reconnection. Plan for this — store last
known state in the EventBus, replay on reconnect, broadcast a
`request_state` event that the server responds to with current state.

**Streaming machine network.** Make sure the streaming machine's network
allows outbound websocket to wherever you host Phoenix. If you're behind
restrictive Wi-Fi, this can bite. Test before the first real stream.

**Phoenix tutorials assume different patterns.** Most "OBS browser source +
React + websocket" content online assumes Node/Express. The Phoenix
Channel protocol is its own thing — different message format, different
reconnect semantics. Plan for ~half a day extra in Phase 4 to absorb the
`Phoenix.Socket` JS client and translate examples.

---

## Net assessment vs the JS-stack version of this plan

The plan is shorter and the architecture is cleaner:
- One deployment, not two
- One auth domain, not three (Twitch OAuth + Cloudflare + own admin)
- One pub/sub system (Phoenix Channels), not a custom EventBus over ws
- One database for sponsors, supporters, event log — not KV stores scattered
  across services
- LiveView for the control panel instead of a hand-rolled phone-friendly form

Total work drops from 5–8 evenings to 4–6, and the resulting system is
materially more extensible. The biggest single win is Phase 4: not having
to choose between StreamElements (easy but limited) and Twitch EventSub
(powerful but lots of glue) — you get the EventSub ergonomics with less
glue than either option in JS-land.
