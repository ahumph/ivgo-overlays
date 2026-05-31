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
    -- script_path() returns the directory containing this .lua file with a
    -- trailing slash, e.g. /Users/adam/ivgo-overlays/ or C:\Users\adam\ivgo-overlays\
    local dir = script_path():gsub("\\", "/")   -- normalise Windows separators
    -- Mac/Linux: dir = /Users/.../    → "file://" + dir + "scenes" = file:///Users/.../scenes
    -- Windows:   dir = C:/Users/.../  → "file:///" + dir + "scenes" = file:///C:/Users/.../scenes
    local prefix = is_windows() and "file:///" or "file://"
    return prefix .. dir .. "scenes"
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
    print("[IVGO] Pulling latest…")
    local ok, output = run_git("pull --rebase --autostash")
    if output ~= "" then print("[IVGO] git pull:\n" .. output) end
    if not ok then
        print("[IVGO] git pull failed — check `git status` and resolve manually.")
        return false
    end
    return true
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

local function make_browser(name, url)
    -- Return owned browser source ref, creating or updating URL as needed.
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
    obs.obs_data_set_int   (d, "width",             1920)
    obs.obs_data_set_int   (d, "height",            1080)
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
    local kind = game_type()
    local mul = 10 ^ (-12 / 20)   -- -12 dBFS as linear multiplier (~0.2512)
    local existing = obs.obs_get_source_by_name(name)
    if existing then
        local d = obs.obs_source_get_settings(existing)
        obs.obs_data_set_bool(d, "capture_audio", true)
        obs.obs_source_update(existing, d)
        obs.obs_data_release(d)
        obs.obs_source_set_volume(existing, mul)
        return existing
    end
    local d = obs.obs_data_create()
    obs.obs_data_set_bool(d, "capture_audio", true)
    local src = obs.obs_source_create(kind, name, d, nil)
    obs.obs_data_release(d)
    if src then obs.obs_source_set_volume(src, mul) end
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
local function build_fire(scene, base, socket_url)
    local src = make_browser("IVGO: Fire Overlay", append_socket_url(base .. "/10-fire.html", socket_url))
    if src then
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
    local url = base .. "/01-starting-soon.html"
    if countdown_mins and countdown_mins > 0 then
        url = url .. "?mins=" .. tostring(countdown_mins) .. "&secs=0"
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
        place(scene, src, 0, 0, 1920, 1080)
        obs.obs_source_release(src)
    end
    build_now_playing(scene, np_base)
    build_fire(scene, base, socket_url)
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

    local overlay = make_browser("IVGO: Game Overlay",  append_socket_url(base .. "/02-game.html", socket_url))
    if overlay then
        place(scene, overlay, 0, 0, 1920, 1080)
        obs.obs_source_release(overlay)
    end

    local cam_frame = make_browser("IVGO: Cam Outline", append_socket_url(base .. "/02-cam-outline.html?toasts=0", socket_url))
    if cam_frame then
        place(scene, cam_frame, 0, 0, 1920, 1080)
        obs.obs_source_release(cam_frame)
    end

    local chat = make_browser("IVGO: Chat",             append_socket_url(base .. "/02-chat.html?toasts=0", socket_url))
    if chat then
        place(scene, chat, 0, 0, 1920, 1080)
        obs.obs_source_release(chat)
    end

    -- 02 Game's cam PiP sits top-right where the !PLAYING label normally
    -- lives — shift the now-playing source down 110px so the label clears it.
    build_now_playing(scene, np_base, 110)
    build_fire(scene, base, socket_url)
    obs.obs_source_release(scene_src)
end

local function build_camera(base, host, host_role, socket_url, np_base)
    -- Layer order bottom → top:
    --   1. Host Camera  x:320, y:180, w:1280, h:720  (centred in frame)
    --   2. 03-camera.html chrome + nameplate (transparent)

    local scene_src = get_scene_source("IVGO · 03 Camera")
    local scene     = obs.obs_scene_from_source(scene_src)

    local cam = make_capture("IVGO: Host Camera", cam_type())
    if cam then
        place(scene, cam, 320, 180, 1280, 720)
        obs.obs_source_release(cam)
    end

    local cam_params = "host=" .. urlencode(host) .. "&hostRole=" .. urlencode(host_role)
    local overlay = make_browser("IVGO: Camera Overlay", append_socket_url(base .. "/03-camera.html?" .. cam_params, socket_url))
    if overlay then
        place(scene, overlay, 0, 0, 1920, 1080)
        obs.obs_source_release(overlay)
    end

    build_now_playing(scene, np_base)
    build_fire(scene, base, socket_url)
    obs.obs_source_release(scene_src)
end

local function build_brb(base, socket_url, np_base)
    local scene_src = get_scene_source("IVGO · 04 Be Right Back")
    local scene     = obs.obs_scene_from_source(scene_src)
    local src       = make_browser("IVGO: BRB", append_socket_url(base .. "/04-brb.html", socket_url))
    if src then
        place(scene, src, 0, 0, 1920, 1080)
        obs.obs_source_release(src)
    end
    build_now_playing(scene, np_base)
    build_fire(scene, base, socket_url)
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
                   "&topic="     .. urlencode(topic)
    local overlay = make_browser("IVGO: Two-Cam Overlay", append_socket_url(base .. "/05-two-cam.html?" .. params, socket_url))
    if overlay then
        place(scene, overlay, 0, 0, 1920, 1080)
        obs.obs_source_release(overlay)
    end

    build_now_playing(scene, np_base)
    build_fire(scene, base, socket_url)
    obs.obs_source_release(scene_src)
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

    local src = make_browser("IVGO: Ending", append_socket_url(base .. "/06-ending.html", socket_url))
    if src then
        place(scene, src, 0, 0, 1920, 1080)
        obs.obs_source_release(src)
    end
    build_now_playing(scene, np_base)
    build_fire(scene, base, socket_url)
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

    local kb_frame = make_browser("IVGO: Arranging Keyboard Frame", base .. "/08-keyboard-frame.html?toasts=0")
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
                   "&egg_top=64&egg_left=302&egg_h=158"

    local overlay = make_browser("IVGO: Arranging Overlay", append_socket_url(base .. "/07-arranging.html?" .. params, socket_url))
    if overlay then
        place(scene, overlay, 0, 0, 1920, 1080)
        obs.obs_source_release(overlay)
    end

    local cam_frame = make_browser("IVGO: Arranging Cam Outline", append_socket_url(base .. "/07-cam-outline.html?toasts=0", socket_url))
    if cam_frame then
        place(scene, cam_frame, 0, 0, 1920, 1080)
        obs.obs_source_release(cam_frame)
    end

    local chat = make_browser("IVGO: Arranging Chat", append_socket_url(base .. "/07-chat.html?toasts=0", socket_url))
    if chat then
        place(scene, chat, 0, 0, 1920, 1080)
        obs.obs_source_release(chat)
    end

    build_now_playing(scene, np_base)
    build_fire(scene, base, socket_url)
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
    build_ending(base, socket_url, np_base)
    build_arranging(base, arr_piece, arr_collection, arr_sprints_total, arr_focus_mins, arr_break_mins, socket_url, np_base)

    print("[IVGO] Done — 7 scenes created / refreshed.")
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

function script_load(settings)
    settings_ref = settings
    maybe_start_now_playing_watcher()
end

function script_defaults(settings)
    obs.obs_data_set_default_string(settings, "host_name",  "ADAM HUMPHREYS")
    obs.obs_data_set_default_string(settings, "host_role",  "ARTISTIC DIRECTOR")
    obs.obs_data_set_default_string(settings, "guest_name", "GUEST NAME")
    obs.obs_data_set_default_string(settings, "guest_role", "ROLE")
    obs.obs_data_set_default_string(settings, "topic",      "WHY VIDEO GAME MUSIC DESERVES A FULL ORCHESTRA")
    obs.obs_data_set_default_int   (settings, "countdown_mins", 5)
    obs.obs_data_set_default_string(settings, "socket_url", "wss://ivgorchestra.fly.dev/overlay")
    obs.obs_data_set_default_string(settings, "now_playing_http_base", "http://localhost:7779")
    obs.obs_data_set_default_bool  (settings, "auto_start_np", true)

    obs.obs_data_set_default_string(settings, "arr_piece",         "AERITH'S SUITE")
    obs.obs_data_set_default_string(settings, "arr_collection",    "FINAL FANTASY VII REBIRTH")
    obs.obs_data_set_default_int   (settings, "arr_sprints_total",  4)
    obs.obs_data_set_default_int   (settings, "arr_focus_mins",    25)
    obs.obs_data_set_default_int   (settings, "arr_break_mins",     5)
end

function script_properties()
    local props = obs.obs_properties_create()

    obs.obs_properties_add_text(props, "host_name",  "Host name",  obs.OBS_TEXT_DEFAULT)
    obs.obs_properties_add_text(props, "_host_name_hint",
        "Shown in the header bar and camera nameplate.",
        obs.OBS_TEXT_INFO)
    obs.obs_properties_add_text(props, "host_role",  "Host role",  obs.OBS_TEXT_DEFAULT)
    obs.obs_properties_add_text(props, "_host_role_hint",
        "Shown below your name.",
        obs.OBS_TEXT_INFO)
    obs.obs_properties_add_text(props, "guest_name", "Guest name", obs.OBS_TEXT_DEFAULT)
    obs.obs_properties_add_text(props, "_guest_name_hint",
        "Two-Camera scene only.",
        obs.OBS_TEXT_INFO)
    obs.obs_properties_add_text(props, "guest_role", "Guest role", obs.OBS_TEXT_DEFAULT)
    obs.obs_properties_add_text(props, "_guest_role_hint",
        "Two-Camera scene only.",
        obs.OBS_TEXT_INFO)
    obs.obs_properties_add_text(props, "topic",      "Topic",      obs.OBS_TEXT_DEFAULT)
    obs.obs_properties_add_text(props, "_topic_hint",
        "Shown in the topic strip of the Two-Camera scene.",
        obs.OBS_TEXT_INFO)
    obs.obs_properties_add_int (props, "countdown_mins", "Countdown (mins)", 0, 120, 1)
    obs.obs_properties_add_text(props, "_countdown_hint",
        "Minutes the 01 Starting Soon countdown starts at when the scene loads. 0 to hide. Can also be overridden per-source via ?mins=<n> on the browser-source URL.",
        obs.OBS_TEXT_INFO)
    obs.obs_properties_add_text(props, "socket_url", "Socket URL", obs.OBS_TEXT_DEFAULT)
    obs.obs_properties_add_text(props, "_socket_hint",
        "Local: ws://localhost:4000/overlay   Live: wss://ivgorchestra.fly.dev/overlay",
        obs.OBS_TEXT_INFO)

    obs.obs_properties_add_text(props, "now_playing_http_base", "Now-Playing HTTP base", obs.OBS_TEXT_DEFAULT)
    obs.obs_properties_add_text(props, "_now_playing_hint",
        "URL of the SMTC watch script's HTTP server. Default http://localhost:7779 — leave blank to skip the now-playing overlay entirely.",
        obs.OBS_TEXT_INFO)
    obs.obs_properties_add_bool(props, "auto_start_np", "Auto-start Now Playing watcher with OBS")
    obs.obs_properties_add_text(props, "_auto_start_np_hint",
        "When enabled, launches tools/now-playing-watch.ps1 hidden in the background each time this script loads — but only if port 7779 isn't already taken. No more manual powershell.exe + browser-source refresh.",
        obs.OBS_TEXT_INFO)
    obs.obs_properties_add_button(props, "btn_start_np", "Start Now Playing watcher now",
        function(_, _) start_now_playing_watcher(); return true end)

    obs.obs_properties_add_text(props, "arr_piece",         "Arranging: Piece (boot default only — change with !piece in chat)",      obs.OBS_TEXT_DEFAULT)
    obs.obs_properties_add_text(props, "arr_collection",    "Arranging: Game (boot default only — change with !from in chat)",       obs.OBS_TEXT_DEFAULT)
    obs.obs_properties_add_int (props, "arr_sprints_total", "Arranging: total sprints", 1, 12, 1)
    obs.obs_properties_add_int (props, "arr_focus_mins",    "Arranging: focus mins",    1, 90, 1)
    obs.obs_properties_add_int (props, "arr_break_mins",    "Arranging: break mins",    1, 60, 1)
    obs.obs_properties_add_text(props, "_arr_hint",
        "Boot-time defaults for the 07 Arranging scene. Once Phoenix is connected, chat commands (!task, !done, !info, !piece, !from, !pomo) and the LiveView control panel take over.",
        obs.OBS_TEXT_INFO)

    obs.obs_properties_add_button(props, "btn", "Create / Refresh Scenes",
        function(_, _) build_all(); return true end)

    obs.obs_properties_add_button(props, "btn_pull", "Pull latest & refresh",
        function(_, _) pull_latest(); build_all(); return true end)

    return props
end
