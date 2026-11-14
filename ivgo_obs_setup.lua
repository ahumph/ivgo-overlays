-- ivgo_obs_setup.lua — IVGO Overlay Installer for OBS
--
-- Install: OBS menu → Tools → Scripts → "+" → select this file.
-- Fill in the fields in the Scripts panel, then click "Update & build scenes".
-- Re-run any time to update details (new guest name, new countdown, etc.).
-- "Update & build scenes" pulls the latest version and builds with it.
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

local function make_media(name, local_file, keep_file)
    -- Return owned FFmpeg Media Source ref, creating or updating settings.
    -- Used for the looping background videos on 01 Starting Soon / 06 Ending,
    -- so playback control (volume, restart, pause, hotkeys) lives in OBS
    -- rather than buried in an HTML <video>. With keep_file, local_file is
    -- only the first file: one picked later in Properties survives rebuilds.
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
        if not keep_file then
            obs.obs_data_set_string(d, "local_file",      settings.local_file)
        end
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
-- a rebuild would appear to do nothing.
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

-- On this scene the clip player plays random clips of the channel in the
-- video frame, over "IVGO: BRB Video" (see sync_brb_audio).
local BRB_SCENE = "IVGO · 04 Be Right Back"
-- Where the reel plays on the clip player's 1920x1080 page: 11-clip.html's
-- default reel_rect, and HoldingScene's L.video. The vertical BRB crops
-- the clip player to it.
local REEL_RECT = {24, 74, 1360, 765}

local function brb_reel_on()
    return settings_ref ~= nil
        and obs.obs_data_get_bool(settings_ref, "clip_player")
        and obs.obs_data_get_bool(settings_ref, "brb_clips")
end

local function configure_clip_source(src)
    configure_stateful_source(src)
    configure_audio_source(src)
    -- The BRB reel asks OBS which scene is live (obsstudio.getCurrentScene),
    -- which needs page permission 2, "Read access to user information".
    local d = obs.obs_source_get_settings(src)
    obs.obs_data_set_int(d, "webpage_control_level", 2)
    obs.obs_source_update(src, d)
    obs.obs_data_release(d)
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
    if brb_reel_on() then
        url = url .. "&reel_scene=" .. urlencode(BRB_SCENE)
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

-- Sources from features since removed (Redact, Resonance). Re-running the
-- installer deletes them from every scene, so a page nobody uses stops
-- running in the background.
local RETIRED_SOURCES = { "IVGO: Redact", "IVGO: Resonance" }

local function remove_retired_sources()
    for _, name in ipairs(RETIRED_SOURCES) do
        local src = obs.obs_get_source_by_name(name)
        if src then
            obs.obs_source_remove(src)
            obs.obs_source_release(src)
            print("[IVGO] Removed '" .. name .. "'")
        end
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

-- The watch-time board (!board, !skills, !dads) and the Bracket Showdown
-- card and inset are drawn by 02 Game's own overlay page now, so the old
-- separate clearance source (its /clearance page is gone) is removed if an
-- earlier build left one behind.
local function remove_old_clearance()
    local old = obs.obs_get_source_by_name("IVGO: Clearance")
    if old then
        obs.obs_source_remove(old)
        obs.obs_source_release(old)
        print("[IVGO] Removed 'IVGO: Clearance'")
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

-- The framed video slot on 01 Starting Soon, 04 Be Right Back and 06
-- Ending: L.video in
-- HoldingScene (ivgo-ex's ivgo-shared.js). The vertical one is V.video
-- times 1.5.
local HOLDING_VIDEO = {24, 74, 1360, 765}
local HOLDING_VIDEO_VERTICAL = {18, 93, 1044, 588}

-- Scene, video source. The vertical scene is the name plus " (Vertical)".
local HOLDING_VIDEOS = {
    {"IVGO · 01 Starting Soon", "IVGO: Starting Soon Video"},
    {"IVGO · 04 Be Right Back", "IVGO: BRB Video"},
    {"IVGO · 06 Ending",        "IVGO: Ending Video"},
}

local function fit_item(item, rect, fill)
    -- Set the whole transform, so a source nudged by hand goes back in the
    -- frame: top-left alignment, no rotation, no crop, sized to rect.
    -- OBS_ALIGN_* are C macros that Lua doesn't get: LEFT is 1, TOP is 4.
    obs.obs_sceneitem_set_alignment(item, 1 + 4)
    obs.obs_sceneitem_set_rot(item, 0)
    local crop = obs.obs_sceneitem_crop()
    obs.obs_sceneitem_set_crop(item, crop)
    local pos = obs.vec2()
    pos.x, pos.y = rect[1], rect[2]
    obs.obs_sceneitem_set_pos(item, pos)
    obs.obs_sceneitem_set_bounds_type(item, fill and obs.OBS_BOUNDS_SCALE_OUTER or obs.OBS_BOUNDS_SCALE_INNER)
    obs.obs_sceneitem_set_bounds_alignment(item, 0)
    local bounds = obs.vec2()
    bounds.x, bounds.y = rect[3], rect[4]
    obs.obs_sceneitem_set_bounds(item, bounds)
    if fill and obs.obs_sceneitem_set_bounds_crop then obs.obs_sceneitem_set_bounds_crop(item, true) end
end

local function fit_in_scene(scene_src, source_name, rect, fill)
    if not scene_src then return end
    local scene = obs.obs_scene_from_source(scene_src)
    local item = scene and obs.obs_scene_find_source(scene, source_name)
    if item then
        fit_item(item, rect, fill)
        -- Bottom of the scene, under the page that frames it. A video added
        -- to a scene that already exists lands on top otherwise.
        obs.obs_sceneitem_set_order(item, obs.OBS_ORDER_MOVE_BOTTOM or 3)
    end
    obs.obs_source_release(scene_src)
end

-- Put the Starting Soon, BRB and Ending videos in their frames, at the
-- bottom of their scenes, on both canvases. Only touches scenes and sources that already exist. Runs after
-- each build and whenever OBS loads the scene collection.
local function fit_holding_videos()
    local canvas = obs.obs_get_canvas_by_name and obs.obs_get_canvas_by_name("Aitum Vertical")
    for _, v in ipairs(HOLDING_VIDEOS) do
        fit_in_scene(obs.obs_get_source_by_name(v[1]), v[2], HOLDING_VIDEO, false)
        if canvas then
            fit_in_scene(obs.obs_canvas_get_source_by_name(canvas, v[1] .. " (Vertical)"), v[2], HOLDING_VIDEO_VERTICAL, true)
        end
    end
    if canvas then obs.obs_canvas_release(canvas) end
end

-- The layers on top of every scene: now playing, the !info card, WeeMan,
-- the clip player, fire and card pulls. opts covers the scenes that differ:
-- np_offset moves now playing down, no_help and no_now_playing leave
-- those out.
local function add_shared_layers(scene, base, socket_url, np_base, opts)
    opts = opts or {}
    if not opts.no_now_playing then build_now_playing(scene, np_base, opts.np_offset) end
    if not opts.no_help then build_help(scene, base, socket_url, np_base) end
    build_weeman(scene, base, socket_url)
    build_clip(scene, base, socket_url)
    build_fire(scene, base, socket_url)
    build_card_pull(scene, base, socket_url)
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
        place(scene, video, HOLDING_VIDEO[1], HOLDING_VIDEO[2], HOLDING_VIDEO[3], HOLDING_VIDEO[4])
        obs.obs_source_release(video)
    end

    local src = make_browser("IVGO: Starting Soon", url)
    if src then
        configure_alert_overlay(src)
        place(scene, src, 0, 0, 1920, 1080)
        obs.obs_source_release(src)
    end
    add_shared_layers(scene, base, socket_url, np_base)
    obs.obs_source_release(scene_src)
end

-- 02 Game's camera layout from the "Game cameras" setting: 0 for the one
-- big cam (the usual), or 1 to 3 cams stacked down the right edge over a
-- shorter chat, for gameplay-led shows with more than one camera.
local function game_stack()
    local v = settings_ref and obs.obs_data_get_string(settings_ref, "game_cams") or "classic"
    local n = tonumber(v)
    if n and n >= 1 and n <= 3 then return n end
    return 0
end

-- The extra stacked cameras, placed or (when not wanted) removed.
local function place_extra_cams(scene, stack)
    for i = 2, 3 do
        local name = "IVGO: Camera " .. i
        if stack >= i then
            local cam = make_capture(name, cam_type())
            if cam then
                place(scene, cam, 1590, 64 + (i - 1) * 190, 320, 180)
                obs.obs_source_release(cam)
            end
        else
            local old = obs.obs_get_source_by_name(name)
            if old then
                obs.obs_source_remove(old)
                obs.obs_source_release(old)
                print("[IVGO] Removed '" .. name .. "'")
            end
        end
    end
end

local function build_game(base, socket_url, np_base)
    -- Layer order bottom → top:
    --   1. Game Capture         x:0,    y:0,   w:1920, h:1080 (fit to screen)
    --   2. Host Camera          x:1570, y:64,  w:340,  h:191  (chamfered cutout)
    --      or, with "Game cameras" 1 to 3: Host Camera, Camera 2, Camera 3
    --      stacked at x:1590, y:64 / 254 / 444, w:320, h:180, over a
    --      320 x 400 chat
    --   3. 02-game.html         header + ticker chrome (transparent)
    --   4. 02-cam-outline.html  chamfered cam border frame (transparent)
    --   5. 02-chat.html         chat panel bottom-right (transparent)
    -- 02-game.html also draws the watch-time board and the Bracket
    -- Showdown card and inset, top left, when chat or the admin page asks.

    local scene_src = get_scene_source("IVGO · 02 Game")
    local scene     = obs.obs_scene_from_source(scene_src)

    local game = make_game_capture("IVGO: Game Capture")
    if game then
        place(scene, game, 0, 0, 1920, 1080)
        obs.obs_source_release(game)
    end

    local stack = game_stack()
    local cam = make_capture("IVGO: Host Camera", cam_type())
    if cam then
        if stack > 0 then
            place(scene, cam, 1590, 64, 320, 180)
        else
            place(scene, cam, 1570, 64, 340, 191)
        end
        obs.obs_source_release(cam)
    end
    place_extra_cams(scene, stack)
    local stack_q = stack > 0 and ("&stack=" .. stack) or ""

    local overlay = make_browser("IVGO: Game Overlay",  append_socket_url(base .. "/game?mic=1" .. stack_q, socket_url))
    if overlay then
        configure_alert_overlay(overlay)
        place(scene, overlay, 0, 0, 1920, 1080)
        obs.obs_source_release(overlay)
    end

    local cam_frame = make_silent_browser("IVGO: Cam Outline", append_socket_url(base .. "/game-cam-outline?toasts=0&sound=0" .. stack_q, socket_url))
    if cam_frame then
        place(scene, cam_frame, 0, 0, 1920, 1080)
        obs.obs_source_release(cam_frame)
    end

    local chat = make_silent_browser("IVGO: Chat",      append_socket_url(base .. "/game-chat?toasts=0&sound=0" .. stack_q, socket_url))
    if chat then
        place(scene, chat, 0, 0, 1920, 1080)
        obs.obs_source_release(chat)
    end

    remove_old_clearance()

    -- 02 Game's cam PiP sits top-right where the !PLAYING label normally
    -- lives — shift the now-playing source down 110px so the label clears it.
    add_shared_layers(scene, base, socket_url, np_base, {np_offset = 110})
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

    add_shared_layers(scene, base, socket_url, np_base)
    obs.obs_source_release(scene_src)
end

local function build_brb(base, socket_url, np_base)
    -- Layer order bottom → top:
    --   1. IVGO: BRB Video    in the frame, about.mkv until another file is
    --                         picked in its Properties (kept on rebuild)
    --   2. 04-brb.html        bars, cards and chat (transparent frame)
    --   3. the shared layers, the clip player among them: on this scene it
    --      plays random clips in the frame (brb_clips)
    local scene_src = get_scene_source(BRB_SCENE)
    local scene     = obs.obs_scene_from_source(scene_src)
    local video     = make_media("IVGO: BRB Video", repo_dir() .. "/media/about.mkv", true)
    if video then
        place(scene, video, HOLDING_VIDEO[1], HOLDING_VIDEO[2], HOLDING_VIDEO[3], HOLDING_VIDEO[4])
        obs.obs_source_release(video)
    end
    local src       = make_browser("IVGO: BRB", append_socket_url(base .. "/brb?mic=1", socket_url))
    if src then
        place(scene, src, 0, 0, 1920, 1080)
        -- The page used to play about.mkv itself and needed its audio
        -- rerouted. The video is its own source now, so turn that off.
        local d = obs.obs_source_get_settings(src)
        obs.obs_data_set_bool(d, "reroute_audio", false)
        obs.obs_source_update(src, d)
        obs.obs_data_release(d)
        obs.obs_source_release(src)
    end
    add_shared_layers(scene, base, socket_url, np_base)
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

    add_shared_layers(scene, base, socket_url, np_base)
    obs.obs_source_release(scene_src)
end

-- One-off mahjong stream. Off unless the "Mahjong scene" box is ticked.
local function build_mahjong(base, topic, socket_url, np_base)
    -- Layer order bottom → top:
    --   1. Table Camera  x:24,   y:72, w:1394, h:874  (filled and cropped)
    --   2. Hand Camera   x:1436, y:72, w:460,  h:259  (right column, top)
    --   3. 18-mahjong.html frames, topic, nameplate and chat (transparent)

    local scene_src = get_scene_source("IVGO · 18 Mahjong")
    local scene     = obs.obs_scene_from_source(scene_src)

    local table_cam = make_capture("IVGO: Table Camera", cam_type())
    if table_cam then
        local item = place(scene, table_cam, 24, 72, 1394, 874)
        if item then
            -- Fill the frame and crop the overflow, not letterbox.
            obs.obs_sceneitem_set_bounds_type(item, obs.OBS_BOUNDS_SCALE_OUTER)
            if obs.obs_sceneitem_set_bounds_crop then obs.obs_sceneitem_set_bounds_crop(item, true) end
        end
        obs.obs_source_release(table_cam)
    end

    local hand_cam = make_capture("IVGO: Hand Camera", cam_type())
    if hand_cam then
        place(scene, hand_cam, 1436, 72, 460, 259)
        obs.obs_source_release(hand_cam)
    end

    local overlay = make_browser("IVGO: Mahjong Overlay",
        append_socket_url(base .. "/mahjong?topic=" .. urlencode(topic), socket_url))
    if overlay then
        configure_alert_overlay(overlay)
        place(scene, overlay, 0, 0, 1920, 1080)
        obs.obs_source_release(overlay)
    end

    add_shared_layers(scene, base, socket_url, np_base)
    obs.obs_source_release(scene_src)
end

-- Bracket Showdown: the whole bracket, live from ivgo-ex. Off unless the
-- "Bracket scene" box is ticked. Run the show from /admin/brackets.
local function build_bracket(base, socket_url, np_base)
    -- Layer order bottom → top:
    --   1. 19-bracket.html  bracket, live matchup, header and ticker (opaque)
    --   2. Host Camera      x:756, y:580, w:408, h:230 (above the page, which
    --                       has its own background and draws the cam frame)

    local scene_src = get_scene_source("IVGO · 19 Bracket")
    local scene     = obs.obs_scene_from_source(scene_src)

    local overlay = make_browser("IVGO: Bracket Overlay", append_socket_url(base .. "/bracket?mic=1", socket_url))
    if overlay then
        configure_alert_overlay(overlay)
        place(scene, overlay, 0, 0, 1920, 1080)
        obs.obs_source_release(overlay)
    end

    local cam = make_capture("IVGO: Host Camera", cam_type())
    if cam then
        place(scene, cam, 756, 580, 408, 230)
        obs.obs_source_release(cam)
    end

    add_shared_layers(scene, base, socket_url, np_base)
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

-- The interview's cameras, in the order people are typed in: the first
-- host is this PC's camera (IVGO: Host Camera), everyone else a remote
-- feed, Interview Camera 1 to 4. Up to five people.
local MAX_CAMS = 5
local HOST_CAM = "IVGO: Host Camera"
local INTERVIEW_CAMS = {
    "IVGO: Interview Camera 1",
    "IVGO: Interview Camera 2",
    "IVGO: Interview Camera 3",
    "IVGO: Interview Camera 4",
}

-- Source name of the camera for the i-th person.
local function cam_name(i)
    if i == 1 then return HOST_CAM end
    return INTERVIEW_CAMS[i - 1]
end

-- An owned ref to the i-th person's camera, made if needed.
local function cam_source(i)
    if i == 1 then return make_capture(HOST_CAM, cam_type()) end
    return make_remote_feed(INTERVIEW_CAMS[i - 1])
end

-- Earlier names, renamed in place on the next build so the call links
-- already pasted into them carry over. In order: Camera 2 lost "(GUEST)"
-- when cameras started following the people list.
local OLD_CAM_NAMES = {
    {"IVGO: Interviewer",                "IVGO: Interview Camera 1"},
    {"IVGO: Interview Guest",            "IVGO: Interview Camera 2"},
    {"IVGO: Interviewer 2",              "IVGO: Interview Camera 3"},
    {"IVGO: Interview Camera 2 (GUEST)", "IVGO: Interview Camera 2"},
}

local function rename_old_cams()
    for _, pair in ipairs(OLD_CAM_NAMES) do
        local old = obs.obs_get_source_by_name(pair[1])
        if old then
            local taken = obs.obs_get_source_by_name(pair[2])
            if taken then
                obs.obs_source_release(taken)
            else
                obs.obs_source_set_name(old, pair[2])
                print("[IVGO] Renamed '" .. pair[1] .. "' to '" .. pair[2] .. "'")
            end
            obs.obs_source_release(old)
        end
    end
end

-- "Name, Role" per line, blank lines skipped. The role is optional.
local function parse_people(text)
    local list = {}
    for line in ((text or "") .. "\n"):gmatch("(.-)\n") do
        line = line:gsub("\r", "")
        local name, role = line:match("^%s*([^,]-)%s*,%s*(.-)%s*$")
        if not name then name, role = line:match("^%s*(.-)%s*$"), "" end
        if name ~= "" then list[#list + 1] = {name = name, role = role} end
    end
    return list
end

-- A small JSON reader for layouts.json (objects, arrays, strings, numbers).
local function json_decode(str)
    local pos = 1
    local function fail(msg) error("layouts.json: " .. msg .. " at character " .. pos, 0) end
    local function skip() pos = str:find("[^ \t\r\n]", pos) or #str + 1 end
    local function read_string()
        local out, i = {}, pos + 1
        while true do
            local c = str:sub(i, i)
            if c == "" then fail("unfinished string") end
            if c == '"' then pos = i + 1; return table.concat(out) end
            if c == "\\" then
                local n = str:sub(i + 1, i + 1)
                if n == "u" then out[#out + 1] = "?"; i = i + 6
                else out[#out + 1] = ({n = "\n", t = "\t", r = "\r"})[n] or n; i = i + 2 end
            else
                out[#out + 1] = c; i = i + 1
            end
        end
    end
    local read_value
    function read_value()
        skip()
        local c = str:sub(pos, pos)
        if c == "{" or c == "[" then
            local is_obj, out = c == "{", {}
            pos = pos + 1; skip()
            if str:sub(pos, pos) == (is_obj and "}" or "]") then pos = pos + 1; return out end
            while true do
                if is_obj then
                    skip()
                    if str:sub(pos, pos) ~= '"' then fail("expected a key") end
                    local key = read_string(); skip()
                    if str:sub(pos, pos) ~= ":" then fail("expected :") end
                    pos = pos + 1
                    out[key] = read_value()
                else
                    out[#out + 1] = read_value()
                end
                skip()
                local d = str:sub(pos, pos); pos = pos + 1
                if d == (is_obj and "}" or "]") then return out end
                if d ~= "," then fail("expected ,") end
            end
        elseif c == '"' then
            return read_string()
        end
        local num = str:match("^-?%d+%.?%d*[eE]?[-+]?%d*", pos)
        if num and num ~= "" then pos = pos + #num; return tonumber(num) end
        for word, v in pairs({["true"] = true, ["false"] = false}) do
            if str:sub(pos, pos + #word - 1) == word then pos = pos + #word; return v end
        end
        if str:sub(pos, pos + 3) == "null" then pos = pos + 4; return nil end
        fail("unexpected '" .. c .. "'")
    end
    return read_value()
end

local function read_file(path)
    local f = io.open(path, "rb")
    if not f then return nil end
    local text = f:read("*a")
    f:close()
    return text
end

-- The golden layouts for Welcome, Talk and Game: ivgo-ex's
-- /overlays/shared/layouts.json, the same file 17-interview.html draws
-- its frames from. Fetched on each build (curl comes with Windows 10 and
-- macOS) and kept in layouts.cache.json beside this script for a build
-- without the internet. Returns the "panel" table, or nil.
local function load_golden()
    local cache = repo_dir() .. "/layouts.cache.json"
    local tmp = cache .. ".tmp"
    os.remove(tmp)
    local h = io.popen(string.format('curl -fsSL --max-time 10 -o "%s" "%s" 2>&1',
        tmp, scenes_base_url() .. "/overlays/shared/layouts.json"), "r")
    local curl_out = h and h:read("*a") or ""
    if h then h:close() end

    local fresh = read_file(tmp)
    if fresh then
        local ok, data = pcall(json_decode, fresh)
        if ok and type(data) == "table" and type(data.panel) == "table" then
            os.remove(cache)
            os.rename(tmp, cache)
            return data.panel
        end
        print("[IVGO] The layouts file from the site didn't read (" .. tostring(data) .. ").")
    else
        print("[IVGO] Could not fetch the layouts file (" .. curl_out:gsub("%s+$", "") .. ").")
    end
    os.remove(tmp)

    local cached = read_file(cache)
    if cached then
        local ok, data = pcall(json_decode, cached)
        if ok and type(data) == "table" and type(data.panel) == "table" then
            print("[IVGO] Using the layouts from the last build that reached the site.")
            return data.panel
        end
    end
    return nil
end

-- Starting soon and BRB: the preroll video. They must match LAYOUTS in
-- ivgo-ex's priv/static/overlays/scenes/17-interview.html.
local INTERVIEW_LAYOUTS = {
    starting = {preroll = {24, 74, 1360, 765}},
    brb      = {preroll = {24, 74, 1360, 765}},
}

-- Scene item helpers for a source added on a re-run, after the overlay
-- already sits in the scene: obs_scene_add puts it on top, over the
-- overlay's frames and chat.
local function scene_item_index(scene, name)
    local found = nil
    local items = obs.obs_scene_enum_items(scene)
    if items then
        for i, it in ipairs(items) do
            if obs.obs_source_get_name(obs.obs_sceneitem_get_source(it)) == name then found = i end
        end
        obs.sceneitem_list_release(items)
    end
    return found
end

-- Moves item under the source named above_name if it sits over it.
local function keep_below(scene, item, above_name)
    if not item then return end
    local mine  = scene_item_index(scene, obs.obs_source_get_name(obs.obs_sceneitem_get_source(item)))
    local above = scene_item_index(scene, above_name)
    if mine and above and mine > above then
        -- Positions count from 0 at the bottom; taking above's slot pushes it up one.
        obs.obs_sceneitem_set_order_position(item, above - 1)
    end
end

-- Takes a source out of one scene (the source itself stays for others).
local function remove_from_scene(scene, name)
    local items = obs.obs_scene_enum_items(scene)
    if items then
        for _, it in ipairs(items) do
            if obs.obs_source_get_name(obs.obs_sceneitem_get_source(it)) == name then
                obs.obs_sceneitem_remove(it)
            end
        end
        obs.sceneitem_list_release(items)
    end
end

local function build_interview_scene(scene_name, r, back, overlay, preroll, base, socket_url, np_base)
    -- r: {preroll = rect} (Starting soon, BRB) or a golden layout,
    -- {game = rect, cams = {rect, ...}} with the cams in people order.
    -- Layer order bottom -> top, each only where r has a place for it:
    --   1. 17-interview.html?layer=back   branded background
    --   2. Preroll video
    --   3. Game Capture
    --   4. The cameras: Host Camera, then Interview Cameras 1 to 4
    --   5. 17-interview.html   frames, nameplates, chat, donations, chrome
    -- Sources the layout has no place for come out of the scene, so a show
    -- with fewer people leaves no empty frames behind.
    local scene_src = get_scene_source(scene_name)
    local scene     = obs.obs_scene_from_source(scene_src)
    local above     = obs.obs_source_get_name(overlay)

    local function put(source, rect)
        if not source then return end
        local item = place(scene, source, rect[1], rect[2], rect[3], rect[4])
        keep_below(scene, item, above)
        obs.obs_source_release(source)
    end

    place(scene, back, 0, 0, 1920, 1080)
    if preroll and r.preroll then
        put(obs.obs_source_get_ref(preroll), r.preroll)
    end

    if r.game then
        put(make_game_capture("IVGO: Game Capture"), r.game)
    else
        remove_from_scene(scene, "IVGO: Game Capture")
    end

    local cams = r.cams or {}
    for i = 1, MAX_CAMS do
        if cams[i] then put(cam_source(i), cams[i]) else remove_from_scene(scene, cam_name(i)) end
    end

    place(scene, overlay, 0, 0, 1920, 1080)

    add_shared_layers(scene, base, socket_url, np_base, {no_now_playing = true})
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
-- V_LAYOUTS in ivgo-ex's 17-interview.html, times 1.5 (V_SCALE). Two people
-- large, top and bottom; who they are is vertical_people below.
local VERTICAL_LAYOUTS = {
    starting = {
        preroll    = {18, 93, 1044, 588},
    },
    welcome = {
        top        = {18, 93, 1044, 690},
        bottom     = {18, 795, 1044, 690},
    },
    talk = {
        top        = {18, 93, 1044, 690},
        bottom     = {18, 795, 1044, 690},
        game       = {18, 1497, 720, 405},
        inset      = {486, 1755, 240, 135},
    },
    brb = {
        preroll    = {18, 93, 1044, 588},
    },
}

-- Which person (camera number, people order) goes in each vertical slot,
-- as 17-interview.html's vTop and friends. Welcome: the second host on
-- top and the first under them. Talk: the second host (or the only one)
-- and the first guest, with the first host inset on the game when they
-- aren't one of the two. No game, no game or inset.
local function vertical_people(layout, n_hosts, n_guests, gameplay)
    local top = n_hosts >= 2 and 2 or 1
    if layout == "welcome" then
        return {top = top, bottom = n_hosts >= 2 and 1 or nil}
    end
    if layout == "talk" then
        return {
            top    = top,
            bottom = n_guests > 0 and n_hosts + 1 or nil,
            inset  = gameplay and top ~= 1 and 1 or nil,
            game   = gameplay,
        }
    end
    return {}
end

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
    return item
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

local function build_vertical_interview(base, params, preroll, socket_url, n_hosts, n_guests, gameplay)
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
                local who = vertical_people(layout, n_hosts, n_guests, gameplay)
                place(scene, back, 0, 0, 1080, 1920)
                place_fill(scene, preroll, r.preroll)
                if who.game then
                    local game = make_game_capture("IVGO: Game Capture")
                    place_fill(scene, game, r.game)
                    if game then obs.obs_source_release(game) end
                else
                    remove_from_scene(scene, "IVGO: Game Capture")
                end
                local used = {}
                for _, slot in ipairs({"top", "bottom", "inset"}) do
                    local i = who[slot]
                    if i and r[slot] then
                        used[i] = true
                        local cam = cam_source(i)
                        -- Under the overlay, if this build adds it.
                        keep_below(scene, place_fill(scene, cam, r[slot]), obs.obs_source_get_name(overlay))
                        if cam then obs.obs_source_release(cam) end
                    end
                end
                for i = 1, MAX_CAMS do
                    if not used[i] then remove_from_scene(scene, cam_name(i)) end
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
        add(scene, make_media("IVGO: Starting Soon Video", repo_dir() .. "/media/buts.mkv"), HOLDING_VIDEO_VERTICAL, true)
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
        add(scene, make_media("IVGO: BRB Video", repo_dir() .. "/media/about.mkv", true), HOLDING_VIDEO_VERTICAL, true)
        add(scene, make_vertical_overlay("IVGO: BRB (Vertical)", url("/brb")), full)
        -- The clip reel: the main canvas's IVGO: Clip Player itself, so both
        -- canvases show the same clip with one sound. Cropped to the reel's
        -- frame (REEL_RECT) and fitted to the video slot, under the overlay.
        if brb_reel_on() then
            local clip = obs.obs_get_source_by_name("IVGO: Clip Player")
            if clip then
                local item = place_fill(scene, clip, HOLDING_VIDEO_VERTICAL)
                if item then
                    local crop = obs.obs_sceneitem_crop()
                    crop.left, crop.top = REEL_RECT[1], REEL_RECT[2]
                    crop.right = 1920 - REEL_RECT[1] - REEL_RECT[3]
                    crop.bottom = 1080 - REEL_RECT[2] - REEL_RECT[4]
                    obs.obs_sceneitem_set_crop(item, crop)
                    keep_below(scene, item, "IVGO: BRB (Vertical)")
                end
                obs.obs_source_release(clip)
            end
        else
            remove_from_scene(scene, "IVGO: Clip Player")
        end
    end)

    scene_for("IVGO · 06 Ending", function(scene)
        add(scene, make_media("IVGO: Ending Video", repo_dir() .. "/media/tetris.webm"), HOLDING_VIDEO_VERTICAL, true)
        add(scene, make_vertical_overlay("IVGO: Ending (Vertical)", url("/ending")), full)
    end)

    obs.obs_canvas_release(canvas)
    print("[IVGO] Vertical scenes built and linked. If they don't show in " ..
          "the Aitum Vertical dock yet, restart OBS.")
end

local function build_interview(base, hosts, guests, gameplay, preroll_video, countdown_mins, socket_url, np_base, vertical)
    -- Up to five scenes, one overlay: starting soon, welcome (the hosts),
    -- talk (everyone), game (everyone and the game, only with gameplay
    -- ticked) and be right back. Welcome, Talk and Game take the golden
    -- layout for their number of cameras. The same overlay and background
    -- sources sit in all of them, so the chat panel never reloads and
    -- alerts play once; the overlay reads the live scene's name and draws
    -- the matching layout. Bind a hotkey to each scene in Settings >
    -- Hotkeys to switch.
    local golden = load_golden()
    if not golden then
        print("[IVGO] Interview scenes skipped: no layouts file. Check the internet connection and build again.")
        return
    end

    -- Hosts first; everyone past five is left out.
    local people = {}
    for _, p in ipairs(hosts) do if #people < MAX_CAMS then people[#people + 1] = p end end
    local n_hosts = #people
    for _, p in ipairs(guests) do if #people < MAX_CAMS then people[#people + 1] = p end end
    local n_guests = #people - n_hosts
    if #hosts + #guests > MAX_CAMS then
        print("[IVGO] The interview has room for " .. MAX_CAMS .. " cameras. Left out: everyone after " .. people[#people].name .. ".")
    end

    local params = "mins=" .. tostring(countdown_mins) .. "&mic=1&egg_off=1"
    for i, p in ipairs(people) do
        params = params .. "&" .. (i <= n_hosts and "host" or "guest") .. "=" .. urlencode(p.name .. "|" .. p.role)
    end
    if gameplay then params = params .. "&game=1" end

    rename_old_cams()

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

    local function panel(key)
        local L = golden[key]
        if not L then print("[IVGO] The layouts file has no layout '" .. key .. "'.") end
        return L or {}
    end

    build_interview_scene("IVGO · 17 Interview · Starting Soon", INTERVIEW_LAYOUTS.starting, back, overlay, preroll, base, socket_url, np_base)
    build_interview_scene("IVGO · 17 Interview · Welcome",       panel(tostring(n_hosts)), back, overlay, preroll, base, socket_url, np_base)
    build_interview_scene("IVGO · 17 Interview · Talk",          panel(tostring(#people)), back, overlay, preroll, base, socket_url, np_base)
    if gameplay then
        build_interview_scene("IVGO · 17 Interview · Game",      panel(#people .. "+game"), back, overlay, preroll, base, socket_url, np_base)
    end
    build_interview_scene("IVGO · 17 Interview · Be Right Back", INTERVIEW_LAYOUTS.brb, back, overlay, preroll, base, socket_url, np_base)

    if vertical then build_vertical_interview(base, params, preroll, socket_url, n_hosts, n_guests, gameplay) end

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
        place(scene, video, HOLDING_VIDEO[1], HOLDING_VIDEO[2], HOLDING_VIDEO[3], HOLDING_VIDEO[4])
        obs.obs_source_release(video)
    end

    local src = make_browser("IVGO: Ending", append_socket_url(base .. "/ending?mic=1", socket_url))
    if src then
        configure_alert_overlay(src)
        place(scene, src, 0, 0, 1920, 1080)
        obs.obs_source_release(src)
    end
    add_shared_layers(scene, base, socket_url, np_base)
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

    -- No !info card here on purpose: this scene's own !info slides the ON
    -- THE DESK card up from the same spot, so the two would move at once.
    add_shared_layers(scene, base, socket_url, np_base, {no_help = true})
    obs.obs_source_release(scene_src)
end

-- The BRB video's sound is muted while the clip player is visible on 04 Be
-- Right Back with the reel on, since the reel's clips play over it in the
-- same frame. Hiding the clip player there (its eye in Sources) stops the
-- reel and brings the video's sound back. With vertical scenes, hide it on
-- the vertical BRB too, or the reel keeps going there.
local function sync_brb_audio()
    local video = obs.obs_get_source_by_name("IVGO: BRB Video")
    if not video then return end
    local muted = false
    if brb_reel_on() then
        local scene_src = obs.obs_get_source_by_name(BRB_SCENE)
        local scene = scene_src and obs.obs_scene_from_source(scene_src)
        local item = scene and obs.obs_scene_find_source(scene, "IVGO: Clip Player")
        muted = item ~= nil and obs.obs_sceneitem_visible(item)
        if scene_src then obs.obs_source_release(scene_src) end
    end
    obs.obs_source_set_muted(video, muted)
    obs.obs_source_release(video)
end

-- IVGO_BRB_WATCH is a global so a reloaded copy of this script (ivgo_update)
-- can disconnect the old copy's handler before connecting its own.
local function unwatch_brb_audio()
    local w = IVGO_BRB_WATCH
    if not w then return end
    obs.signal_handler_disconnect(w.handler, "item_visible", w.fn)
    obs.obs_source_release(w.source)
    IVGO_BRB_WATCH = nil
end

local function watch_brb_audio()
    unwatch_brb_audio()
    local scene_src = obs.obs_get_source_by_name(BRB_SCENE)
    if scene_src then
        local handler = obs.obs_source_get_signal_handler(scene_src)
        local fn = function(_) sync_brb_audio() end
        obs.signal_handler_connect(handler, "item_visible", fn)
        IVGO_BRB_WATCH = { source = scene_src, handler = handler, fn = fn }
    end
    sync_brb_audio()
end

-- Once: an interview set up with the old one-field-per-person settings
-- becomes the Hosts and Guests lists. The old cameras were this PC (the
-- player), Camera 1 (interviewer), Camera 2 (the guest) and Camera 3 (a
-- second interviewer). Now they follow the lists, hosts first, so with a
-- second interviewer Cameras 2 and 3 swap names to keep their call links.
local function migrate_interview_settings()
    local s = settings_ref
    if obs.obs_data_has_user_value(s, "interview_hosts") or obs.obs_data_has_user_value(s, "interview_guests") then return end
    if not (obs.obs_data_has_user_value(s, "interviewer_name") or obs.obs_data_has_user_value(s, "guest_name")) then return end

    local function line(name_key, role)
        local name = obs.obs_data_get_string(s, name_key)
        if name == "" then return nil end
        return role ~= "" and (name .. ", " .. role) or name
    end
    local get = function(key) return obs.obs_data_get_string(s, key) end
    local hosts = {}
    for _, l in ipairs({
        line("host_name", get("host_role")) or false,
        line("interviewer_name", get("interviewer_role")) or false,
        line("interviewer2_name", get("interviewer2_role")) or false,
    }) do
        if l then hosts[#hosts + 1] = l end
    end
    local credit = get("guest_credit")
    local guest = line("guest_name", credit ~= "" and credit or get("guest_role")) or ""
    obs.obs_data_set_string(s, "interview_hosts", table.concat(hosts, "\n"))
    obs.obs_data_set_string(s, "interview_guests", guest)
    print("[IVGO] Moved the interview names into Hosts and Guests.")

    if get("interviewer2_name") ~= "" then
        local cam2 = obs.obs_get_source_by_name("IVGO: Interview Camera 2 (GUEST)")
        local cam3 = obs.obs_get_source_by_name("IVGO: Interview Camera 3")
        if cam2 and cam3 then
            obs.obs_source_set_name(cam3, "IVGO: Interview Camera 2")
            obs.obs_source_set_name(cam2, "IVGO: Interview Camera 3")
            print("[IVGO] Swapped Interview Cameras 2 and 3: the second host is Camera 2 now, the guest Camera 3.")
        end
        if cam2 then obs.obs_source_release(cam2) end
        if cam3 then obs.obs_source_release(cam3) end
    end
end

local function build_all()
    migrate_interview_settings()
    local base       = scenes_base_url()
    local host       = obs.obs_data_get_string(settings_ref, "host_name")
    local host_role  = obs.obs_data_get_string(settings_ref, "host_role")
    local guest      = obs.obs_data_get_string(settings_ref, "guest_name")
    local g_role     = obs.obs_data_get_string(settings_ref, "guest_role")
    local topic      = obs.obs_data_get_string(settings_ref, "topic")
    local countdown_mins = obs.obs_data_get_int   (settings_ref, "countdown_mins")
    local socket_url     = obs.obs_data_get_string(settings_ref, "socket_url")
    local np_base        = obs.obs_data_get_string(settings_ref, "now_playing_http_base")
    local preroll_video    = obs.obs_data_get_string(settings_ref, "preroll_video")
    local gameplay         = obs.obs_data_get_bool  (settings_ref, "interview_game")

    local arr_piece         = obs.obs_data_get_string(settings_ref, "arr_piece")
    local arr_collection    = obs.obs_data_get_string(settings_ref, "arr_collection")
    local arr_sprints_total = obs.obs_data_get_int   (settings_ref, "arr_sprints_total")
    local arr_focus_mins    = obs.obs_data_get_int   (settings_ref, "arr_focus_mins")
    local arr_break_mins    = obs.obs_data_get_int   (settings_ref, "arr_break_mins")

    print("[IVGO] Building scenes from: " .. base)
    remove_retired_sources()

    build_starting_soon(base, countdown_mins, socket_url, np_base)
    build_game(base, socket_url, np_base)
    build_camera(base, host, host_role, socket_url, np_base)
    build_brb(base, socket_url, np_base)
    build_two_cam(base, host, host_role, guest, g_role, topic, socket_url, np_base)
    -- Only for interview shows: off unless ticked, so other streamers'
    -- scene lists don't fill up with scenes they'll never use.
    local interviews = obs.obs_data_get_bool(settings_ref, "interview_scenes")
    if interviews then
        -- No hosts typed in: the show's host on this PC's camera.
        local hosts = parse_people(obs.obs_data_get_string(settings_ref, "interview_hosts"))
        if #hosts == 0 then hosts = {{name = host, role = host_role}} end
        build_interview(base, hosts, parse_people(obs.obs_data_get_string(settings_ref, "interview_guests")),
                        gameplay, preroll_video, countdown_mins, socket_url, np_base,
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
    -- One-off show: off unless ticked, same as the interview scenes.
    local mahjong = obs.obs_data_get_bool(settings_ref, "mahjong_scene")
    if mahjong then
        build_mahjong(base, topic, socket_url, np_base)
    end
    local bracket = obs.obs_data_get_bool(settings_ref, "bracket_scene")
    if bracket then
        build_bracket(base, socket_url, np_base)
    end
    fit_holding_videos()
    watch_brb_audio()

    local count = 7 + (interviews and (gameplay and 5 or 4) or 0) + (mahjong and 1 or 0) + (bracket and 1 or 0)
    print("[IVGO] Done — " .. count .. " scenes created / refreshed.")
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
Builds all the IVGO scenes in OBS. Fill in the fields below, then click
<b>Update &amp; build scenes</b> at the top. It pulls the latest version
first and builds with it. Hover over a field for what it does.<br><br>
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

-- ── Update in one click ─────────────────────────────────────────────────────
-- OBS keeps running the script it loaded, so new code from a pull would
-- normally need a manual reload. ivgo_update instead loads the pulled file
-- into this same script, which replaces these globals and the script_*
-- hooks with the new version's, hands it the settings and hotkey, and lets
-- the new code build the scenes. New settings fields only show in the
-- panel after reopening Tools > Scripts.

function ivgo_build()
    build_all()
end

-- Called on the newly loaded code by the old version's ivgo_update.
function ivgo_adopt(settings, hotkey_id)
    settings_ref = settings
    stop_clip_hotkey_id = hotkey_id
    script_defaults(settings)
end

function ivgo_update()
    local ok, changed = pull_latest()
    if not ok then
        print("[IVGO] Building with the version already loaded.")
        build_all()
        return
    end
    if not changed then
        print("[IVGO] Already up to date.")
        build_all()
        return
    end

    local chunk, err = loadfile(script_path() .. "ivgo_obs_setup.lua")
    local loaded = chunk and pcall(chunk)
    if not loaded then
        print("[IVGO] Pulled a new version but could not load it (" .. tostring(err) ..
              "). Reload this script in Tools > Scripts, then click Update & build scenes.")
        return
    end
    print("[IVGO] Loaded the new version.")
    -- These names now point at the new code's functions.
    ivgo_adopt(settings_ref, stop_clip_hotkey_id)
    ivgo_build()
end

function script_load(settings)
    settings_ref = settings
    ensure_obs_websocket_enabled()
    maybe_start_now_playing_watcher()

    -- Keep the Starting Soon and Ending videos in their frames without a
    -- rebuild: on OBS start, on a scene collection switch, and now (when
    -- the script is reloaded with scenes already loaded).
    -- The BRB video's mute follows the clip player the same way.
    obs.obs_frontend_add_event_callback(function(event)
        if event == obs.OBS_FRONTEND_EVENT_FINISHED_LOADING
            or event == obs.OBS_FRONTEND_EVENT_SCENE_COLLECTION_CHANGED then
            fit_holding_videos()
            watch_brb_audio()
        elseif event == obs.OBS_FRONTEND_EVENT_SCENE_COLLECTION_CHANGING
            or event == obs.OBS_FRONTEND_EVENT_EXIT then
            unwatch_brb_audio()
        end
    end)
    fit_holding_videos()
    watch_brb_audio()

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
    obs.obs_data_set_default_bool  (settings, "mahjong_scene", false)
    obs.obs_data_set_default_bool  (settings, "vertical_interview", false)
    obs.obs_data_set_default_bool  (settings, "vertical_scenes", false)
    obs.obs_data_set_default_string(settings, "interview_hosts",  "ADAM HUMPHREYS, ARTISTIC DIRECTOR\nPHOEBE, HOST")
    obs.obs_data_set_default_string(settings, "interview_guests", "GUEST NAME, SPECIAL GUEST")
    obs.obs_data_set_default_bool  (settings, "interview_game",   true)
    obs.obs_data_set_default_string(settings, "preroll_video",    "")
    obs.obs_data_set_default_int   (settings, "countdown_mins", 5)
    obs.obs_data_set_default_string(settings, "socket_url", "wss://ivgorchestra.fly.dev/overlay")
    obs.obs_data_set_default_string(settings, "now_playing_http_base", "http://localhost:7779")
    obs.obs_data_set_default_bool  (settings, "auto_start_np", true)
    obs.obs_data_set_default_string(settings, "twitch_channel", "irishvideogameorchestra")
    obs.obs_data_set_default_bool  (settings, "clip_player", true)
    obs.obs_data_set_default_string(settings, "clip_size", "large")
    obs.obs_data_set_default_string(settings, "game_cams", "classic")
    obs.obs_data_set_default_bool  (settings, "brb_clips", true)
    obs.obs_data_set_default_bool  (settings, "weeman_avatars", true)
    obs.obs_data_set_default_bool  (settings, "weeman_bubbles", true)
    obs.obs_data_set_default_int   (settings, "weeman_mins", 15)
    obs.obs_data_set_default_bool  (settings, "help_card", true)
    obs.obs_data_set_default_bool  (settings, "bracket_scene", false)

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

-- Hover text for a field, in place of an info line under it.
local function tip(prop, text)
    if prop and obs.obs_property_set_long_description then obs.obs_property_set_long_description(prop, text) end
    return prop
end

-- A text box of several lines, its label above it.
local function add_lines(props, name, text)
    label_above(props, name, text)
    return obs.obs_properties_add_text(props, name, "", obs.OBS_TEXT_MULTILINE)
end

-- A framed section of the panel. With checkable, its tick box is the bool
-- setting called name.
local function section(props, name, title, checkable, fill)
    local sub = obs.obs_properties_create()
    fill(sub)
    obs.obs_properties_add_group(props, name, title, checkable and obs.OBS_GROUP_CHECKABLE or obs.OBS_GROUP_NORMAL, sub)
end

function script_properties()
    local props = obs.obs_properties_create()

    -- The button calls the global below rather than a local function, so
    -- after an update hot-loads new code it runs the new version.
    tip(obs.obs_properties_add_button(props, "btn_update", "Update & build scenes",
        function(_, _) ivgo_update(); return true end),
        "Pulls the latest version, loads it and builds the scenes, all in one go. Without the internet it builds with the version already loaded.")

    section(props, "grp_show", "Show", false, function(g)
        tip(add_text(g, "host_name", "Host name"), "Shown in the header bar and camera nameplate.")
        tip(add_text(g, "host_role", "Host role"), "Shown below your name.")
        tip(add_int(g, "countdown_mins", "Countdown (mins)", 0, 120, 1),
            "Minutes the Starting Soon countdowns start at when the scene loads. 0 to hide.")
        local game_cams = add_list(g, "game_cams", "Game cameras", obs.OBS_COMBO_TYPE_LIST, obs.OBS_COMBO_FORMAT_STRING)
        obs.obs_property_list_add_string(game_cams, "One big cam (usual)", "classic")
        obs.obs_property_list_add_string(game_cams, "1 cam, stacked layout", "1")
        obs.obs_property_list_add_string(game_cams, "2 cams, stacked", "2")
        obs.obs_property_list_add_string(game_cams, "3 cams, stacked", "3")
        tip(game_cams, "The stacked layout puts up to three cams down the right edge of 02 Game, 320x180 each, with a shorter chat under them and the gameplay full frame. Pick a camera for IVGO: Camera 2 and IVGO: Camera 3 after the build. Back to One big cam removes them.")
        tip(obs.obs_properties_add_bool(g, "vertical_scenes", "Vertical scenes (needs the Aitum Vertical plugin)"),
            "Also builds Starting Soon, Game, Camera, Be Right Back and Ending on Aitum Vertical's 1080x1920 canvas, linked to their main scenes so switching one switches both. Needs OBS 31.1 or later. Restart OBS after the first build so Aitum lists the new scenes.")
    end)

    section(props, "interview_scenes", "Interview scenes (IVGO · 17 Interview)", true, function(g)
        tip(add_lines(g, "interview_hosts", "Hosts, one per line: Name, Role"),
            "The first host is on this PC's camera (IVGO: Host Camera). Welcome shows the hosts.")
        tip(add_lines(g, "interview_guests", "Guests, one per line: Name, Role"),
            "Remote guests, after the hosts. The role shows on their nameplate and is optional.")
        tip(obs.obs_properties_add_bool(g, "interview_game", "Gameplay or screen share"),
            "Adds the Game scene: the game or a screen share large, with everyone's cameras beside it.")
        tip(add_text(g, "preroll_video", "Preroll video"),
            "A YouTube link, or the full path of a video file. Plays on the interview's Starting Soon and Be Right Back.")
        tip(obs.obs_properties_add_bool(g, "vertical_interview", "Vertical interview scenes (needs the Aitum Vertical plugin)"),
            "Also builds the interview on Aitum Vertical's 1080x1920 canvas, with two people large. Needs OBS 31.1 or later. Restart OBS after the first build so Aitum lists the new scenes.")
        obs.obs_properties_add_text(g, "_interview_hint",
            "Up to 5 people. Talk and Game show everyone. After a build, paste each remote person's call link into their camera, in list order: IVGO: Interview Camera 1, 2, 3 and 4.",
            obs.OBS_TEXT_INFO)
    end)

    section(props, "grp_other", "Two-Camera, Mahjong and Bracket", false, function(g)
        tip(add_text(g, "guest_name", "Guest name"), "The 05 Two Camera scene's guest.")
        tip(add_text(g, "guest_role", "Guest role"), "The 05 Two Camera scene's guest.")
        tip(add_text(g, "topic", "Topic"), "Shown in the topic strip of the Two-Camera scene.")
        tip(obs.obs_properties_add_bool(g, "mahjong_scene", "Mahjong scene (IVGO · 18 Mahjong)"),
            "A big table camera, a hand camera and chat down the right. Pick a camera for IVGO: Table Camera and IVGO: Hand Camera after the first build. Mods set the topic with !topic. Unticking doesn't delete the scene; remove it in OBS.")
        tip(obs.obs_properties_add_bool(g, "bracket_scene", "Bracket scene (IVGO · 19 Bracket)"),
            "The whole Bracket Showdown, live, with the host cam under the final. Run the show from /admin/brackets or chat (!win, !matchup, !bracket, !undo). 02 Game shows the matchup card and a small bracket without this. Unticking doesn't delete the scene; remove it in OBS.")
    end)

    section(props, "grp_chat", "Chat extras", false, function(g)
        tip(obs.obs_properties_add_bool(g, "clip_player", "Clip player (chat clip links and !so shoutouts)"),
            "Plays a panel when anyone posts a link to one of this channel's clips, or when a mod types !so <user>. Raid alerts interrupt it.")
        local clip_size = add_list(g, "clip_size", "Clip player size", obs.OBS_COMBO_TYPE_LIST, obs.OBS_COMBO_FORMAT_STRING)
        obs.obs_property_list_add_string(clip_size, "Large: 1280x720, centered", "large")
        obs.obs_property_list_add_string(clip_size, "Small: 960x540, top left", "small")
        tip(clip_size, "Large covers the middle of the canvas. Small tucks under the header bar in the top left so gameplay stays readable.")
        tip(obs.obs_properties_add_bool(g, "brb_clips", "Random clips on Be Right Back"),
            "Plays this channel's clips in the Be Right Back frame: the 50 most viewed from the last 90 days, topped up with older ones. Clips from chat and !so play next. To show your own video, pick a file in IVGO: BRB Video and hide IVGO: Clip Player on that scene, and on the vertical one too.")
        tip(obs.obs_properties_add_bool(g, "weeman_avatars", "WeeMan avatars (chat !weeman)"),
            "Viewers type !weeman to send a WeeMan walking along the bottom of the stream, in their chat colour with their name. One each, 20 at once. Mods clear them with !weemanclear.")
        tip(add_int(g, "weeman_mins", "WeeMan: minutes on screen", 1, 120, 1), "How long each WeeMan stays.")
        tip(obs.obs_properties_add_bool(g, "weeman_bubbles", "WeeMan: show chat speech bubbles"),
            "What a viewer says in chat appears in a bubble above their WeeMan. This puts viewer text on your stream, so untick it to show only names.")
        tip(obs.obs_properties_add_bool(g, "help_card", "Commands card (chat !info)"),
            "Viewers type !info to slide up a card of the chat commands that work. On every scene except Arranging, which has its own.")
    end)

    section(props, "grp_arranging", "Arranging", false, function(g)
        tip(add_text(g, "arr_piece", "Piece"), "Start-up default only. Change it with !piece in chat.")
        tip(add_text(g, "arr_collection", "Game"), "Start-up default only. Change it with !from in chat.")
        tip(add_int(g, "arr_sprints_total", "Total sprints", 1, 12, 1), "Start-up default for 07 Arranging.")
        tip(add_int(g, "arr_focus_mins", "Focus mins", 1, 90, 1), "Start-up default for 07 Arranging.")
        tip(add_int(g, "arr_break_mins", "Break mins", 1, 60, 1), "Start-up default for 07 Arranging.")
    end)

    section(props, "grp_advanced", "Advanced", false, function(g)
        tip(add_text(g, "twitch_channel", "Twitch channel"),
            "The channel the clip player and WeeMen read chat from, and the only channel whose clips play from viewer links.")
        tip(add_text(g, "socket_url", "Socket URL"),
            "Live: wss://ivgorchestra.fly.dev/overlay. Local: ws://localhost:4000/overlay")
        tip(add_text(g, "now_playing_http_base", "Now Playing HTTP base"),
            "The Now Playing watch script's server, http://localhost:7779 by default. Leave blank to skip the Now Playing overlay.")
        tip(obs.obs_properties_add_bool(g, "auto_start_np", "Start the Now Playing watcher with OBS"),
            "Starts tools/now-playing-watch.ps1 hidden each time this script loads, unless port 7779 is already taken.")
        obs.obs_properties_add_button(g, "btn_start_np", "Start Now Playing watcher now",
            function(_, _) start_now_playing_watcher(); return true end)
    end)

    return props
end
