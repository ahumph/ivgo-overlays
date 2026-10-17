-- ivgo_obs_setup.lua — IVGO Overlay Installer for OBS
--
-- Install: OBS menu → Tools → Scripts → "+" → select this file.
-- Fill in the fields in the Scripts panel, then click "Create / Refresh Scenes".
-- Re-run any time to update details (new guest name, new countdown, etc.).
--
-- After the first run, open each compositing scene (Game, Camera, Two-Cam) and
-- right-click the placeholder capture sources to point them at your game window
-- and webcam(s).

obs = obslua

-- ── globals ───────────────────────────────────────────────────────────────────

local settings_ref = nil

-- ── platform helpers ──────────────────────────────────────────────────────────

local function is_windows()
    -- package.config's first character is the path separator
    return package.config:sub(1, 1) == "\\"
end

local function cam_type()
    return is_windows() and "dshow_input" or "av_capture_input_v2"
end

local function game_type()
    -- macOS has no game_capture; display_capture is the closest equivalent
    return is_windows() and "game_capture" or "display_capture"
end

-- ── URL helpers ───────────────────────────────────────────────────────────────

local function urlencode(str)
    return (str:gsub("([^%w%-%.%_%~])", function(c)
        return string.format("%%%02X", string.byte(c))
    end))
end

local function append_socket_url(url, socket_url)
    if not socket_url or socket_url == "" then return url end
    local sep = url:find("?") and "&" or "?"
    return url .. sep .. "socket_url=" .. urlencode(socket_url)
end

local function scenes_base_url()
    -- Overlay scenes are hosted publicly so console/Lightstream setups (which
    -- can't load file:// paths) work the same as local OBS setups.
    return "https://overlays.ivgorchestra.com"
end

-- ── git ──────────────────────────────────────────────────────────────────────

local function repo_dir()
    -- script_path() ends with a separator; strip it for `git -C` and normalise
    -- backslashes to forward slashes (git on Windows accepts either).
    return script_path():gsub("\\", "/"):gsub("/$", "")
end

local function run_git(args)
    -- Run `git <args>` in the repo dir. Returns ok, output (stdout+stderr).
    -- GIT_TERMINAL_PROMPT=0 makes git fail fast instead of blocking on a
    -- credential prompt (which would freeze OBS — io.popen has no stdin).
    -- io.popen on Windows already wraps in cmd.exe /c, so cmd-syntax is fine.
    local dir = repo_dir()
    local cmd
    if is_windows() then
        cmd = string.format(
            'set GIT_TERMINAL_PROMPT=0&& git -C "%s" %s 2>&1', dir, args)
    else
        cmd = string.format(
            'GIT_TERMINAL_PROMPT=0 git -C "%s" %s 2>&1', dir, args)
    end
    local handle = io.popen(cmd, "r")
    if not handle then return false, "could not run git" end
    local output = handle:read("*a") or ""
    local ok = handle:close()
    return ok and true or false, output
end

local function pull_latest()
    -- `--rebase` replays any local commits on top of the upstream branch so
    -- pulling doesn't fail when the user has committed work locally.
    -- `--autostash` shelves uncommitted edits before the rebase and restores
    -- them after, so iterating on scenes/*.html between streams Just Works.
    -- If the rebase hits a conflict, git leaves the repo mid-rebase — we
    -- surface that in the log and the user resolves with `git status` /
    -- `git rebase --abort` from a terminal.
    --
    -- Returns ok, changed. OBS keeps running the script it loaded until it's
    -- reloaded, so a pull that brought in new code can't use it yet.
    print("[IVGO] Pulling latest…")
    local _, before = run_git("rev-parse HEAD")
    local ok, output = run_git("pull --rebase --autostash")
    if output ~= "" then print("[IVGO] git pull:\n" .. output) end
    if not ok then
        print("[IVGO] git pull failed — check `git status` and resolve manually.")
        return false, false
    end
    local _, after = run_git("rev-parse HEAD")
    return true, before ~= after
end

-- ── OBS source / scene helpers ────────────────────────────────────────────────

local function get_scene_source(name)
    -- Return an owned source ref for the named scene, creating it if needed.
    -- Caller must obs.obs_source_release() the result.
    local source = obs.obs_get_source_by_name(name)
    if source then return source end
    local scene = obs.obs_scene_create(name)
    obs.obs_scene_release(scene)
    return obs.obs_get_source_by_name(name)
end

local function make_browser(name, url, width, height)
    -- Return owned browser source ref, creating or updating URL as needed.
    -- width/height default to the 1920x1080 main canvas.
    -- Caller must obs.obs_source_release() the result.
    local existing = obs.obs_get_source_by_name(name)
    if existing then
        local d = obs.obs_source_get_settings(existing)
        obs.obs_data_set_string(d, "url", url)
        obs.obs_source_update(existing, d)
        obs.obs_data_release(d)
        return existing
    end
    local d = obs.obs_data_create()
    obs.obs_data_set_string(d, "url",               url)
    obs.obs_data_set_int   (d, "width",             width or 1920)
    obs.obs_data_set_int   (d, "height",            height or 1080)
    obs.obs_data_set_bool  (d, "shutdown",          true)   -- pause when hidden
    obs.obs_data_set_bool  (d, "restart_when_active", true) -- re-run entrance anims
    obs.obs_data_set_int   (d, "fps",               30)
    local src = obs.obs_source_create("browser_source", name, d, nil)
    obs.obs_data_release(d)
    return src
end

local function make_media(name, local_file)
    -- Return owned FFmpeg Media Source ref, creating or updating settings.
    -- Used for the looping background videos on 01 Starting Soon / 06 Ending,
    -- so playback control (volume, restart, pause, hotkeys) lives in OBS
    -- rather than buried in an HTML <video>.
    local settings = {
        local_file          = local_file,
        is_local_file       = true,
        looping             = true,
        restart_on_activate = true,
        close_when_inactive = true,
    }
    local existing = obs.obs_get_source_by_name(name)
    if existing then
        local d = obs.obs_source_get_settings(existing)
        obs.obs_data_set_string(d, "local_file",          settings.local_file)
        obs.obs_data_set_bool  (d, "is_local_file",       settings.is_local_file)
        obs.obs_data_set_bool  (d, "looping",             settings.looping)
        obs.obs_data_set_bool  (d, "restart_on_activate", settings.restart_on_activate)
        obs.obs_data_set_bool  (d, "close_when_inactive", settings.close_when_inactive)
        obs.obs_source_update(existing, d)
        obs.obs_data_release(d)
        return existing
    end
    local d = obs.obs_data_create()
    obs.obs_data_set_string(d, "local_file",          settings.local_file)
    obs.obs_data_set_bool  (d, "is_local_file",       settings.is_local_file)
    obs.obs_data_set_bool  (d, "looping",             settings.looping)
    obs.obs_data_set_bool  (d, "restart_on_activate", settings.restart_on_activate)
    obs.obs_data_set_bool  (d, "close_when_inactive", settings.close_when_inactive)
    local src = obs.obs_source_create("ffmpeg_source", name, d, nil)
    obs.obs_data_release(d)
    return src
end

local function make_capture(name, kind)
    -- Return owned capture source ref (video or game), creating if needed.
    -- Created sources have no device selected — user configures via Properties.
    -- Caller must obs.obs_source_release() the result.
    local existing = obs.obs_get_source_by_name(name)
    if existing then return existing end
    local d = obs.obs_data_create()
    local src = obs.obs_source_create(kind, name, d, nil)
    obs.obs_data_release(d)
    return src
end

local function make_game_capture(name)
    -- Like make_capture but ensures the game's audio is routed through the
    -- source. capture_audio is updated on existing sources too, so re-running
    -- the installer turns audio on for sources created before this change.
    -- Volume is reset to -12 dBFS on every refresh — game audio at 0 dB clips
    -- against voice; -12 dB leaves headroom for chat toasts and the host mic.
    -- (display_capture on macOS ignores capture_audio; harmless to set.)
    -- Output only, not monitored: you already hear the game from the PC,
    -- so monitoring it too plays it twice. Set on existing sources as well,
    -- to undo the old Monitor and Output setting.
    local kind = game_type()
    local mul = 10 ^ (-12 / 20)   -- -12 dBFS as linear multiplier (~0.2512)
    local existing = obs.obs_get_source_by_name(name)
    if existing then
        local d = obs.obs_source_get_settings(existing)
        obs.obs_data_set_bool(d, "capture_audio", true)
        obs.obs_source_update(existing, d)
        obs.obs_data_release(d)
        obs.obs_source_set_volume(existing, mul)
        obs.obs_source_set_monitoring_type(existing, obs.OBS_MONITORING_TYPE_NONE)
        return existing
    end
    local d = obs.obs_data_create()
    obs.obs_data_set_bool(d, "capture_audio", true)
    local src = obs.obs_source_create(kind, name, d, nil)
    obs.obs_data_release(d)
    if src then
        obs.obs_source_set_volume(src, mul)
        obs.obs_source_set_monitoring_type(src, obs.OBS_MONITORING_TYPE_NONE)
    end
    return src
end

-- Browser sources don't route their own audio into OBS's mixer by default -
-- it plays out through the OS's default device instead, so it's silent on
-- stream and unheard by you unless you happen to be capturing desktop audio
-- too. `reroute_audio` makes the source its own mixer channel, and
-- MONITOR_AND_OUTPUT sends that channel to both the stream and your own
-- monitoring device. Any browser source that plays a sound needs both
-- settings to actually be heard by anyone - build_clip's already had this
-- (see configure_clip_source below); build_fire and build_card_pull need it
-- too, and didn't have it, so their alert sounds have been silent on stream
-- this whole time.
local function configure_audio_source(src)
    local d = obs.obs_source_get_settings(src)
    obs.obs_data_set_bool(d, "reroute_audio", true)
    obs.obs_source_update(src, d)
    obs.obs_data_release(d)
    obs.obs_source_set_monitoring_type(src, obs.OBS_MONITORING_TYPE_MONITOR_AND_OUTPUT)
end

-- A scene's main overlay plays the alert sounds. Give it a fader in
-- OBS's mixer (monitored, like configure_audio_source), reset to -12 dBFS
-- on every build, the same as the game capture: the alert clips peak near
-- 0 dB and drown the game at full volume. Without this its sound skips
-- OBS and goes straight to the desktop speakers, never reaching the
-- stream. In the mixer it's only heard while its scene is live.
local function configure_alert_overlay(src)
    configure_audio_source(src)
    obs.obs_source_set_volume(src, 10 ^ (-12 / 20))
end

-- For pages that play no sound (sound=0 or canvas=vertical in the URL):
-- the scene's main overlay plays each alert. Keep them out of OBS's audio
-- altogether, with no fader and no monitoring, so there's nothing to turn
-- on by mistake.
local function no_mixer_channel(src)
    local d = obs.obs_source_get_settings(src)
    obs.obs_data_set_bool(d, "reroute_audio", false)
    obs.obs_source_update(src, d)
    obs.obs_data_release(d)
    obs.obs_source_set_monitoring_type(src, obs.OBS_MONITORING_TYPE_NONE)
end

local function make_silent_browser(name, url)
    -- A helper page beside a scene's main overlay: no alerts, no sound.
    local src = make_browser(name, url)
    if src then no_mixer_channel(src) end
    return src
end

local function place(scene, source, x, y, w, h)
    -- Add source to scene (if not already present) then set position + bounds.
    -- Sources are added in call order, so call bottom-layer sources first.
    -- On subsequent runs the item already exists; only position/size are updated.
    local src_name = obs.obs_source_get_name(source)
    local item = nil

    local items = obs.obs_scene_enum_items(scene)
    if items then
        for _, it in ipairs(items) do
            if obs.obs_source_get_name(obs.obs_sceneitem_get_source(it)) == src_name then
                item = it
                break
            end
        end
        obs.sceneitem_list_release(items)
    end

    if item == nil then
        item = obs.obs_scene_add(scene, source)
    end

    if not item then
        print("[IVGO] Warning: could not place source '" .. src_name .. "'")
        return
    end

    local pos = obs.vec2()
    pos.x, pos.y = x, y
    obs.obs_sceneitem_set_pos(item, pos)

    local bounds = obs.vec2()
    bounds.x, bounds.y = w, h
    obs.obs_sceneitem_set_bounds_type(item, obs.OBS_BOUNDS_SCALE_INNER)
    obs.obs_sceneitem_set_bounds(item, bounds)

    return item
end

local function set_crop(item, top, bottom, left, right)
    -- Apply source-side crop to a scene item. Values are in source pixels
    -- (before bounding-box scaling), matching OBS's Edit Transform dialog.
    if not item then return end
    local crop = obs.obs_sceneitem_crop()
    crop.top    = top
    crop.bottom = bottom
    crop.left   = left
    crop.right  = right
    obs.obs_sceneitem_set_crop(item, crop)
end

local function ensure_group(scene, group_name, item_names)
    -- Best-effort: gather the named scene items and wrap them in an OBS group.
    -- Idempotent — if a group of this name already exists, no-op. If the Lua
    -- binding for obs_scene_insert_group misbehaves on this OBS version, the
    -- sources stay placed (just ungrouped) and the user can right-click →
    -- Group Selected Items in the Sources panel.
    local existing = obs.obs_get_source_by_name(group_name)
    if existing then
        obs.obs_source_release(existing)
        return
    end

    if not obs.obs_scene_insert_group then return end

    local order = {}
    for i, n in ipairs(item_names) do order[n] = i end

    local items = obs.obs_scene_enum_items(scene)
    if not items then return end

    local found = {}
    for _, it in ipairs(items) do
        local n = obs.obs_source_get_name(obs.obs_sceneitem_get_source(it))
        if order[n] then found[order[n]] = it end
    end

    local payload = {}
    for i = 1, #item_names do
        if not found[i] then
            obs.sceneitem_list_release(items)
            return
        end
        payload[#payload + 1] = found[i]
    end

    local ok, err = pcall(function()
        obs.obs_scene_insert_group(scene, group_name, payload)
    end)
    if not ok then
        print("[IVGO] Auto-group failed (" .. tostring(err) .. "); please group manually.")
    end

    obs.sceneitem_list_release(items)
end

local function ensure_crop_filter(source, name, top, bottom, left, right)
    -- Attach (or update) a Crop/Pad source filter. Runs at the source level
    -- so it executes BEFORE any subsequent filter (notably the chamfer mask),
    -- unlike scene-item crop which runs after filters.
    if not source then return end
    local existing = obs.obs_source_get_filter_by_name(source, name)
    if existing then
        local d = obs.obs_source_get_settings(existing)
        obs.obs_data_set_int (d, "top",    top)
        obs.obs_data_set_int (d, "bottom", bottom)
        obs.obs_data_set_int (d, "left",   left)
        obs.obs_data_set_int (d, "right",  right)
        obs.obs_data_set_bool(d, "relative", true)
        obs.obs_source_update(existing, d)
        obs.obs_data_release(d)
        obs.obs_source_release(existing)
        return
    end
    local d = obs.obs_data_create()
    obs.obs_data_set_int (d, "top",    top)
    obs.obs_data_set_int (d, "bottom", bottom)
    obs.obs_data_set_int (d, "left",   left)
    obs.obs_data_set_int (d, "right",  right)
    obs.obs_data_set_bool(d, "relative", true)
    local filter = obs.obs_source_create_private("crop_filter", name, d)
    obs.obs_data_release(d)
    if filter then
        obs.obs_source_filter_add(source, filter)
        obs.obs_source_release(filter)
    end
end

local function ensure_alpha_mask(source, name, image_path)
    -- Attach (or update) an "Image Mask/Blend" filter set to "Alpha Mask
    -- (Alpha Channel)" so the source is clipped to the mask PNG's opaque
    -- pixels. Stretches the mask to the post-filter source dimensions so
    -- the chamfered shape scales with the cropped keyboard band rather
    -- than the original Pianoteq window. Idempotent.
    if not source then return end
    local existing = obs.obs_source_get_filter_by_name(source, name)
    if existing then
        local d = obs.obs_source_get_settings(existing)
        obs.obs_data_set_string(d, "image_path", image_path)
        obs.obs_data_set_string(d, "type", "mask_alpha_filter.effect")
        obs.obs_data_set_bool  (d, "stretch", true)
        obs.obs_source_update(existing, d)
        obs.obs_data_release(d)
        obs.obs_source_release(existing)
        return
    end
    local d = obs.obs_data_create()
    obs.obs_data_set_string(d, "type", "mask_alpha_filter.effect")
    obs.obs_data_set_string(d, "image_path", image_path)
    obs.obs_data_set_bool  (d, "stretch", true)
    local filter = obs.obs_source_create_private("mask_filter", name, d)
    obs.obs_data_release(d)
    if filter then
        obs.obs_source_filter_add(source, filter)
        obs.obs_source_release(filter)
    end
end

-- ── scene builders ────────────────────────────────────────────────────────────

-- Now-Playing overlay: a single "IVGO: Now Playing" browser source that
-- references the standalone scene served by tools/now-playing-watch.ps1
-- over HTTP. Adding it to multiple OBS scenes creates separate scene-items
-- sharing the same source — so visibility/transform is per-scene but the
-- HTML, label-handle, and !np / !playing listener are configured once.
--
-- Requires the watch script to be running:
--   powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tools\now-playing-watch.ps1
-- If the script isn't running OBS shows an empty source (no crash) — restart
-- the script and refresh the source's cache to recover.
-- Fire overlay (chat !fine reward): a single "IVGO: Fire Overlay" browser
-- source layered on the topmost row of every main scene. Same source
-- referenced across scenes — one WebSocket to Phoenix, one Twitch IRC
-- connection, one configuration. Listens for the `overlay.fire` event on
-- overlay:events; payload from ivgo-ex once the !fine command lands a
-- successful Ostis deduction.
--
-- toasts=0 / egg_off=1 / raid_bg_off=1 are required, not cosmetic: the
-- auto-wire block in ivgo-shared.js mounts toasts, the alrighty/raid egg and
-- the WeeMan raid backdrop on *every* page that connects to the bus. Without
-- these, a raid plays WeeManRaid.mp4 twice with doubled audio — once from the
-- scene's chrome overlay and once from here.
local function build_fire(scene, base, socket_url)
    local url = base .. "/fire?toasts=0&egg_off=1&raid_bg_off=1"
    local src = make_browser("IVGO: Fire Overlay", append_socket_url(url, socket_url))
    if src then
        configure_audio_source(src)
        place(scene, src, 0, 0, 1920, 1080)
        obs.obs_source_release(src)
    end
end

-- Trading-card pull reveal (chat !pull reward): a single "IVGO: Card Pull"
-- browser source layered on every main scene, same pattern as build_fire
-- immediately above. Listens for the `card.pull` event on overlay:events
-- (ivgo-ex Trading Cards feature); payload lands after a successful !pull.
-- Pops bottom-left as a WeeMan card back, flips to reveal, holds ~6s.
--
-- toasts=0/egg_off=1/raid_bg_off=1 for the same reason build_fire needs
-- them: this scene loads ivgo-shared.js too, which auto-mounts toasts, the
-- video egg and the raid backdrop on every page that connects to the bus.
-- Without these, stacking it on a scene that already has its own chrome
-- mounting those elements doubles them.
local function build_card_pull(scene, base, socket_url)
    local url = base .. "/card-pull?toasts=0&egg_off=1&raid_bg_off=1"
    local src = make_browser("IVGO: Card Pull", append_socket_url(url, socket_url))
    if src then
        configure_audio_source(src)
        place(scene, src, 0, 0, 1920, 1080)
        obs.obs_source_release(src)
    end
end

-- Clip player (chat clip links + mod shoutouts): a single "IVGO: Clip Player"
-- browser source layered just under the fire overlay on every main scene.
-- Reads chat over its own anonymous IRC socket and plays a centered panel.
-- Viewer links only play IVGO's own clips; `!so <user>` from a mod plays that
-- streamer's featured clip. Raid alerts interrupt it. Disable per-scene with
-- clip_off=1, or repo-wide via the "Clip player" checkbox in script settings.
--
-- Reads its two settings off settings_ref directly rather than taking them as
-- arguments, so the call site in each scene builder stays a one-liner like
-- build_fire's.
-- Browser sources don't put their audio in the mixer by default — it goes out
-- through the OBS process, so a clip is silent on stream unless you happen to
-- capture desktop audio. `reroute_audio` makes the source its own mixer
-- channel, and MONITOR_AND_OUTPUT sends it to both the stream and your
-- headphones. This is the "enable audio + monitor it" pair you'd otherwise set
-- by hand on every fresh install.
--
-- The two false flags matter because this source is stateful in a way the
-- other overlays aren't: it holds an IRC connection plus the cooldown and
-- already-played bookkeeping. Letting OBS shut it down when hidden, or refresh
-- it on scene activation, would drop a playing clip and wipe every cooldown —
-- so a clip could be spammed again right after a scene change.
--
-- Re-applied to existing sources on every rebuild, since make_browser's update
-- path only touches the URL.
--
-- Shared by every chat-driven source that holds live state. Also forces a
-- fresh page load on each rebuild: OBS only reloads a browser source when its
-- URL changes, and these deliberately have restart_when_active off, so an HTML
-- edit with no URL change would otherwise keep serving the cached old page and
-- "Create / Refresh Scenes" would appear to do nothing.
local function configure_stateful_source(src)
    local d = obs.obs_source_get_settings(src)
    obs.obs_data_set_bool(d, "shutdown",            false)
    obs.obs_data_set_bool(d, "restart_when_active", false)
    obs.obs_source_update(src, d)
    obs.obs_data_release(d)

    local ph = obs.obs_source_get_proc_handler(src)
    local cd = obs.calldata_create()
    obs.proc_handler_call(ph, "refreshnocache", cd)
    obs.calldata_destroy(cd)
end

local function configure_clip_source(src)
    configure_stateful_source(src)
    configure_audio_source(src)
end

local function build_clip(scene, base, socket_url)
    if not settings_ref then return end
    if not obs.obs_data_get_bool(settings_ref, "clip_player") then return end

    local channel = obs.obs_data_get_string(settings_ref, "twitch_channel")
    local size    = obs.obs_data_get_string(settings_ref, "clip_size")
    local url = base .. "/clip?toasts=0&egg_off=1&raid_bg_off=1"
    if channel and channel ~= "" then
        url = url .. "&channel=" .. string.lower(channel)
    end
    if size and size ~= "" then
        url = url .. "&clip_size=" .. size
    end
    local src = make_browser("IVGO: Clip Player", append_socket_url(url, socket_url))
    if src then
        configure_clip_source(src)
        place(scene, src, 0, 0, 1920, 1080)
        obs.obs_source_release(src)
    end
end

-- WeeMan avatars (chat !weeman): viewer-summoned WeeMen walking along the
-- bottom of the stream for 15 minutes, tinted with the viewer's chat colour,
-- with their chat messages appearing in speech bubbles above them.
--
-- Layered above the scene chrome so they walk on top of the ticker rather than
-- behind it, but below the clip player and fire overlay so an alert always
-- wins the foreground.
--
-- Stateful for the same reasons as the clip player: an IRC connection plus the
-- current cast and their timers.
local function build_weeman(scene, base, socket_url)
    if not settings_ref then return end
    if not obs.obs_data_get_bool(settings_ref, "weeman_avatars") then return end

    local channel = obs.obs_data_get_string(settings_ref, "twitch_channel")
    local mins    = obs.obs_data_get_int(settings_ref, "weeman_mins")
    local url = base .. "/weeman?toasts=0&egg_off=1&raid_bg_off=1"
    if channel and channel ~= "" then
        url = url .. "&channel=" .. string.lower(channel)
    end
    if mins and mins > 0 then
        url = url .. "&weeman_mins=" .. tostring(mins)
    end
    if not obs.obs_data_get_bool(settings_ref, "weeman_bubbles") then
        url = url .. "&weeman_bubbles=0"
    end

    local src = make_browser("IVGO: WeeMan Avatars", append_socket_url(url, socket_url))
    if src then
        configure_stateful_source(src)
        place(scene, src, 0, 0, 1920, 1080)
        obs.obs_source_release(src)
    end
end

-- Redaction overlay (chat !redact / !declassify): black-bars a random one of
-- 4 screen sectors, server-picked, so every connected source (and a reload of
-- one) agrees on what's covered. No settings of its own - the page just
-- listens on the shared overlay:events bus, same as WeeMan.
local function build_redact(scene, base, socket_url)
    if not settings_ref then return end
    if not obs.obs_data_get_bool(settings_ref, "redact_overlay") then return end

    -- The scene's main overlay plays the alerts: no second copy here.
    local url = base .. "/redact?toasts=0&egg_off=1&raid_bg_off=1&sound=0"
    local src = make_silent_browser("IVGO: Redact", append_socket_url(url, socket_url))
    if src then
        configure_stateful_source(src)
        place(scene, src, 0, 0, 1920, 1080)
        obs.obs_source_release(src)
    end
end

-- Resonance Mode (chat !resonance): the only source here that also opens its
-- own obs-websocket connection (separate from the socket_url Phoenix
-- connection above) to duck/boost real OBS input volumes and, optionally,
-- toggle a pre-made visual filter - see priv/static/overlays/scenes/
-- 16-resonance.html in ivgo-ex for what it does with these. Music/duck source
-- names are per-setup, so they come from the fields below rather than being
-- guessed.
local function build_resonance(scene, base, socket_url)
    if not settings_ref then return end
    if not obs.obs_data_get_bool(settings_ref, "resonance_overlay") then return end

    local music_source  = obs.obs_data_get_string(settings_ref, "resonance_music_source")
    local duck_sources  = obs.obs_data_get_string(settings_ref, "resonance_duck_sources")
    local boost_db      = obs.obs_data_get_double(settings_ref, "resonance_boost_db")
    local duck_db        = obs.obs_data_get_double(settings_ref, "resonance_duck_db")
    local filter_source = obs.obs_data_get_string(settings_ref, "resonance_filter_source")
    local filter_name   = obs.obs_data_get_string(settings_ref, "resonance_filter_name")

    -- The scene's main overlay plays the alerts: no second copy here.
    local url = base .. "/resonance?toasts=0&egg_off=1&raid_bg_off=1&sound=0"
    local sep = "&"
    if music_source and music_source ~= "" then
        url = url .. sep .. "music_source=" .. urlencode(music_source); sep = "&"
    end
    if duck_sources and duck_sources ~= "" then
        url = url .. sep .. "duck_sources=" .. urlencode(duck_sources); sep = "&"
    end
    if boost_db and boost_db ~= 0 then
        url = url .. sep .. "boost_db=" .. tostring(boost_db); sep = "&"
    end
    if duck_db and duck_db ~= 0 then
        url = url .. sep .. "duck_db=" .. tostring(duck_db); sep = "&"
    end
    if filter_source and filter_source ~= "" then
        url = url .. sep .. "filter_source=" .. urlencode(filter_source); sep = "&"
    end
    if filter_name and filter_name ~= "" then
        url = url .. sep .. "filter_name=" .. urlencode(filter_name); sep = "&"
    end

    local src = make_silent_browser("IVGO: Resonance", append_socket_url(url, socket_url))
    if src then
        configure_stateful_source(src)
        place(scene, src, 0, 0, 1920, 1080)
        obs.obs_source_release(src)
    end
end

-- !info for every scene except 07 Arranging, which has its own: there the
-- command slides the ON THE DESK piece card up, driven by ivgo-ex. This is the
-- same gesture and label handle, listing the chat commands that work on this
-- scene instead. Adding it to Arranging would slide two panels up at once.
--
-- The row list is built from the features that are actually switched on, so
-- the card never advertises a command that would do nothing.
local function build_help(scene, base, socket_url, np_base)
    if not settings_ref then return end
    if not obs.obs_data_get_bool(settings_ref, "help_card") then return end

    local items = {}
    if np_base and np_base ~= "" then table.insert(items, "np") end
    if obs.obs_data_get_bool(settings_ref, "clip_player") then table.insert(items, "clip") end
    if obs.obs_data_get_bool(settings_ref, "weeman_avatars") then table.insert(items, "weeman") end
    -- !fine costs Ostis, which only exists when the Phoenix backend is wired up.
    if socket_url and socket_url ~= "" then table.insert(items, "fine") end
    -- Only the feature-gated rows go in the URL. The always-present ones
    -- (!concerts, !socials, !discord, !x, !info — answered by Nightbot, or by
    -- the card itself) are STATIC_ITEMS inside 13-help.html, so editing them
    -- needs a page refresh rather than a scene rebuild.

    local channel = obs.obs_data_get_string(settings_ref, "twitch_channel")
    local url = base .. "/help?toasts=0&egg_off=1&raid_bg_off=1"
    url = url .. "&help_items=" .. table.concat(items, ",")
    if channel and channel ~= "" then
        url = url .. "&channel=" .. string.lower(channel)
    end

    local src = make_browser("IVGO: Commands Card", append_socket_url(url, socket_url))
    if src then
        configure_stateful_source(src)
        place(scene, src, 0, 0, 1920, 1080)
        obs.obs_source_release(src)
    end
end

local function build_now_playing(scene, np_base, y_offset)
    if not np_base or np_base == "" then return end
    local src = make_browser("IVGO: Now Playing", np_base .. "/scenes/09-now-playing.html?debug=0")
    if src then
        -- y_offset shifts the entire 1920×1080 source down by that many px in
        -- this particular scene, so the !PLAYING label lands further down. The
        -- source content (label at ~top:154) is near the top of the canvas, so
        -- the shifted-off bottom is empty space and clips cleanly.
        place(scene, src, 0, y_offset or 0, 1920, 1080)
        obs.obs_source_release(src)
    end
end

local function build_starting_soon(base, countdown_mins, socket_url, np_base)
    local url = base .. "/starting-soon?mic=1"
    if countdown_mins and countdown_mins > 0 then
        url = url .. "&mins=" .. tostring(countdown_mins) .. "&secs=0"
    end
    url = append_socket_url(url, socket_url)

    local scene_src = get_scene_source("IVGO · 01 Starting Soon")
    local scene     = obs.obs_scene_from_source(scene_src)

    -- Background video — added first so it sits at the bottom of the layer
    -- stack, below the chrome browser source.
    local video = make_media("IVGO: Starting Soon Video", repo_dir() .. "/media/buts.mkv")
    if video then
        place(scene, video, 0, 0, 1920, 1080)
        obs.obs_source_release(video)
    end

    local src = make_browser("IVGO: Starting Soon", url)
    if src then
        configure_alert_overlay(src)
        place(scene, src, 0, 0, 1920, 1080)
        obs.obs_source_release(src)
    end
    build_now_playing(scene, np_base)
    build_help(scene, base, socket_url, np_base)
    build_weeman(scene, base, socket_url)
    build_clip(scene, base, socket_url)
    build_fire(scene, base, socket_url)
    build_card_pull(scene, base, socket_url)
    build_redact(scene, base, socket_url)
    build_resonance(scene, base, socket_url)
    obs.obs_source_release(scene_src)
end

local function build_game(base, socket_url, np_base)
    -- Layer order bottom → top:
    --   1. Game Capture         x:0,    y:0,   w:1920, h:1080 (fit to screen)
    --   2. Host Camera          x:1570, y:64,  w:340,  h:191  (chamfered cutout)
    --   3. 02-game.html         header + ticker chrome (transparent)
    --   4. 02-cam-outline.html  chamfered cam border frame (transparent)
    --   5. 02-chat.html         chat panel bottom-right (transparent)

    local scene_src = get_scene_source("IVGO · 02 Game")
    local scene     = obs.obs_scene_from_source(scene_src)

    local game = make_game_capture("IVGO: Game Capture")
    if game then
        place(scene, game, 0, 0, 1920, 1080)
        obs.obs_source_release(game)
    end

    local cam = make_capture("IVGO: Host Camera", cam_type())
    if cam then
        place(scene, cam, 1570, 64, 340, 191)
        obs.obs_source_release(cam)
    end

    local overlay = make_browser("IVGO: Game Overlay",  append_socket_url(base .. "/game?mic=1", socket_url))
    if overlay then
        configure_alert_overlay(overlay)
        place(scene, overlay, 0, 0, 1920, 1080)
        obs.obs_source_release(overlay)
    end

    local cam_frame = make_silent_browser("IVGO: Cam Outline", append_socket_url(base .. "/game-cam-outline?toasts=0&sound=0", socket_url))
    if cam_frame then
        place(scene, cam_frame, 0, 0, 1920, 1080)
        obs.obs_source_release(cam_frame)
    end

    local chat = make_silent_browser("IVGO: Chat",      append_socket_url(base .. "/game-chat?toasts=0&sound=0", socket_url))
    if chat then
        place(scene, chat, 0, 0, 1920, 1080)
        obs.obs_source_release(chat)
    end

    -- 02 Game's cam PiP sits top-right where the !PLAYING label normally
    -- lives — shift the now-playing source down 110px so the label clears it.
    build_now_playing(scene, np_base, 110)
    build_help(scene, base, socket_url, np_base)
    build_weeman(scene, base, socket_url)
    build_clip(scene, base, socket_url)
    build_fire(scene, base, socket_url)
    build_card_pull(scene, base, socket_url)
    build_redact(scene, base, socket_url)
    build_resonance(scene, base, socket_url)
    obs.obs_source_release(scene_src)
end

local function build_camera(base, host, host_role, socket_url, np_base)
    -- Layer order bottom → top:
    --   1. Host Camera  x:320, y:180, w:1280, h:720  (centred in frame)
    --   2. 03-camera.html chrome + nameplate (transparent)
    --   3. 03-chat.html chat panel, right margin beside the cam (transparent)

    local scene_src = get_scene_source("IVGO · 03 Camera")
    local scene     = obs.obs_scene_from_source(scene_src)

    local cam = make_capture("IVGO: Host Camera", cam_type())
    if cam then
        place(scene, cam, 320, 180, 1280, 720)
        obs.obs_source_release(cam)
    end

    local cam_params = "host=" .. urlencode(host) .. "&hostRole=" .. urlencode(host_role) .. "&mic=1"
    local overlay = make_browser("IVGO: Camera Overlay", append_socket_url(base .. "/camera?" .. cam_params, socket_url))
    if overlay then
        configure_alert_overlay(overlay)
        place(scene, overlay, 0, 0, 1920, 1080)
        obs.obs_source_release(overlay)
    end

    local chat = make_silent_browser("IVGO: Camera Chat", append_socket_url(base .. "/camera-chat?toasts=0&sound=0", socket_url))
    if chat then
        place(scene, chat, 0, 0, 1920, 1080)
        obs.obs_source_release(chat)
    end

    build_now_playing(scene, np_base)
    build_help(scene, base, socket_url, np_base)
    build_weeman(scene, base, socket_url)
    build_clip(scene, base, socket_url)
    build_fire(scene, base, socket_url)
    build_card_pull(scene, base, socket_url)
    build_redact(scene, base, socket_url)
    build_resonance(scene, base, socket_url)
    obs.obs_source_release(scene_src)
end

local function build_brb(base, socket_url, np_base)
    local scene_src = get_scene_source("IVGO · 04 Be Right Back")
    local scene     = obs.obs_scene_from_source(scene_src)
    local src       = make_browser("IVGO: BRB", append_socket_url(base .. "/brb?mic=1", socket_url))
    if src then
        place(scene, src, 0, 0, 1920, 1080)
        -- The page's own about.mkv <video> carries its audio, baked into the
        -- browser source rather than a separate OBS media source. Browser
        -- sources don't route their own audio into OBS's mixer by default,
        -- so reroute_audio is needed for the stream to hear it at all - no
        -- monitoring type change here, unlike build_fire/build_card_pull.
        local d = obs.obs_source_get_settings(src)
        obs.obs_data_set_bool(d, "reroute_audio", true)
        obs.obs_source_update(src, d)
        obs.obs_data_release(d)
        obs.obs_source_release(src)
    end
    build_now_playing(scene, np_base)
    build_help(scene, base, socket_url, np_base)
    build_weeman(scene, base, socket_url)
    build_clip(scene, base, socket_url)
    build_fire(scene, base, socket_url)
    build_card_pull(scene, base, socket_url)
    build_redact(scene, base, socket_url)
    build_resonance(scene, base, socket_url)
    obs.obs_source_release(scene_src)
end

local function build_two_cam(base, host, host_role, guest, g_role, topic, socket_url, np_base)
    -- Layer order bottom → top:
    --   1. Host Camera   x:88,   y:72, w:904, h:858  (left slot)
    --   2. Guest Camera  x:1010, y:72, w:904, h:858  (right slot)
    --   3. 05-two-cam.html chrome + nameplates + topic strip (transparent)

    local scene_src = get_scene_source("IVGO · 05 Two Camera")
    local scene     = obs.obs_scene_from_source(scene_src)

    local host_cam = make_capture("IVGO: Host Camera",  cam_type())
    if host_cam then
        place(scene, host_cam, 88, 72, 904, 858)
        obs.obs_source_release(host_cam)
    end

    local guest_cam = make_capture("IVGO: Guest Camera", cam_type())
    if guest_cam then
        place(scene, guest_cam, 1010, 72, 904, 858)
        obs.obs_source_release(guest_cam)
    end

    local params = "host="       .. urlencode(host)      ..
                   "&hostRole="  .. urlencode(host_role)  ..
                   "&guest="     .. urlencode(guest)      ..
                   "&guestRole=" .. urlencode(g_role)     ..
                   "&topic="     .. urlencode(topic)     ..
                   "&mic=1"
    local overlay = make_browser("IVGO: Two-Cam Overlay", append_socket_url(base .. "/two-camera?" .. params, socket_url))
    if overlay then
        configure_alert_overlay(overlay)
        place(scene, overlay, 0, 0, 1920, 1080)
        obs.obs_source_release(overlay)
    end

    build_now_playing(scene, np_base)
    build_help(scene, base, socket_url, np_base)
    build_weeman(scene, base, socket_url)
    build_clip(scene, base, socket_url)
    build_fire(scene, base, socket_url)
    build_card_pull(scene, base, socket_url)
    build_redact(scene, base, socket_url)
    build_resonance(scene, base, socket_url)
    obs.obs_source_release(scene_src)
end

-- Remote feed for an interview (a VDO.Ninja view link, say): a browser
-- source whose URL is pasted into its Properties once. Unlike make_browser,
-- an existing one keeps that URL on every re-run. Its audio goes to the
-- mixer and stays running while hidden, so the call never drops on a
-- scene switch.
local function make_remote_feed(name)
    local existing = obs.obs_get_source_by_name(name)
    if existing then return existing end
    local d = obs.obs_data_create()
    obs.obs_data_set_string(d, "url",           "")
    obs.obs_data_set_int   (d, "width",         1920)
    obs.obs_data_set_int   (d, "height",        1080)
    obs.obs_data_set_bool  (d, "reroute_audio", true)
    obs.obs_data_set_bool  (d, "shutdown",      false)
    local src = obs.obs_source_create("browser_source", name, d, nil)
    obs.obs_data_release(d)
    if src then
        obs.obs_source_set_monitoring_type(src, obs.OBS_MONITORING_TYPE_MONITOR_AND_OUTPUT)
    end
    return src
end

-- The preroll / BRB video: a YouTube link plays in a browser source using
-- YouTube's embed player; anything else is a local file for a media
-- source. Either loops, restarts each time its scene comes on, and its
-- sound goes to the mixer. Returns nil when no video is set.
local function youtube_id(link)
    return link:match("[?&]v=([%w_-]+)") or link:match("youtu%.be/([%w_-]+)")
        or link:match("/embed/([%w_-]+)") or link:match("/shorts/([%w_-]+)")
end

local function make_preroll(video)
    if not video or video == "" then return nil end
    local id = youtube_id(video)
    if id then
        local url = "https://www.youtube.com/embed/" .. id ..
            "?autoplay=1&loop=1&playlist=" .. id .. "&controls=0&rel=0&modestbranding=1"
        local src = make_browser("IVGO: Preroll (YouTube)", url)
        if src then configure_audio_source(src) end
        return src
    end
    return make_media("IVGO: Preroll (File)", video)
end

-- Source rectangles {x, y, w, h} for the interview layouts. They must
-- match LAYOUTS in ivgo-ex's priv/static/overlays/scenes/17-interview.html,
-- which draws the frames and nameplates around them.
local INTERVIEW_LAYOUTS = {
    starting = {
        preroll     = {24, 74, 1360, 765},
    },
    welcome = {
        interviewer = {14, 66, 940, 529},
        player      = {966, 66, 940, 529},
    },
    brb = {
        preroll     = {24, 74, 1360, 765},
    },
    talk = {
        game        = {14, 607, 756, 425},
        player      = {518, 885, 240, 135},
        interviewer = {14, 66, 940, 529},
        guest       = {966, 66, 940, 529},
    },
    game = {
        game        = {10, 66, 1440, 810},
        player      = {1116, 682, 320, 180},
        interviewer = {1462, 330, 448, 252},
        guest       = {1462, 66, 448, 252},
    },
}

local function build_interview_scene(scene_name, layout, back, overlay, preroll, base, socket_url, np_base)
    -- Layer order bottom -> top, each only where the layout has a place
    -- for it (INTERVIEW_LAYOUTS):
    --   1. 17-interview.html?layer=back   branded background
    --   2. Preroll video
    --   3. Game Capture
    --   4. Host Camera (the player)
    --   5. Interviewer and Interview Guest (remote feeds)
    --   6. 17-interview.html   frames, nameplates, chat, donations, chrome
    local scene_src = get_scene_source(scene_name)
    local scene     = obs.obs_scene_from_source(scene_src)
    local r         = INTERVIEW_LAYOUTS[layout]

    local function put(source, rect)
        if source and rect then place(scene, source, rect[1], rect[2], rect[3], rect[4]) end
    end

    place(scene, back, 0, 0, 1920, 1080)
    put(preroll, r.preroll)

    if r.game then
        local game = make_game_capture("IVGO: Game Capture")
        put(game, r.game)
        if game then obs.obs_source_release(game) end
    end

    if r.player then
        local cam = make_capture("IVGO: Host Camera", cam_type())
        put(cam, r.player)
        if cam then obs.obs_source_release(cam) end
    end

    if r.interviewer then
        local interviewer = make_remote_feed("IVGO: Interviewer")
        put(interviewer, r.interviewer)
        if interviewer then obs.obs_source_release(interviewer) end
    end

    if r.guest then
        local guest = make_remote_feed("IVGO: Interview Guest")
        put(guest, r.guest)
        if guest then obs.obs_source_release(guest) end
    end

    place(scene, overlay, 0, 0, 1920, 1080)

    build_help(scene, base, socket_url, np_base)
    build_weeman(scene, base, socket_url)
    build_clip(scene, base, socket_url)
    build_fire(scene, base, socket_url)
    build_card_pull(scene, base, socket_url)
    build_redact(scene, base, socket_url)
    build_resonance(scene, base, socket_url)
    obs.obs_source_release(scene_src)
end

-- ── Vertical interview scenes (Aitum Vertical) ───────────────────────────────
-- Aitum Vertical adds a second, 1080x1920 canvas to OBS (OBS 31.1 or later).
-- These scenes go on it, reuse the same cams, game capture and preroll as
-- the main interview scenes, and get their own 1080x1920 overlay
-- (17-interview.html?canvas=vertical). Each main scene is linked to its
-- vertical one, so switching the main scene switches the vertical too.

local VERTICAL_CANVAS = "Aitum Vertical"

-- Source rectangles {x, y, w, h} on the 1080x1920 canvas. They must match
-- V_LAYOUTS in ivgo-ex's 17-interview.html, times 1.5 (V_SCALE).
local VERTICAL_LAYOUTS = {
    starting = {
        preroll     = {18, 93, 1044, 588},
    },
    welcome = {
        interviewer = {18, 93, 1044, 690},
        player      = {18, 795, 1044, 690},
    },
    talk = {
        interviewer = {18, 93, 1044, 690},
        guest       = {18, 795, 1044, 690},
        game        = {18, 1497, 720, 405},
        player      = {486, 1755, 240, 135},
    },
    brb = {
        preroll     = {18, 93, 1044, 588},
    },
}

-- Main scene -> the vertical scene it switches to. Talk serves Game too.
local VERTICAL_LINKS = {
    {"IVGO · 17 Interview · Starting Soon", "IVGO · 17 Interview · Starting Soon (Vertical)", "starting"},
    {"IVGO · 17 Interview · Welcome",       "IVGO · 17 Interview · Welcome (Vertical)",       "welcome"},
    {"IVGO · 17 Interview · Talk",          "IVGO · 17 Interview · Talk (Vertical)",          "talk"},
    {"IVGO · 17 Interview · Game",          "IVGO · 17 Interview · Talk (Vertical)",          "talk"},
    {"IVGO · 17 Interview · Be Right Back", "IVGO · 17 Interview · Be Right Back (Vertical)", "brb"},
}

-- Scenes this script made on the vertical canvas. Aitum Vertical only
-- takes in a canvas's scenes when the scene collection loads, so until
-- OBS restarts nothing else holds them: keep a reference for the session.
local vertical_scene_refs = {}

local function get_vertical_scene(canvas, name)
    -- Return the scene (borrowed) and an owned source ref, creating the
    -- scene on the canvas if needed. Caller releases the source.
    local src = obs.obs_canvas_get_source_by_name(canvas, name)
    if src then return obs.obs_scene_from_source(src), src end
    local scene = obs.obs_canvas_scene_create(canvas, name)
    if not scene then return nil, nil end
    table.insert(vertical_scene_refs, scene)
    return scene, obs.obs_source_get_ref(obs.obs_scene_get_source(scene))
end

local function canvas_size(canvas)
    local ok, w, h = pcall(function()
        local ovi = obs.obs_video_info()
        if obs.obs_canvas_get_video_info(canvas, ovi) then return ovi.base_width, ovi.base_height end
    end)
    if ok and w and h then return w, h end
    return 1080, 1920
end

local function place_fill(scene, source, rect)
    -- Like place(), but fill the box and crop the overflow, so a 16:9 cam
    -- fills a taller frame instead of sitting in it letterboxed.
    if not (source and rect) then return end
    local item = place(scene, source, rect[1], rect[2], rect[3], rect[4])
    if not item then return end
    obs.obs_sceneitem_set_bounds_type(item, obs.OBS_BOUNDS_SCALE_OUTER)
    if obs.obs_sceneitem_set_bounds_crop then obs.obs_sceneitem_set_bounds_crop(item, true) end
end

local function link_vertical_scene(main_name, vertical_name, width, height)
    -- Aitum Vertical keeps each link on the main scene's settings, as a
    -- "canvas" list of {width, height, scene}; it switches the vertical
    -- canvas whose size matches when the main scene changes. Replace any
    -- link for this canvas size and keep links for other canvases.
    local src = obs.obs_get_source_by_name(main_name)
    if not src then return end
    local settings = obs.obs_source_get_settings(src)
    local links = obs.obs_data_array_create()
    local old = obs.obs_data_get_array(settings, "canvas")
    if old then
        for i = 0, obs.obs_data_array_count(old) - 1 do
            local link = obs.obs_data_array_item(old, i)
            if obs.obs_data_get_int(link, "width") ~= width or obs.obs_data_get_int(link, "height") ~= height then
                obs.obs_data_array_push_back(links, link)
            end
            obs.obs_data_release(link)
        end
        obs.obs_data_array_release(old)
    end
    local link = obs.obs_data_create()
    obs.obs_data_set_int(link, "width", width)
    obs.obs_data_set_int(link, "height", height)
    obs.obs_data_set_string(link, "scene", vertical_name)
    obs.obs_data_array_push_back(links, link)
    obs.obs_data_release(link)
    obs.obs_data_set_array(settings, "canvas", links)
    obs.obs_data_array_release(links)
    obs.obs_data_release(settings)
    obs.obs_source_release(src)
end

local function open_vertical_canvas()
    -- Return Aitum Vertical's canvas (owned; caller releases it) and its
    -- size, or nil when OBS or the plugin can't give us one.
    if not obs.obs_get_canvas_by_name then
        print("[IVGO] Vertical scenes need OBS 31.1 or later. Skipped.")
        return nil
    end
    local canvas = obs.obs_get_canvas_by_name(VERTICAL_CANVAS)
    if not canvas then
        print("[IVGO] Vertical scenes need the Aitum Vertical plugin (aitum.tv/vertical). Skipped.")
        return nil
    end
    local width, height = canvas_size(canvas)
    if width ~= 1080 or height ~= 1920 then
        print("[IVGO] Warning: the vertical canvas is " .. width .. "x" .. height ..
              ". The vertical scenes are laid out for 1080x1920.")
    end
    return canvas, width, height
end

local function make_vertical_overlay(name, url)
    -- A 1080x1920 browser source for a vertical scene. The page plays no
    -- sound (canvas=vertical), so it has no fader either.
    local src = make_browser(name, url, 1080, 1920)
    if src then no_mixer_channel(src) end
    return src
end

local function build_vertical_interview(base, params, preroll, socket_url)
    local canvas, width, height = open_vertical_canvas()
    if not canvas then return end

    local back = make_browser("IVGO: Interview Background (Vertical)",
        base .. "/interview?layer=back&canvas=vertical", 1080, 1920)
    local overlay = make_browser("IVGO: Interview Overlay (Vertical)",
        append_socket_url(base .. "/interview?" .. params .. "&canvas=vertical", socket_url), 1080, 1920)
    if not (back and overlay) then
        print("[IVGO] Warning: could not create the vertical interview overlay sources")
        obs.obs_canvas_release(canvas)
        return
    end
    -- Same as the main overlay: keep running, read the live scene. It
    -- plays no sound and has no fader (no_mixer_channel).
    configure_stateful_source(overlay)
    local d = obs.obs_source_get_settings(overlay)
    obs.obs_data_set_int(d, "webpage_control_level", 2)
    obs.obs_source_update(overlay, d)
    obs.obs_data_release(d)
    no_mixer_channel(overlay)

    local made = {}
    for _, link in ipairs(VERTICAL_LINKS) do
        local vertical_name, layout = link[2], link[3]
        if not made[vertical_name] then
            made[vertical_name] = true
            local scene, scene_src = get_vertical_scene(canvas, vertical_name)
            if scene then
                local r = VERTICAL_LAYOUTS[layout]
                place(scene, back, 0, 0, 1080, 1920)
                place_fill(scene, preroll, r.preroll)
                if r.game then
                    local game = make_game_capture("IVGO: Game Capture")
                    place_fill(scene, game, r.game)
                    if game then obs.obs_source_release(game) end
                end
                if r.player then
                    local cam = make_capture("IVGO: Host Camera", cam_type())
                    place_fill(scene, cam, r.player)
                    if cam then obs.obs_source_release(cam) end
                end
                if r.interviewer then
                    local feed = make_remote_feed("IVGO: Interviewer")
                    place_fill(scene, feed, r.interviewer)
                    if feed then obs.obs_source_release(feed) end
                end
                if r.guest then
                    local feed = make_remote_feed("IVGO: Interview Guest")
                    place_fill(scene, feed, r.guest)
                    if feed then obs.obs_source_release(feed) end
                end
                place(scene, overlay, 0, 0, 1080, 1920)
                obs.obs_source_release(scene_src)
            else
                print("[IVGO] Warning: could not create '" .. vertical_name .. "' on the vertical canvas")
            end
        end
        link_vertical_scene(link[1], vertical_name, width, height)
    end

    obs.obs_source_release(back)
    obs.obs_source_release(overlay)
    obs.obs_canvas_release(canvas)
    print("[IVGO] Vertical interview scenes built and linked. If they don't show in " ..
          "the Aitum Vertical dock yet, restart OBS.")
end

-- ── Vertical main scenes (Aitum Vertical) ────────────────────────────────────
-- 01 Starting Soon, 02 Game, 03 Camera, 04 Be Right Back and 06 Ending on
-- the vertical canvas, each with its page's ?canvas=vertical overlay and
-- linked to its main scene. The same cam, game capture and background
-- videos are reused. The alert, !info and now playing sources stay on the
-- main canvas only.

-- Source rectangles {x, y, w, h} on the 1080x1920 canvas. They must match
-- V_GAME and V_CAM in ivgo-ex's 02-game.html and 03-camera.html, times 1.5.
-- The vertical game fills a box taller than 16:9, cropped to its centre.
local VERTICAL_MAIN = {
    game   = { cam = {0, 81, 1080, 795}, game = {0, 879, 1080, 987} },
    camera = { cam = {18, 93, 1044, 1320} },
}

local function build_vertical_main(base, host, host_role, countdown_mins, socket_url)
    local canvas, width, height = open_vertical_canvas()
    if not canvas then return end

    -- No egg or raid video: they're sized for 1920x1080.
    local function url(path, extra)
        return append_socket_url(base .. path .. "?canvas=vertical&egg_off=1&raid_bg_off=1" .. (extra or ""), socket_url)
    end

    local function scene_for(main_name, build)
        local vertical_name = main_name .. " (Vertical)"
        local scene, scene_src = get_vertical_scene(canvas, vertical_name)
        if not scene then
            print("[IVGO] Warning: could not create '" .. vertical_name .. "' on the vertical canvas")
            return
        end
        build(scene)
        obs.obs_source_release(scene_src)
        link_vertical_scene(main_name, vertical_name, width, height)
    end

    local function add(scene, source, rect, fill)
        if not source then return end
        if fill then place_fill(scene, source, rect) else place(scene, source, rect[1], rect[2], rect[3], rect[4]) end
        obs.obs_source_release(source)
    end

    local full = {0, 0, 1080, 1920}

    local countdown = ""
    if countdown_mins and countdown_mins > 0 then
        countdown = "&mins=" .. tostring(countdown_mins) .. "&secs=0"
    end
    scene_for("IVGO · 01 Starting Soon", function(scene)
        add(scene, make_media("IVGO: Starting Soon Video", repo_dir() .. "/media/buts.mkv"), full, true)
        add(scene, make_vertical_overlay("IVGO: Starting Soon (Vertical)", url("/starting-soon", countdown)), full)
    end)

    scene_for("IVGO · 02 Game", function(scene)
        add(scene, make_game_capture("IVGO: Game Capture"), VERTICAL_MAIN.game.game, true)
        add(scene, make_capture("IVGO: Host Camera", cam_type()), VERTICAL_MAIN.game.cam, true)
        local overlay = make_vertical_overlay("IVGO: Game Overlay (Vertical)", url("/game"))
        if overlay then
            -- A fader at -12 dBFS like the main Game Overlay, but not
            -- monitored. The page itself plays nothing (canvas=vertical):
            -- OBS mixes audio once for both canvases, so the main Game
            -- Overlay's alerts already reach the vertical stream.
            local d = obs.obs_source_get_settings(overlay)
            obs.obs_data_set_bool(d, "reroute_audio", true)
            obs.obs_source_update(overlay, d)
            obs.obs_data_release(d)
            obs.obs_source_set_monitoring_type(overlay, obs.OBS_MONITORING_TYPE_NONE)
            obs.obs_source_set_volume(overlay, 10 ^ (-12 / 20))
        end
        add(scene, overlay, full)
    end)

    scene_for("IVGO · 03 Camera", function(scene)
        add(scene, make_capture("IVGO: Host Camera", cam_type()), VERTICAL_MAIN.camera.cam, true)
        add(scene, make_vertical_overlay("IVGO: Camera Overlay (Vertical)",
            url("/camera", "&host=" .. urlencode(host) .. "&hostRole=" .. urlencode(host_role))), full)
    end)

    scene_for("IVGO · 04 Be Right Back", function(scene)
        add(scene, make_vertical_overlay("IVGO: BRB (Vertical)", url("/brb")), full)
    end)

    scene_for("IVGO · 06 Ending", function(scene)
        add(scene, make_media("IVGO: Ending Video", repo_dir() .. "/media/tetris.webm"), full, true)
        add(scene, make_vertical_overlay("IVGO: Ending (Vertical)", url("/ending")), full)
    end)

    obs.obs_canvas_release(canvas)
    print("[IVGO] Vertical scenes built and linked. If they don't show in " ..
          "the Aitum Vertical dock yet, restart OBS.")
end

local function build_interview(base, interviewer, interviewer_role, guest, g_role, guest_credit, player, preroll_video, countdown_mins, socket_url, np_base, vertical)
    -- Five scenes, one overlay: starting soon, welcome, the interview (the
    -- conversation large), the interview with the game large, and be right
    -- back. The same overlay and background sources sit in all of them, so
    -- the chat panel never reloads and alerts play once; the overlay reads
    -- the live scene's name and draws the matching layout. Bind a hotkey to
    -- each scene in Settings > Hotkeys to switch.
    local params = "interviewer="      .. urlencode(interviewer)      ..
                   "&interviewerRole=" .. urlencode(interviewer_role) ..
                   "&guest="           .. urlencode(guest)            ..
                   "&guestRole="       .. urlencode(g_role)           ..
                   "&guestCredit="     .. urlencode(guest_credit)     ..
                   "&player="          .. urlencode(player)           ..
                   "&mins="            .. tostring(countdown_mins)    ..
                   "&mic=1&egg_off=1"

    local back = make_browser("IVGO: Interview Background", base .. "/interview?layer=back")
    local overlay = make_browser("IVGO: Interview Overlay", append_socket_url(base .. "/interview?" .. params, socket_url))
    if not (back and overlay) then
        print("[IVGO] Warning: could not create the interview overlay sources")
        return
    end

    -- Keep running across the switch, and let the page read which scene
    -- is live (page permissions: read access to user information).
    configure_stateful_source(overlay)
    local d = obs.obs_source_get_settings(overlay)
    obs.obs_data_set_int(d, "webpage_control_level", 2)
    obs.obs_source_update(overlay, d)
    obs.obs_data_release(d)
    -- It keeps running when an interview scene isn't live, so outside the
    -- mixer its alert sounds would play on the desktop speakers all stream.
    configure_alert_overlay(overlay)

    local preroll = make_preroll(preroll_video)

    build_interview_scene("IVGO · 17 Interview · Starting Soon", "starting", back, overlay, preroll, base, socket_url, np_base)
    build_interview_scene("IVGO · 17 Interview · Welcome",       "welcome",  back, overlay, preroll, base, socket_url, np_base)
    build_interview_scene("IVGO · 17 Interview · Talk",          "talk",     back, overlay, preroll, base, socket_url, np_base)
    build_interview_scene("IVGO · 17 Interview · Game",          "game",     back, overlay, preroll, base, socket_url, np_base)
    build_interview_scene("IVGO · 17 Interview · Be Right Back", "brb",      back, overlay, preroll, base, socket_url, np_base)

    if vertical then build_vertical_interview(base, params, preroll, socket_url) end

    if preroll then obs.obs_source_release(preroll) end
    obs.obs_source_release(back)
    obs.obs_source_release(overlay)
end

local function build_ending(base, socket_url, np_base)
    local scene_src = get_scene_source("IVGO · 06 Ending")
    local scene     = obs.obs_scene_from_source(scene_src)

    -- Background video — added first so it sits at the bottom of the layer
    -- stack, below the chrome browser source.
    local video = make_media("IVGO: Ending Video", repo_dir() .. "/media/tetris.webm")
    if video then
        place(scene, video, 0, 0, 1920, 1080)
        obs.obs_source_release(video)
    end

    local src = make_browser("IVGO: Ending", append_socket_url(base .. "/ending?mic=1", socket_url))
    if src then
        configure_alert_overlay(src)
        place(scene, src, 0, 0, 1920, 1080)
        obs.obs_source_release(src)
    end
    build_now_playing(scene, np_base)
    build_help(scene, base, socket_url, np_base)
    build_weeman(scene, base, socket_url)
    build_clip(scene, base, socket_url)
    build_fire(scene, base, socket_url)
    build_card_pull(scene, base, socket_url)
    build_redact(scene, base, socket_url)
    build_resonance(scene, base, socket_url)
    obs.obs_source_release(scene_src)
end

local function build_arranging(base, piece, collection, sprints_total, focus_mins, break_mins, socket_url, np_base)
    -- Layer order bottom → top:
    --   1. Screen Capture (display)  x:0,    y:0,    w:1920, h:1080  (notation / DAW)
    --   2. Host Camera               x:10,   y:64,   w:282,  h:158   (small PiP top-left,
    --                                 10px from viewport left, 10px below header)
    --   3. Pianoteq Window           x:266,  y:842,  w:1260, h:192   (live keyboard,
    --                                 right-side: 10px gap to chat's left edge)
    --   4. 08-keyboard-frame.html    chamfered outline around the Pianoteq capture.
    --                                 Hide both #3 and #4 (or group them) to remove
    --                                 the keyboard from the scene without losing the
    --                                 placement.
    --   5. 07-arranging.html         chrome: header, task list, pomo timer, ticker,
    --                                 and the sliding info panel — sits above the
    --                                 keyboard so the panel covers it when !info fires.
    --                                 The "ON THE DESK" workbench strip is hidden by
    --                                 default and only surfaces for 10s when chat
    --                                 fires !info (or a mod changes !piece / !from).
    --   6. 07-cam-outline.html       cam border frame + "AT THE DESK" badge
    --   7. 07-chat.html              chat panel (right column)

    local scene_src = get_scene_source("IVGO · 07 Arranging")
    local scene     = obs.obs_scene_from_source(scene_src)

    -- Arranging streams use notation software, not games — screen capture on
    -- both platforms. The OBS source ID differs: monitor_capture on Windows,
    -- display_capture on macOS. Using the wrong ID creates an unconfigured
    -- source that shows "Display Device not connected or not available".
    local screen_kind = is_windows() and "monitor_capture" or "display_capture"
    local screen = make_capture("IVGO: Arranging Screen", screen_kind)
    if screen then
        place(scene, screen, 0, 0, 1920, 1080)
        obs.obs_source_release(screen)
    end

    local cam = make_capture("IVGO: Host Camera", cam_type())
    if cam then
        place(scene, cam, 10, 64, 282, 158)
        obs.obs_source_release(cam)
    end

    -- Pianoteq window capture + chamfered frame overlay. If the user has
    -- already wrapped them in an "IVGO: Keyboard" group (manually, since
    -- OBS's Lua group API is unreliable), place items into the group's
    -- internal scene instead of the parent — that way re-runs of the
    -- installer don't drop fresh top-level copies alongside the grouped
    -- ones. Group items use coords relative to the group's transform;
    -- when the group is at (0,0,1920,1080) they're identical to scene coords.
    local kb_scene = scene
    local kb_group_src = obs.obs_get_source_by_name("IVGO: Keyboard")
    if kb_group_src then
        local g = obs.obs_group_from_source(kb_group_src)
        if g then kb_scene = g end
        obs.obs_source_release(kb_group_src)
    end

    local kb = make_capture("IVGO: Pianoteq", "window_capture")
    if kb then
        -- Crop is applied as a source filter (not scene-item crop) so it
        -- runs BEFORE the chamfer mask in the filter chain. Otherwise the
        -- mask would clip the full Pianoteq window and the cropped keyboard
        -- band would never intersect the chamfered region.
        --   top=825 drops the GUI panels above the keyboard,
        --   bottom=2 / left=35 / right=41 are small bezel trims.
        ensure_crop_filter(kb, "IVGO Keyboard Crop", 825, 2, 35, 41)
        -- Mask the cropped keyboard band to the chamfered panel shape.
        local mask_path = repo_dir() .. "/media/keyboard-mask.png"
        ensure_alpha_mask(kb, "IVGO Chamfer Mask", mask_path)
        place(kb_scene, kb, 266, 842, 1260, 192)
        obs.obs_source_release(kb)
    end

    local kb_frame = make_silent_browser("IVGO: Arranging Keyboard Frame", base .. "/keyboard-frame?toasts=0&sound=0")
    if kb_frame then
        place(kb_scene, kb_frame, 0, 0, 1920, 1080)
        obs.obs_source_release(kb_frame)
    end

    -- Best-effort auto-group when there's no existing group. Falls back to a
    -- log message if obs_scene_insert_group isn't behaving in this OBS version,
    -- in which case the user does the 3-click manual group once and subsequent
    -- runs land in the kb_scene branch above.
    if kb_scene == scene then
        ensure_group(scene, "IVGO: Keyboard", { "IVGO: Pianoteq", "IVGO: Arranging Keyboard Frame" })
    end

    -- Video easter egg: place 10px right of the host cam at the cam's top edge,
    -- locking height to the cam's 158px so the clip and the cam read as a pair.
    local params = "piece="       .. urlencode(piece)      ..
                   "&collection=" .. urlencode(collection) ..
                   "&total="      .. urlencode(tostring(sprints_total)) ..
                   "&focus_mins=" .. urlencode(tostring(focus_mins)) ..
                   "&break_mins=" .. urlencode(tostring(break_mins)) ..
                   "&toasts_anchor=above-chat-right" ..
                   "&egg_top=64&egg_left=302&egg_h=158" ..
                   "&mic=1"

    local overlay = make_browser("IVGO: Arranging Overlay", append_socket_url(base .. "/arranging?" .. params, socket_url))
    if overlay then
        configure_alert_overlay(overlay)
        place(scene, overlay, 0, 0, 1920, 1080)
        obs.obs_source_release(overlay)
    end

    local cam_frame = make_silent_browser("IVGO: Arranging Cam Outline", append_socket_url(base .. "/arranging-cam-outline?toasts=0&sound=0", socket_url))
    if cam_frame then
        place(scene, cam_frame, 0, 0, 1920, 1080)
        obs.obs_source_release(cam_frame)
    end

    local chat = make_silent_browser("IVGO: Arranging Chat", append_socket_url(base .. "/arranging-chat?toasts=0&sound=0", socket_url))
    if chat then
        place(scene, chat, 0, 0, 1920, 1080)
        obs.obs_source_release(chat)
    end

    build_now_playing(scene, np_base)
    -- No build_help here on purpose: this scene's own !info slides the ON THE
    -- DESK card up from the same spot, so the two would move at once.
    build_weeman(scene, base, socket_url)
    build_clip(scene, base, socket_url)
    build_fire(scene, base, socket_url)
    build_card_pull(scene, base, socket_url)
    build_redact(scene, base, socket_url)
    build_resonance(scene, base, socket_url)
    obs.obs_source_release(scene_src)
end

local function build_all()
    local base       = scenes_base_url()
    local host       = obs.obs_data_get_string(settings_ref, "host_name")
    local host_role  = obs.obs_data_get_string(settings_ref, "host_role")
    local guest      = obs.obs_data_get_string(settings_ref, "guest_name")
    local g_role     = obs.obs_data_get_string(settings_ref, "guest_role")
    local topic      = obs.obs_data_get_string(settings_ref, "topic")
    local countdown_mins = obs.obs_data_get_int   (settings_ref, "countdown_mins")
    local socket_url     = obs.obs_data_get_string(settings_ref, "socket_url")
    local np_base        = obs.obs_data_get_string(settings_ref, "now_playing_http_base")
    local interviewer      = obs.obs_data_get_string(settings_ref, "interviewer_name")
    local interviewer_role = obs.obs_data_get_string(settings_ref, "interviewer_role")
    local guest_credit     = obs.obs_data_get_string(settings_ref, "guest_credit")
    local preroll_video    = obs.obs_data_get_string(settings_ref, "preroll_video")

    local arr_piece         = obs.obs_data_get_string(settings_ref, "arr_piece")
    local arr_collection    = obs.obs_data_get_string(settings_ref, "arr_collection")
    local arr_sprints_total = obs.obs_data_get_int   (settings_ref, "arr_sprints_total")
    local arr_focus_mins    = obs.obs_data_get_int   (settings_ref, "arr_focus_mins")
    local arr_break_mins    = obs.obs_data_get_int   (settings_ref, "arr_break_mins")

    print("[IVGO] Building scenes from: " .. base)

    build_starting_soon(base, countdown_mins, socket_url, np_base)
    build_game(base, socket_url, np_base)
    build_camera(base, host, host_role, socket_url, np_base)
    build_brb(base, socket_url, np_base)
    build_two_cam(base, host, host_role, guest, g_role, topic, socket_url, np_base)
    -- Only for interview shows: off unless ticked, so other streamers'
    -- scene lists don't fill up with scenes they'll never use.
    local interviews = obs.obs_data_get_bool(settings_ref, "interview_scenes")
    if interviews then
        build_interview(base, interviewer, interviewer_role, guest, g_role, guest_credit, host, preroll_video, countdown_mins, socket_url, np_base,
                        obs.obs_data_get_bool(settings_ref, "vertical_interview"))
    elseif obs.obs_data_get_bool(settings_ref, "vertical_interview") then
        print("[IVGO] Vertical interview scenes need Interview scenes ticked too. Skipped.")
    end
    build_ending(base, socket_url, np_base)
    -- After build_ending, so every main scene exists to link to.
    if obs.obs_data_get_bool(settings_ref, "vertical_scenes") then
        build_vertical_main(base, host, host_role, countdown_mins, socket_url)
    end
    build_arranging(base, arr_piece, arr_collection, arr_sprints_total, arr_focus_mins, arr_break_mins, socket_url, np_base)

    print("[IVGO] Done — " .. (interviews and 12 or 7) .. " scenes created / refreshed.")
end

-- ── Now-Playing watcher auto-start ────────────────────────────────────────────
-- Spawns tools/now-playing-watch.ps1 detached on script load so the
-- localhost:7779 HTTP server is up before any browser source resolves the
-- Now Playing URL. The PowerShell wrapper TCP-probes port 7779 first and
-- short-circuits if something is already listening (re-running this script,
-- a manual launch, or a leftover process from a previous OBS session).

local function start_now_playing_watcher()
    local script_dir = script_path()  -- includes trailing slash on Windows
    local ps1 = script_dir .. "tools\\now-playing-watch.ps1"
    -- Single-line PowerShell: try-connect to 127.0.0.1:7779, only Start-Process
    -- the watcher if the connect fails (i.e. nobody is listening).
    -- `start /B ""` detaches from the OBS process so it survives OBS exit only
    -- as long as the spawned watcher itself stays alive — Start-Process gives
    -- the watcher its own process group, so closing OBS does NOT kill it.
    local cmd = string.format(
        'start /B "" powershell.exe -NoProfile -WindowStyle Hidden -Command ' ..
        '"try { $c=New-Object Net.Sockets.TcpClient; $c.Connect(\'127.0.0.1\',7779); $c.Close() } ' ..
        'catch { Start-Process powershell.exe -WindowStyle Hidden -ArgumentList ' ..
        '\'-NoProfile\',\'-ExecutionPolicy\',\'Bypass\',\'-WindowStyle\',\'Hidden\',\'-File\',\'%s\' }"',
        ps1
    )
    print("[IVGO] Ensuring Now Playing watcher is running: " .. ps1)
    os.execute(cmd)
end

local function maybe_start_now_playing_watcher()
    if not settings_ref then return end
    if not obs.obs_data_get_bool(settings_ref, "auto_start_np") then
        print("[IVGO] Now Playing auto-start disabled — skipping watcher launch.")
        return
    end
    -- Empty np_base = user explicitly disabled the overlay; don't spawn.
    local np_base = obs.obs_data_get_string(settings_ref, "now_playing_http_base")
    if np_base == nil or np_base == "" then
        print("[IVGO] Now-Playing HTTP base is blank — skipping watcher launch.")
        return
    end
    start_now_playing_watcher()
end

-- ── OBS script hooks ──────────────────────────────────────────────────────────

function script_description()
    return [[<b>IVGO Overlay Installer</b><br><br>
Builds all seven IVGO scenes in OBS. Fill in the fields below then click
<b>Create / Refresh Scenes</b>.<br><br>
Safe to re-run: updates existing scenes rather than duplicating them.<br><br>
After the first run, right-click the placeholder capture sources in the
Game, Camera, Two-Cam, and Arranging scenes to point them at your webcam,
game window, and notation-software display.]]
end

-- ── obs-websocket auto-enable ────────────────────────────────────────────────
-- The Mic/Aux mute indicator in the overlay connects to OBS via obs-websocket
-- (built into OBS 28+). For non-technical users we write a sane default config
-- (port 4455, no auth) on first launch if the user hasn't already configured
-- one. If a config already exists with the server enabled, we leave it alone
-- so we don't clobber a password they set deliberately.

local function obs_ws_config_path()
    local sep = is_windows() and "\\" or "/"
    local base
    if is_windows() then
        base = os.getenv("APPDATA")
        if not base then return nil end
        return base .. "\\obs-studio\\plugin_config\\obs-websocket\\config.json"
    elseif package.config:sub(1,1) == "/" then
        local home = os.getenv("HOME")
        if not home then return nil end
        -- macOS uses ~/Library/Application Support; Linux uses ~/.config.
        -- Probe for the macOS path first; if its parent OBS dir doesn't exist
        -- fall back to the Linux path.
        local mac = home .. "/Library/Application Support/obs-studio/plugin_config/obs-websocket/config.json"
        local mac_obs_dir = home .. "/Library/Application Support/obs-studio"
        local f = io.open(mac_obs_dir, "r")
        if f then f:close(); return mac end
        return home .. "/.config/obs-studio/plugin_config/obs-websocket/config.json"
    end
    return nil
end

local function ensure_dir(path)
    -- Create parent directories as needed. Path is the FILE path, not the dir.
    local dir = path:match("(.*)[/\\][^/\\]+$")
    if not dir then return end
    if is_windows() then
        os.execute(string.format('if not exist "%s" mkdir "%s"', dir, dir))
    else
        os.execute(string.format('mkdir -p "%s"', dir))
    end
end

local function read_file(path)
    local f = io.open(path, "r")
    if not f then return nil end
    local s = f:read("*a")
    f:close()
    return s
end

local function write_file(path, contents)
    local f = io.open(path, "w")
    if not f then return false end
    f:write(contents)
    f:close()
    return true
end

local function ensure_obs_websocket_enabled()
    local path = obs_ws_config_path()
    if not path then
        print("[IVGO] obs-websocket: could not resolve config path for this OS — skipping auto-enable.")
        return
    end
    local existing = read_file(path)
    if existing then
        -- Cheap "is the server already enabled?" probe. We avoid pulling in a
        -- full JSON parser; obs-websocket writes a stable key order so a
        -- substring check is good enough for the common case.
        if existing:find('"server_enabled"%s*:%s*true') then
            print("[IVGO] obs-websocket already enabled — leaving config alone.")
            return
        end
        -- Server present but disabled: don't overwrite (user may have a
        -- password set). Tell them what to do instead.
        print("[IVGO] obs-websocket is installed but disabled. Enable it via OBS → Tools → WebSocket Server Settings, set port 4455 and clear the password (or set one and put it in the URL — see README).")
        return
    end

    -- No config at all → write defaults.
    ensure_dir(path)
    local default_json = table.concat({
        '{',
        '    "alerts_enabled": false,',
        '    "auth_required": false,',
        '    "first_load": false,',
        '    "server_enabled": true,',
        '    "server_password": "",',
        '    "server_port": 4455',
        '}'
    }, "\n")
    if write_file(path, default_json) then
        print("[IVGO] obs-websocket: wrote default config (port 4455, no auth) to " .. path .. " — RESTART OBS ONCE to activate.")
    else
        print("[IVGO] obs-websocket: failed to write config to " .. path)
    end
end

-- ── Stop-clip hotkey ──────────────────────────────────────────────────────
-- Panic button for a clip you want off screen *now* without typing !clipstop
-- in chat — which is awkward mid-game. Reloads the Clip Player page, which
-- kills playback and audio instantly.
--
-- The blunt instrument is deliberate: OBS Lua has no clean channel into a
-- running browser source, and a reload needs no extra plumbing. The cost is
-- that per-viewer cooldowns and the already-played list reset, so the clip
-- that just got pulled could be re-posted immediately. `!clipstop` is the
-- better everyday lever; this is the one you hit when chat isn't an option.
--
-- No key is bound by default — set one in OBS → Settings → Hotkeys, under
-- "IVGO: Stop clip player".
local stop_clip_hotkey_id = obs.OBS_INVALID_HOTKEY_ID

local function stop_clip_now()
    local src = obs.obs_get_source_by_name("IVGO: Clip Player")
    if not src then
        print("[IVGO] Stop clip: no 'IVGO: Clip Player' source found.")
        return
    end
    local ph = obs.obs_source_get_proc_handler(src)
    local cd = obs.calldata_create()
    obs.proc_handler_call(ph, "refreshnocache", cd)
    obs.calldata_destroy(cd)
    obs.obs_source_release(src)
    print("[IVGO] Stop clip: Clip Player reloaded.")
end

function script_load(settings)
    settings_ref = settings
    ensure_obs_websocket_enabled()
    maybe_start_now_playing_watcher()

    stop_clip_hotkey_id = obs.obs_hotkey_register_frontend(
        "ivgo_stop_clip", "IVGO: Stop clip player",
        function(pressed) if pressed then stop_clip_now() end end)
    local hk = obs.obs_data_get_array(settings, "ivgo_stop_clip_hotkey")
    obs.obs_hotkey_load(stop_clip_hotkey_id, hk)
    obs.obs_data_array_release(hk)
end

-- Persist the user's chosen key across OBS restarts.
function script_save(settings)
    local hk = obs.obs_hotkey_save(stop_clip_hotkey_id)
    obs.obs_data_set_array(settings, "ivgo_stop_clip_hotkey", hk)
    obs.obs_data_array_release(hk)
end

function script_defaults(settings)
    obs.obs_data_set_default_string(settings, "host_name",  "ADAM HUMPHREYS")
    obs.obs_data_set_default_string(settings, "host_role",  "ARTISTIC DIRECTOR")
    obs.obs_data_set_default_string(settings, "guest_name", "GUEST NAME")
    obs.obs_data_set_default_string(settings, "guest_role", "ROLE")
    obs.obs_data_set_default_string(settings, "topic",      "WHY VIDEO GAME MUSIC DESERVES A FULL ORCHESTRA")
    obs.obs_data_set_default_bool  (settings, "interview_scenes", false)
    obs.obs_data_set_default_bool  (settings, "vertical_interview", false)
    obs.obs_data_set_default_bool  (settings, "vertical_scenes", false)
    obs.obs_data_set_default_string(settings, "interviewer_name", "PHOEBE")
    obs.obs_data_set_default_string(settings, "interviewer_role", "HOST")
    obs.obs_data_set_default_string(settings, "guest_credit",     "")
    obs.obs_data_set_default_string(settings, "preroll_video",    "")
    obs.obs_data_set_default_int   (settings, "countdown_mins", 5)
    obs.obs_data_set_default_string(settings, "socket_url", "wss://ivgorchestra.fly.dev/overlay")
    obs.obs_data_set_default_string(settings, "now_playing_http_base", "http://localhost:7779")
    obs.obs_data_set_default_bool  (settings, "auto_start_np", true)
    obs.obs_data_set_default_string(settings, "twitch_channel", "irishvideogameorchestra")
    obs.obs_data_set_default_bool  (settings, "clip_player", true)
    obs.obs_data_set_default_string(settings, "clip_size", "large")
    obs.obs_data_set_default_bool  (settings, "weeman_avatars", true)
    obs.obs_data_set_default_bool  (settings, "weeman_bubbles", true)
    obs.obs_data_set_default_int   (settings, "weeman_mins", 15)
    obs.obs_data_set_default_bool  (settings, "redact_overlay", true)
    obs.obs_data_set_default_bool  (settings, "resonance_overlay", true)
    obs.obs_data_set_default_double(settings, "resonance_boost_db", 6)
    obs.obs_data_set_default_double(settings, "resonance_duck_db", -18)
    obs.obs_data_set_default_bool  (settings, "help_card", true)

    obs.obs_data_set_default_string(settings, "arr_piece",         "AERITH'S SUITE")
    obs.obs_data_set_default_string(settings, "arr_collection",    "FINAL FANTASY VII REBIRTH")
    obs.obs_data_set_default_int   (settings, "arr_sprints_total",  4)
    obs.obs_data_set_default_int   (settings, "arr_focus_mins",    25)
    obs.obs_data_set_default_int   (settings, "arr_break_mins",     5)
end

-- OBS lays each setting out as label | field, so the long labels here left
-- the fields squeezed into a narrow column. These put the label on its
-- own full-width line above the field instead, the way the hints below
-- each field already show.
local function label_above(props, name, text)
    obs.obs_properties_add_text(props, "_" .. name .. "_label", "<b>" .. text .. "</b>", obs.OBS_TEXT_INFO)
end

local function add_text(props, name, text)
    label_above(props, name, text)
    return obs.obs_properties_add_text(props, name, "", obs.OBS_TEXT_DEFAULT)
end

local function add_int(props, name, text, min, max, step)
    label_above(props, name, text)
    return obs.obs_properties_add_int(props, name, "", min, max, step)
end

local function add_float(props, name, text, min, max, step)
    label_above(props, name, text)
    return obs.obs_properties_add_float(props, name, "", min, max, step)
end

local function add_list(props, name, text, type, format)
    label_above(props, name, text)
    return obs.obs_properties_add_list(props, name, "", type, format)
end

function script_properties()
    local props = obs.obs_properties_create()

    add_text(props, "host_name", "Host name")
    obs.obs_properties_add_text(props, "_host_name_hint",
        "Shown in the header bar and camera nameplate.",
        obs.OBS_TEXT_INFO)
    add_text(props, "host_role", "Host role")
    obs.obs_properties_add_text(props, "_host_role_hint",
        "Shown below your name.",
        obs.OBS_TEXT_INFO)
    add_text(props, "guest_name", "Guest name")
    obs.obs_properties_add_text(props, "_guest_name_hint",
        "Two-Camera and Interview scenes.",
        obs.OBS_TEXT_INFO)
    add_text(props, "guest_role", "Guest role")
    obs.obs_properties_add_text(props, "_guest_role_hint",
        "Two-Camera and Interview scenes.",
        obs.OBS_TEXT_INFO)
    obs.obs_properties_add_bool(props, "vertical_scenes", "Vertical scenes (needs the Aitum Vertical plugin)")
    obs.obs_properties_add_text(props, "_vertical_scenes_hint",
        "Also builds Starting Soon, Game, Camera, Be Right Back and Ending on Aitum Vertical's 1080x1920 canvas, and links each to its main scene so switching the main scene switches the vertical one. Needs OBS 31.1 or later. Restart OBS after the first build so Aitum lists the new scenes.",
        obs.OBS_TEXT_INFO)
    obs.obs_properties_add_bool(props, "interview_scenes", "Interview scenes (IVGO · 17 Interview ...)")
    obs.obs_properties_add_text(props, "_interview_scenes_hint",
        "Only for interview shows: starting soon, welcome, talk, game and be right back, with remote feeds for the interviewer and guest. Leave unticked otherwise. Unticking doesn't delete scenes already made; remove those in OBS.",
        obs.OBS_TEXT_INFO)
    obs.obs_properties_add_bool(props, "vertical_interview", "Vertical interview scenes (needs the Aitum Vertical plugin)")
    obs.obs_properties_add_text(props, "_vertical_interview_hint",
        "Also builds the interview scenes on Aitum Vertical's 1080x1920 canvas, and links each to its main scene so switching the main scene switches the vertical one. Talk is used for both Talk and Game. Needs OBS 31.1 or later and Interview scenes ticked. Restart OBS after the first build so Aitum lists the new scenes.",
        obs.OBS_TEXT_INFO)
    add_text(props, "interviewer_name", "Interviewer name")
    add_text(props, "interviewer_role", "Interviewer role")
    obs.obs_properties_add_text(props, "_interviewer_hint",
        "Interview scenes only. The guest name and role above are used there too, and your host name labels the game.",
        obs.OBS_TEXT_INFO)
    add_text(props, "guest_credit", "Guest credit")
    obs.obs_properties_add_text(props, "_guest_credit_hint",
        "Under the guest's name on the interview's starting-soon and be-right-back scenes, e.g. Resident Evil / Leon S. Kennedy.",
        obs.OBS_TEXT_INFO)
    add_text(props, "preroll_video", "Interview preroll video")
    obs.obs_properties_add_text(props, "_preroll_hint",
        "A YouTube link, or the full path of a video file. Plays on the interview's starting-soon and be-right-back scenes.",
        obs.OBS_TEXT_INFO)
    add_text(props, "topic", "Topic")
    obs.obs_properties_add_text(props, "_topic_hint",
        "Shown in the topic strip of the Two-Camera scene.",
        obs.OBS_TEXT_INFO)
    add_int(props, "countdown_mins", "Countdown (mins)", 0, 120, 1)
    obs.obs_properties_add_text(props, "_countdown_hint",
        "Minutes the 01 Starting Soon countdown starts at when the scene loads. 0 to hide. Can also be overridden per-source via ?mins=<n> on the browser-source URL.",
        obs.OBS_TEXT_INFO)
    add_text(props, "socket_url", "Socket URL")
    obs.obs_properties_add_text(props, "_socket_hint",
        "Local: ws://localhost:4000/overlay   Live: wss://ivgorchestra.fly.dev/overlay",
        obs.OBS_TEXT_INFO)

    add_text(props, "now_playing_http_base", "Now-Playing HTTP base")
    obs.obs_properties_add_text(props, "_now_playing_hint",
        "URL of the SMTC watch script's HTTP server. Default http://localhost:7779 — leave blank to skip the now-playing overlay entirely.",
        obs.OBS_TEXT_INFO)
    obs.obs_properties_add_bool(props, "auto_start_np", "Auto-start Now Playing watcher with OBS")
    obs.obs_properties_add_text(props, "_auto_start_np_hint",
        "When enabled, launches tools/now-playing-watch.ps1 hidden in the background each time this script loads — but only if port 7779 isn't already taken. No more manual powershell.exe + browser-source refresh.",
        obs.OBS_TEXT_INFO)
    obs.obs_properties_add_button(props, "btn_start_np", "Start Now Playing watcher now",
        function(_, _) start_now_playing_watcher(); return true end)

    add_text(props, "twitch_channel", "Twitch channel")
    obs.obs_properties_add_text(props, "_twitch_channel_hint",
        "Channel login the clip player reads chat from — and the only channel whose clips play from viewer links.",
        obs.OBS_TEXT_INFO)
    obs.obs_properties_add_bool(props, "clip_player", "Clip player (chat clip links + !so shoutouts)")
    obs.obs_properties_add_text(props, "_clip_player_hint",
        "Plays a panel when anyone posts a link to one of this channel's clips, or when a mod types !so <user> (shows that streamer's featured clip). Raid alerts interrupt it. Uncheck and rebuild scenes to remove the source.",
        obs.OBS_TEXT_INFO)
    local clip_size = add_list(props, "clip_size", "Clip player size",
        obs.OBS_COMBO_TYPE_LIST, obs.OBS_COMBO_FORMAT_STRING)
    obs.obs_property_list_add_string(clip_size, "Large — 1280x720, centered",     "large")
    obs.obs_property_list_add_string(clip_size, "Small — 960x540, top-left",      "small")
    obs.obs_properties_add_text(props, "_clip_size_hint",
        "Large covers the middle of the canvas; small tucks under the header bar in the top-left corner so gameplay stays readable. Rebuild scenes after changing.",
        obs.OBS_TEXT_INFO)

    obs.obs_properties_add_bool(props, "weeman_avatars", "WeeMan avatars (chat !weeman)")
    obs.obs_properties_add_text(props, "_weeman_hint",
        "Viewers type !weeman to send a WeeMan walking along the bottom of the stream, tinted with their chat colour and captioned with their name. One each, at most 20 at once. Mods clear them with !weemanclear.",
        obs.OBS_TEXT_INFO)
    add_int(props, "weeman_mins", "WeeMan: minutes on screen", 1, 120, 1)
    obs.obs_properties_add_bool(props, "weeman_bubbles", "WeeMan: show chat speech bubbles")

    obs.obs_properties_add_bool(props, "redact_overlay", "Redaction overlay (chat !redact / !declassify)")
    obs.obs_properties_add_text(props, "_redact_hint",
        "!redact (100 Ostis) covers a random one of 4 screen sectors with a black CLASSIFIED bar. !declassify (150 Ostis) clears all of them at once. 15s cooldown between redactions; caps at 4 covered at a time.",
        obs.OBS_TEXT_INFO)

    obs.obs_properties_add_bool(props, "resonance_overlay", "Resonance Mode (chat !resonance)")
    obs.obs_properties_add_text(props, "_resonance_hint",
        "!resonance (300 Ostis, 5min cooldown) runs a 45s window: ducks/boosts real OBS input volumes (read and restored exactly, your mix is never clobbered) and shows a red HUD. Needs the source names below to actually touch OBS audio - blank means the HUD still shows but nothing gets ducked.",
        obs.OBS_TEXT_INFO)
    add_text(props, "resonance_music_source", "Resonance: music source name")
    add_text(props, "resonance_duck_sources", "Resonance: duck source names (comma-separated)")
    obs.obs_properties_add_text(props, "_resonance_sources_hint",
        "Exact OBS input names, e.g. music source \"Music\", duck sources \"Mic/Aux, Game\". Case-sensitive.",
        obs.OBS_TEXT_INFO)
    add_float(props, "resonance_boost_db", "Resonance: music boost (dB)", -60, 30, 1)
    add_float(props, "resonance_duck_db", "Resonance: duck amount (dB)", -60, 30, 1)
    add_text(props, "resonance_filter_source", "Resonance: visual filter source (optional)")
    add_text(props, "resonance_filter_name", "Resonance: visual filter name (optional)")
    obs.obs_properties_add_text(props, "_resonance_filter_hint",
        "Optional: the name of a filter you've already added to the filter source (e.g. a Color Correction filter on your Game source, left disabled by default) - Resonance Mode enables it for the 45s window and disables it again after. Leave both blank to skip.",
        obs.OBS_TEXT_INFO)

    obs.obs_properties_add_bool(props, "help_card", "Commands card (chat !info)")
    obs.obs_properties_add_text(props, "_help_card_hint",
        "Viewers type !info to slide up a card listing the chat commands that work, the same way !info works on the Arranging scene. Added to every scene except Arranging, which has its own !info. Only lists commands whose feature is switched on above.",
        obs.OBS_TEXT_INFO)

    obs.obs_properties_add_text(props, "_weeman_bubbles_hint",
        "While a viewer's WeeMan is out, what they say in chat appears in a speech bubble above it. This puts viewer text on your stream, so untick it if you would rather only show names.",
        obs.OBS_TEXT_INFO)

    add_text(props, "arr_piece", "Arranging: Piece (boot default only — change with !piece in chat)")
    add_text(props, "arr_collection", "Arranging: Game (boot default only — change with !from in chat)")
    add_int(props, "arr_sprints_total", "Arranging: total sprints", 1, 12, 1)
    add_int(props, "arr_focus_mins", "Arranging: focus mins",    1, 90, 1)
    add_int(props, "arr_break_mins", "Arranging: break mins",    1, 60, 1)
    obs.obs_properties_add_text(props, "_arr_hint",
        "Boot-time defaults for the 07 Arranging scene. Once Phoenix is connected, chat commands (!task, !done, !info, !piece, !from, !pomo) and the LiveView control panel take over.",
        obs.OBS_TEXT_INFO)

    obs.obs_properties_add_button(props, "btn", "Create / Refresh Scenes",
        function(_, _) build_all(); return true end)

    obs.obs_properties_add_button(props, "btn_pull", "Pull latest & refresh",
        function(_, _)
            local ok, changed = pull_latest()
            if ok and changed then
                -- The new script isn't loaded yet; building now would use the
                -- old one and miss anything new (scenes, settings).
                print("[IVGO] Updated. Reload this script (Tools > Scripts, the reload button) " ..
                      "to use the new version, then click Create / Refresh Scenes.")
            elseif ok then
                build_all()
            end
            return true
        end)

    return props
end
