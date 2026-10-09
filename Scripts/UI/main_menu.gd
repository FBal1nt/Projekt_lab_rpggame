extends Control

const UI_THEME = preload("res://Scripts/UI/ui_theme.gd")

@onready var menu_panel: PanelContainer = $MenuPanel
@onready var title_label: Label = $MenuPanel/MarginContainer/MenuVBox/Title
@onready var subtitle_label: Label = $MenuPanel/MarginContainer/MenuVBox/Subtitle
@onready var start_button: Button = $MenuPanel/MarginContainer/MenuVBox/StartButton
@onready var settings_button: Button = $MenuPanel/MarginContainer/MenuVBox/SettingsButton
@onready var exit_button: Button = $MenuPanel/MarginContainer/MenuVBox/ExitButton

var settings_overlay: ColorRect
var settings_panel: PanelContainer
var volume_slider: HSlider
var volume_value_label: Label
var fullscreen_toggle: CheckButton
var settings_config := ConfigFile.new()


func _ready() -> void:
	UI_THEME.style_panel(menu_panel, Color("d8b56c"), Color(0.025, 0.045, 0.075, 0.94))
	UI_THEME.style_button(start_button, Color("e9bd61"), true)
	UI_THEME.style_button(settings_button, Color("8baac7"))
	UI_THEME.style_button(exit_button, Color("c77769"))

	title_label.add_theme_color_override("font_color", UI_THEME.IVORY)
	title_label.add_theme_font_size_override("font_size", 40)
	subtitle_label.add_theme_color_override("font_color", UI_THEME.GOLD)
	exit_button.add_theme_color_override("font_color", Color("f1c6bc"))

	start_button.icon = load("res://Arts/UI/Icons/play_sword.png")
	settings_button.icon = load("res://Arts/UI/Icons/settings.png")
	exit_button.icon = load("res://Arts/UI/Icons/exit.png")

	$MenuPanel/MarginContainer/MenuVBox/VersionLabel.add_theme_color_override("font_color", UI_THEME.MUTED)
	$MenuPanel/MarginContainer/MenuVBox/Divider.add_theme_color_override("color", Color(0.75, 0.57, 0.30, 0.8))

	_build_settings_panel()
	_load_settings()


func _on_start_button_pressed() -> void:
	var result := get_tree().change_scene_to_file("res://Scenes/Lobby/Lobby.tscn")
	if result != OK:
		push_error("Nem sikerült betölteni a Lobby jelenetet. Ellenőrizd a Scenes/Lobby/Lobby.tscn útvonalat.")


func _on_settings_button_pressed() -> void:
	settings_overlay.show()
	settings_panel.show()


func _on_exit_button_pressed() -> void:
	get_tree().quit()


func _build_settings_panel() -> void:
	settings_overlay = ColorRect.new()
	settings_overlay.name = "SettingsOverlay"
	settings_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	settings_overlay.color = Color(0.005, 0.012, 0.025, 0.78)
	settings_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	settings_overlay.visible = false
	add_child(settings_overlay)

	settings_panel = PanelContainer.new()
	settings_panel.name = "SettingsPanel"
	settings_panel.anchor_left = 0.5
	settings_panel.anchor_top = 0.5
	settings_panel.anchor_right = 0.5
	settings_panel.anchor_bottom = 0.5
	settings_panel.offset_left = -235.0
	settings_panel.offset_top = -190.0
	settings_panel.offset_right = 235.0
	settings_panel.offset_bottom = 190.0
	settings_panel.visible = false
	UI_THEME.style_panel(settings_panel, Color("d8b56c"), Color(0.025, 0.045, 0.075, 0.99))
	add_child(settings_panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 24)
	margin.add_theme_constant_override("margin_top", 22)
	margin.add_theme_constant_override("margin_right", 24)
	margin.add_theme_constant_override("margin_bottom", 22)
	settings_panel.add_child(margin)

	var layout := VBoxContainer.new()
	layout.add_theme_constant_override("separation", 14)
	margin.add_child(layout)

	var heading := Label.new()
	heading.text = "BEÁLLÍTÁSOK"
	heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	heading.add_theme_color_override("font_color", UI_THEME.IVORY)
	heading.add_theme_font_size_override("font_size", 26)
	layout.add_child(heading)

	var separator := HSeparator.new()
	layout.add_child(separator)

	var volume_row := HBoxContainer.new()
	volume_row.add_theme_constant_override("separation", 12)
	layout.add_child(volume_row)

	var volume_label := Label.new()
	volume_label.text = "Fő hangerő"
	volume_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	volume_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	volume_row.add_child(volume_label)

	volume_value_label = Label.new()
	volume_value_label.custom_minimum_size.x = 54
	volume_value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	volume_value_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	volume_row.add_child(volume_value_label)

	volume_slider = HSlider.new()
	volume_slider.min_value = 0.0
	volume_slider.max_value = 1.0
	volume_slider.step = 0.05
	volume_slider.custom_minimum_size = Vector2(0, 28)
	layout.add_child(volume_slider)
	volume_slider.value_changed.connect(_on_volume_changed)

	fullscreen_toggle = CheckButton.new()
	fullscreen_toggle.text = "Teljes képernyő"
	layout.add_child(fullscreen_toggle)
	fullscreen_toggle.toggled.connect(_on_fullscreen_toggled)

	var note := Label.new()
	note.text = "A módosítások ezen a gépen mentődnek el."
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.add_theme_color_override("font_color", UI_THEME.MUTED)
	note.add_theme_font_size_override("font_size", 13)
	layout.add_child(note)

	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	layout.add_child(spacer)

	var back_button := Button.new()
	back_button.text = "VISSZA"
	back_button.custom_minimum_size = Vector2(0, 48)
	UI_THEME.style_button(back_button, Color("d8b56c"), true)
	back_button.pressed.connect(_on_settings_back_pressed)
	layout.add_child(back_button)


func _load_settings() -> void:
	settings_config.load("user://settings.cfg")
	var saved_volume := float(settings_config.get_value("audio", "master_volume", 0.8))
	var saved_fullscreen := bool(settings_config.get_value("display", "fullscreen", false))

	volume_slider.value = clampf(saved_volume, 0.0, 1.0)
	fullscreen_toggle.button_pressed = saved_fullscreen
	_on_volume_changed(volume_slider.value)
	_apply_fullscreen(saved_fullscreen)


func _on_volume_changed(value: float) -> void:
	if volume_value_label != null:
		volume_value_label.text = str(roundi(value * 100.0)) + "%"

	var master_bus := AudioServer.get_bus_index("Master")
	if master_bus >= 0:
		AudioServer.set_bus_mute(master_bus, value <= 0.001)
		AudioServer.set_bus_volume_linear(master_bus, maxf(value, 0.001))


func _on_fullscreen_toggled(enabled: bool) -> void:
	_apply_fullscreen(enabled)


func _apply_fullscreen(enabled: bool) -> void:
	var mode := DisplayServer.WINDOW_MODE_FULLSCREEN if enabled else DisplayServer.WINDOW_MODE_WINDOWED
	DisplayServer.window_set_mode(mode)


func _on_settings_back_pressed() -> void:
	settings_config.set_value("audio", "master_volume", volume_slider.value)
	settings_config.set_value("display", "fullscreen", fullscreen_toggle.button_pressed)
	var save_error := settings_config.save("user://settings.cfg")
	if save_error != OK:
		push_warning("A beállításokat nem sikerült lemezre menteni.")
	settings_overlay.hide()
	settings_panel.hide()
