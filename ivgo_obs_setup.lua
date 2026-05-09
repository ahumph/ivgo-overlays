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
    -- Stash any local edits (including untracked), fast-forward, then pop —
    -- so iterating on scenes/*.html between streams doesn't block the pull.
    -- The stash pop is always attempted, even if the pull fails, so a
    -- network blip can never strand local work in the stash list.
    print("[IVGO] Pulling latest…")

    local ok_stash, out_stash = run_git('stash push -u -m "ivgo-pull-autostash"')
    if not ok_stash then
        print("[IVGO] git stash failed — aborting pull:\n" .. out_stash)
        return false
    end
    -- `stash push` with a clean tree returns 0 and prints "No local changes
    -- to save"; we only pop if a stash was actually created.
    local stashed = not out_stash:find("No local changes to save", 1, true)

    local ok_pull, out_pull = run_git("pull --ff-only")
    if out_pull ~= "" then print("[IVGO] git pull:\n" .. out_pull) end
    if not ok_pull then
        print("[IVGO] git pull failed — continuing with local files.")
    end

    if stashed then
        local ok_pop, out_pop = run_git("stash pop")
        if not ok_pop then
            print("[IVGO] git stash pop hit a conflict — your local edits " ..
                  "are still in the stash. Run `git stash list` and resolve " ..
                  "manually:\n" .. out_pop)
        elseif out_pop ~= "" then
            print("[IVGO] git stash pop:\n" .. out_pop)
        end
    end

    return ok_pull
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
    -- (display_capture on macOS ignores capture_audio; harmless to set.)
    local kind = game_type()
    local existing = obs.obs_get_source_by_name(name)
    if existing then
        local d = obs.obs_source_get_settings(existing)
        obs.obs_data_set_bool(d, "capture_audio", true)
        obs.obs_source_update(existing, d)
        obs.obs_data_release(d)
        return existing
    end
    local d = obs.obs_data_create()
    obs.obs_data_set_bool(d, "capture_audio", true)
    local src = obs.obs_source_create(kind, name, d, nil)
    obs.obs_data_release(d)
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
end

-- ── scene builders ────────────────────────────────────────────────────────────

local function build_starting_soon(base, countdown, socket_url)
    local url = base .. "/01-starting-soon.html"
    if countdown ~= "" then
        url = url .. "?target=" .. urlencode(countdown)
    end
    url = append_socket_url(url, socket_url)

    local scene_src = get_scene_source("IVGO · 01 Starting Soon")
    local scene     = obs.obs_scene_from_source(scene_src)
    local src       = make_browser("IVGO: Starting Soon", url)
    if src then
        place(scene, src, 0, 0, 1920, 1080)
        obs.obs_source_release(src)
    end
    obs.obs_source_release(scene_src)
end

local function build_game(base, socket_url)
    -- Layer order bottom → top:
    --   1. Game Capture         x:88,   y:72,  w:1452, h:824
    --   2. Host Camera          x:1570, y:64,  w:340,  h:191  (chamfered cutout)
    --   3. 02-game.html         header + ticker chrome (transparent)
    --   4. 02-cam-outline.html  chamfered cam border frame (transparent)
    --   5. 02-chat.html         chat panel bottom-right (transparent)

    local scene_src = get_scene_source("IVGO · 02 Game")
    local scene     = obs.obs_scene_from_source(scene_src)

    local game = make_game_capture("IVGO: Game Capture")
    if game then
        place(scene, game, 88, 72, 1452, 824)
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

    obs.obs_source_release(scene_src)
end

local function build_camera(base, socket_url)
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

    local overlay = make_browser("IVGO: Camera Overlay", append_socket_url(base .. "/03-camera.html", socket_url))
    if overlay then
        place(scene, overlay, 0, 0, 1920, 1080)
        obs.obs_source_release(overlay)
    end

    obs.obs_source_release(scene_src)
end

local function build_brb(base, socket_url)
    local scene_src = get_scene_source("IVGO · 04 Be Right Back")
    local scene     = obs.obs_scene_from_source(scene_src)
    local src       = make_browser("IVGO: BRB", append_socket_url(base .. "/04-brb.html", socket_url))
    if src then
        place(scene, src, 0, 0, 1920, 1080)
        obs.obs_source_release(src)
    end
    obs.obs_source_release(scene_src)
end

local function build_two_cam(base, host, host_role, guest, g_role, topic, socket_url)
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

    obs.obs_source_release(scene_src)
end

local function build_ending(base, socket_url)
    local scene_src = get_scene_source("IVGO · 06 Ending")
    local scene     = obs.obs_scene_from_source(scene_src)
    local src       = make_browser("IVGO: Ending", append_socket_url(base .. "/06-ending.html", socket_url))
    if src then
        place(scene, src, 0, 0, 1920, 1080)
        obs.obs_source_release(src)
    end
    obs.obs_source_release(scene_src)
end

local function build_all()
    local base       = scenes_base_url()
    local host       = obs.obs_data_get_string(settings_ref, "host_name")
    local host_role  = obs.obs_data_get_string(settings_ref, "host_role")
    local guest      = obs.obs_data_get_string(settings_ref, "guest_name")
    local g_role     = obs.obs_data_get_string(settings_ref, "guest_role")
    local topic      = obs.obs_data_get_string(settings_ref, "topic")
    local countdown  = obs.obs_data_get_string(settings_ref, "countdown")
    local socket_url = obs.obs_data_get_string(settings_ref, "socket_url")

    print("[IVGO] Building scenes from: " .. base)

    build_starting_soon(base, countdown, socket_url)
    build_game(base, socket_url)
    build_camera(base, socket_url)
    build_brb(base, socket_url)
    build_two_cam(base, host, host_role, guest, g_role, topic, socket_url)
    build_ending(base, socket_url)

    print("[IVGO] Done — 6 scenes created / refreshed.")
end

-- ── OBS script hooks ──────────────────────────────────────────────────────────

function script_description()
    return [[<b>IVGO Overlay Installer</b><br><br>
Builds all six IVGO scenes in OBS. Fill in the fields below then click
<b>Create / Refresh Scenes</b>.<br><br>
Safe to re-run: updates existing scenes rather than duplicating them.<br><br>
After the first run, right-click the placeholder capture sources in the
Game, Camera, and Two-Cam scenes to point them at your webcam and game window.]]
end

function script_load(settings)
    settings_ref = settings
end

function script_defaults(settings)
    obs.obs_data_set_default_string(settings, "host_name",  "ADAM HUMPHREYS")
    obs.obs_data_set_default_string(settings, "host_role",  "ARTISTIC DIRECTOR")
    obs.obs_data_set_default_string(settings, "guest_name", "GUEST NAME")
    obs.obs_data_set_default_string(settings, "guest_role", "ROLE")
    obs.obs_data_set_default_string(settings, "topic",      "WHY VIDEO GAME MUSIC DESERVES A FULL ORCHESTRA")
    obs.obs_data_set_default_string(settings, "countdown",  "2026-06-06T19:00:00Z")
    obs.obs_data_set_default_string(settings, "socket_url", "wss://ivgorchestra.fly.dev/overlay")
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
    obs.obs_properties_add_text(props, "countdown",  "Countdown",  obs.OBS_TEXT_DEFAULT)
    obs.obs_properties_add_text(props, "_countdown_hint",
        "Format: YYYY-MM-DDTHH:MM:SSZ (UTC). Example: 2026-06-06T18:00:00Z = 7pm BST. Leave blank for static screen.",
        obs.OBS_TEXT_INFO)
    obs.obs_properties_add_text(props, "socket_url", "Socket URL", obs.OBS_TEXT_DEFAULT)
    obs.obs_properties_add_text(props, "_socket_hint",
        "Local: ws://localhost:4000/overlay   Live: wss://ivgorchestra.fly.dev/overlay",
        obs.OBS_TEXT_INFO)

    obs.obs_properties_add_button(props, "btn", "Create / Refresh Scenes",
        function(_, _) build_all(); return true end)

    obs.obs_properties_add_button(props, "btn_pull", "Pull latest & refresh",
        function(_, _) pull_latest(); build_all(); return true end)

    return props
end
