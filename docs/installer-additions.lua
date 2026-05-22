-- ivgo_obs_setup.lua — additions for the Arranging scene.
-- Patch the existing installer with the three additions below.
--
-- All three changes are additive — they don't touch any existing function.
-- After applying, re-run "Create / Refresh Scenes" in the Scripts panel and
-- a new "IVGO · 07 Arranging" scene will appear alongside the other six.

-- ── 1. Add a build function ──────────────────────────────────────────────────
-- Drop in alongside the other build_* helpers (above build_all).

local function build_arranging(base, piece, collection, sprints_total, focus_mins, break_mins, socket_url)
    -- Layer order bottom → top:
    --   1. Screen Capture (display)  x:0,  y:0,    w:1920, h:1080  (covers the whole frame)
    --   2. Host Camera               x:24, y:72,   w:282,  h:158   (small PiP top-left)
    --   3. 07-arranging.html         chrome: header, task list, pomo timer, ticker.
    --                                 The "ON THE DESK" workbench strip is hidden by default
    --                                 and only surfaces for 10s when chat fires !info (or a
    --                                 moderator changes !piece / !from).
    --   4. 07-cam-outline.html       cam border frame + "AT THE DESK" badge
    --   5. 07-chat.html              chat panel (right column)

    local scene_src = get_scene_source("IVGO · 07 Arranging")
    local scene     = obs.obs_scene_from_source(scene_src)

    -- Windows uses monitor_capture; macOS uses display_capture. (We deliberately
    -- don't use game_capture here — arranging streams use notation software,
    -- not games.)
    local screen_kind = is_windows() and "monitor_capture" or "display_capture"
    local screen = make_capture("IVGO: Arranging Screen", screen_kind)
    if screen then
        place(scene, screen, 0, 0, 1920, 1080)
        obs.obs_source_release(screen)
    end

    local cam = make_capture("IVGO: Host Camera", cam_type())
    if cam then
        place(scene, cam, 24, 72, 282, 158)
        obs.obs_source_release(cam)
    end

    local params = "piece="       .. urlencode(piece)      ..
                   "&collection=" .. urlencode(collection) ..
                   "&total="      .. urlencode(tostring(sprints_total)) ..
                   "&focus_mins=" .. urlencode(tostring(focus_mins)) ..
                   "&break_mins=" .. urlencode(tostring(break_mins))

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

    obs.obs_source_release(scene_src)
end

-- ── 2. Call it from build_all ────────────────────────────────────────────────
-- Inside build_all(), after build_ending(...), read the new fields and call
-- build_arranging(). Add these lines:

    local piece         = obs.obs_data_get_string(settings_ref, "arr_piece")
    local collection    = obs.obs_data_get_string(settings_ref, "arr_collection")
    local sprints_total = obs.obs_data_get_int   (settings_ref, "arr_sprints_total")
    local focus_mins    = obs.obs_data_get_int   (settings_ref, "arr_focus_mins")
    local break_mins    = obs.obs_data_get_int   (settings_ref, "arr_break_mins")

    build_arranging(base, piece, collection, sprints_total, focus_mins, break_mins, socket_url)

-- ── 3. Defaults + properties ─────────────────────────────────────────────────
-- Inside script_defaults(), add:

    obs.obs_data_set_default_string(settings, "arr_piece",        "AERITH'S SUITE")
    obs.obs_data_set_default_string(settings, "arr_collection",   "FINAL FANTASY VII REBIRTH")
    obs.obs_data_set_default_int   (settings, "arr_sprints_total", 4)
    obs.obs_data_set_default_int   (settings, "arr_focus_mins",   25)
    obs.obs_data_set_default_int   (settings, "arr_break_mins",    5)

-- Inside script_properties(), add (after the "topic" / "_topic_hint" block,
-- before the countdown block — keeps related fields together):

    obs.obs_properties_add_text(props, "arr_piece",        "Arranging: piece",       obs.OBS_TEXT_DEFAULT)
    obs.obs_properties_add_text(props, "arr_collection",   "Arranging: collection",  obs.OBS_TEXT_DEFAULT)
    obs.obs_properties_add_int (props, "arr_sprints_total", "Arranging: total sprints", 1, 12, 1)
    obs.obs_properties_add_int (props, "arr_focus_mins",   "Arranging: focus mins",   1, 90, 1)
    obs.obs_properties_add_int (props, "arr_break_mins",   "Arranging: break mins",   1, 60, 1)
    obs.obs_properties_add_text(props, "_arr_hint",
        "Used by the 07 Arranging scene. These are boot-time defaults — once Phoenix is connected, chat commands (!task, !done, !info, !piece, !from, !pomo) and the LiveView control panel take over.",
        obs.OBS_TEXT_INFO)
