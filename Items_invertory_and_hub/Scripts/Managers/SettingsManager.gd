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
	Vector2i(1920, 1080)
]

signal settings_changed

var master_volume: float = 0.8
var fullscreen: bool = false
var window_resolution: Vector2i = Vector2i(1280, 720)
var vsync_enabled: bool = true

var _config := ConfigFile.new()
var _settings_button: Button
var _overlay: ColorRect
var _panel: PanelContainer
var _volume_slider: HSlider
var _volume_value_label: Label
var _fullscreen_toggle: CheckButton
var _resolution_option: OptionButton
var _vsync_toggle: CheckButton
var _was_paused_before_open: bool = false


# -----------------------------------------------------------------------------
# Lifecycle and input handling
# -----------------------------------------------------------------------------

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 100
	_load_settings()
	_build_ui()
	_apply_all_settings()
	_refresh_controls()


func _input(event: InputEvent) -> void:
	if not event is InputEventKey:
		return
	var key_event := event as InputEventKey
	if not key_event.pressed or key_event.echo:
		return
	if key_event.keycode == KEY_F10:
		toggle_settings()
		get_viewport().set_input_as_handled()
	elif key_event.keycode == KEY_ESCAPE and is_open():
		close_settings()
		get_viewport().set_input_as_handled()


# -----------------------------------------------------------------------------
# Public settings API (safe to call from any scene)
# -----------------------------------------------------------------------------

func is_open() -> bool:
	return _overlay != null and _overlay.visible


func open_settings() -> void:
	if _overlay == null or is_open():
		return
	_was_paused_before_open = get_tree().paused
	get_tree().paused = true
	_overlay.show()
	_panel.show()
	_panel.move_to_front()
	_refresh_controls()


func close_settings() -> void:
	if _overlay == null or not is_open():
		return
	_save_settings()
	_overlay.hide()
	_panel.hide()
	if not _was_paused_before_open:
		get_tree().paused = false


func toggle_settings() -> void:
	if is_open():
		close_settings()
	else:
		open_settings()


func set_master_volume(value: float) -> void:
	master_volume = clampf(value, 0.0, 1.0)
	_apply_audio_settings()
	_save_settings()
	settings_changed.emit()


func set_fullscreen(enabled: bool) -> void:
	fullscreen = enabled
	_apply_display_settings()
	_save_settings()
	settings_changed.emit()


func set_window_resolution(resolution: Vector2i) -> void:
	if not RESOLUTIONS.has(resolution):
		return
	window_resolution = resolution
	_apply_display_settings()
	_save_settings()
	settings_changed.emit()


func set_vsync(enabled: bool) -> void:
	vsync_enabled = enabled
	_apply_vsync()
	_save_settings()
	settings_changed.emit()


func reset_to_defaults() -> void:
	master_volume = 0.8
	fullscreen = false
	window_resolution = Vector2i(1280, 720)
	vsync_enabled = true
	_apply_all_settings()
	_refresh_controls()
	_save_settings()
	settings_changed.emit()


# -----------------------------------------------------------------------------
# Global settings overlay and controls
# -----------------------------------------------------------------------------

func _build_ui() -> void:
	_settings_button = Button.new()
	_settings_button.name = "GlobalSettingsButton"
	_settings_button.anchor_left = 1.0
	_settings_button.anchor_top = 1.0
	_settings_button.anchor_right = 1.0
	_settings_button.anchor_bottom = 1.0
	# A fixed safe margin keeps the global button in the empty lower-right corner.
	_settings_button.offset_left = -76.0
	_settings_button.offset_right = -20.0
	_settings_button.offset_top = -76.0
	_settings_button.offset_bottom = -20.0
	_settings_button.text = ""
	_settings_button.icon = load("res://Arts/UI/Icons/settings.png") as Texture2D
	_settings_button.tooltip_text = "Beállítások (F10)"
	_settings_button.custom_minimum_size = Vector2(56, 56)
	_settings_button.add_theme_font_size_override("font_size", 26)
	UI_THEME.style_button(_settings_button, Color("8baac7"), true)
	_settings_button.alignment = HORIZONTAL_ALIGNMENT_CENTER
	_settings_button.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_settings_button.pressed.connect(open_settings)
	add_child(_settings_button)

	_overlay = ColorRect.new()
	_overlay.name = "GlobalSettingsOverlay"
	_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_overlay.color = Color(0.005, 0.012, 0.025, 0.82)
	_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	_overlay.visible = false
	add_child(_overlay)

	_panel = PanelContainer.new()
	_panel.name = "GlobalSettingsPanel"
	_panel.anchor_left = 0.5
	_panel.anchor_top = 0.5
	_panel.anchor_right = 0.5
	_panel.anchor_bottom = 0.5
	_panel.offset_left = -280.0
	_panel.offset_top = -265.0
	_panel.offset_right = 280.0
	_panel.offset_bottom = 265.0
	_panel.custom_minimum_size = Vector2(560, 530)
	_panel.visible = false
	UI_THEME.style_panel(_panel, Color("d8b56c"), Color(0.025, 0.045, 0.075, 0.99))
	add_child(_panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 26)
	margin.add_theme_constant_override("margin_top", 22)
	margin.add_theme_constant_override("margin_right", 26)
	margin.add_theme_constant_override("margin_bottom", 22)
	_panel.add_child(margin)

	var layout := VBoxContainer.new()
	layout.add_theme_constant_override("separation", 12)
	margin.add_child(layout)

	var heading := Label.new()
	heading.text = "BEÁLLÍTÁSOK"
	heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	heading.add_theme_color_override("font_color", UI_THEME.IVORY)
	heading.add_theme_font_size_override("font_size", 28)
	layout.add_child(heading)

	var hint := Label.new()
	hint.text = "F10: megnyitás / bezárás   •   Esc: bezárás"
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_color_override("font_color", UI_THEME.MUTED)
	hint.add_theme_font_size_override("font_size", 13)
	layout.add_child(hint)
	layout.add_child(HSeparator.new())

	var volume_row := HBoxContainer.new()
	volume_row.add_theme_constant_override("separation", 12)
	layout.add_child(volume_row)
	var volume_label := _make_label("Fő hangerő", 16, UI_THEME.IVORY)
	volume_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	volume_row.add_child(volume_label)
	_volume_value_label = _make_label("80%", 16, UI_THEME.GOLD)
	_volume_value_label.custom_minimum_size.x = 56
	_volume_value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	volume_row.add_child(_volume_value_label)

	_volume_slider = HSlider.new()
	_volume_slider.min_value = 0.0
	_volume_slider.max_value = 1.0
	_volume_slider.step = 0.05
	_volume_slider.custom_minimum_size = Vector2(0, 30)
	layout.add_child(_volume_slider)
	_volume_slider.value_changed.connect(_on_volume_changed)

	_fullscreen_toggle = CheckButton.new()
	_fullscreen_toggle.text = "Teljes képernyő"
	layout.add_child(_fullscreen_toggle)
	_fullscreen_toggle.toggled.connect(_on_fullscreen_toggled)

	var resolution_label := _make_label("Ablakfelbontás", 16, UI_THEME.IVORY)
	layout.add_child(resolution_label)
	_resolution_option = OptionButton.new()
	_resolution_option.custom_minimum_size = Vector2(0, 42)
	for resolution in RESOLUTIONS:
		_resolution_option.add_item("%d × %d" % [resolution.x, resolution.y])
	layout.add_child(_resolution_option)
	_resolution_option.item_selected.connect(_on_resolution_selected)

	_vsync_toggle = CheckButton.new()
	_vsync_toggle.text = "Függőleges szinkronizálás (VSync)"
	layout.add_child(_vsync_toggle)
	_vsync_toggle.toggled.connect(_on_vsync_toggled)

	var note := _make_label("A beállítások külön fájlba mentődnek, a karakter- és inventorymentéseket nem módosítják.", 13, UI_THEME.MUTED)
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	layout.add_child(note)

	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	layout.add_child(spacer)

	var button_row := HBoxContainer.new()
	button_row.add_theme_constant_override("separation", 12)
	layout.add_child(button_row)
	var reset_button := Button.new()
	reset_button.text = "ALAPÉRTELMEZETT"
	reset_button.custom_minimum_size = Vector2(0, 48)
	reset_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	UI_THEME.style_button(reset_button, Color("8baac7"))
	reset_button.pressed.connect(reset_to_defaults)
	button_row.add_child(reset_button)
	var close_button := Button.new()
	close_button.text = "VISSZA"
	close_button.custom_minimum_size = Vector2(0, 48)
	close_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	UI_THEME.style_button(close_button, Color("d8b56c"), true)
	close_button.pressed.connect(close_settings)
	button_row.add_child(close_button)


func _make_label(text_value: String, font_size: int, color: Color) -> Label:
	var result := Label.new()
	result.text = text_value
	result.add_theme_color_override("font_color", color)
	result.add_theme_font_size_override("font_size", font_size)
	result.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	return result


func _refresh_controls() -> void:
	if _volume_slider == null:
		return
	_volume_slider.set_value_no_signal(master_volume)
	_volume_value_label.text = "%d%%" % roundi(master_volume * 100.0)
	_fullscreen_toggle.set_pressed_no_signal(fullscreen)
	_vsync_toggle.set_pressed_no_signal(vsync_enabled)
	var selected_index := RESOLUTIONS.find(window_resolution)
	if selected_index < 0:
		selected_index = RESOLUTIONS.find(Vector2i(1280, 720))
	_resolution_option.select(maxi(selected_index, 0))


func _on_volume_changed(value: float) -> void:
	set_master_volume(value)
	if _volume_value_label != null:
		_volume_value_label.text = "%d%%" % roundi(master_volume * 100.0)


func _on_fullscreen_toggled(enabled: bool) -> void:
	set_fullscreen(enabled)


func _on_resolution_selected(index: int) -> void:
	if index >= 0 and index < RESOLUTIONS.size():
		set_window_resolution(RESOLUTIONS[index])


func _on_vsync_toggled(enabled: bool) -> void:
	set_vsync(enabled)


# -----------------------------------------------------------------------------
# Persistence and applying settings to the engine
# -----------------------------------------------------------------------------

func _load_settings() -> void:
	var error := _config.load(SETTINGS_PATH)
	if error != OK and error != ERR_FILE_NOT_FOUND:
		push_warning("A beállításfájl nem olvasható; alapértelmezett értékek használata.")
	master_volume = clampf(float(_config.get_value("audio", "master_volume", 0.8)), 0.0, 1.0)
	fullscreen = bool(_config.get_value("display", "fullscreen", false))
	var width := int(_config.get_value("display", "window_width", 1280))
	var height := int(_config.get_value("display", "window_height", 720))
	var stored_resolution := Vector2i(width, height)
	window_resolution = stored_resolution if RESOLUTIONS.has(stored_resolution) else Vector2i(1280, 720)
	vsync_enabled = bool(_config.get_value("display", "vsync", true))


func _save_settings() -> void:
	_config.set_value("audio", "master_volume", master_volume)
	_config.set_value("display", "fullscreen", fullscreen)
	_config.set_value("display", "window_width", window_resolution.x)
	_config.set_value("display", "window_height", window_resolution.y)
	_config.set_value("display", "vsync", vsync_enabled)
	var error := _config.save(SETTINGS_PATH)
	if error != OK:
		push_warning("A beállításokat nem sikerült lemezre menteni: %s" % error_string(error))


func _apply_all_settings() -> void:
	_apply_audio_settings()
	_apply_display_settings()
	_apply_vsync()


func _apply_audio_settings() -> void:
	var master_bus := AudioServer.get_bus_index("Master")
	if master_bus >= 0:
		AudioServer.set_bus_mute(master_bus, master_volume <= 0.001)
		AudioServer.set_bus_volume_linear(master_bus, maxf(master_volume, 0.001))


func _apply_display_settings() -> void:
	if fullscreen:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
	else:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
		DisplayServer.window_set_size(window_resolution)
		var screen_size := DisplayServer.screen_get_size()
		DisplayServer.window_set_position(Vector2i(
			maxi(int((screen_size.x - window_resolution.x) / 2), 0),
			maxi(int((screen_size.y - window_resolution.y) / 2), 0)
		))


func _apply_vsync() -> void:
	DisplayServer.window_set_vsync_mode(
		DisplayServer.VSYNC_ENABLED if vsync_enabled else DisplayServer.VSYNC_DISABLED
	)
