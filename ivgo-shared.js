// ivgo-shared.js — IVGO Twitch overlay primitives (CHANNEL theme)
// Loaded by every scene HTML. Exposes window.IVGO with tokens + components.

// ── Ticker copy ───────────────────────────────────────────────────────────
// Edit here. All scenes pull from this object.

// Upcoming concerts — edit this list to update all scenes at once.
const EVENTS = [
  'START QUEST · MAC BELFAST · 06.06.2026',
  'PRESS PLAY · MAC BELFAST · 06.06.2026',
  'THE ADVENTURE CONTINUES · HELIX DUBLIN · 01.08.2026',
];

const SOCIAL = [
  'IVGORCHESTRA.COM',
  'REGISTERED CHARITY · BELFAST',
  'INSTAGRAM · @ivgorchestra',
  'BLUESKY · @ivgorchestra.com',
  'YOUTUBE · @IrishVideoGameOrchestra',
  'TIKTOK · @ivgorchestra',
];

const TICKER = {
  startingSoon: [...EVENTS, ...SOCIAL],
  game:         [...EVENTS, ...SOCIAL],
  camera:       [...EVENTS, ...SOCIAL],
  brb:          [...EVENTS, 'BACK IN A MOMENT', ...SOCIAL],
  twoCam:       [...EVENTS, 'QUESTIONS WELCOME IN CHAT', ...SOCIAL],
  ending:       [...EVENTS, 'THANKS FOR WATCHING', ...SOCIAL],
  arranging:    [...EVENTS, 'WORK ALONG WITH !TASK <TASK> IN CHAT', '!DONE TO TICK OFF A TASK', '!INFO FOR THE CURRENT PIECE', '!POMO TO SEE THE TIMER', ...SOCIAL],
};

const T = {
  bg:        '#111114',
  bg2:       '#1a1a1e',
  bg3:       '#222228',
  ink:       '#ffffff',
  ink2:      'rgba(255,255,255,0.70)',
  ink3:      'rgba(255,255,255,0.33)',
  rule:      'rgba(255,255,255,0.07)',
  rule2:     'rgba(255,255,255,0.16)',
  live:      '#ff5a3c',
  amber:     '#f5a524',
  done:      '#22c55e',
  accent:     '#289ae6',
  accentDeep: '#1a6fb0',
  accentGlow: 'rgba(40,154,230,0.55)',
  accentWash: 'rgba(40,154,230,0.08)',
  brand:      '#289ae6',
  mono:      'ui-monospace, "JetBrains Mono", "IBM Plex Mono", Menlo, Consolas, monospace',
  sans:      '"Inter", "Helvetica Neue", Helvetica, Arial, sans-serif',
  display:   '"Archivo", "Helvetica Neue", Helvetica, Arial, sans-serif',
};

// ── EventBus ──────────────────────────────────────────────────────────────
// Connects to Phoenix Channel overlay:events and dispatches Twitch events.
// Usage: window.IVGO.bus.on("channel.follow", ({user_name}) => ...)
// Requires ?socket_url=wss://... param or defaults to same host /overlay path.
// No-ops gracefully when Phoenix is not available.

const _bus = (function () {
  const listeners = {};
  let _channel = null;
  let _socket = null;
  const _extraChannels = {};   // topic → { channel, listeners: {event: [fn]} }
  const _pendingJoins = [];    // joinChannel() calls made before socket connect

  function on(event, fn) {
    listeners[event] = listeners[event] || [];
    listeners[event].push(fn);
  }

  function dispatch(event, payload) {
    (listeners[event] || []).forEach(fn => {
      try { fn(payload); } catch (e) { console.error('[IVGO bus]', e); }
    });
  }

  // Lazy-join an additional Phoenix Channel topic. Returns an object exposing
  //   .on(event, fn)  — register listener for a server-pushed event
  // The same handle is returned for repeat calls to the same topic so multiple
  // listeners can be attached.
  function joinChannel(topic) {
    if (_extraChannels[topic]) return _extraChannels[topic].handle;

    const entry = { channel: null, listeners: {} };
    const handle = {
      on(event, fn) {
        entry.listeners[event] = entry.listeners[event] || [];
        entry.listeners[event].push(fn);
        if (entry.channel) entry.channel.on(event, fn);
        return handle;
      }
    };
    entry.handle = handle;
    _extraChannels[topic] = entry;

    if (_socket) {
      _wireExtraChannel(topic, entry);
    } else {
      _pendingJoins.push(topic);
    }
    return handle;
  }

  function _wireExtraChannel(topic, entry) {
    try {
      entry.channel = _socket.channel(topic, {});
      Object.keys(entry.listeners).forEach(event => {
        entry.listeners[event].forEach(fn => entry.channel.on(event, fn));
      });
      entry.channel.join()
        .receive('ok', resp => {
          console.log('[IVGO bus] joined ' + topic);
          // Surface initial state push via a synthetic 'state' event.
          if (resp && resp.state) (entry.listeners['state'] || []).forEach(fn => {
            try { fn(resp.state); } catch (e) { console.error('[IVGO bus]', e); }
          });
        })
        .receive('error', e => console.warn('[IVGO bus] join error on ' + topic, e));
    } catch (e) {
      console.warn('[IVGO bus] joinChannel failed for ' + topic, e);
    }
  }

  function connect() {
    if (typeof Phoenix === 'undefined') return;

    const params = new URLSearchParams(location.search);
    if (params.get('toasts') === '0') return;
    // Fallback chain: explicit ?socket_url= wins; otherwise build from
    // location if the page has a real host (served from a dev server or
    // OBS via http URL); otherwise default to the production Fly URL so
    // testing the scene HTML directly from disk (file://, location.host
    // is empty) doesn't construct the bogus "ws:///overlay" URL.
    const socketUrl = params.get('socket_url')
      || (location.host
            ? (location.protocol === 'https:' ? 'wss://' : 'ws://') + location.host + '/overlay'
            : 'wss://ivgorchestra.fly.dev/overlay');

    try {
      _socket = new Phoenix.Socket(socketUrl, {});
      _socket.connect();

      _channel = _socket.channel('overlay:events', {});
      ['channel.follow', 'channel.subscribe', 'channel.subscription.gift', 'channel.cheer', 'channel.raid'].forEach(type => {
        _channel.on(type, payload => dispatch(type, payload));
      });
      _channel.join()
        .receive('ok', () => console.log('[IVGO bus] joined overlay:events'))
        .receive('error', e => console.warn('[IVGO bus] join error', e));

      _socket.onError(() => console.warn('[IVGO bus] socket error'));

      // Flush any joinChannel() calls that landed before connect.
      _pendingJoins.splice(0).forEach(topic => _wireExtraChannel(topic, _extraChannels[topic]));
    } catch (e) {
      console.warn('[IVGO bus] connect failed', e);
    }
  }

  if (typeof document !== 'undefined') {
    document.addEventListener('DOMContentLoaded', connect);
  }

  return { on, dispatch, joinChannel };
})();

// ── ToastQueue ────────────────────────────────────────────────────────────
// Bottom-left toast notifications. Max 3 visible, FIFO queue, 5s auto-dismiss.
// Mounts a container div into document.body on first use.
// Usage: window.IVGO.toast({ type: 'follow'|'sub'|'gift'|'cheer', ... })

const _toast = (function () {
  let container = null;
  const queue = [];
  let visible = 0;
  let _timer = null;
  let _lastShowTime = 0;
  const MAX_VISIBLE = 3;
  const DISMISS_MS = 5000;
  const STAGGER_MS = 2000;

  function getContainer() {
    if (container) return container;
    container = document.createElement('div');
    // Anchor configurable via URL param so scenes with a right-column chat
    // (e.g. 07 Arranging) can route toasts above the chat instead of into
    // the bottom-left where toasts overlap event-feed activity.
    //   default          → bottom:46px, left:10px
    //   above-chat-right → bottom:550px (10px above the chat's top edge at y=540), right:10px
    const anchor = new URLSearchParams(location.search).get('toasts_anchor') || 'bl';
    let anchorCss;
    if (anchor === 'above-chat-right') {
      anchorCss = 'bottom:550px;right:10px;align-items:flex-end';
    } else {
      anchorCss = 'bottom:46px;left:10px';
    }
    container.style.cssText = 'position:fixed;' + anchorCss + ';display:flex;flex-direction:column-reverse;gap:8px;z-index:9999;pointer-events:none';
    document.body.appendChild(container);
    return container;
  }

  // One timer running at a time. Wait enforces STAGGER_MS since last show,
  // regardless of whether items were pre-queued or arrived one by one.
  function scheduleNext() {
    if (_timer !== null) return;
    if (queue.length === 0) return;
    const elapsed = Date.now() - _lastShowTime;
    const wait = _lastShowTime === 0 ? 0 : Math.max(0, STAGGER_MS - elapsed);
    _timer = setTimeout(function () {
      _timer = null;
      if (queue.length === 0) return;
      if (visible >= MAX_VISIBLE) evictOldest();
      show(queue.shift());
      scheduleNext();
    }, wait);
  }

  // Remove the oldest (topmost) toast immediately to make room for a new one.
  function evictOldest() {
    const c = getContainer();
    const oldest = c.lastChild; // lastChild = oldest in DOM = visually topmost in column-reverse
    if (!oldest) return;
    if (oldest._dismissTimer) clearTimeout(oldest._dismissTimer);
    oldest.remove();
    visible--;
  }

  // Animate a toast out, decrement visible, and drain queue.
  function dismissEl(el) {
    if (!el.parentNode) return; // already evicted
    const h = el.offsetHeight;
    el.style.transition = 'opacity 300ms, max-height 300ms ease-in, padding 300ms ease-in';
    el.style.maxHeight = h + 'px';
    requestAnimationFrame(function () {
      el.style.opacity = '0';
      el.style.maxHeight = '0';
      el.style.paddingTop = '0';
      el.style.paddingBottom = '0';
    });
    setTimeout(function () {
      if (!el.parentNode) return;
      el.remove();
      visible--;
      scheduleNext();
    }, 300);
  }

  function show(item) {
    _lastShowTime = Date.now();
    visible++;
    const el = document.createElement('div');
    el.className = 'ovl-chamfer-sm ovl-toast-enter';
    el.style.cssText = [
      'background:rgba(17,17,20,.92)',
      'border:1px solid ' + (item.accent || T.rule2),
      'padding:12px 16px',
      'font-family:' + T.mono,
      'font-size:11px',
      'letter-spacing:.16em',
      'color:' + T.ink,
      'min-width:220px',
      'max-width:320px',
      'pointer-events:none',
      'box-shadow:0 4px 24px rgba(0,0,0,.5)',
      'overflow:hidden',
      'max-height:200px',
    ].join(';');

    const labelEl = document.createElement('div');
    labelEl.style.cssText = 'color:' + (item.accent || T.accent) + ';font-size:9px;letter-spacing:.32em;margin-bottom:4px';
    labelEl.textContent = item.label;

    const line1El = document.createElement('div');
    line1El.style.cssText = 'color:' + T.ink;
    line1El.textContent = item.line1;

    el.appendChild(labelEl);
    el.appendChild(line1El);

    if (item.line2) {
      const line2El = document.createElement('div');
      line2El.style.cssText = 'color:' + T.ink3 + ';font-size:10px;margin-top:2px';
      line2El.textContent = item.line2;
      el.appendChild(line2El);
    }

    // Prepend so newest sits at bottom; older ones pushed upward by column-reverse
    const c = getContainer();
    c.insertBefore(el, c.firstChild);

    el._dismissTimer = setTimeout(function () { dismissEl(el); }, DISMISS_MS);
  }

  function push(item) {
    queue.push(item);
    scheduleNext();
  }

  function toast(opts) {
    const map = {
      follow: {
        label: 'NEW FOLLOWER',
        line1: opts.user_name || opts.user_login || 'Someone',
        line2: 'followed the channel',
        accent: T.accent,
      },
      sub: {
        label: 'NEW SUBSCRIBER' + (opts.tier ? ' \u00b7 ' + opts.tier : ''),
        line1: opts.user_name || opts.user_login || 'Someone',
        line2: opts.is_gift ? 'gifted sub' : null,
        accent: '#a855f7',
      },
      gift: {
        label: 'GIFT SUBS',
        line1: (opts.user_name || 'Someone') + ' gifted ' + (opts.total || 1) + ' sub' + ((opts.total || 1) > 1 ? 's' : ''),
        line2: opts.tier || null,
        accent: '#a855f7',
      },
      cheer: {
        label: 'BITS',
        line1: (opts.user_name || 'Anonymous') + ' cheered ' + (opts.bits || '?') + ' bits',
        line2: opts.message ? opts.message.slice(0, 60) : null,
        accent: T.amber,
      },
      raid: {
        label: 'RAID',
        line1: (opts.user_name || 'Someone') + ' raided with ' + (opts.viewers || 0),
        line2: null,
        accent: T.amber,
      },
    };

    const item = map[opts.type];
    if (item) push(item);
  }

  return { toast };
})();

// ── VideoEgg ──────────────────────────────────────────────────────────────
// Plays a short video clip when a follow/sub/gift (alrighty) or raid arrives.
// Priority queue: raid interrupts alrighty (interrupted alrighty resumes after
// the raid ends, drained via pendingNormal). Same-priority triggers queue
// with last-wins semantics so we never play the same clip twice back-to-back.
//
// Per-scene placement is configurable via URL params, since scenes differ in
// where they want the clip to land:
//   egg_top    (default 64)     px from viewport top
//   egg_left   (default 10)     px from viewport left
//   egg_h      (default null)   if set, locks height and scales width by the
//                                clip's natural aspect; otherwise uses the
//                                clip's natural w/h.
//   egg_off    (default false)  set to "1" to disable on this scene entirely.
const _videoEgg = (function () {
  const CLIPS = {
    alrighty: { src: '../media/alrighty-then.mp4', w: 480, h: 270, border: T.rule2, priority: 1 },
    raid:     { src: '../media/raid.mp4',          w: 480, h: 480, border: T.amber, priority: 2 },
  };

  const params = typeof location !== 'undefined' ? new URLSearchParams(location.search) : null;
  const DISABLED = params && params.get('egg_off') === '1';
  const EGG_TOP  = params && params.get('egg_top')  != null ? parseInt(params.get('egg_top'),  10) : 64;
  const EGG_LEFT = params && params.get('egg_left') != null ? parseInt(params.get('egg_left'), 10) : 10;
  const EGG_H    = params && params.get('egg_h')    != null ? parseInt(params.get('egg_h'),    10) : null;

  let containerEl = null;
  let videoEl = null;
  let current = null;
  let pendingHigh = false;
  let pendingNormal = false;
  let lastSrc = null;
  // playGen guards against a stale .catch() from an interrupted play()
  // resetting state after a new clip has already started.
  let playGen = 0;

  function ensureMounted() {
    if (containerEl) return;
    containerEl = document.createElement('div');
    containerEl.className = 'ovl-chamfer-sm';
    // z-index:9 sits above HeaderBar (5) and Ticker (6) but below toasts
    // (9999) so a toast popping during a clip overlays cleanly.
    containerEl.style.cssText = [
      'position:fixed',
      'top:' + EGG_TOP + 'px',
      'left:' + EGG_LEFT + 'px',
      'opacity:0',
      'pointer-events:none',
      'transition:opacity 250ms ease',
      'z-index:9',
      'background:#000',
      'overflow:hidden',
      'box-shadow:0 4px 24px rgba(0,0,0,.5)',
    ].join(';');

    videoEl = document.createElement('video');
    videoEl.preload = 'auto';
    videoEl.playsInline = true;
    videoEl.style.cssText = 'width:100%;height:100%;object-fit:cover;display:block';
    videoEl.addEventListener('ended', onEnded);
    videoEl.addEventListener('error', onError);

    containerEl.appendChild(videoEl);
    document.body.appendChild(containerEl);
  }

  function applyClip(clip) {
    const h = EGG_H != null ? EGG_H : clip.h;
    const w = EGG_H != null ? Math.round(EGG_H * clip.w / clip.h) : clip.w;
    containerEl.style.width  = w + 'px';
    containerEl.style.height = h + 'px';
    containerEl.style.border = '1px solid ' + clip.border;
    if (lastSrc !== clip.src) {
      videoEl.src = clip.src;
      lastSrc = clip.src;
    }
  }

  function hide() {
    if (containerEl) containerEl.style.opacity = '0';
  }

  function reset() {
    current = null;
    pendingHigh = false;
    pendingNormal = false;
    hide();
  }

  function play(clipName) {
    const clip = CLIPS[clipName];
    if (!clip) return;
    ensureMounted();
    current = clipName;
    applyClip(clip);
    containerEl.style.opacity = '1';

    const myGen = ++playGen;
    videoEl.currentTime = 0;
    videoEl.play().catch(err => {
      if (myGen !== playGen) return;   // stale: a newer play() superseded us
      console.warn('[IVGO videoEgg] play() rejected:', err);
      reset();
    });
  }

  function onEnded() {
    if (pendingHigh)   { pendingHigh   = false; play('raid');     return; }
    if (pendingNormal) { pendingNormal = false; play('alrighty'); return; }
    current = null;
    hide();
  }

  function onError(e) {
    console.warn('[IVGO videoEgg] video error', e);
    reset();
  }

  function trigger(clipName) {
    if (DISABLED) return;
    const clip = CLIPS[clipName];
    if (!clip) return;
    if (current === null) { play(clipName); return; }
    if (clipName === 'raid' && current !== 'raid') {
      if (current === 'alrighty') pendingNormal = true;
      play('raid');
      return;
    }
    if (clip.priority >= 2) pendingHigh = true;
    else pendingNormal = true;
  }

  return {
    alrighty: function () { trigger('alrighty'); },
    raid:     function () { trigger('raid'); },
  };
})();

// Auto-wire Twitch events to toasts and video easter egg
if (typeof document !== 'undefined') {
  document.addEventListener('DOMContentLoaded', function () {
    _bus.on('channel.follow', p => _toast.toast({ type: 'follow', ...p }));
    _bus.on('channel.subscribe', p => _toast.toast({ type: 'sub', ...p }));
    _bus.on('channel.subscription.gift', p => _toast.toast({ type: 'gift', ...p }));
    _bus.on('channel.cheer', p => _toast.toast({ type: 'cheer', ...p }));
    _bus.on('channel.raid', p => _toast.toast({ type: 'raid', ...p }));

    _bus.on('channel.follow',            () => _videoEgg.alrighty());
    _bus.on('channel.subscribe',         () => _videoEgg.alrighty());
    _bus.on('channel.subscription.gift', () => _videoEgg.alrighty());
    _bus.on('channel.raid',              () => _videoEgg.raid());
  });
}

// Inject overlay CSS once
if (typeof document !== 'undefined' && !document.getElementById('ovl-styles')) {
  const s = document.createElement('style');
  s.id = 'ovl-styles';
  s.textContent = `
    @import url('https://fonts.googleapis.com/css2?family=Inter:wght@400;500;600;700&family=Archivo:wght@500;600;700;800;900&family=JetBrains+Mono:wght@400;500;600&display=swap');

    html, body, #root { margin:0; padding:0; height:100%; background:transparent; overflow:hidden; }

    .ovl-root{position:fixed;inset:0;color:${T.ink};font-family:${T.sans};letter-spacing:.01em;
      background:${T.bg};overflow:hidden}
    /* Compositing scenes (game / two-cam / cam) override .ovl-root background to transparent
       so gameplay or webcam capture from OBS shows through */
    .ovl-root.ovl-transparent{background:transparent}

    .ovl-grid{position:absolute;inset:0;background-image:
      linear-gradient(${T.rule} 1px, transparent 1px),
      linear-gradient(90deg, ${T.rule} 1px, transparent 1px);
      background-size:80px 80px;mask-image:radial-gradient(ellipse at center, #000 30%, transparent 80%);}
    .ovl-bluewash{position:absolute;inset:0;pointer-events:none;
      background:radial-gradient(ellipse 70% 50% at 20% 100%, ${T.accentWash} 0%, transparent 60%),
                 radial-gradient(ellipse 60% 40% at 90% 0%, rgba(40,154,230,.06) 0%, transparent 70%);}
    .ovl-vignette{position:absolute;inset:0;background:radial-gradient(ellipse at center, transparent 40%, rgba(0,0,0,.55) 100%);pointer-events:none}
    .ovl-noise{position:absolute;inset:0;opacity:.04;pointer-events:none;mix-blend-mode:overlay;
      background-image:url("data:image/svg+xml;utf8,<svg xmlns='http://www.w3.org/2000/svg' width='120' height='120'><filter id='n'><feTurbulence type='fractalNoise' baseFrequency='1.6' numOctaves='2' stitchTiles='stitch'/></filter><rect width='120' height='120' filter='url(%23n)' opacity='.9'/></svg>")}

    .ovl-chamfer{
      clip-path: polygon(10px 0, 100% 0, 100% calc(100% - 10px), calc(100% - 10px) 100%, 0 100%, 0 10px);
    }
    .ovl-chamfer-sm{
      clip-path: polygon(6px 0, 100% 0, 100% calc(100% - 6px), calc(100% - 6px) 100%, 0 100%, 0 6px);
    }

    .ovl-mono{font-family:${T.mono};letter-spacing:.06em;text-transform:uppercase;font-size:11px;color:${T.ink2};}
    .ovl-rule{height:1px;background:${T.rule};width:100%}
    .ovl-rule-v{width:1px;background:${T.rule};height:100%}

    @keyframes ovl-pulse { 0%,100%{opacity:1;transform:scale(1)} 50%{opacity:.55;transform:scale(.85)} }
    .ovl-live-dot{width:9px;height:9px;border-radius:50%;background:${T.live};box-shadow:0 0 12px ${T.live};animation:ovl-pulse 1.4s ease-in-out infinite}

    @keyframes ovl-ticker { from{transform:translateX(0)} to{transform:translateX(-50%)} }
    .ovl-ticker-track{display:inline-flex;gap:48px;animation:ovl-ticker 60s linear infinite;white-space:nowrap}

    @keyframes ovl-blink { 0%,55%{opacity:1} 60%,100%{opacity:.25} }
    .ovl-blink{animation:ovl-blink 2.2s steps(1) infinite}

    .ovl-scan::after{content:"";position:absolute;inset:0;pointer-events:none;
      background:repeating-linear-gradient(0deg, rgba(255,255,255,.018) 0 2px, transparent 2px 4px)}

    @keyframes ovl-bar1 {0%,100%{height:14%}50%{height:78%}}
    @keyframes ovl-bar2 {0%,100%{height:32%}50%{height:96%}}
    @keyframes ovl-bar3 {0%,100%{height:64%}40%{height:18%}80%{height:88%}}
    @keyframes ovl-bar4 {0%,100%{height:22%}30%{height:60%}70%{height:42%}}
    @keyframes ovl-bar5 {0%,100%{height:48%}60%{height:14%}}

    .ovl-screen-ph{
      background:
        repeating-linear-gradient(135deg, rgba(255,255,255,.018) 0 14px, transparent 14px 28px),
        linear-gradient(180deg, #16202a 0%, #0c1218 100%);
    }
    /* For compositing scenes, the gameplay/cam areas should be transparent so
       the underlying OBS source (game capture, webcam) is visible. */
    .ovl-screen-cutout{ background: transparent !important; }

    .ovl-btn-arrow{display:inline-flex;align-items:center;gap:8px;font-family:${T.mono};font-size:11px;letter-spacing:.14em;text-transform:uppercase;color:${T.ink}}

    /* Scene entrance animations — use the individual translate property rather
       than transform, so they compose with positioning transforms (like
       translate(-50%,-50%) on centred elements) instead of overriding them. */
    @keyframes ovl-rise   { from{translate:0 12px;opacity:0}    to{translate:0 0;opacity:1} }
    @keyframes ovl-rail   { from{translate:-64px 0;opacity:0}   to{translate:0 0;opacity:1} }
    @keyframes ovl-header { from{translate:0 -54px;opacity:0}   to{translate:0 0;opacity:1} }
    @keyframes ovl-tick   { from{translate:0 36px;opacity:0}    to{translate:0 0;opacity:1} }
    /* Slow vertical pan for background-image media that's taller than the box. */
    @keyframes ovl-gif-pan { 0%{background-position:center top} 100%{background-position:center bottom} }
    .ovl-anim-gif-pan { animation: ovl-gif-pan 8s ease-in-out infinite alternate; }
    .ovl-anim-rail   { animation: ovl-rail   .55s cubic-bezier(.2,.8,.2,1) both; }
    .ovl-anim-header { animation: ovl-header .55s cubic-bezier(.2,.8,.2,1) .12s both; }
    .ovl-anim-rise   { animation: ovl-rise   .55s cubic-bezier(.2,.8,.2,1) .24s both; }
    .ovl-anim-tick   { animation: ovl-tick   .55s cubic-bezier(.2,.8,.2,1) .36s both; }

    @keyframes ovl-toast-in { from{translate:0 12px;opacity:0} to{translate:0 0;opacity:1} }
    .ovl-toast-enter { animation: ovl-toast-in 250ms cubic-bezier(.2,.8,.2,1) both; }
  `;
  document.head.appendChild(s);
}

// ── Primitives ────────────────────────────────────────────────────────────

// Deterministic username colour fallback when Twitch sends no colour
function _chatColor(name) {
  const palette = ['#7dd3fc','#a7f3d0','#fde68a','#fca5a5','#c4b5fd','#f9a8d4','#86efac','#fdba74'];
  let h = 0;
  for (let i = 0; i < name.length; i++) h = (h * 31 + name.charCodeAt(i)) & 0xffffffff;
  return palette[Math.abs(h) % palette.length];
}

// IVGO brand logo mark (ivgo-logo-mark.svg) — viewBox 0 0 71 48
function Wordmark({size = 22, opacity = 1, color = T.ink}) {
  const h = size, w = Math.round(size * (71 / 48) * 10) / 10;
  return React.createElement('svg', {width:w, height:h, viewBox:'0 0 71 48', style:{opacity, display:'block'}, 'aria-hidden':'true'},
    React.createElement('path', {fill:color, d:'m26.371 33.477-.552-.1c-3.92-.729-6.397-3.1-7.57-6.829-.733-2.324.597-4.035 3.035-4.148 1.995-.092 3.362 1.055 4.57 2.39 1.557 1.72 2.984 3.558 4.514 5.305 2.202 2.515 4.797 4.134 8.347 3.634 3.183-.448 5.958-1.725 8.371-3.828.363-.316.761-.592 1.144-.886l-.241-.284c-2.027.63-4.093.841-6.205.735-3.195-.16-6.24-.828-8.964-2.582-2.486-1.601-4.319-3.746-5.19-6.611-.704-2.315.736-3.934 3.135-3.6.948.133 1.746.56 2.463 1.165.583.493 1.143 1.015 1.738 1.493 2.8 2.25 6.712 2.375 10.265-.068-5.842-.026-9.817-3.24-13.308-7.313-1.366-1.594-2.7-3.216-4.095-4.785-2.698-3.036-5.692-5.71-9.79-6.623C12.8-.623 7.745.14 2.893 2.361 1.926 2.804.997 3.319 0 4.149c.494 0 .763.006 1.032 0 2.446-.064 4.28 1.023 5.602 3.024.962 1.457 1.415 3.104 1.761 4.798.513 2.515.247 5.078.544 7.605.761 6.494 4.08 11.026 10.26 13.346 2.267.852 4.591 1.135 7.172.555ZM10.751 3.852c-.976.246-1.756-.148-2.56-.962 1.377-.343 2.592-.476 3.897-.528-.107.848-.607 1.306-1.336 1.49Zm32.002 37.924c-.085-.626-.62-.901-1.04-1.228-1.857-1.446-4.03-1.958-6.333-2-1.375-.026-2.735-.128-4.031-.61-.595-.22-1.26-.505-1.244-1.272.015-.78.693-1 1.31-1.184.505-.15 1.026-.247 1.6-.382-1.46-.936-2.886-1.065-4.787-.3-2.993 1.202-5.943 1.06-8.926-.017-1.684-.608-3.179-1.563-4.735-2.408l-.077.057c1.29 2.115 3.034 3.817 5.004 5.271 3.793 2.8 7.936 4.471 12.784 3.73A66.714 66.714 0 0 1 37 40.877c1.98-.16 3.866.398 5.753.899Zm-9.14-30.345c-.105-.076-.206-.266-.42-.069 1.745 2.36 3.985 4.098 6.683 5.193 4.354 1.767 8.773 2.07 13.293.51 3.51-1.21 6.033-.028 7.343 3.38.19-3.955-2.137-6.837-5.843-7.401-2.084-.318-4.01.373-5.962.94-5.434 1.575-10.485.798-15.094-2.553Zm27.085 15.425c.708.059 1.416.123 2.124.185-1.6-1.405-3.55-1.517-5.523-1.404-3.003.17-5.167 1.903-7.14 3.972-1.739 1.824-3.31 3.87-5.903 4.604.043.078.054.117.066.117.35.005.699.021 1.047.005 3.768-.17 7.317-.965 10.14-3.7.89-.86 1.685-1.817 2.544-2.71.716-.746 1.584-1.159 2.645-1.07Zm-8.753-4.67c-2.812.246-5.254 1.409-7.548 2.943-1.766 1.18-3.654 1.738-5.776 1.37-.374-.066-.75-.114-1.124-.17l-.013.156c.135.07.265.151.405.207.354.14.702.308 1.07.395 4.083.971 7.992.474 11.516-1.803 2.221-1.435 4.521-1.707 7.013-1.336.252.038.503.083.756.107.234.022.479.255.795.003-2.179-1.574-4.526-2.096-7.094-1.872Zm-10.049-9.544c1.475.051 2.943-.142 4.486-1.059-.452.04-.643.04-.827.076-2.126.424-4.033-.04-5.733-1.383-.623-.493-1.257-.974-1.889-1.457-2.503-1.914-5.374-2.555-8.514-2.5.05.154.054.26.108.315 3.417 3.455 7.371 5.836 12.369 6.008Zm24.727 17.731c-2.114-2.097-4.952-2.367-7.578-.537 1.738.078 3.043.632 4.101 1.728a13 13 0 0 0 1.182 1.106c1.6 1.29 4.311 1.352 5.896.155-1.861-.726-1.861-.726-3.601-2.452Zm-21.058 16.06c-1.858-3.46-4.981-4.24-8.59-4.008a9.667 9.667 0 0 1 2.977 1.39c.84.586 1.547 1.311 2.243 2.055 1.38 1.473 3.534 2.376 4.962 2.07-.656-.412-1.238-.848-1.592-1.507Z'})
  );
}

// IVGO WeeMan brand mark (wee-man.svg) — viewBox 0 0 375 375
function WeeMan({size = 36, color = T.ink}) {
  return React.createElement('svg', {width:size, height:size, viewBox:'0 0 375 375', style:{display:'block'}, 'aria-hidden':'true'},
    React.createElement('path', {fill:color, d:'M 203.921875 79.390625 C 206.992188 80.921875 209.746094 82.777344 212.402344 84.960938 L 213.414062 85.777344 C 218.300781 89.945312 222.347656 95.753906 224.691406 101.738281 C 227.285156 109.125 228.089844 116.804688 226.683594 124.511719 C 225.121094 132.367188 221.40625 138.847656 216.429688 145.019531 L 217.085938 144.609375 C 221.417969 141.890625 225.761719 139.1875 230.117188 136.503906 L 231.316406 135.765625 C 233.136719 134.648438 234.960938 133.53125 236.792969 132.429688 L 237.730469 131.863281 C 238.300781 131.519531 238.871094 131.175781 239.441406 130.835938 C 240.078125 130.449219 240.710938 130.050781 241.332031 129.636719 C 241.855469 128.59375 241.757812 127.695312 241.769531 126.53125 L 241.777344 125.789062 C 241.785156 125.257812 241.789062 124.726562 241.792969 124.191406 C 241.800781 123.34375 241.8125 122.496094 241.824219 121.648438 C 241.84375 119.839844 241.863281 118.035156 241.882812 116.226562 C 241.90625 114.148438 241.929688 112.070312 241.953125 109.988281 C 241.960938 109.164062 241.96875 108.339844 241.976562 107.515625 L 241.996094 105.945312 L 242.011719 104.59375 C 242.09375 102.074219 242.273438 99.558594 242.433594 97.046875 L 275.390625 97.046875 C 275.539062 109.984375 275.539062 109.984375 275.570312 115.40625 C 275.589844 119.148438 275.617188 122.894531 275.667969 126.636719 C 275.703125 129.363281 275.726562 132.089844 275.734375 134.816406 C 275.738281 136.261719 275.75 137.703125 275.777344 139.144531 C 275.800781 140.507812 275.8125 141.867188 275.804688 143.226562 C 275.804688 143.960938 275.824219 144.695312 275.847656 145.429688 C 275.832031 146.734375 275.78125 147.800781 275.390625 149.046875 C 274.308594 150.207031 273.136719 150.90625 271.726562 151.613281 C 271.285156 151.875 270.839844 152.136719 270.398438 152.402344 L 269.121094 153.097656 C 266.625 154.472656 264.160156 155.894531 261.703125 157.332031 C 258.605469 159.144531 255.5 160.945312 252.386719 162.734375 C 249.132812 164.609375 245.890625 166.511719 242.660156 168.433594 C 239.519531 170.304688 236.363281 172.144531 233.183594 173.953125 C 229.632812 175.972656 226.085938 177.996094 222.5625 180.0625 C 222.125 180.320312 221.6875 180.574219 221.25 180.824219 C 220.644531 181.175781 220.042969 181.53125 219.4375 181.886719 L 218.398438 182.496094 C 217.476562 183.144531 217.007812 183.605469 216.429688 184.570312 C 216.027344 185.535156 215.648438 186.507812 215.292969 187.492188 L 214.980469 188.34375 C 214.652344 189.234375 214.328125 190.128906 214.003906 191.023438 C 213.675781 191.921875 213.347656 192.820312 213.019531 193.714844 C 212.816406 194.273438 212.613281 194.832031 212.410156 195.386719 C 211.710938 197.308594 211.710938 197.308594 211.304688 198.121094 L 212.40625 197.832031 C 215.84375 196.9375 219.277344 196.042969 222.714844 195.148438 C 224.484375 194.691406 226.25 194.230469 228.015625 193.769531 C 229.722656 193.324219 231.429688 192.882812 233.136719 192.4375 L 235.085938 191.929688 C 243.199219 189.8125 243.199219 189.8125 244.628906 189.695312 C 245.535156 190.164062 245.535156 190.164062 246.164062 190.933594 L 246.878906 191.765625 L 247.558594 192.625 C 247.976562 193.109375 248.394531 193.589844 248.816406 194.070312 L 249.445312 194.800781 C 250.453125 195.925781 251.539062 196.976562 252.613281 198.039062 C 253.578125 199.015625 254.472656 200.042969 255.367188 201.085938 C 256.171875 202 257.035156 202.839844 257.902344 203.695312 C 258.804688 204.609375 259.628906 205.582031 260.46875 206.554688 C 261.273438 207.460938 262.128906 208.304688 262.996094 209.152344 C 263.652344 209.816406 264.261719 210.503906 264.871094 211.210938 C 266.15625 212.6875 267.480469 214.117188 268.820312 215.539062 L 271.007812 217.859375 C 272.128906 219.050781 273.246094 220.246094 274.359375 221.441406 L 275.003906 222.132812 C 276.519531 223.757812 278.03125 225.390625 279.535156 227.03125 C 281.085938 228.710938 282.65625 230.375 284.226562 232.039062 C 286.433594 234.382812 288.621094 236.742188 290.769531 239.136719 C 290.199219 240.574219 289.285156 241.367188 288.140625 242.386719 C 287.738281 242.746094 287.339844 243.105469 286.9375 243.464844 L 286.296875 244.039062 C 285.183594 245.046875 284.085938 246.074219 282.988281 247.101562 L 282.296875 247.75 C 280.835938 249.113281 279.378906 250.480469 277.921875 251.847656 C 273.460938 256.035156 273.460938 256.035156 271.269531 258.039062 C 270.242188 258.980469 269.226562 259.933594 268.230469 260.90625 L 267.578125 261.53125 C 267.164062 261.925781 266.753906 262.328125 266.347656 262.730469 C 265.789062 263.265625 265.789062 263.265625 264.769531 264.039062 C 264.054688 263.976562 264.054688 263.976562 263.304688 263.671875 C 262.660156 263.160156 262.660156 263.160156 262.003906 262.5 L 261.25 261.75 L 260.449219 260.933594 L 259.613281 260.097656 C 259.027344 259.507812 258.441406 258.917969 257.859375 258.328125 C 256.976562 257.433594 256.085938 256.542969 255.199219 255.648438 L 253.492188 253.929688 L 252.695312 253.132812 C 251.277344 251.691406 249.910156 250.210938 248.589844 248.683594 C 246.425781 246.222656 244.101562 243.902344 241.808594 241.5625 C 241.152344 240.886719 240.5 240.210938 239.851562 239.527344 C 238.910156 238.539062 237.957031 237.566406 237 236.59375 L 236.128906 235.664062 C 235.328125 234.867188 234.621094 234.207031 233.640625 233.640625 C 232.410156 233.5625 231.476562 233.917969 230.347656 234.375 C 229.820312 234.535156 229.289062 234.695312 228.761719 234.851562 C 228.195312 235.035156 227.628906 235.21875 227.066406 235.40625 L 226.097656 235.722656 C 224.257812 236.324219 222.417969 236.933594 220.582031 237.542969 C 219.75 237.816406 218.917969 238.09375 218.085938 238.367188 L 216.769531 238.804688 C 213.867188 239.761719 210.960938 240.695312 208.042969 241.609375 C 205.566406 242.386719 203.097656 243.171875 200.625 243.96875 C 199.089844 244.460938 197.554688 244.949219 196.011719 245.421875 C 188.664062 247.402344 188.664062 247.402344 182.425781 251.457031 C 181.582031 252.433594 180.875 253.433594 180.175781 254.515625 C 179.734375 255.035156 179.285156 255.546875 178.824219 256.050781 L 178.25 256.71875 C 177.4375 257.644531 176.609375 258.550781 175.78125 259.460938 C 174.730469 260.609375 173.6875 261.765625 172.667969 262.9375 C 171.339844 264.46875 169.96875 265.964844 168.605469 267.460938 C 167.882812 268.257812 167.167969 269.0625 166.464844 269.875 L 165.832031 270.574219 C 165.121094 271.378906 165.121094 271.378906 164.441406 272.402344 C 163.21875 274.015625 162.0625 275.328125 160.195312 276.1875 C 159.074219 276.597656 157.949219 276.96875 156.8125 277.328125 C 155.953125 277.613281 155.09375 277.898438 154.234375 278.183594 L 152.910156 278.617188 C 150.898438 279.289062 148.910156 280.015625 146.917969 280.746094 L 145.738281 281.175781 L 143.332031 282.054688 C 141.148438 282.851562 138.964844 283.648438 136.785156 284.441406 L 135.441406 284.933594 C 130.167969 286.851562 124.890625 288.753906 119.613281 290.648438 L 117.398438 291.441406 L 116.316406 291.832031 C 113.921875 292.691406 111.527344 293.5625 109.136719 294.4375 L 106.378906 295.445312 C 105.539062 295.753906 104.699219 296.0625 103.859375 296.371094 L 102.359375 296.917969 L 101.0625 297.398438 C 99.976562 297.730469 99.976562 297.730469 98.511719 297.730469 L 97.273438 294.574219 L 96.878906 293.5625 C 96.148438 291.695312 95.417969 289.828125 94.6875 287.960938 C 93.335938 284.492188 91.972656 281.027344 90.609375 277.5625 C 90.066406 276.1875 89.527344 274.8125 88.984375 273.4375 C 88.730469 272.789062 88.472656 272.140625 88.214844 271.492188 C 87.855469 270.585938 87.5 269.683594 87.144531 268.777344 L 86.824219 267.976562 C 86.269531 266.546875 85.886719 265.195312 85.695312 263.671875 C 88.082031 262.421875 90.53125 261.414062 93.039062 260.425781 C 93.761719 260.136719 94.480469 259.851562 95.203125 259.5625 L 96.832031 258.917969 C 100.960938 257.277344 105.082031 255.621094 109.203125 253.964844 L 135.207031 243.523438 L 136.246094 243.105469 L 137.203125 242.722656 L 138.03125 242.390625 C 138.796875 242.0625 139.539062 241.75 140.257812 241.332031 C 140.714844 240.429688 140.714844 240.429688 141.011719 239.320312 L 141.402344 238.03125 L 141.8125 236.617188 C 141.957031 236.125 142.105469 235.636719 142.253906 235.144531 C 142.648438 233.820312 143.039062 232.496094 143.425781 231.171875 C 143.832031 229.792969 144.242188 228.417969 144.65625 227.039062 C 145.320312 224.808594 145.980469 222.578125 146.640625 220.347656 C 147.839844 216.300781 149.046875 212.257812 150.265625 208.214844 C 150.589844 207.136719 150.914062 206.054688 151.238281 204.976562 C 152.796875 199.75 154.394531 194.539062 156.003906 189.332031 C 152.554688 189.324219 149.105469 189.34375 145.652344 189.390625 C 144.050781 189.410156 142.445312 189.425781 140.84375 189.417969 C 139.292969 189.414062 137.742188 189.429688 136.191406 189.460938 C 135.605469 189.46875 135.015625 189.46875 134.429688 189.464844 C 132.554688 189.441406 130.6875 189.429688 128.90625 190.0625 C 127.242188 191.085938 125.941406 192.480469 124.648438 193.925781 C 123.890625 194.726562 123.042969 195.402344 122.175781 196.082031 C 120.566406 197.378906 118.996094 198.710938 117.4375 200.066406 L 116.742188 200.671875 L 115.332031 201.898438 C 114.167969 202.910156 113 203.914062 111.832031 204.917969 L 111.203125 205.460938 C 110.042969 206.453125 108.867188 207.425781 107.664062 208.375 C 106.347656 207.828125 105.605469 207.082031 104.667969 206.015625 L 103.792969 205.023438 C 102.652344 203.679688 101.542969 202.316406 100.433594 200.945312 C 99.632812 199.980469 98.804688 199.046875 97.960938 198.121094 C 96.5625 196.582031 95.246094 194.996094 93.941406 193.378906 C 92.855469 192.0625 91.738281 190.777344 90.613281 189.492188 C 88.792969 187.40625 87.027344 185.289062 85.328125 183.105469 C 87.800781 180.605469 90.386719 178.234375 93.132812 176.03125 C 94.984375 174.539062 96.710938 172.941406 98.441406 171.3125 C 100.019531 169.832031 101.660156 168.460938 103.347656 167.109375 C 104.96875 165.761719 106.496094 164.316406 108.039062 162.878906 C 109.351562 161.65625 110.699219 160.472656 112.058594 159.300781 L 113.339844 158.195312 L 114.738281 156.988281 L 115.417969 156.402344 L 116.0625 155.851562 L 116.636719 155.351562 C 117.164062 154.925781 117.722656 154.550781 118.285156 154.175781 C 119.203125 154.078125 119.203125 154.078125 120.324219 154.074219 L 121.605469 154.058594 L 123.015625 154.058594 L 124.5 154.046875 C 125.84375 154.035156 127.183594 154.03125 128.527344 154.027344 C 129.933594 154.019531 131.335938 154.011719 132.738281 154 C 135.394531 153.984375 138.054688 153.972656 140.710938 153.960938 C 143.734375 153.945312 146.761719 153.925781 149.785156 153.910156 C 156.011719 153.871094 162.234375 153.835938 168.457031 153.808594 C 167.222656 152.808594 165.933594 151.882812 164.589844 151.039062 C 159.140625 147.433594 154.816406 142.644531 151.609375 136.960938 L 151.019531 135.941406 C 147.785156 129.988281 146.269531 122.929688 146.414062 116.179688 C 146.886719 108.046875 148.761719 100.910156 153.246094 94.027344 C 157.460938 87.714844 162.859375 83.058594 169.53125 79.511719 C 180.160156 74.472656 193.265625 74.3125 203.921875 79.390625'})
  );
}

function LiveBadge({label = 'LIVE'}) {
  return React.createElement('div', {className:'ovl-chamfer-sm', style:{
    display:'inline-flex', alignItems:'center', gap:8,
    padding:'8px 14px', background:'#16060a', border:`1px solid ${T.live}`,
    fontFamily:T.mono, fontSize:12, letterSpacing:'.18em', color:'#ffd6d2'
  }},
    React.createElement('span', {className:'ovl-live-dot'}),
    label
  );
}

function Chip({children, accent, mono=true, style={}}) {
  return React.createElement('div', {className:'ovl-chamfer-sm', style:{
    padding:'8px 14px',
    background: accent ? '#0e1a26' : T.bg2,
    border:`1px solid ${accent || T.rule2}`,
    fontFamily: mono?T.mono:T.sans, fontSize:11, letterSpacing:'.16em',
    textTransform:'uppercase', color: accent ? '#d0eafa' : T.ink,
    ...style
  }}, children);
}

function MetaLine({items}) {
  return React.createElement('div', {style:{display:'flex',alignItems:'center',gap:14,fontFamily:T.mono,fontSize:11,letterSpacing:'.14em',color:T.ink2,textTransform:'uppercase'}},
    items.map((it, i) => React.createElement(React.Fragment, {key:i},
      i>0 && React.createElement('span', {style:{color:T.ink3}}, '│'),
      React.createElement('span', null, it)
    ))
  );
}

function AudioBars({count = 22, color = T.accent, height = 42, speed = 1}) {
  // speed: multiplier on each bar's animation duration. 1 = original cadence;
  // >1 slower, <1 faster. Per-scene tuning so a calm "Starting Soon" can sit
  // at speed=1.6 without slowing the BRB bars.
  const bars = Array.from({length: count});
  const anims = ['ovl-bar1','ovl-bar2','ovl-bar3','ovl-bar4','ovl-bar5'];
  return React.createElement('div', {style:{display:'flex',alignItems:'flex-end',gap:3,height,width:'100%'}},
    bars.map((_,i) => React.createElement('div', {key:i, style:{
      flex:1,
      background: color,
      boxShadow:`0 0 6px ${T.accentGlow}`,
      opacity:.92,
      animation:`${anims[i % anims.length]} ${(0.9 + (i%5)*0.18) * speed}s ease-in-out ${(i%7)*0.08}s infinite`
    }}))
  );
}

function UtilityRail() { return null; }

function CornerTrim({pos = 'br', size = 28}) {
  const styles = {position:'absolute', width:size, height:size, borderColor:T.ink2, borderStyle:'solid', borderWidth:0};
  if (pos === 'tl') Object.assign(styles, {top:0,left:0,borderTopWidth:1,borderLeftWidth:1});
  if (pos === 'tr') Object.assign(styles, {top:0,right:0,borderTopWidth:1,borderRightWidth:1});
  if (pos === 'bl') Object.assign(styles, {bottom:0,left:0,borderBottomWidth:1,borderLeftWidth:1});
  if (pos === 'br') Object.assign(styles, {bottom:0,right:0,borderBottomWidth:1,borderRightWidth:1});
  return React.createElement('div', {style:styles});
}

// kind: 'cam' | 'game' — set transparent=true to make the placeholder a transparent
// cutout (used in OBS so the real game/cam capture shows through).
function MediaPlaceholder({label, sub, style={}, kind='cam', transparent=false}) {
  const cls = transparent ? 'ovl-screen-cutout' : 'ovl-screen-ph';
  return React.createElement('div', {className:cls, style:{
    position:'relative', display:'flex', alignItems:'center', justifyContent:'center',
    color:T.ink2, ...style
  }},
    React.createElement(CornerTrim, {pos:'tl'}),
    React.createElement(CornerTrim, {pos:'tr'}),
    React.createElement(CornerTrim, {pos:'bl'}),
    React.createElement(CornerTrim, {pos:'br'}),
    !transparent && React.createElement('div', {style:{display:'flex',flexDirection:'column',alignItems:'center',gap:10}},
      React.createElement('div', {style:{fontFamily:T.mono,fontSize:11,letterSpacing:'.34em',color:T.ink3,textTransform:'uppercase'}},
        kind === 'cam' ? 'CAMERA' : 'GAMEPLAY'
      ),
      React.createElement('div', {style:{fontFamily:T.display,fontSize:42,fontWeight:800,letterSpacing:'.02em'}}, label),
      sub && React.createElement('div', {style:{fontFamily:T.mono,fontSize:11,letterSpacing:'.22em',color:T.ink3,textTransform:'uppercase'}}, sub)
    )
  );
}

function NowPlayingStrip({game = 'FINAL FANTASY VII REBIRTH', track = "AERITH'S SUITE", composer = 'NOBUO UEMATSU · ARR. IVGO'}) {
  return React.createElement('div', {className:'ovl-chamfer', style:{
    background:`linear-gradient(90deg, ${T.bg2} 0%, ${T.bg3} 100%)`,
    border:`1px solid ${T.rule2}`, padding:'14px 20px 14px 18px',
    display:'flex', alignItems:'center', gap:18, minWidth:520
  }},
    React.createElement('div', {style:{display:'flex',flexDirection:'column',alignItems:'flex-start',gap:6,paddingRight:18,borderRight:`1px solid ${T.rule}`}},
      React.createElement('div', {style:{fontFamily:T.mono,fontSize:9,letterSpacing:'.32em',color:T.ink3}}, 'NOW PLAYING'),
      React.createElement('div', {style:{fontFamily:T.mono,fontSize:11,letterSpacing:'.18em',color:T.ink2}}, game)
    ),
    React.createElement('div', {style:{display:'flex',flexDirection:'column',gap:4,flex:1}},
      React.createElement('div', {style:{fontFamily:T.display,fontSize:22,fontWeight:700,letterSpacing:'.04em'}}, track),
      React.createElement('div', {style:{fontFamily:T.mono,fontSize:10,letterSpacing:'.22em',color:T.ink3,textTransform:'uppercase'}}, composer)
    ),
    React.createElement('div', {style:{width:120,height:34}}, React.createElement(AudioBars, {count:16, height:34, color:T.ink}))
  );
}

function ChatPanel({channel = 'irishvideogameorchestra', style={}}) {
  const [messages, setMessages] = React.useState([]);
  const [connected, setConnected] = React.useState(false);

  React.useEffect(() => {
    const ws = new WebSocket('wss://irc-ws.chat.twitch.tv');
    ws.onopen = () => {
      ws.send('CAP REQ :twitch.tv/tags');
      ws.send('PASS SCHMOOPIIE');
      ws.send('NICK justinfan' + Math.floor(Math.random() * 99999));
      ws.send('JOIN #' + channel.toLowerCase());
    };
    ws.onmessage = (ev) => {
      ev.data.split('\r\n').filter(Boolean).forEach(line => {
        if (line.startsWith('PING')) { ws.send('PONG :tmi.twitch.tv'); return; }
        if (!line.includes('PRIVMSG')) {
          if (line.includes(' 376 ') || line.includes('JOIN #')) setConnected(true);
          return;
        }
        const tags = {};
        if (line.startsWith('@')) {
          line.slice(1, line.indexOf(' ')).split(';').forEach(t => {
            const eq = t.indexOf('=');
            tags[t.slice(0, eq)] = t.slice(eq + 1);
          });
        }
        const msgMatch = line.match(/PRIVMSG #\S+ :(.+)$/);
        if (!msgMatch) return;
        const name = tags['display-name'] || 'viewer';
        setMessages(prev => [...prev.slice(-5), {
          id: tags['id'] || Math.random().toString(36),
          u: name,
          c: tags['color'] || _chatColor(name),
          t: msgMatch[1],
        }]);
      });
    };
    ws.onclose = () => setConnected(false);
    return () => ws.close();
  }, [channel]);

  return React.createElement('div', {className:'ovl-chamfer', style:{
    background:'rgba(17,17,20,.82)', backdropFilter:'blur(8px)',
    border:`1px solid ${T.rule2}`, padding:'14px 16px',
    display:'flex', flexDirection:'column', gap:10, ...style
  }},
    React.createElement('div', {style:{display:'flex',alignItems:'center',justifyContent:'space-between'}},
      React.createElement('div', {style:{fontFamily:T.mono,fontSize:10,letterSpacing:'.32em',color:T.ink2}}, 'CHAT'),
      React.createElement('div', {style:{display:'flex',alignItems:'center',gap:6}},
        connected && React.createElement('span', {className:'ovl-live-dot', style:{width:6,height:6}}),
        React.createElement('span', {style:{fontFamily:T.mono,fontSize:10,letterSpacing:'.22em',color:T.ink3}},
          connected ? 'CONNECTED' : 'CONNECTING\u2026')
      )
    ),
    React.createElement('div', {style:{height:1,background:T.rule}}),
    React.createElement('div', {style:{display:'flex',flexDirection:'column',gap:8}},
      messages.length === 0
        ? React.createElement('div', {style:{fontFamily:T.mono,fontSize:10,letterSpacing:'.18em',color:T.ink3}}, 'WAITING FOR CHAT\u2026')
        : messages.map((m, i) => React.createElement('div', {key:m.id, style:{
            display:'flex', gap:8, fontSize:13, lineHeight:1.35,
            opacity: 0.5 + (i / Math.max(messages.length - 1, 1)) * 0.5,
          }},
            React.createElement('span', {style:{color:m.c,fontWeight:600,fontFamily:T.mono,fontSize:11,letterSpacing:'.06em',flexShrink:0}}, m.u),
            React.createElement('span', {style:{color:T.ink,wordBreak:'break-word',fontFamily:T.mono,fontSize:11,letterSpacing:'.04em'}}, m.t)
          ))
    )
  );
}

function GoalBar({label='SEASON 26-27 FUND', value=4280, target=8000}) {
  const pct = Math.min(100, (value/target)*100);
  return React.createElement('div', {className:'ovl-chamfer-sm', style:{
    background:T.bg2, border:`1px solid ${T.rule2}`, padding:'10px 14px', minWidth:280
  }},
    React.createElement('div', {style:{display:'flex',justifyContent:'space-between',alignItems:'baseline',marginBottom:8}},
      React.createElement('span', {style:{fontFamily:T.mono,fontSize:10,letterSpacing:'.26em',color:T.accent}}, `┤ ${label}`),
      React.createElement('span', {style:{fontFamily:T.mono,fontSize:11,letterSpacing:'.14em',color:T.ink}},
        `£${value.toLocaleString()}`,
        React.createElement('span', {style:{color:T.ink3}}, ` / £${target.toLocaleString()}`)
      )
    ),
    React.createElement('div', {style:{height:6,background:'#101820',position:'relative',overflow:'hidden'}},
      React.createElement('div', {style:{position:'absolute',inset:0,width:`${pct}%`,background:`linear-gradient(90deg, ${T.accentDeep} 0%, ${T.accent} 100%)`,boxShadow:`0 0 12px ${T.accentGlow}`,transition:'width 800ms cubic-bezier(.2,.8,.2,1)'}})
    )
  );
}

function Ticker({items}) {
  const all = [...items, ...items];
  return React.createElement('div', {className:'ovl-anim-tick', style:{
    position:'absolute', bottom:0, left:0, right:0, height:36,
    background:'#06080a', borderTop:`1px solid ${T.rule2}`,
    display:'flex', alignItems:'center', overflow:'hidden', zIndex:6
  }},
    React.createElement('div', {style:{
      flexShrink:0, padding:'0 20px', height:'100%', display:'flex', alignItems:'center',
      borderRight:`1px solid ${T.rule2}`
    }},
      React.createElement('img', {src:'../brand-assets/IVGO_w.png', style:{height:18, display:'block'}, alt:'IVGO'})
    ),
    React.createElement('div', {style:{flex:1,overflow:'hidden',position:'relative'}},
      React.createElement('div', {className:'ovl-ticker-track', style:{paddingLeft:24,fontFamily:T.mono,fontSize:11,letterSpacing:'.18em',color:T.ink2,textTransform:'uppercase'}},
        all.map((it,i) => React.createElement('span', {key:i, style:{display:'inline-flex',alignItems:'center',gap:14}},
          React.createElement('span', {style:{color:T.ink3}}, '|'),
          React.createElement('span', null, it)
        ))
      )
    ),
    React.createElement('div', {style:{flexShrink:0,padding:'0 18px',height:'100%',display:'flex',alignItems:'center',gap:10,
      borderLeft:`1px solid ${T.rule2}`, background:'#0c1420',
      fontFamily:T.mono, fontSize:10, letterSpacing:'.22em', color:T.ink2}},
      React.createElement('span', null, 'TWITCH.TV/IVGORCHESTRA')
    )
  );
}

function HeaderBar() {
  const sep = React.createElement('span', {style:{color:T.rule2, padding:'0 2px'}}, '│');
  return React.createElement('div', {className:'ovl-anim-header', style:{
    position:'absolute', top:0, left:0, right:0, height:54,
    background:`linear-gradient(180deg, ${T.bg2} 0%, rgba(15,20,24,0) 100%)`,
    borderBottom:`1px solid ${T.rule}`,
    boxShadow:`inset 0 -1px 0 0 rgba(40,154,230,.18)`,
    display:'flex', alignItems:'stretch', zIndex:5
  }},
    React.createElement('div', {style:{
      flexShrink:0, padding:'0 20px', background:'#06080a',
      borderRight:`1px solid ${T.rule2}`,
      display:'flex', alignItems:'center'
    }},
      React.createElement(WeeMan, {size:58, color:T.ink})
    ),
    React.createElement('div', {style:{flex:1, display:'flex', alignItems:'center', justifyContent:'space-between', padding:'0 24px'}},
      React.createElement('div', {style:{display:'flex', alignItems:'center', gap:12}},
        React.createElement('span', {style:{fontFamily:T.mono, fontSize:11, letterSpacing:'.28em', color:T.ink2, textTransform:'uppercase'}}, 'IRISH VIDEO GAME ORCHESTRA'),
        sep,
        React.createElement('span', {style:{fontFamily:T.mono, fontSize:11, letterSpacing:'.18em', color:T.ink3, textTransform:'uppercase'}}, 'IVGORCHESTRA.COM')
      ),
      React.createElement('div', {style:{display:'flex', alignItems:'center', gap:12}},
        React.createElement('span', {style:{fontFamily:T.mono, fontSize:10, letterSpacing:'.22em', color:T.ink3}}, 'EST. 2015'),
        sep,
        React.createElement('span', {style:{fontFamily:T.mono, fontSize:10, letterSpacing:'.22em', color:T.ink3}}, 'BELFAST'),
        sep,
        React.createElement('span', {style:{fontFamily:T.mono, fontSize:10, letterSpacing:'.22em', color:T.ink3}}, 'NIC108928')
      )
    )
  );
}

// ── Arranging-scene components ────────────────────────────────────────────
// Sibling-style helpers for coworking/arranging streams. Live in shared so
// they can be reused; tone is calmer and more information-dense than the
// broadcast components above.

// Lower-third for arranging: two-cell PIECE / FROM card. Ephemeral — the scene
// gates visibility on `info_shown` events and unmounts after 10s.
function WorkbenchStrip({
  piece = "AERITH'S SUITE",
  collection = 'FINAL FANTASY VII REBIRTH',
  gif = null
}) {
  // Pick MP4 over GIF when both are available — smaller, smoother, no frame-blending.
  const mediaUrl = gif && (gif.mp4 || gif.gif || (typeof gif === 'string' ? gif : null));
  const isVideo  = mediaUrl && /\.mp4($|\?)/i.test(mediaUrl);

  return React.createElement('div', {className:'ovl-chamfer', style:{
    background:`linear-gradient(180deg, ${T.bg2} 0%, ${T.bg3} 100%)`,
    border:`1px solid ${T.rule2}`,
    boxShadow:`inset 0 1px 0 0 rgba(40,154,230,.18)`,
    height: '100%', boxSizing: 'border-box',
    display:'flex', alignItems:'stretch', padding:0,
    overflow:'hidden', position:'relative'
  }},
    // Right-half visual layer (animated). Sits behind the text cells via
    // source order; left-edge mask fades into the FROM/piece text area.
    mediaUrl && (isVideo
      ? React.createElement('video', {
          src: mediaUrl, autoPlay:true, muted:true, loop:true, playsInline:true,
          style: {
            position:'absolute', top:0, bottom:0, right:0, width:'62.5%',
            objectFit:'cover', objectPosition:'center center',
            WebkitMaskImage: 'linear-gradient(to right, transparent 0%, black 100%)',
            maskImage:       'linear-gradient(to right, transparent 0%, black 100%)',
            pointerEvents:'none', opacity:0.9
          }
        })
      // Background-image div so we can animate `background-position` for a slow
      // vertical pan — object-position is not reliably animatable in CEF.
      : React.createElement('div', {
          className: 'ovl-anim-gif-pan',
          style: {
            position:'absolute', top:0, bottom:0, right:0, width:'62.5%',
            backgroundImage: `url("${mediaUrl}")`,
            backgroundRepeat: 'no-repeat',
            backgroundSize: 'cover',
            backgroundPosition: 'center center',
            WebkitMaskImage: 'linear-gradient(to right, transparent 0%, black 100%)',
            maskImage:       'linear-gradient(to right, transparent 0%, black 100%)',
            pointerEvents:'none', opacity:0.9
          }
        })),
    React.createElement('div', {style:{
      flexShrink:0, padding:'0 22px', display:'flex', alignItems:'center', gap:10,
      background:'#06080a', borderRight:`1px solid ${T.rule2}`
    }},
      React.createElement('div', {style:{width:8, height:8, background:T.accent, boxShadow:`0 0 10px ${T.accentGlow}`}}),
      React.createElement('div', {style:{fontFamily:T.mono,fontSize:10,letterSpacing:'.36em',color:T.ink2,textTransform:'uppercase'}}, 'ON THE DESK')
    ),
    React.createElement('div', {style:{
      flex:1, display:'flex', flexDirection:'column', justifyContent:'center', gap:8,
      padding:'0 28px', minWidth:0
    }},
      React.createElement('div', {style:{
        fontFamily:T.display, fontSize:34, fontWeight:800, letterSpacing:'.02em',
        color:T.ink, lineHeight:1,
        whiteSpace:'nowrap', overflow:'hidden', textOverflow:'ellipsis'
      }}, piece),
      React.createElement('div', {style:{display:'flex', alignItems:'center', gap:14}},
        React.createElement('span', {style:{fontFamily:T.mono,fontSize:13,letterSpacing:'.34em',color:T.ink3,textTransform:'uppercase'}}, 'FROM'),
        React.createElement('span', {style:{
          fontFamily:T.mono, fontSize:20, letterSpacing:'.14em',
          color:T.ink2, textTransform:'uppercase',
          whiteSpace:'nowrap', overflow:'hidden', textOverflow:'ellipsis'
        }}, collection)
      )
    )
  );
}

// Pomodoro timer: phase chip + countdown + sprint dots.
// phase: 'FOCUS' | 'BREAK' | 'IDLE'  (string or lowercase — case-insensitive)
// startedAt: ISO-8601 string (or ms epoch). If null, the timer is idle/paused
// and shows the full configured durationMs in a dim colour.
function SprintTimer({
  phase = 'IDLE', sprint = 1, total = 4, durationMs, startedAt,
}) {
  const phaseU = String(phase || 'IDLE').toUpperCase();
  const defaults = { FOCUS: 25*60*1000, BREAK: 5*60*1000, IDLE: 25*60*1000 };
  const ms = durationMs != null ? durationMs : defaults[phaseU] || defaults.FOCUS;
  const startMs = startedAt
    ? (typeof startedAt === 'number' ? startedAt : Date.parse(startedAt))
    : null;
  const idle = phaseU === 'IDLE' || startMs == null;

  const computeRemaining = React.useCallback(() => {
    if (idle) return ms;
    return Math.max(0, ms - (Date.now() - startMs));
  }, [ms, startMs, idle]);

  const [remaining, setRemaining] = React.useState(computeRemaining);
  React.useEffect(() => {
    setRemaining(computeRemaining());
    if (idle) return;
    const id = setInterval(() => setRemaining(computeRemaining()), 250);
    return () => clearInterval(id);
  }, [computeRemaining, idle]);

  const mm = String(Math.floor(remaining / 60000)).padStart(2, '0');
  const ss = String(Math.floor((remaining % 60000) / 1000)).padStart(2, '0');

  const accent = phaseU === 'BREAK' ? T.amber : (idle ? T.ink3 : T.accent);
  const accentGlow = phaseU === 'BREAK' ? 'rgba(245,165,36,.55)' : (idle ? 'transparent' : T.accentGlow);
  const phaseLabel = idle ? 'POMO IDLE' : (phaseU === 'BREAK' ? 'SHORT BREAK' : 'FOCUS SPRINT');
  const numberColor = idle ? T.ink3 : T.ink;

  const dots = [];
  for (let i = 1; i <= total; i++) {
    const filled = i < sprint;
    const current = i === sprint && !idle;
    dots.push(React.createElement('div', {key:i, style:{
      width: current ? 10 : 8, height: current ? 10 : 8,
      borderRadius:'50%',
      background: filled ? accent : (current ? accent : 'transparent'),
      border: `1px solid ${filled ? accent : (current ? accent : T.rule2)}`,
      boxShadow: current ? `0 0 8px ${accentGlow}` : 'none',
      opacity: filled ? 0.55 : 1,
    }}));
  }

  return React.createElement('div', {className:'ovl-chamfer-sm', style:{
    background:'rgba(6,8,10,.78)', backdropFilter:'blur(8px)',
    border:`1px solid ${T.rule2}`, padding:'12px 16px',
    display:'flex', alignItems:'center', gap:18,
    // border-box width:284 — matches the cam-outline's rendered outer width
    // (cam-outline is 282 content + 2 border = 284). Content area = 250,
    // which is tight for the FOCUS-SPRINT + MM:SS + SPRINT N/T + dots layout;
    // if labels start clipping with longer phases, drop the phase fontSize
    // 10→9 and gap 18→14 below to free ~14px.
    width: 340, boxSizing: 'border-box'
  }},
    React.createElement('div', {style:{display:'flex',flexDirection:'column',gap:4,flex:1}},
      React.createElement('div', {style:{display:'flex',alignItems:'center',gap:8}},
        React.createElement('div', {style:{width:6, height:6, background:accent, boxShadow:idle ? 'none' : `0 0 8px ${accentGlow}`}}),
        React.createElement('div', {style:{fontFamily:T.mono,fontSize:10,letterSpacing:'.32em',color:accent}}, phaseLabel)
      ),
      React.createElement('div', {style:{display:'flex',alignItems:'baseline',gap:4,fontFamily:T.display,fontWeight:800,color:numberColor}},
        React.createElement('span', {style:{fontSize:38,lineHeight:1,letterSpacing:'.02em'}}, mm),
        React.createElement('span', {
          style:{fontSize:28,color:T.ink3,lineHeight:1},
          className: idle ? '' : 'ovl-blink'
        }, ':'),
        React.createElement('span', {style:{fontSize:38,lineHeight:1,letterSpacing:'.02em'}}, ss)
      )
    ),
    React.createElement('div', {style:{width:1, height:48, background:T.rule2}}),
    React.createElement('div', {style:{display:'flex',flexDirection:'column',gap:6,alignItems:'flex-end'}},
      React.createElement('div', {style:{fontFamily:T.mono,fontSize:9,letterSpacing:'.32em',color:T.ink3}}, `SPRINT ${sprint} / ${total}`),
      React.createElement('div', {style:{display:'flex',gap:6}}, ...dots)
    )
  );
}

// Vertical list of viewer tasks. Sits under the cam in the arranging scene.
// tasks: [{id, user_login, user_name, text, added_at, done_at}]
// Shows up to `cap` rows; sort = open (oldest→newest), then done (newest→oldest).
// Done tasks stay visible (green tick) until shouldered out by new entries.
function TaskList({tasks = [], cap = 6, width = 282}) {
  const open = [];
  const done = [];
  tasks.forEach(t => (t.done_at ? done : open).push(t));
  open.sort((a, b) => (a.added_at || '').localeCompare(b.added_at || ''));
  done.sort((a, b) => (b.done_at || '').localeCompare(a.done_at || ''));
  const visible = [...open, ...done].slice(0, cap);

  const checkbox = (isDone) => React.createElement('div', {style:{
    width:12, height:12, flexShrink:0,
    border:`1px solid ${isDone ? T.done : T.rule2}`,
    background: isDone ? T.done : 'transparent',
    display:'flex', alignItems:'center', justifyContent:'center',
    transition:'background 200ms ease, border-color 200ms ease'
  }},
    isDone && React.createElement('svg', {width:10, height:10, viewBox:'0 0 10 10', 'aria-hidden':'true'},
      React.createElement('path', {
        d:'M1.5 5.2 L4 7.5 L8.5 2.5',
        stroke:'#fff', strokeWidth:1.6, fill:'none', strokeLinecap:'round', strokeLinejoin:'round'
      })
    )
  );

  return React.createElement('div', {className:'ovl-chamfer-sm', style:{
    width, background:'rgba(6,8,10,.78)', backdropFilter:'blur(8px)',
    border:`1px solid ${T.rule2}`,
    display:'flex', flexDirection:'column'
  }},
    React.createElement('div', {style:{
      padding:'8px 12px', borderBottom:`1px solid ${T.rule}`,
      display:'flex', alignItems:'center', justifyContent:'space-between'
    }},
      React.createElement('div', {style:{fontFamily:T.mono,fontSize:10,letterSpacing:'.32em',color:T.accent}}, 'TASKS'),
      React.createElement('div', {style:{fontFamily:T.mono,fontSize:9,letterSpacing:'.24em',color:T.ink3}},
        `${open.length} OPEN`
      )
    ),
    React.createElement('div', {style:{display:'flex', flexDirection:'column'}},
      visible.length === 0
        ? React.createElement('div', {style:{
            padding:'12px', fontFamily:T.mono, fontSize:10, letterSpacing:'.18em',
            color:T.ink3, textTransform:'uppercase'
          }}, 'DROP A TASK · !task <thing>')
        : visible.map(t => React.createElement('div', {key:t.id, style:{
            padding:'7px 12px', display:'flex', alignItems:'center', gap:8,
            borderTop:`1px solid ${T.rule}`,
            opacity: t.done_at ? 0.78 : 1,
            transition:'opacity 200ms ease'
          }},
            checkbox(!!t.done_at),
            React.createElement('span', {style:{
              fontFamily:T.mono, fontSize:10, letterSpacing:'.06em',
              color: _chatColor(t.user_name || t.user_login || 'viewer'),
              flexShrink:0, fontWeight:600,
              maxWidth:80, overflow:'hidden', textOverflow:'ellipsis', whiteSpace:'nowrap'
            }}, t.user_name || t.user_login || 'viewer'),
            React.createElement('span', {style:{
              fontFamily:T.sans, fontSize:12, color:T.ink, lineHeight:1.25,
              overflow:'hidden', textOverflow:'ellipsis', whiteSpace:'nowrap', minWidth:0, flex:1
            }}, t.text)
          ))
    )
  );
}

// Thin status strip — current micro-task. Sits just above the ticker.
function TaskBar({task = 'VOICING TROMBONES BARS 32–48', cta = 'WORK ALONG · #COWORK'}) {
  return React.createElement('div', {style:{
    position:'absolute', left:0, right:0, bottom:36,
    height:32, display:'flex', alignItems:'stretch',
    background:'rgba(6,8,10,.78)', backdropFilter:'blur(8px)',
    borderTop:`1px solid ${T.rule}`,
    fontFamily:T.mono, fontSize:11, letterSpacing:'.18em',
    color:T.ink2, textTransform:'uppercase', zIndex:5
  }},
    React.createElement('div', {style:{
      flexShrink:0, padding:'0 18px', display:'flex', alignItems:'center', gap:8,
      borderRight:`1px solid ${T.rule2}`, color:T.accent, letterSpacing:'.32em', fontSize:10
    }},
      React.createElement('span', {style:{width:6,height:6,background:T.accent,boxShadow:`0 0 6px ${T.accentGlow}`}}),
      'TASK'
    ),
    React.createElement('div', {style:{flex:1, padding:'0 18px', display:'flex', alignItems:'center', color:T.ink, overflow:'hidden', whiteSpace:'nowrap', textOverflow:'ellipsis'}}, task),
    React.createElement('div', {style:{
      flexShrink:0, padding:'0 18px', display:'flex', alignItems:'center',
      borderLeft:`1px solid ${T.rule2}`, color:T.ink2, letterSpacing:'.28em', fontSize:10
    }}, cta)
  );
}

// transparent: when true, the outer Scene background is removed so OBS can
// composite gameplay/cam capture under the overlay. Use for game / two-cam / cam scenes.
function Scene({children, label, transparent=false}) {
  const cls = ['ovl-root', 'ovl-scan', transparent ? 'ovl-transparent' : ''].filter(Boolean).join(' ');
  return React.createElement('div', {className:cls, 'data-screen-label':label},
    !transparent && React.createElement('div', {className:'ovl-grid'}),
    !transparent && React.createElement('div', {className:'ovl-bluewash'}),
    !transparent && React.createElement('div', {className:'ovl-vignette'}),
    children,
    !transparent && React.createElement('div', {className:'ovl-noise'})
  );
}

// Expose
window.IVGO = {
  T, TICKER,
  Wordmark, WeeMan, LiveBadge, Chip, MetaLine, AudioBars,
  UtilityRail, CornerTrim, MediaPlaceholder,
  NowPlayingStrip, ChatPanel, GoalBar, Ticker, HeaderBar, Scene,
  WorkbenchStrip, SprintTimer, TaskBar, TaskList,
  bus: _bus,
  toast: _toast.toast,
};
