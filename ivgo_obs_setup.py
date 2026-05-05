# ivgo_obs_setup.py — IVGO Overlay Installer for OBS
#
# Install: OBS menu → Tools → Scripts → "+" → select this file.
# Fill fields in the Scripts panel, click "Create / Refresh Scenes".
# Re-run any time to update URLs (e.g. new guest name, new countdown target).
#
# After first run, open each compositing scene (Game, Camera, Two-Cam) and
# right-click the placeholder capture sources to point them at your
# game window and webcam(s).

import sys
import urllib.parse
import obspython as obs

# ── globals ───────────────────────────────────────────────────────────────────

_settings = None


# ── OBS script hooks ─────────────────────────────────────────────────────────

def script_description():
    return (
        "<b>IVGO Overlay Installer</b><br><br>"
        "Builds all seven IVGO scenes in OBS. Fill in the fields then click "
        "<b>Create / Refresh Scenes</b>.<br><br>"
        "Safe to re-run: updates existing scenes rather than duplicating them.<br><br>"
        "After first run, configure the placeholder capture sources in each "
        "compositing scene (Game, Camera, Two-Cam) to point at your devices."
    )


def script_load(settings):
    global _settings
    _settings = settings


def script_defaults(settings):
    obs.obs_data_set_default_string(settings, "base_url",   "https://overlays.ivgorchestra.com/scenes")
    obs.obs_data_set_default_string(settings, "host_name",  "ADAM HUMPHREYS")
    obs.obs_data_set_default_string(settings, "host_role",  "ARTISTIC DIRECTOR")
    obs.obs_data_set_default_string(settings, "guest_name", "GUEST NAME")
    obs.obs_data_set_default_string(settings, "guest_role", "ROLE")
    obs.obs_data_set_default_string(settings, "topic",      "WHY VIDEO GAME MUSIC DESERVES A FULL ORCHESTRA")
    obs.obs_data_set_default_string(settings, "countdown",  "2026-06-06T19:00:00Z")


def script_properties():
    props = obs.obs_properties_create()

    obs.obs_properties_add_text(props, "base_url",   "Overlay base URL",                           obs.OBS_TEXT_DEFAULT)
    obs.obs_properties_add_text(props, "host_name",  "Host name",                                  obs.OBS_TEXT_DEFAULT)
    obs.obs_properties_add_text(props, "host_role",  "Host role",                                  obs.OBS_TEXT_DEFAULT)
    obs.obs_properties_add_text(props, "guest_name", "Guest name  (Two-Cam scene)",                obs.OBS_TEXT_DEFAULT)
    obs.obs_properties_add_text(props, "guest_role", "Guest role  (Two-Cam scene)",                obs.OBS_TEXT_DEFAULT)
    obs.obs_properties_add_text(props, "topic",      "Interview topic  (Two-Cam scene)",           obs.OBS_TEXT_DEFAULT)
    obs.obs_properties_add_text(props, "countdown",  "Countdown target ISO 8601 — e.g. 2026-06-06T19:00:00Z",
                                obs.OBS_TEXT_DEFAULT)

    obs.obs_properties_add_button(props, "btn", "Create / Refresh Scenes", _on_create_clicked)
    return props


def _on_create_clicked(props, prop):
    _build_all()
    return True


# ── low-level helpers ─────────────────────────────────────────────────────────

def _cam_type():
    """Video capture source type for this platform."""
    return "av_capture_input_v2" if sys.platform == "darwin" else "dshow_input"


def _game_type():
    """Game/screen capture source type for this platform."""
    # macOS has no game_capture; display_capture is the closest equivalent.
    # On Windows, game_capture works for most titles and is preferred.
    return "display_capture" if sys.platform == "darwin" else "game_capture"


def _get_scene_source(name):
    """Return an owned source ref for the named scene, creating it if needed.
    Caller must obs.obs_source_release() the result."""
    source = obs.obs_get_source_by_name(name)
    if source:
        return source
    # Create scene — OBS registers it internally (refcount 2: OBS + us).
    scene = obs.obs_scene_create(name)
    # Drop our direct scene ref; OBS keeps its own.
    obs.obs_scene_release(scene)
    # Now grab an owned source ref by name (the normal way).
    return obs.obs_get_source_by_name(name)


def _browser(name, url):
    """Return owned browser source ref, creating or updating URL as needed.
    Caller must obs.obs_source_release() the result."""
    existing = obs.obs_get_source_by_name(name)
    if existing:
        d = obs.obs_data_create()
        obs.obs_data_set_string(d, "url", url)
        obs.obs_source_update(existing, d)
        obs.obs_data_release(d)
        return existing

    d = obs.obs_data_create()
    obs.obs_data_set_string(d, "url",               url)
    obs.obs_data_set_int   (d, "width",             1920)
    obs.obs_data_set_int   (d, "height",            1080)
    obs.obs_data_set_bool  (d, "shutdown",          True)   # pause when hidden
    obs.obs_data_set_bool  (d, "restart_when_active", True) # re-run entrance anims
    obs.obs_data_set_int   (d, "fps",               30)
    src = obs.obs_source_create("browser_source", name, d, None)
    obs.obs_data_release(d)
    return src


def _capture(name, kind):
    """Return owned capture source ref (video or game), creating if needed.
    Created sources have no device selected — user configures via Properties.
    Caller must obs.obs_source_release() the result."""
    existing = obs.obs_get_source_by_name(name)
    if existing:
        return existing
    d = obs.obs_data_create()
    src = obs.obs_source_create(kind, name, d, None)
    obs.obs_data_release(d)
    return src


def _place(scene, source, x, y, w, h):
    """Add source to scene (if not already present) then set position + bounds.

    Sources are added in call order, so call bottom-layer sources first.
    On subsequent runs the item already exists; only position/size are updated.
    """
    src_name = obs.obs_source_get_name(source)

    # Find existing scene item for this source.
    item = None
    items = obs.obs_scene_enum_items(scene)
    if items:
        for it in items:
            if obs.obs_source_get_name(obs.obs_sceneitem_get_source(it)) == src_name:
                item = it
                break
        obs.sceneitem_list_release(items)

    if item is None:
        item = obs.obs_scene_add(scene, source)

    if not item:
        print(f"[IVGO] Warning: could not place source '{src_name}'")
        return

    pos = obs.vec2()
    pos.x, pos.y = float(x), float(y)
    obs.obs_sceneitem_set_pos(item, pos)

    bounds = obs.vec2()
    bounds.x, bounds.y = float(w), float(h)
    obs.obs_sceneitem_set_bounds_type(item, obs.OBS_BOUNDS_SCALE_INNER)
    obs.obs_sceneitem_set_bounds(item, bounds)


# ── scene builders ────────────────────────────────────────────────────────────

def _build_all():
    base      = obs.obs_data_get_string(_settings, "base_url").rstrip("/")
    host      = obs.obs_data_get_string(_settings, "host_name")
    host_role = obs.obs_data_get_string(_settings, "host_role")
    guest     = obs.obs_data_get_string(_settings, "guest_name")
    g_role    = obs.obs_data_get_string(_settings, "guest_role")
    topic     = obs.obs_data_get_string(_settings, "topic")
    countdown = obs.obs_data_get_string(_settings, "countdown")

    _build_starting_soon(base, countdown)
    _build_game(base)
    _build_camera(base)
    _build_brb(base)
    _build_two_cam(base, host, host_role, guest, g_role, topic)
    _build_ending(base)

    print("[IVGO] Done — 6 scenes created / refreshed.")


def _build_starting_soon(base, countdown):
    url = base + "/01-starting-soon.html"
    if countdown:
        url += "?" + urllib.parse.urlencode({"target": countdown})

    scene_src = _get_scene_source("IVGO · 01 Starting Soon")
    scene     = obs.obs_scene_from_source(scene_src)

    src = _browser("IVGO: Starting Soon", url)
    if src:
        _place(scene, src, 0, 0, 1920, 1080)
        obs.obs_source_release(src)

    obs.obs_source_release(scene_src)


def _build_game(base):
    # Layer order bottom → top:
    #   1. Game Capture        x:88,   y:72,  w:1452, h:824
    #   2. Host Camera         x:1570, y:64,  w:340,  h:191  (chamfered cutout)
    #   3. 02-game.html        header + ticker chrome (transparent)
    #   4. 02-cam-outline.html chamfered cam border frame (transparent)
    #   5. 02-chat.html        chat panel bottom-right (transparent)

    scene_src = _get_scene_source("IVGO · 02 Game")
    scene     = obs.obs_scene_from_source(scene_src)

    game = _capture("IVGO: Game Capture", _game_type())
    if game:
        _place(scene, game, 88, 72, 1452, 824)
        obs.obs_source_release(game)

    cam = _capture("IVGO: Host Camera", _cam_type())
    if cam:
        _place(scene, cam, 1570, 64, 340, 191)
        obs.obs_source_release(cam)

    overlay = _browser("IVGO: Game Overlay",   base + "/02-game.html")
    if overlay:
        _place(scene, overlay, 0, 0, 1920, 1080)
        obs.obs_source_release(overlay)

    cam_frame = _browser("IVGO: Cam Outline",  base + "/02-cam-outline.html")
    if cam_frame:
        _place(scene, cam_frame, 0, 0, 1920, 1080)
        obs.obs_source_release(cam_frame)

    chat = _browser("IVGO: Chat",              base + "/02-chat.html")
    if chat:
        _place(scene, chat, 0, 0, 1920, 1080)
        obs.obs_source_release(chat)

    obs.obs_source_release(scene_src)


def _build_camera(base):
    # Layer order bottom → top:
    #   1. Host Camera  x:320, y:180, w:1280, h:720  (centred in frame)
    #   2. 03-camera.html chrome + nameplate (transparent)

    scene_src = _get_scene_source("IVGO · 03 Camera")
    scene     = obs.obs_scene_from_source(scene_src)

    cam = _capture("IVGO: Host Camera", _cam_type())
    if cam:
        _place(scene, cam, 320, 180, 1280, 720)
        obs.obs_source_release(cam)

    overlay = _browser("IVGO: Camera Overlay", base + "/03-camera.html")
    if overlay:
        _place(scene, overlay, 0, 0, 1920, 1080)
        obs.obs_source_release(overlay)

    obs.obs_source_release(scene_src)


def _build_brb(base):
    scene_src = _get_scene_source("IVGO · 04 Be Right Back")
    scene     = obs.obs_scene_from_source(scene_src)

    src = _browser("IVGO: BRB", base + "/04-brb.html")
    if src:
        _place(scene, src, 0, 0, 1920, 1080)
        obs.obs_source_release(src)

    obs.obs_source_release(scene_src)


def _build_two_cam(base, host, host_role, guest, g_role, topic):
    # Layer order bottom → top:
    #   1. Host Camera   x:88,   y:72, w:904, h:858  (left slot)
    #   2. Guest Camera  x:1010, y:72, w:904, h:858  (right slot)
    #   3. 05-two-cam.html chrome + nameplates + topic strip (transparent)

    scene_src = _get_scene_source("IVGO · 05 Two Camera")
    scene     = obs.obs_scene_from_source(scene_src)

    host_cam = _capture("IVGO: Host Camera",  _cam_type())
    if host_cam:
        _place(scene, host_cam, 88, 72, 904, 858)
        obs.obs_source_release(host_cam)

    guest_cam = _capture("IVGO: Guest Camera", _cam_type())
    if guest_cam:
        _place(scene, guest_cam, 1010, 72, 904, 858)
        obs.obs_source_release(guest_cam)

    params = urllib.parse.urlencode({
        "host":      host,
        "hostRole":  host_role,
        "guest":     guest,
        "guestRole": g_role,
        "topic":     topic,
    })
    overlay = _browser("IVGO: Two-Cam Overlay", f"{base}/05-two-cam.html?{params}")
    if overlay:
        _place(scene, overlay, 0, 0, 1920, 1080)
        obs.obs_source_release(overlay)

    obs.obs_source_release(scene_src)


def _build_ending(base):
    scene_src = _get_scene_source("IVGO · 06 Ending")
    scene     = obs.obs_scene_from_source(scene_src)

    src = _browser("IVGO: Ending", base + "/06-ending.html")
    if src:
        _place(scene, src, 0, 0, 1920, 1080)
        obs.obs_source_release(src)

    obs.obs_source_release(scene_src)
