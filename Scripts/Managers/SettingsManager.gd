extends CanvasLayer

## Global settings service. Because this script is an Autoload, the same UI and
## settings API are available from the main menu, lobby, and any dungeon scene.

const UI_THEME = preload("res://Scripts/UI/ui_theme.gd")
const SETTINGS_PATH := "user://settings.cfg"

const RESOLUTIONS: Array[Vector2i] = [
	Vector2i(1024, 576),
	Vector2i(1280, 720),
	Vector2i(1366, 768),
	Vector2i(1600, 900),
	Vector2i(1920, 1080),
	Vector2i(2560, 1440)
]

const DISPLAY_MODE_WINDOWED := 0
const DISPLAY_MODE_BORDERLESS := 1
const DISPLAY_MODE_EXCLUSIVE := 2

const FPS_LIMITS: Array[int] = [0, 30, 60, 120, 144]
const COMBAT_SPEED_OPTIONS: Array[float] = [1.0, 1.5, 2.0]
const AUTOSAVE_INTERVAL_OPTIONS: Array[float] = [30.0, 60.0, 120.0, 300.0]

const MOVEMENT_MODE_BOTH := 0
const MOVEMENT_MODE_WASD := 1
const MOVEMENT_MODE_CLICK := 2
const CONTROLS_SCHEMA_VERSION := 2

const DEFAULT_KEYBINDINGS := {
	"interact": KEY_E,
	"toggle_backpack": KEY_TAB,
	"quick_potion": KEY_Q,
	"toggle_map": KEY_M,
	"wizard_element": KEY_F,
	"priest_heal": KEY_H,
	"pause_game": KEY_P
}

const KEYBIND_METADATA: Array[Dictionary] = [
	{
		"id": "interact",
		"label": "Interakció / Kijárati kapu",
		"desc": "Interakció a kijárati kapuval a dungeon teljesítésekor."
	},
	{
		"id": "toggle_backpack",
		"label": "Hátizsák megnyitása",
		"desc": "Megnyitja vagy bezárja a hős hátizsákját a dungeonban."
	},
	{
		"id": "quick_potion",
		"label": "Gyors gyógyital",
		"desc": "Azonnal elfogyaszt egy gyógyitalt a hátizsákból."
	},
	{
		"id": "toggle_map",
		"label": "Teljes térkép",
		"desc": "Megnyitja vagy bezárja a teljes képernyős dungeon térképet."
	},
	{
		"id": "wizard_element",
		"label": "Varázsló elemváltás",
		"desc": "Váltás a tűz és a jég elem között (Varázsló kaszt)."
	},
	{
		"id": "priest_heal",
		"label": "Papnő öngyógyítás",
		"desc": "Aktiválja a Papnő önálló gyógyító varázslatát."
	},
	{
		"id": "pause_game",
		"label": "Szünet menü",
		"desc": "Megnyitja a dungeon szünet menüjét (az ESC is működik)."
	}
]

signal settings_changed

# Display & Graphics
var display_mode: int = DISPLAY_MODE_WINDOWED
var fullscreen: bool = false
var window_resolution: Vector2i = Vector2i(1280, 720)
var vsync_enabled: bool = true
var fps_limit: int = 0
var show_fps: bool = false
var fog_mist_scale: float = 1.0
var brightness: float = 1.0

# Audio
var audio_muted: bool = false
var master_volume: float = 0.8
var music_volume: float = 0.75
var sfx_volume: float = 0.85
var mute_when_unfocused: bool = false

# Gameplay & HUD
var camera_zoom: float = 4.0
var combat_speed: float = 1.0
var show_minimap: bool = true
var show_tile_hover: bool = true
var autosave_enabled: bool = true
var autosave_interval_seconds: float = 60.0
var show_settings_button: bool = true

# Controls
var movement_mode: int = MOVEMENT_MODE_BOTH
var keybindings: Dictionary = DEFAULT_KEYBINDINGS.duplicate()

var _config := ConfigFile.new()
var _window_focused: bool = true
var _was_paused_before_open: bool = false
var _active_tab_index: int = 0
var _capturing_action: String = ""
var _fps_update_accum: float = 0.0
var _is_refreshing_ui: bool = false
var _font_refresh_queued: bool = false
var _last_observed_window_size: Vector2i = Vector2i.ZERO

# Runtime overlays & audio
var _brightness_layer: CanvasLayer
var _darken_rect: ColorRect
var _brighten_rect: ColorRect
var _fps_panel: PanelContainer
var _fps_label: Label
var _test_sfx_player: AudioStreamPlayer

# Settings modal controls
var _settings_button: Button
var _overlay: ColorRect
var _panel: PanelContainer
var _status_label: Label
var _reset_button: Button
var _tab_buttons: Array[Button] = []
var _tab_labels: Array[Label] = []
var _tab_pages: Array[Control] = []

# Display controls
var _display_mode_option: OptionButton
var _resolution_option: OptionButton
var _resolution_live_label: Label
var _vsync_toggle: CheckButton
var _fps_limit_option: OptionButton
var _show_fps_toggle: CheckButton
var _fog_mist_slider: HSlider
var _fog_mist_value_label: Label
var _brightness_slider: HSlider
var _brightness_value_label: Label

# Audio controls
var _mute_toggle: CheckButton
var _master_slider: HSlider
var _master_value_label: Label
var _music_slider: HSlider
var _music_value_label: Label
var _sfx_slider: HSlider
var _sfx_value_label: Label
var _mute_unfocused_toggle: CheckButton

# Gameplay controls
var _camera_zoom_slider: HSlider
var _camera_zoom_value_label: Label
var _combat_speed_option: OptionButton
var _show_minimap_toggle: CheckButton
var _show_tile_hover_toggle: CheckButton
var _autosave_toggle: CheckButton
var _autosave_interval_option: OptionButton
var _show_gear_button_toggle: CheckButton

# Controls tab
var _movement_mode_option: OptionButton
var _keybind_buttons: Dictionary = {}


# -----------------------------------------------------------------------------
# Lifecycle, focus notifications, and input handling
# -----------------------------------------------------------------------------

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 110
	_ensure_audio_buses()
	_load_settings()
	_build_runtime_overlays()
	_build_ui()
	_apply_all_settings()
	_refresh_controls()
	var root := get_tree().root
	if root != null and not root.size_changed.is_connected(_on_viewport_size_changed):
		root.size_changed.connect(_on_viewport_size_changed)


func _exit_tree() -> void:
	if display_mode == DISPLAY_MODE_WINDOWED and DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_WINDOWED:
		var live_size := DisplayServer.window_get_size()
		if live_size.x >= 640 and live_size.y >= 360:
			window_resolution = live_size
			_save_settings()


func _on_viewport_size_changed() -> void:
	_sync_live_window_size_if_changed()
	_schedule_font_atlas_refresh()


func _sync_live_window_size_if_changed() -> void:
	var live_size := DisplayServer.window_get_size()
	if live_size.x <= 0 or live_size.y <= 0:
		return
	if live_size == _last_observed_window_size:
		return
	_last_observed_window_size = live_size
	if display_mode == DISPLAY_MODE_WINDOWED and DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_WINDOWED:
		window_resolution = live_size
	_sync_resolution_control(live_size)


func _schedule_font_atlas_refresh() -> void:
	if _font_refresh_queued or not is_inside_tree():
		return
	_font_refresh_queued = true
	call_deferred("_flush_font_atlas_next_frame")


func _flush_font_atlas_next_frame() -> void:
	if not is_inside_tree():
		_font_refresh_queued = false
		return
	await get_tree().process_frame
	await get_tree().process_frame
	_font_refresh_queued = false
	if not is_inside_tree():
		return
	var ts := TextServerManager.get_primary_interface()
	var fallback_font := ThemeDB.fallback_font
	if ts != null and fallback_font != null:
		for rid in fallback_font.get_rids():
			if ts.has_method("font_clear_size_cache"):
				ts.font_clear_size_cache(rid)
	var root := get_tree().root
	if root != null:
		root.propagate_notification(Control.NOTIFICATION_THEME_CHANGED)


func _process(delta: float) -> void:
	_sync_live_window_size_if_changed()

	if _settings_button != null:
		var dm := get_node_or_null("/root/DungeonManager")
		var loading: bool = dm != null and dm.has_method("is_loading_dungeon") and bool(dm.is_loading_dungeon())
		_settings_button.visible = show_settings_button and not loading and not is_open()

	if _fps_panel != null and _fps_panel.visible:
		_fps_update_accum += delta
		if _fps_update_accum >= 0.25:
			_fps_update_accum = 0.0
			_fps_label.text = "FPS: %d" % Engine.get_frames_per_second()


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		_window_focused = false
		if mute_when_unfocused:
			_apply_audio_settings()
	elif what == NOTIFICATION_APPLICATION_FOCUS_IN:
		_window_focused = true
		if mute_when_unfocused:
			_apply_audio_settings()


func _mark_input_handled() -> void:
	if not is_inside_tree():
		return
	var vp := get_viewport()
	if vp != null and vp.is_inside_tree():
		vp.set_input_as_handled()


func _input(event: InputEvent) -> void:
	if not is_inside_tree():
		return
	var dm := get_node_or_null("/root/DungeonManager")
	if dm != null and dm.has_method("is_loading_dungeon") and dm.is_loading_dungeon():
		return
	if not (event is InputEventKey):
		return
	var key_event := event as InputEventKey
	if not key_event.pressed or key_event.echo:
		return

	if is_open() and not _capturing_action.is_empty():
		var captured_code := key_event.keycode if key_event.keycode != KEY_NONE else key_event.physical_keycode
		if captured_code == KEY_ESCAPE:
			_cancel_keybind_capture()
			_set_status("Billentyűkiosztás megszakítva.", false)
			_mark_input_handled()
			return
		if _is_rebindable_keycode(captured_code):
			var action_id := _capturing_action
			_capturing_action = ""
			set_keybind(action_id, captured_code)
			_set_status("Új billentyű beállítva: %s" % get_keybind_label(action_id), true)
			_mark_input_handled()
			return
		_set_status("Ez a billentyű nem használható. Próbálj egy betűt, számot vagy F-billentyűt.", false)
		_mark_input_handled()
		return

	var is_f10 := key_event.keycode == KEY_F10 or key_event.physical_keycode == KEY_F10
	var is_esc := key_event.keycode == KEY_ESCAPE or key_event.physical_keycode == KEY_ESCAPE
	if is_f10:
		toggle_settings()
		_mark_input_handled()
	elif is_esc and is_open():
		close_settings()
		_mark_input_handled()


# -----------------------------------------------------------------------------
# Public settings API (safe to call from any scene)
# -----------------------------------------------------------------------------

func is_open() -> bool:
	return _overlay != null and _overlay.visible


func open_settings() -> void:
	var dm := get_node_or_null("/root/DungeonManager")
	if dm != null and dm.has_method("is_loading_dungeon") and dm.is_loading_dungeon():
		return
	if _overlay == null or is_open():
		return
	_capturing_action = ""
	_was_paused_before_open = get_tree().paused
	get_tree().paused = true
	_overlay.show()
	_panel.show()
	_panel.move_to_front()
	_select_tab(_active_tab_index)
	_refresh_controls()
	_set_status("A módosítások azonnal érvénybe lépnek és automatikusan mentődnek.", false)
	AudioManager.sfx(&"ui_window_open")


func close_settings() -> void:
	if _overlay == null or not is_open():
		return
	_cancel_keybind_capture()
	_save_settings()
	_overlay.hide()
	_panel.hide()
	if not _was_paused_before_open:
		get_tree().paused = false
	AudioManager.sfx(&"ui_window_close")


func toggle_settings() -> void:
	if is_open():
		close_settings()
	else:
		open_settings()


# Display setters
func set_display_mode(mode: int) -> void:
	display_mode = clampi(mode, DISPLAY_MODE_WINDOWED, DISPLAY_MODE_EXCLUSIVE)
	fullscreen = display_mode != DISPLAY_MODE_WINDOWED
	_apply_display_settings()
	_refresh_controls()
	_commit_setting_change("Ablak mód frissítve.")


func set_fullscreen(enabled: bool) -> void:
	set_display_mode(DISPLAY_MODE_BORDERLESS if enabled else DISPLAY_MODE_WINDOWED)


func set_window_resolution(resolution: Vector2i) -> void:
	if resolution.x < 640 or resolution.y < 360:
		return
	window_resolution = resolution
	_apply_display_settings()
	_last_observed_window_size = DisplayServer.window_get_size()
	_sync_resolution_control(_last_observed_window_size)
	_commit_setting_change("Felbontás: %d × %d" % [resolution.x, resolution.y])


func set_vsync(enabled: bool) -> void:
	vsync_enabled = enabled
	_apply_vsync()
	_commit_setting_change("VSync %s." % ("bekapcsolva" if enabled else "kikapcsolva"))


func set_fps_limit(limit: int) -> void:
	fps_limit = limit if FPS_LIMITS.has(limit) else 0
	_apply_fps_limit()
	var label_text := "Korlátlan" if fps_limit <= 0 else "%d FPS" % fps_limit
	_commit_setting_change("Max. képkockaszám: %s" % label_text)


func set_show_fps(enabled: bool) -> void:
	show_fps = enabled
	_apply_fps_overlay()
	_commit_setting_change("FPS számláló %s." % ("bekapcsolva" if enabled else "kikapcsolva"))


func set_fog_mist_scale(value: float) -> void:
	fog_mist_scale = clampf(value, 0.0, 1.0)
	_commit_setting_change("Dungeon köd-effekt: %d%%" % roundi(fog_mist_scale * 100.0))


func set_brightness(value: float) -> void:
	brightness = clampf(value, 0.7, 1.3)
	_apply_brightness()
	_commit_setting_change("Fényerő: %d%%" % roundi(brightness * 100.0))


# Audio setters
func set_audio_muted(muted: bool) -> void:
	audio_muted = muted
	_apply_audio_settings()
	_commit_setting_change("Hang %s." % ("elnémítva" if muted else "visszakapcsolva"))


func set_master_volume(value: float) -> void:
	master_volume = clampf(value, 0.0, 1.0)
	_apply_audio_settings()
	_commit_setting_change("Fő hangerő: %d%%" % roundi(master_volume * 100.0))


func set_music_volume(value: float) -> void:
	music_volume = clampf(value, 0.0, 1.0)
	_apply_audio_settings()
	_commit_setting_change("Zene hangerő: %d%%" % roundi(music_volume * 100.0))


func set_sfx_volume(value: float) -> void:
	sfx_volume = clampf(value, 0.0, 1.0)
	_apply_audio_settings()
	_commit_setting_change("Hangeffektek: %d%%" % roundi(sfx_volume * 100.0))


func set_mute_when_unfocused(enabled: bool) -> void:
	mute_when_unfocused = enabled
	_apply_audio_settings()
	_commit_setting_change("Háttérbe váltáskori némítás %s." % ("be" if enabled else "ki"))


func play_test_sound() -> void:
	if _test_sfx_player == null:
		return
	var sfx_idx := AudioServer.get_bus_index("SFX")
	_test_sfx_player.bus = &"SFX" if sfx_idx >= 0 else &"Master"
	_test_sfx_player.stop()
	_test_sfx_player.play()
	if audio_muted or master_volume <= 0.001 or sfx_volume <= 0.001:
		_set_status("A hang jelenleg le van némítva vagy 0%-on áll.", false)
	else:
		_set_status("Teszt hang lejátszva.", true)


# Gameplay & HUD setters
func set_camera_zoom(value: float) -> void:
	camera_zoom = clampf(value, 2.5, 6.0)
	_commit_setting_change("Kamera közelítés: %.2f×" % camera_zoom)


func set_combat_speed(speed_value: float) -> void:
	combat_speed = clampf(speed_value, 1.0, 2.0)
	_commit_setting_change("Harc sebessége: %.1f×" % combat_speed)


func set_show_minimap(enabled: bool) -> void:
	show_minimap = enabled
	_commit_setting_change("Mini-térkép %s." % ("látható" if enabled else "rejtve"))


func set_show_tile_hover(enabled: bool) -> void:
	show_tile_hover = enabled
	_commit_setting_change("Célmező kijelölés %s." % ("bekapcsolva" if enabled else "kikapcsolva"))


func set_autosave_enabled(enabled: bool) -> void:
	autosave_enabled = enabled
	_refresh_controls()
	_commit_setting_change("Automatikus mentés %s." % ("bekapcsolva" if enabled else "kikapcsolva"))


func set_autosave_interval(seconds: float) -> void:
	autosave_interval_seconds = clampf(seconds, 15.0, 600.0)
	_commit_setting_change("Automatikus mentés: %d mp" % int(round(autosave_interval_seconds)))


func set_show_settings_button(enabled: bool) -> void:
	show_settings_button = enabled
	_commit_setting_change("Gyors beállítás gomb %s (F10 mindig elérhető)." % ("látható" if enabled else "rejtve"))


# Controls & Keybindings API
func set_movement_mode(mode: int) -> void:
	movement_mode = clampi(mode, MOVEMENT_MODE_BOTH, MOVEMENT_MODE_CLICK)
	var labels := ["WASD + Egér", "Csak WASD / Nyilak", "Csak egér (Kattintás)"]
	_commit_setting_change("Mozgás vezérlése: %s" % labels[movement_mode])


func is_wasd_movement_enabled() -> bool:
	return movement_mode == MOVEMENT_MODE_BOTH or movement_mode == MOVEMENT_MODE_WASD


func is_click_movement_enabled() -> bool:
	return movement_mode == MOVEMENT_MODE_BOTH or movement_mode == MOVEMENT_MODE_CLICK


func get_keybind(action_id: String) -> int:
	return int(keybindings.get(action_id, DEFAULT_KEYBINDINGS.get(action_id, KEY_NONE)))


func get_keybind_label(action_id: String) -> String:
	var code := get_keybind(action_id)
	if code == KEY_NONE:
		return "-"
	return OS.get_keycode_string(code)


func matches_keybind(event: InputEvent, action_id: String) -> bool:
	if not (event is InputEventKey):
		return false
	var key_event := event as InputEventKey
	var expected := get_keybind(action_id)
	if expected == KEY_NONE:
		return false
	return key_event.keycode == expected or key_event.physical_keycode == expected


func set_keybind(action_id: String, keycode: int) -> void:
	if not DEFAULT_KEYBINDINGS.has(action_id) or not _is_rebindable_keycode(keycode):
		return
	var previous_code := get_keybind(action_id)
	# Swap if another action already uses this key so there are never hidden conflicts.
	for other_id in keybindings.keys():
		if String(other_id) != action_id and int(keybindings[other_id]) == keycode:
			keybindings[other_id] = previous_code
	keybindings[action_id] = keycode
	_refresh_controls()
	_save_settings()
	settings_changed.emit()


func reset_keybindings() -> void:
	_cancel_keybind_capture()
	keybindings = DEFAULT_KEYBINDINGS.duplicate()
	_refresh_controls()
	_commit_setting_change("Billentyűkiosztás visszaállítva alapértelmezettre.")


func reset_to_defaults() -> void:
	_cancel_keybind_capture()
	display_mode = DISPLAY_MODE_WINDOWED
	fullscreen = false
	window_resolution = Vector2i(1280, 720)
	vsync_enabled = true
	fps_limit = 0
	show_fps = false
	fog_mist_scale = 1.0
	brightness = 1.0

	audio_muted = false
	master_volume = 0.8
	music_volume = 0.75
	sfx_volume = 0.85
	mute_when_unfocused = false

	camera_zoom = 4.0
	combat_speed = 1.0
	show_minimap = true
	show_tile_hover = true
	autosave_enabled = true
	autosave_interval_seconds = 60.0
	show_settings_button = true

	movement_mode = MOVEMENT_MODE_BOTH
	keybindings = DEFAULT_KEYBINDINGS.duplicate()

	_apply_all_settings()
	_refresh_controls()
	_save_settings()
	settings_changed.emit()
	_set_status("Minden beállítás visszaállítva alapértelmezettre.", true)


func reset_active_category_to_defaults() -> void:
	reset_category_to_defaults(_active_tab_index)


func reset_category_to_defaults(tab_index: int) -> void:
	var status_msg: String = ""
	match clampi(tab_index, 0, 3):
		0:
			display_mode = DISPLAY_MODE_WINDOWED
			fullscreen = false
			window_resolution = Vector2i(1280, 720)
			vsync_enabled = true
			fps_limit = 0
			show_fps = false
			fog_mist_scale = 1.0
			brightness = 1.0
			_apply_display_settings()
			_apply_vsync()
			_apply_fps_limit()
			_apply_fps_overlay()
			_apply_brightness()
			status_msg = "Megjelenítés beállításai visszaállítva alapértelmezettre."
		1:
			audio_muted = false
			master_volume = 0.8
			music_volume = 0.75
			sfx_volume = 0.85
			mute_when_unfocused = false
			_apply_audio_settings()
			status_msg = "Hang beállítások visszaállítva alapértelmezettre."
		2:
			camera_zoom = 4.0
			combat_speed = 1.0
			show_minimap = true
			show_tile_hover = true
			autosave_enabled = true
			autosave_interval_seconds = 60.0
			show_settings_button = true
			status_msg = "Játékmenet beállításai visszaállítva alapértelmezettre."
		3:
			_cancel_keybind_capture()
			movement_mode = MOVEMENT_MODE_BOTH
			keybindings = DEFAULT_KEYBINDINGS.duplicate()
			status_msg = "Irányítás beállításai visszaállítva alapértelmezettre."

	_refresh_controls()
	_save_settings()
	settings_changed.emit()
	_set_status(status_msg, true)


func _commit_setting_change(status_message: String) -> void:
	_save_settings()
	settings_changed.emit()
	_set_status(status_message, true)


func _is_rebindable_keycode(code: int) -> bool:
	if code == KEY_NONE or code == KEY_ESCAPE or code == KEY_F10:
		return false
	if code in [KEY_SHIFT, KEY_CTRL, KEY_ALT, KEY_META, KEY_CAPSLOCK]:
		return false
	if code in [KEY_W, KEY_A, KEY_S, KEY_D, KEY_UP, KEY_DOWN, KEY_LEFT, KEY_RIGHT]:
		return false
	return true


# -----------------------------------------------------------------------------
# Runtime overlays (Brightness, FPS Counter, Procedural Test Chime)
# -----------------------------------------------------------------------------

func _ensure_audio_buses() -> void:
	for bus_name in ["Music", "SFX"]:
		if AudioServer.get_bus_index(bus_name) == -1:
			var idx := AudioServer.bus_count
			AudioServer.add_bus(idx)
			AudioServer.set_bus_name(idx, bus_name)
			AudioServer.set_bus_send(idx, &"Master")


func _build_runtime_overlays() -> void:
	_brightness_layer = CanvasLayer.new()
	_brightness_layer.name = "BrightnessOverlayLayer"
	_brightness_layer.layer = 95
	_brightness_layer.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(_brightness_layer)

	_darken_rect = ColorRect.new()
	_darken_rect.name = "BrightnessDarken"
	_darken_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_darken_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_darken_rect.color = Color(0.0, 0.0, 0.0, 0.0)
	_darken_rect.visible = false
	_brightness_layer.add_child(_darken_rect)

	_brighten_rect = ColorRect.new()
	_brighten_rect.name = "BrightnessLift"
	_brighten_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_brighten_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_brighten_rect.color = Color(1.0, 0.98, 0.94, 0.0)
	var add_mat := CanvasItemMaterial.new()
	add_mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	_brighten_rect.material = add_mat
	_brighten_rect.visible = false
	_brightness_layer.add_child(_brighten_rect)

	_fps_panel = PanelContainer.new()
	_fps_panel.name = "FpsCounterPanel"
	_fps_panel.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	_fps_panel.anchor_left = 0.0
	_fps_panel.anchor_top = 1.0
	_fps_panel.anchor_right = 0.0
	_fps_panel.anchor_bottom = 1.0
	_fps_panel.offset_left = 14.0
	_fps_panel.offset_top = -42.0
	_fps_panel.offset_right = 104.0
	_fps_panel.offset_bottom = -14.0
	_fps_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fps_panel.add_theme_stylebox_override(
		"panel",
		UI_THEME.make_box(Color(0.03, 0.045, 0.075, 0.85), Color(0.58, 0.46, 0.26, 0.85), 1, 6)
	)
	_fps_panel.visible = false
	add_child(_fps_panel)

	_fps_label = Label.new()
	_fps_label.text = "FPS: 60"
	_fps_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_fps_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_fps_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fps_label.add_theme_font_size_override("font_size", 12)
	_fps_label.add_theme_color_override("font_color", Color(0.75, 0.95, 0.72, 1.0))
	_fps_panel.add_child(_fps_label)

	_test_sfx_player = AudioStreamPlayer.new()
	_test_sfx_player.name = "TestSfxPlayer"
	_test_sfx_player.process_mode = Node.PROCESS_MODE_ALWAYS
	_test_sfx_player.stream = _build_test_chime_stream()
	add_child(_test_sfx_player)


func _build_test_chime_stream() -> AudioStreamWAV:
	var sample_rate := 22050
	var duration := 0.28
	var sample_count := int(sample_rate * duration)
	var data := PackedByteArray()
	data.resize(sample_count * 2)
	for i in range(sample_count):
		var t := float(i) / float(sample_rate)
		var env := pow(1.0 - (t / duration), 1.8) * minf(t / 0.012, 1.0)
		var wave := sin(TAU * 587.33 * t) * 0.55 + sin(TAU * 880.0 * t) * 0.35
		var s := clampi(int(round(wave * env * 22000.0)), -32768, 32767)
		data[i * 2] = s & 0xFF
		data[i * 2 + 1] = (s >> 8) & 0xFF
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = sample_rate
	wav.stereo = false
	wav.data = data
	return wav


# -----------------------------------------------------------------------------
# Settings modal UI construction
# -----------------------------------------------------------------------------

func _build_ui() -> void:
	_settings_button = Button.new()
	_settings_button.name = "GlobalSettingsButton"
	_settings_button.anchor_left = 1.0
	_settings_button.anchor_top = 1.0
	_settings_button.anchor_right = 1.0
	_settings_button.anchor_bottom = 1.0
	_settings_button.offset_left = -74.0
	_settings_button.offset_right = -18.0
	_settings_button.offset_top = -74.0
	_settings_button.offset_bottom = -18.0
	_settings_button.text = ""
	_settings_button.icon = load(UiIcons.SETTINGS) as Texture2D
	_settings_button.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	_settings_button.tooltip_text = "Beállítások (F10)"
	_settings_button.custom_minimum_size = Vector2(56, 56)
	_settings_button.focus_mode = Control.FOCUS_NONE
	UI_THEME.style_button(_settings_button, Color("8baac7"), true)
	_settings_button.alignment = HORIZONTAL_ALIGNMENT_CENTER
	_settings_button.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_settings_button.pressed.connect(open_settings)
	add_child(_settings_button)

	_overlay = ColorRect.new()
	_overlay.name = "GlobalSettingsOverlay"
	_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_overlay.color = Color(0.006, 0.012, 0.026, 0.84)
	_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	_overlay.visible = false
	add_child(_overlay)

	_panel = PanelContainer.new()
	_panel.name = "GlobalSettingsPanel"
	_panel.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	_panel.anchor_left = 0.5
	_panel.anchor_top = 0.5
	_panel.anchor_right = 0.5
	_panel.anchor_bottom = 0.5
	_panel.offset_left = -410.0
	_panel.offset_top = -305.0
	_panel.offset_right = 410.0
	_panel.offset_bottom = 305.0
	_panel.custom_minimum_size = Vector2(820, 610)
	_panel.visible = false
	UI_THEME.style_panel(_panel, Color("d8b56c"), Color(0.024, 0.042, 0.072, 0.99))
	add_child(_panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 24)
	margin.add_theme_constant_override("margin_top", 18)
	margin.add_theme_constant_override("margin_right", 24)
	margin.add_theme_constant_override("margin_bottom", 18)
	_panel.add_child(margin)

	var layout := VBoxContainer.new()
	layout.add_theme_constant_override("separation", 12)
	margin.add_child(layout)

	# Header
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 10)
	layout.add_child(header)

	header.add_child(UiIcons.make_icon_rect(UiIcons.SETTINGS, Vector2(26, 26)))

	var title_box := VBoxContainer.new()
	title_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_box.add_theme_constant_override("separation", 1)
	header.add_child(title_box)

	var heading := _make_label("BEÁLLÍTÁSOK", 24, UI_THEME.GOLD)
	title_box.add_child(heading)

	var subtitle := _make_label("F10: megnyitás / bezárás   •   ESC: bezárás   •   Külön fájlba mentve (settings.cfg)", 12, UI_THEME.MUTED)
	title_box.add_child(subtitle)

	var close_x := Button.new()
	UI_THEME.style_button(close_x, Color(0.65, 0.55, 0.45, 1.0), false)
	for state_name in ["normal", "hover", "pressed", "focus"]:
		var sb := close_x.get_theme_stylebox(state_name)
		if sb is StyleBoxFlat:
			var compact_sb := sb.duplicate() as StyleBoxFlat
			compact_sb.content_margin_left = 6.0
			compact_sb.content_margin_right = 6.0
			compact_sb.content_margin_top = 6.0
			compact_sb.content_margin_bottom = 6.0
			close_x.add_theme_stylebox_override(state_name, compact_sb)
	close_x.custom_minimum_size = Vector2(40, 40)
	close_x.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	UiIcons.apply_button_icon(close_x, UiIcons.CLOSE, 18)
	close_x.alignment = HORIZONTAL_ALIGNMENT_CENTER
	close_x.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	close_x.pressed.connect(close_settings)
	header.add_child(close_x)

	# Category tabs (strictly fixed 178x42 slots — cannot expand vertically or horizontally)
	var tab_bar := HBoxContainer.new()
	tab_bar.alignment = BoxContainer.ALIGNMENT_CENTER
	tab_bar.custom_minimum_size = Vector2(0, 42)
	tab_bar.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	tab_bar.add_theme_constant_override("separation", 8)
	layout.add_child(tab_bar)

	var tabs := [
		{"label": "MEGJELENÍTÉS", "icon": UiIcons.VISION},
		{"label": "HANG", "icon": UiIcons.SPARKLE},
		{"label": "JÁTÉKMENET", "icon": UiIcons.PLAY_SWORD},
		{"label": "IRÁNYÍTÁS", "icon": UiIcons.SCROLL}
	]
	_tab_buttons.clear()
	_tab_labels.clear()
	for i in range(tabs.size()):
		var tab_slot := Control.new()
		tab_slot.custom_minimum_size = Vector2(178, 42)
		tab_slot.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		tab_slot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		tab_slot.clip_contents = true
		tab_bar.add_child(tab_slot)

		var tab_btn := Button.new()
		tab_btn.text = ""
		tab_btn.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		tab_btn.focus_mode = Control.FOCUS_NONE
		tab_btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		tab_btn.pressed.connect(_select_tab.bind(i))
		tab_slot.add_child(tab_btn)

		var tab_inner := HBoxContainer.new()
		tab_inner.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		tab_inner.alignment = BoxContainer.ALIGNMENT_CENTER
		tab_inner.mouse_filter = Control.MOUSE_FILTER_IGNORE
		tab_inner.add_theme_constant_override("separation", 7)
		tab_btn.add_child(tab_inner)

		var tab_icon := UiIcons.make_icon_rect(String(tabs[i]["icon"]), Vector2(18, 18))
		tab_icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		tab_inner.add_child(tab_icon)

		var tab_label := _make_label(String(tabs[i]["label"]), 13, UI_THEME.IVORY)
		tab_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		tab_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		tab_inner.add_child(tab_label)

		_tab_buttons.append(tab_btn)
		_tab_labels.append(tab_label)
		_style_tab_button(i, i == 0)

	# Recessed content area
	var content_frame := PanelContainer.new()
	content_frame.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content_frame.add_theme_stylebox_override(
		"panel",
		UI_THEME.make_box(Color(0.015, 0.026, 0.046, 0.96), Color(0.36, 0.44, 0.58, 0.65), 1, 10)
	)
	layout.add_child(content_frame)

	var content_margin := MarginContainer.new()
	content_margin.add_theme_constant_override("margin_left", 14)
	content_margin.add_theme_constant_override("margin_top", 12)
	content_margin.add_theme_constant_override("margin_right", 14)
	content_margin.add_theme_constant_override("margin_bottom", 12)
	content_frame.add_child(content_margin)

	_tab_pages.clear()
	var display_page := _create_scrollable_page(content_margin)
	_build_display_tab(display_page)
	var audio_page := _create_scrollable_page(content_margin)
	_build_audio_tab(audio_page)
	var gameplay_page := _create_scrollable_page(content_margin)
	_build_gameplay_tab(gameplay_page)
	var controls_page := _create_scrollable_page(content_margin)
	_build_controls_tab(controls_page)

	# Status feedback label
	_status_label = _make_label("A módosítások azonnal érvénybe lépnek és automatikusan mentődnek.", 12, UI_THEME.MUTED)
	_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	layout.add_child(_status_label)

	# Footer
	var footer := HBoxContainer.new()
	footer.add_theme_constant_override("separation", 12)
	layout.add_child(footer)

	_reset_button = Button.new()
	_reset_button.text = "ALAPÉRTELMEZETT"
	UI_THEME.style_button(_reset_button, Color(0.76, 0.48, 0.36, 1.0), false)
	_reset_button.custom_minimum_size = Vector2(210, 44)
	UiIcons.apply_button_icon(_reset_button, UiIcons.RESTART, 16)
	_reset_button.add_theme_font_size_override("font_size", 14)
	_reset_button.alignment = HORIZONTAL_ALIGNMENT_CENTER
	_reset_button.pressed.connect(reset_active_category_to_defaults)
	footer.add_child(_reset_button)

	var footer_spacer := Control.new()
	footer_spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	footer.add_child(footer_spacer)

	var close_button := Button.new()
	close_button.text = "MENTÉS ÉS VISSZA"
	UI_THEME.style_button(close_button, Color("d8b56c"), true)
	close_button.custom_minimum_size = Vector2(220, 44)
	close_button.add_theme_font_size_override("font_size", 14)
	close_button.alignment = HORIZONTAL_ALIGNMENT_CENTER
	close_button.pressed.connect(close_settings)
	footer.add_child(close_button)

	_select_tab(0)


func _create_scrollable_page(parent: Control) -> VBoxContainer:
	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	parent.add_child(scroll)

	var vbox := VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_theme_constant_override("separation", 10)
	scroll.add_child(vbox)

	_tab_pages.append(scroll)
	return vbox


func _build_display_tab(page: VBoxContainer) -> void:
	_display_mode_option = OptionButton.new()
	_display_mode_option.custom_minimum_size = Vector2(235, 36)
	_display_mode_option.add_item("Ablakos")
	_display_mode_option.add_item("Keret nélküli teljes képernyő")
	_display_mode_option.add_item("Teljes képernyő (Exkluzív)")
	_display_mode_option.item_selected.connect(_on_display_mode_selected)
	_add_setting_row(page, "Ablak mód", "Válassz ablakos, keret nélküli vagy exkluzív teljes képernyős nézetet.", _display_mode_option)

	var res_box := VBoxContainer.new()
	res_box.add_theme_constant_override("separation", 3)
	_resolution_option = OptionButton.new()
	_resolution_option.custom_minimum_size = Vector2(235, 36)
	for res in RESOLUTIONS:
		_resolution_option.add_item("%d × %d" % [res.x, res.y])
	_resolution_option.item_selected.connect(_on_resolution_selected)
	res_box.add_child(_resolution_option)

	_resolution_live_label = _make_label("Aktuális: 1280 × 720", 12, UI_THEME.GOLD)
	_resolution_live_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	res_box.add_child(_resolution_live_label)

	_add_setting_row(page, "Ablakfelbontás", "Ablakos módban élőben követi az ablak átméretezését is; a listából előre beállított méretet választhatsz.", res_box)

	_vsync_toggle = CheckButton.new()
	_vsync_toggle.toggled.connect(_on_vsync_toggled)
	_add_setting_row(page, "Függőleges szinkronizálás (VSync)", "Megakadályozza a képtörést (screen tearing) a monitor frissítéséhez igazítva.", _vsync_toggle)

	_fps_limit_option = OptionButton.new()
	_fps_limit_option.custom_minimum_size = Vector2(235, 36)
	for limit in FPS_LIMITS:
		_fps_limit_option.add_item("Korlátlan" if limit <= 0 else "%d FPS" % limit)
	_fps_limit_option.item_selected.connect(_on_fps_limit_selected)
	_add_setting_row(page, "Max. képkockaszám (FPS limit)", "Korlátozza a maximális FPS-t a kisebb terhelés és hőtermelés érdekében.", _fps_limit_option)

	_show_fps_toggle = CheckButton.new()
	_show_fps_toggle.toggled.connect(_on_show_fps_toggled)
	_add_setting_row(page, "FPS számláló megjelenítése", "Élő képkockaszám kijelzése a képernyő bal alsó sarkában.", _show_fps_toggle)

	var mist_controls := _make_slider_control(0.0, 1.0, 0.05, 190)
	_fog_mist_slider = mist_controls["slider"]
	_fog_mist_value_label = mist_controls["value_label"]
	_fog_mist_slider.value_changed.connect(_on_fog_mist_changed)
	_add_setting_row(page, "Dungeon köd-effekt erőssége", "A Fog of War mozgó köd shaderének intenzitása (0% = tiszta, éles sötétség).", mist_controls["box"])

	var bright_controls := _make_slider_control(0.7, 1.3, 0.05, 190)
	_brightness_slider = bright_controls["slider"]
	_brightness_value_label = bright_controls["value_label"]
	_brightness_slider.value_changed.connect(_on_brightness_changed)
	_add_setting_row(page, "Képernyő fényerő", "Világosítja vagy sötétíti a teljes játékteret a sötét kazamatákban.", bright_controls["box"])


func _build_audio_tab(page: VBoxContainer) -> void:
	_mute_toggle = CheckButton.new()
	_mute_toggle.toggled.connect(_on_mute_toggled)
	_add_setting_row(page, "Összes hang némítása", "Azonnal elnémítja a játék minden hangcsatornáját.", _mute_toggle)

	var master_controls := _make_slider_control(0.0, 1.0, 0.05, 200)
	_master_slider = master_controls["slider"]
	_master_value_label = master_controls["value_label"]
	_master_slider.value_changed.connect(_on_master_volume_changed)
	_add_setting_row(page, "Fő hangerő (Master)", "Minden hangcsatorna globális hangereje.", master_controls["box"])

	var music_controls := _make_slider_control(0.0, 1.0, 0.05, 200)
	_music_slider = music_controls["slider"]
	_music_value_label = music_controls["value_label"]
	_music_slider.value_changed.connect(_on_music_volume_changed)
	_add_setting_row(page, "Zene hangerő (Music)", "Háttérzene csatorna hangereje.", music_controls["box"])

	var sfx_controls := _make_slider_control(0.0, 1.0, 0.05, 200)
	_sfx_slider = sfx_controls["slider"]
	_sfx_value_label = sfx_controls["value_label"]
	_sfx_slider.value_changed.connect(_on_sfx_volume_changed)
	_add_setting_row(page, "Hangeffektek (SFX)", "Harci, felületi és visszajelző hangok csatornája.", sfx_controls["box"])

	_mute_unfocused_toggle = CheckButton.new()
	_mute_unfocused_toggle.toggled.connect(_on_mute_unfocused_toggled)
	_add_setting_row(page, "Némítás háttérbe váltáskor", "Alt+Tab esetén automatikusan elnémítja a játékot, visszatéréskor visszaállítja.", _mute_unfocused_toggle)

	var test_btn := Button.new()
	test_btn.text = "HANGTESZT"
	UI_THEME.style_button(test_btn, Color(0.45, 0.78, 0.62, 1.0), true)
	test_btn.custom_minimum_size = Vector2(150, 38)
	test_btn.add_theme_font_size_override("font_size", 13)
	test_btn.alignment = HORIZONTAL_ALIGNMENT_CENTER
	test_btn.pressed.connect(play_test_sound)
	_add_setting_row(page, "Hangerő kipróbálása", "Lejátszik egy rövid teszthangot az aktuális Fő és SFX hangerővel.", test_btn)


func _build_gameplay_tab(page: VBoxContainer) -> void:
	var zoom_controls := _make_slider_control(2.5, 6.0, 0.25, 190)
	_camera_zoom_slider = zoom_controls["slider"]
	_camera_zoom_value_label = zoom_controls["value_label"]
	_camera_zoom_slider.value_changed.connect(_on_camera_zoom_changed)
	_add_setting_row(page, "Dungeon kamera közelítés", "Milyen közelről kövesse a kamera a hőst felfedezés közben (alap: 4.0×).", zoom_controls["box"])

	_combat_speed_option = OptionButton.new()
	_combat_speed_option.custom_minimum_size = Vector2(215, 36)
	_combat_speed_option.add_item("Normál (1.0×)")
	_combat_speed_option.add_item("Gyors (1.5×)")
	_combat_speed_option.add_item("Villámgyors (2.0×)")
	_combat_speed_option.item_selected.connect(_on_combat_speed_selected)
	_add_setting_row(page, "Párbaj tempója", "Gyorsítja a harci ablak körei közötti szüneteket és az eredményjelzőt.", _combat_speed_option)

	_show_minimap_toggle = CheckButton.new()
	_show_minimap_toggle.toggled.connect(_on_show_minimap_toggled)
	_add_setting_row(page, "Mini-térkép megjelenítése", "Elrejti vagy megjeleníti a jobb felső sarokban lévő dungeon mini-térképet.", _show_minimap_toggle)

	_show_tile_hover_toggle = CheckButton.new()
	_show_tile_hover_toggle.toggled.connect(_on_show_tile_hover_toggled)
	_add_setting_row(page, "Célmező kiemelése egérrel", "Megjeleníti az egér alatti léphető mező vagy ellenség célkeresztjét.", _show_tile_hover_toggle)

	_autosave_toggle = CheckButton.new()
	_autosave_toggle.toggled.connect(_on_autosave_toggled)
	_add_setting_row(page, "Időzített automatikus mentés", "Rendszeres időközönként elmenti a haladást az autosave.json fájlba.", _autosave_toggle)

	_autosave_interval_option = OptionButton.new()
	_autosave_interval_option.custom_minimum_size = Vector2(215, 36)
	for sec in AUTOSAVE_INTERVAL_OPTIONS:
		_autosave_interval_option.add_item("%d másodpercenként" % int(sec))
	_autosave_interval_option.item_selected.connect(_on_autosave_interval_selected)
	_add_setting_row(page, "Automatikus mentés gyakorisága", "Milyen gyakran fusson le az automatikus mentés játék közben.", _autosave_interval_option)

	_show_gear_button_toggle = CheckButton.new()
	_show_gear_button_toggle.toggled.connect(_on_show_gear_button_toggled)
	_add_setting_row(page, "Gyors beállítás gomb a sarokban", "A jobb alsó sarokban látható fogaskerék ikon (F10-zel mindig megnyitható).", _show_gear_button_toggle)


func _build_controls_tab(page: VBoxContainer) -> void:
	_movement_mode_option = OptionButton.new()
	_movement_mode_option.custom_minimum_size = Vector2(235, 36)
	_movement_mode_option.add_item("WASD + Egér (Mindkettő)")
	_movement_mode_option.add_item("Csak WASD / Nyilak")
	_movement_mode_option.add_item("Csak egér (Kattintás)")
	_movement_mode_option.item_selected.connect(_on_movement_mode_selected)
	_add_setting_row(page, "Mozgás vezérlése", "Válaszd ki, hogy billentyűzettel (WASD / nyilak), kattintással, vagy mindkettővel irányítod-e a hős mozgását.", _movement_mode_option)

	_keybind_buttons.clear()
	for entry in KEYBIND_METADATA:
		var action_id := String(entry["id"])
		var btn := Button.new()
		UI_THEME.style_button(btn, Color("8baac7"), false)
		btn.custom_minimum_size = Vector2(170, 38)
		btn.add_theme_font_size_override("font_size", 13)
		btn.alignment = HORIZONTAL_ALIGNMENT_CENTER
		btn.pressed.connect(_begin_keybind_capture.bind(action_id))
		_keybind_buttons[action_id] = btn
		_add_setting_row(page, String(entry["label"]), String(entry["desc"]), btn)

	var reset_keys_btn := Button.new()
	reset_keys_btn.text = "BILLENTYŰK VISSZAÁLLÍTÁSA"
	UI_THEME.style_button(reset_keys_btn, Color(0.76, 0.56, 0.34, 1.0), false)
	reset_keys_btn.custom_minimum_size = Vector2(230, 38)
	reset_keys_btn.add_theme_font_size_override("font_size", 12)
	reset_keys_btn.alignment = HORIZONTAL_ALIGNMENT_CENTER
	reset_keys_btn.pressed.connect(reset_keybindings)
	_add_setting_row(page, "Alapértelmezett kiosztás", "Visszaállítja az összes átállított billentyűt az eredeti értékére.", reset_keys_btn)

	# Fixed controls quick reference card
	var ref_card := PanelContainer.new()
	ref_card.add_theme_stylebox_override(
		"panel",
		UI_THEME.make_box(Color(0.03, 0.05, 0.085, 0.9), Color(0.55, 0.45, 0.28, 0.65), 1, 8)
	)
	page.add_child(ref_card)

	var ref_margin := MarginContainer.new()
	ref_margin.add_theme_constant_override("margin_left", 14)
	ref_margin.add_theme_constant_override("margin_top", 10)
	ref_margin.add_theme_constant_override("margin_right", 14)
	ref_margin.add_theme_constant_override("margin_bottom", 10)
	ref_card.add_child(ref_margin)

	var ref_label := _make_label(
		"Fix vezérlők:   WASD / Nyílbillentyűk: lépés   •   Bal klikk: támadás / mozgás   •   Jobb klikk: közvetlen mozgás (hátizsákban: használat / felszerelés)   •   ESC: ablak bezárása / szünet   •   F10: beállítások",
		12,
		Color(0.84, 0.80, 0.70, 1.0)
	)
	ref_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	ref_margin.add_child(ref_label)


func _add_setting_row(parent: VBoxContainer, title_text: String, desc_text: String, control: Control) -> void:
	var card := PanelContainer.new()
	card.add_theme_stylebox_override(
		"panel",
		UI_THEME.make_box(Color(0.028, 0.046, 0.078, 0.92), Color(0.24, 0.32, 0.46, 0.75), 1, 8)
	)
	parent.add_child(card)

	var card_margin := MarginContainer.new()
	card_margin.add_theme_constant_override("margin_left", 14)
	card_margin.add_theme_constant_override("margin_top", 8)
	card_margin.add_theme_constant_override("margin_right", 14)
	card_margin.add_theme_constant_override("margin_bottom", 8)
	card.add_child(card_margin)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	card_margin.add_child(row)

	var text_col := VBoxContainer.new()
	text_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text_col.add_theme_constant_override("separation", 2)
	row.add_child(text_col)

	var title := _make_label(title_text, 14, UI_THEME.IVORY)
	text_col.add_child(title)

	var desc := _make_label(desc_text, 11, UI_THEME.MUTED)
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text_col.add_child(desc)

	control.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(control)


func _make_slider_control(min_val: float, max_val: float, step_val: float, slider_width: float) -> Dictionary:
	var box := HBoxContainer.new()
	box.add_theme_constant_override("separation", 10)

	var slider := HSlider.new()
	slider.min_value = min_val
	slider.max_value = max_val
	slider.step = step_val
	slider.custom_minimum_size = Vector2(slider_width, 28)
	slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	box.add_child(slider)

	var val_label := _make_label("100%", 14, UI_THEME.GOLD)
	val_label.custom_minimum_size = Vector2(56, 0)
	val_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	box.add_child(val_label)

	return {"box": box, "slider": slider, "value_label": val_label}


func _make_label(text_value: String, font_size: int, color: Color) -> Label:
	var result := Label.new()
	result.text = text_value
	result.add_theme_color_override("font_color", color)
	result.add_theme_font_size_override("font_size", font_size)
	result.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	return result


func _make_tab_stylebox(background: Color, border: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = background
	style.border_color = border
	style.set_border_width_all(2)
	style.set_corner_radius_all(10)
	style.shadow_color = Color(0.0, 0.0, 0.0, 0.35)
	style.shadow_size = 4
	style.content_margin_left = 0.0
	style.content_margin_right = 0.0
	style.content_margin_top = 0.0
	style.content_margin_bottom = 0.0
	return style


func _style_tab_button(index: int, is_active: bool) -> void:
	if index < 0 or index >= _tab_buttons.size():
		return
	var btn: Button = _tab_buttons[index]
	var accent: Color = UI_THEME.GOLD if is_active else Color(0.50, 0.62, 0.78, 0.9)
	var normal_bg: Color = Color(0.24, 0.16, 0.065, 0.97) if is_active else Color(0.035, 0.065, 0.10, 0.94)
	var hover_bg: Color = Color(0.34, 0.22, 0.08, 0.99) if is_active else Color(0.085, 0.13, 0.17, 0.98)
	var pressed_bg: Color = Color(0.15, 0.105, 0.045, 1.0) if is_active else Color(0.025, 0.045, 0.075, 1.0)

	btn.add_theme_stylebox_override("normal", _make_tab_stylebox(normal_bg, accent))
	btn.add_theme_stylebox_override("hover", _make_tab_stylebox(hover_bg, accent.lightened(0.18)))
	btn.add_theme_stylebox_override("pressed", _make_tab_stylebox(pressed_bg, accent.darkened(0.08)))
	btn.add_theme_stylebox_override("focus", _make_tab_stylebox(Color(0.0, 0.0, 0.0, 0.0), accent.lightened(0.18)))
	btn.add_theme_stylebox_override("disabled", _make_tab_stylebox(Color(0.06, 0.07, 0.08, 0.75), Color(0.35, 0.38, 0.40, 0.7)))
	btn.focus_mode = Control.FOCUS_NONE

	if index < _tab_labels.size():
		_tab_labels[index].add_theme_color_override(
			"font_color",
			UI_THEME.IVORY if is_active else Color(0.84, 0.88, 0.94, 1.0)
		)


func _select_tab(index: int) -> void:
	_cancel_keybind_capture()
	_active_tab_index = clampi(index, 0, maxi(_tab_pages.size() - 1, 0))
	for i in range(_tab_pages.size()):
		_tab_pages[i].visible = (i == _active_tab_index)
	for i in range(_tab_buttons.size()):
		_style_tab_button(i, i == _active_tab_index)
	if _reset_button != null:
		var category_names: Array[String] = ["Megjelenítés", "Hang", "Játékmenet", "Irányítás"]
		var active_name: String = category_names[clampi(_active_tab_index, 0, category_names.size() - 1)]
		_reset_button.tooltip_text = "Csak az aktív kategória (%s) beállításait állítja alapértelmezettre." % active_name


func _set_status(message: String, positive: bool) -> void:
	if _status_label == null:
		return
	_status_label.text = message
	_status_label.add_theme_color_override(
		"font_color",
		Color(0.62, 0.92, 0.66, 1.0) if positive else UI_THEME.MUTED
	)


func _begin_keybind_capture(action_id: String) -> void:
	_capturing_action = action_id
	var vp := get_viewport()
	if vp != null:
		var focus_owner := vp.gui_get_focus_owner()
		if focus_owner != null:
			focus_owner.release_focus()
	_refresh_keybind_buttons()
	_set_status("Nyomj meg egy új billentyűt... (ESC: mégse)", false)


func _cancel_keybind_capture() -> void:
	if _capturing_action.is_empty():
		return
	_capturing_action = ""
	_refresh_keybind_buttons()


func _refresh_keybind_buttons() -> void:
	for action_id in _keybind_buttons:
		var btn := _keybind_buttons[action_id] as Button
		if btn == null:
			continue
		var id_str := String(action_id)
		if _capturing_action == id_str:
			btn.text = "Nyomj meg egy gombot..."
			UI_THEME.style_button(btn, UI_THEME.GOLD, true)
		else:
			btn.text = "[ %s ]" % get_keybind_label(id_str)
			UI_THEME.style_button(btn, Color("8baac7"), false)
		btn.add_theme_font_size_override("font_size", 13)
		btn.custom_minimum_size = Vector2(170, 38)
		btn.alignment = HORIZONTAL_ALIGNMENT_CENTER


func _sync_resolution_control(live_size: Vector2i) -> void:
	if _resolution_option == null:
		return
	var prev_refreshing := _is_refreshing_ui
	_is_refreshing_ui = true

	var effective_size := live_size if (live_size.x > 0 and live_size.y > 0) else window_resolution
	if _resolution_live_label != null:
		_resolution_live_label.text = "Aktuális: %d × %d" % [effective_size.x, effective_size.y]

	var preset_idx := RESOLUTIONS.find(effective_size)
	if preset_idx >= 0:
		while _resolution_option.item_count > RESOLUTIONS.size():
			_resolution_option.remove_item(_resolution_option.item_count - 1)
		_resolution_option.select(preset_idx)
	else:
		var custom_text := "%d × %d (Egyéni)" % [effective_size.x, effective_size.y]
		if _resolution_option.item_count == RESOLUTIONS.size():
			_resolution_option.add_item(custom_text)
		else:
			_resolution_option.set_item_text(RESOLUTIONS.size(), custom_text)
		_resolution_option.select(RESOLUTIONS.size())

	_resolution_option.disabled = (display_mode != DISPLAY_MODE_WINDOWED)
	_resolution_option.tooltip_text = "Csak ablakos módban módosítható." if _resolution_option.disabled else ""
	_is_refreshing_ui = prev_refreshing


func _refresh_controls() -> void:
	if _master_slider == null:
		return
	_is_refreshing_ui = true

	# Display
	_display_mode_option.select(clampi(display_mode, 0, 2))
	var current_win_size := DisplayServer.window_get_size()
	_last_observed_window_size = current_win_size
	if display_mode == DISPLAY_MODE_WINDOWED and DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_WINDOWED and current_win_size.x > 0 and current_win_size.y > 0:
		window_resolution = current_win_size
		_sync_resolution_control(current_win_size)
	else:
		_sync_resolution_control(current_win_size if current_win_size.x > 0 and current_win_size.y > 0 else window_resolution)
	_vsync_toggle.set_pressed_no_signal(vsync_enabled)
	var fps_idx := FPS_LIMITS.find(fps_limit)
	_fps_limit_option.select(maxi(fps_idx, 0))
	_show_fps_toggle.set_pressed_no_signal(show_fps)
	_fog_mist_slider.set_value_no_signal(fog_mist_scale)
	_fog_mist_value_label.text = "%d%%" % roundi(fog_mist_scale * 100.0)
	_brightness_slider.set_value_no_signal(brightness)
	_brightness_value_label.text = "%d%%" % roundi(brightness * 100.0)

	# Audio
	_mute_toggle.set_pressed_no_signal(audio_muted)
	_master_slider.set_value_no_signal(master_volume)
	_master_value_label.text = "%d%%" % roundi(master_volume * 100.0)
	_music_slider.set_value_no_signal(music_volume)
	_music_value_label.text = "%d%%" % roundi(music_volume * 100.0)
	_sfx_slider.set_value_no_signal(sfx_volume)
	_sfx_value_label.text = "%d%%" % roundi(sfx_volume * 100.0)
	_mute_unfocused_toggle.set_pressed_no_signal(mute_when_unfocused)

	# Gameplay
	_camera_zoom_slider.set_value_no_signal(camera_zoom)
	_camera_zoom_value_label.text = "%.2f×" % camera_zoom
	var speed_idx := _find_closest_float_index(COMBAT_SPEED_OPTIONS, combat_speed)
	_combat_speed_option.select(speed_idx)
	_show_minimap_toggle.set_pressed_no_signal(show_minimap)
	_show_tile_hover_toggle.set_pressed_no_signal(show_tile_hover)
	_autosave_toggle.set_pressed_no_signal(autosave_enabled)
	var save_idx := _find_closest_float_index(AUTOSAVE_INTERVAL_OPTIONS, autosave_interval_seconds)
	_autosave_interval_option.select(save_idx)
	_autosave_interval_option.disabled = not autosave_enabled
	_show_gear_button_toggle.set_pressed_no_signal(show_settings_button)

	# Controls
	if _movement_mode_option != null:
		_movement_mode_option.select(clampi(movement_mode, MOVEMENT_MODE_BOTH, MOVEMENT_MODE_CLICK))
	_refresh_keybind_buttons()

	_is_refreshing_ui = false


func _find_closest_float_index(values: Array[float], target: float) -> int:
	var best_idx := 0
	var best_diff := INF
	for i in range(values.size()):
		var diff := absf(values[i] - target)
		if diff < best_diff:
			best_diff = diff
			best_idx = i
	return best_idx


# -----------------------------------------------------------------------------
# Control callbacks
# -----------------------------------------------------------------------------

func _on_display_mode_selected(index: int) -> void:
	if _is_refreshing_ui:
		return
	set_display_mode(index)


func _on_resolution_selected(index: int) -> void:
	if _is_refreshing_ui:
		return
	if index >= 0 and index < RESOLUTIONS.size():
		set_window_resolution(RESOLUTIONS[index])


func _on_vsync_toggled(enabled: bool) -> void:
	if _is_refreshing_ui:
		return
	set_vsync(enabled)


func _on_fps_limit_selected(index: int) -> void:
	if _is_refreshing_ui:
		return
	if index >= 0 and index < FPS_LIMITS.size():
		set_fps_limit(FPS_LIMITS[index])


func _on_show_fps_toggled(enabled: bool) -> void:
	if _is_refreshing_ui:
		return
	set_show_fps(enabled)


func _on_fog_mist_changed(value: float) -> void:
	if _is_refreshing_ui:
		return
	if _fog_mist_value_label != null:
		_fog_mist_value_label.text = "%d%%" % roundi(value * 100.0)
	set_fog_mist_scale(value)


func _on_brightness_changed(value: float) -> void:
	if _is_refreshing_ui:
		return
	if _brightness_value_label != null:
		_brightness_value_label.text = "%d%%" % roundi(value * 100.0)
	set_brightness(value)


func _on_mute_toggled(enabled: bool) -> void:
	if _is_refreshing_ui:
		return
	set_audio_muted(enabled)


func _on_master_volume_changed(value: float) -> void:
	if _is_refreshing_ui:
		return
	if _master_value_label != null:
		_master_value_label.text = "%d%%" % roundi(value * 100.0)
	set_master_volume(value)


func _on_music_volume_changed(value: float) -> void:
	if _is_refreshing_ui:
		return
	if _music_value_label != null:
		_music_value_label.text = "%d%%" % roundi(value * 100.0)
	set_music_volume(value)


func _on_sfx_volume_changed(value: float) -> void:
	if _is_refreshing_ui:
		return
	if _sfx_value_label != null:
		_sfx_value_label.text = "%d%%" % roundi(value * 100.0)
	set_sfx_volume(value)


func _on_mute_unfocused_toggled(enabled: bool) -> void:
	if _is_refreshing_ui:
		return
	set_mute_when_unfocused(enabled)


func _on_camera_zoom_changed(value: float) -> void:
	if _is_refreshing_ui:
		return
	if _camera_zoom_value_label != null:
		_camera_zoom_value_label.text = "%.2f×" % value
	set_camera_zoom(value)


func _on_combat_speed_selected(index: int) -> void:
	if _is_refreshing_ui:
		return
	if index >= 0 and index < COMBAT_SPEED_OPTIONS.size():
		set_combat_speed(COMBAT_SPEED_OPTIONS[index])


func _on_show_minimap_toggled(enabled: bool) -> void:
	if _is_refreshing_ui:
		return
	set_show_minimap(enabled)


func _on_show_tile_hover_toggled(enabled: bool) -> void:
	if _is_refreshing_ui:
		return
	set_show_tile_hover(enabled)


func _on_autosave_toggled(enabled: bool) -> void:
	if _is_refreshing_ui:
		return
	set_autosave_enabled(enabled)


func _on_autosave_interval_selected(index: int) -> void:
	if _is_refreshing_ui:
		return
	if index >= 0 and index < AUTOSAVE_INTERVAL_OPTIONS.size():
		set_autosave_interval(AUTOSAVE_INTERVAL_OPTIONS[index])


func _on_show_gear_button_toggled(enabled: bool) -> void:
	if _is_refreshing_ui:
		return
	set_show_settings_button(enabled)


func _on_movement_mode_selected(index: int) -> void:
	if _is_refreshing_ui:
		return
	set_movement_mode(index)


# -----------------------------------------------------------------------------
# Persistence and applying settings to the engine
# -----------------------------------------------------------------------------

func _load_settings() -> void:
	var error := _config.load(SETTINGS_PATH)
	if error != OK and error != ERR_FILE_NOT_FOUND:
		push_warning("A beállításfájl nem olvasható; alapértelmezett értékek használata.")

	# Display
	var legacy_fullscreen := bool(_config.get_value("display", "fullscreen", false))
	var default_mode := DISPLAY_MODE_BORDERLESS if legacy_fullscreen else DISPLAY_MODE_WINDOWED
	display_mode = clampi(int(_config.get_value("display", "display_mode", default_mode)), DISPLAY_MODE_WINDOWED, DISPLAY_MODE_EXCLUSIVE)
	fullscreen = display_mode != DISPLAY_MODE_WINDOWED
	var width := int(_config.get_value("display", "window_width", 1280))
	var height := int(_config.get_value("display", "window_height", 720))
	var stored_resolution := Vector2i(width, height)
	window_resolution = stored_resolution if (stored_resolution.x >= 640 and stored_resolution.y >= 360) else Vector2i(1280, 720)
	vsync_enabled = bool(_config.get_value("display", "vsync", true))
	var stored_fps := int(_config.get_value("display", "fps_limit", 0))
	fps_limit = stored_fps if FPS_LIMITS.has(stored_fps) else 0
	show_fps = bool(_config.get_value("display", "show_fps", false))
	fog_mist_scale = clampf(float(_config.get_value("display", "fog_mist_scale", 1.0)), 0.0, 1.0)
	brightness = clampf(float(_config.get_value("display", "brightness", 1.0)), 0.7, 1.3)

	# Audio
	audio_muted = bool(_config.get_value("audio", "muted", false))
	master_volume = clampf(float(_config.get_value("audio", "master_volume", 0.8)), 0.0, 1.0)
	music_volume = clampf(float(_config.get_value("audio", "music_volume", 0.75)), 0.0, 1.0)
	sfx_volume = clampf(float(_config.get_value("audio", "sfx_volume", 0.85)), 0.0, 1.0)
	mute_when_unfocused = bool(_config.get_value("audio", "mute_when_unfocused", false))

	# Gameplay
	camera_zoom = clampf(float(_config.get_value("gameplay", "camera_zoom", 4.0)), 2.5, 6.0)
	combat_speed = clampf(float(_config.get_value("gameplay", "combat_speed", 1.0)), 1.0, 2.0)
	show_minimap = bool(_config.get_value("gameplay", "show_minimap", true))
	show_tile_hover = bool(_config.get_value("gameplay", "show_tile_hover", true))
	autosave_enabled = bool(_config.get_value("gameplay", "autosave_enabled", true))
	autosave_interval_seconds = clampf(float(_config.get_value("gameplay", "autosave_interval_seconds", 60.0)), 15.0, 600.0)
	show_settings_button = bool(_config.get_value("gameplay", "show_settings_button", true))

	# Controls
	var controls_version := int(_config.get_value("controls", "schema_version", 1))
	movement_mode = clampi(int(_config.get_value("controls", "movement_mode", MOVEMENT_MODE_BOTH)), MOVEMENT_MODE_BOTH, MOVEMENT_MODE_CLICK)
	keybindings = DEFAULT_KEYBINDINGS.duplicate()
	for action_id in DEFAULT_KEYBINDINGS.keys():
		var stored_code := int(_config.get_value("controls", String(action_id), int(DEFAULT_KEYBINDINGS[action_id])))
		if controls_version < CONTROLS_SCHEMA_VERSION and String(action_id) == "toggle_backpack" and stored_code == KEY_I:
			stored_code = KEY_TAB
		if _is_rebindable_keycode(stored_code):
			keybindings[action_id] = stored_code


func _save_settings() -> void:
	_config.set_value("display", "display_mode", display_mode)
	_config.set_value("display", "fullscreen", fullscreen)
	_config.set_value("display", "window_width", window_resolution.x)
	_config.set_value("display", "window_height", window_resolution.y)
	_config.set_value("display", "vsync", vsync_enabled)
	_config.set_value("display", "fps_limit", fps_limit)
	_config.set_value("display", "show_fps", show_fps)
	_config.set_value("display", "fog_mist_scale", fog_mist_scale)
	_config.set_value("display", "brightness", brightness)

	_config.set_value("audio", "muted", audio_muted)
	_config.set_value("audio", "master_volume", master_volume)
	_config.set_value("audio", "music_volume", music_volume)
	_config.set_value("audio", "sfx_volume", sfx_volume)
	_config.set_value("audio", "mute_when_unfocused", mute_when_unfocused)

	_config.set_value("gameplay", "camera_zoom", camera_zoom)
	_config.set_value("gameplay", "combat_speed", combat_speed)
	_config.set_value("gameplay", "show_minimap", show_minimap)
	_config.set_value("gameplay", "show_tile_hover", show_tile_hover)
	_config.set_value("gameplay", "autosave_enabled", autosave_enabled)
	_config.set_value("gameplay", "autosave_interval_seconds", autosave_interval_seconds)
	_config.set_value("gameplay", "show_settings_button", show_settings_button)

	_config.set_value("controls", "schema_version", CONTROLS_SCHEMA_VERSION)
	_config.set_value("controls", "movement_mode", movement_mode)
	for action_id in keybindings.keys():
		_config.set_value("controls", String(action_id), int(keybindings[action_id]))

	var error := _config.save(SETTINGS_PATH)
	if error != OK:
		push_warning("A beállításokat nem sikerült lemezre menteni: %s" % error_string(error))


func _apply_all_settings() -> void:
	_apply_audio_settings()
	_apply_display_settings()
	_apply_vsync()
	_apply_fps_limit()
	_apply_fps_overlay()
	_apply_brightness()


func _apply_audio_settings() -> void:
	_ensure_audio_buses()
	var unfocused_mute := mute_when_unfocused and not _window_focused
	var effective_master_mute := audio_muted or unfocused_mute or master_volume <= 0.001

	var master_bus := AudioServer.get_bus_index("Master")
	if master_bus >= 0:
		AudioServer.set_bus_mute(master_bus, effective_master_mute)
		AudioServer.set_bus_volume_linear(master_bus, maxf(master_volume, 0.001))

	var music_bus := AudioServer.get_bus_index("Music")
	if music_bus >= 0:
		AudioServer.set_bus_mute(music_bus, music_volume <= 0.001)
		AudioServer.set_bus_volume_linear(music_bus, maxf(music_volume, 0.001))

	var sfx_bus := AudioServer.get_bus_index("SFX")
	if sfx_bus >= 0:
		AudioServer.set_bus_mute(sfx_bus, sfx_volume <= 0.001)
		AudioServer.set_bus_volume_linear(sfx_bus, maxf(sfx_volume, 0.001))


func _apply_display_settings() -> void:
	match display_mode:
		DISPLAY_MODE_EXCLUSIVE:
			if DisplayServer.window_get_mode() != DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN:
				DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN)
		DISPLAY_MODE_BORDERLESS:
			if DisplayServer.window_get_mode() != DisplayServer.WINDOW_MODE_FULLSCREEN:
				DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
		_:
			if DisplayServer.window_get_mode() != DisplayServer.WINDOW_MODE_WINDOWED:
				DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
			DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS, false)
			var screen_size := DisplayServer.screen_get_size()
			var target_size := Vector2i(
				mini(window_resolution.x, maxi(screen_size.x, 640)),
				mini(window_resolution.y, maxi(screen_size.y, 480))
			)
			if DisplayServer.window_get_size() != target_size:
				DisplayServer.window_set_size(target_size)
				DisplayServer.window_set_position(Vector2i(
					maxi(int((screen_size.x - target_size.x) / 2.0), 0),
					maxi(int((screen_size.y - target_size.y) / 2.0), 0)
				))
	_schedule_font_atlas_refresh()


func _apply_vsync() -> void:
	DisplayServer.window_set_vsync_mode(
		DisplayServer.VSYNC_ENABLED if vsync_enabled else DisplayServer.VSYNC_DISABLED
	)


func _apply_fps_limit() -> void:
	Engine.max_fps = maxi(fps_limit, 0)


func _apply_fps_overlay() -> void:
	if _fps_panel != null:
		_fps_panel.visible = show_fps
		if show_fps and _fps_label != null:
			_fps_label.text = "FPS: %d" % Engine.get_frames_per_second()


func _apply_brightness() -> void:
	if _darken_rect == null or _brighten_rect == null:
		return
	if brightness < 0.995:
		_darken_rect.visible = true
		_darken_rect.color = Color(0.0, 0.0, 0.0, clampf((1.0 - brightness) * 1.4, 0.0, 0.55))
		_brighten_rect.visible = false
	elif brightness > 1.005:
		_darken_rect.visible = false
		_brighten_rect.visible = true
		_brighten_rect.color = Color(1.0, 0.98, 0.94, clampf((brightness - 1.0) * 0.35, 0.0, 0.22))
	else:
		_darken_rect.visible = false
		_brighten_rect.visible = false
