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

var load_button: Button
var save_dialog_overlay: ColorRect
var save_dialog_panel: PanelContainer
var save_dialog_title: Label
var save_dialog_subtitle: Label
var save_cards_grid: GridContainer
var autosave_button: Button
var save_dialog_primary: Button
var save_dialog_cancel: Button
var overwrite_dialog: ConfirmationDialog
var dialog_mode: String = "new"
var selected_save_id: int = 1
var save_card_buttons: Dictionary = {}


func _ready() -> void:
	UI_THEME.style_panel(menu_panel, Color("d8b56c"), Color(0.025, 0.045, 0.075, 0.94))
	start_button.text = "Új játék"
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

	_add_load_button()
	_build_save_dialog()
	_build_settings_panel()
	_load_settings()


func _add_load_button() -> void:
	var menu_vbox := $MenuPanel/MarginContainer/MenuVBox as VBoxContainer
	load_button = Button.new()
	load_button.name = "LoadGameButton"
	load_button.text = "Játék betöltése"
	load_button.custom_minimum_size = Vector2(0, 58)
	load_button.icon = load("res://Arts/UI/Icons/inventory.png")
	UI_THEME.style_button(load_button, Color("9c8060"))
	menu_vbox.add_child(load_button)
	menu_vbox.move_child(load_button, settings_button.get_index())
	load_button.pressed.connect(_on_load_button_pressed)


func _on_start_button_pressed() -> void:
	_open_save_dialog("new")


func _on_load_button_pressed() -> void:
	_open_save_dialog("load")


func _build_save_dialog() -> void:
	save_dialog_overlay = ColorRect.new()
	save_dialog_overlay.name = "SaveDialogOverlay"
	save_dialog_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	save_dialog_overlay.color = Color(0.005, 0.008, 0.012, 0.84)
	save_dialog_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	save_dialog_overlay.visible = false
	add_child(save_dialog_overlay)

	save_dialog_panel = PanelContainer.new()
	save_dialog_panel.name = "SaveDialogPanel"
	save_dialog_panel.anchor_left = 0.5
	save_dialog_panel.anchor_top = 0.5
	save_dialog_panel.anchor_right = 0.5
	save_dialog_panel.anchor_bottom = 0.5
	save_dialog_panel.offset_left = -360
	save_dialog_panel.offset_top = -260
	save_dialog_panel.offset_right = 360
	save_dialog_panel.offset_bottom = 260
	UI_THEME.style_panel(save_dialog_panel, Color("c08a47"), Color(0.035, 0.027, 0.026, 0.99))
	save_dialog_overlay.add_child(save_dialog_panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 24)
	margin.add_theme_constant_override("margin_top", 20)
	margin.add_theme_constant_override("margin_right", 24)
	margin.add_theme_constant_override("margin_bottom", 20)
	save_dialog_panel.add_child(margin)

	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 12)
	margin.add_child(content)

	save_dialog_title = Label.new()
	save_dialog_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	save_dialog_title.add_theme_color_override("font_color", UI_THEME.IVORY)
	save_dialog_title.add_theme_font_size_override("font_size", 28)
	content.add_child(save_dialog_title)

	save_dialog_subtitle = Label.new()
	save_dialog_subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	save_dialog_subtitle.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	save_dialog_subtitle.add_theme_color_override("font_color", UI_THEME.MUTED)
	save_dialog_subtitle.add_theme_font_size_override("font_size", 13)
	content.add_child(save_dialog_subtitle)

	var separator := HSeparator.new()
	separator.add_theme_color_override("color", Color(0.67, 0.48, 0.27, 0.8))
	content.add_child(separator)

	save_cards_grid = GridContainer.new()
	save_cards_grid.columns = 3
	save_cards_grid.add_theme_constant_override("h_separation", 10)
	save_cards_grid.add_theme_constant_override("v_separation", 10)
	content.add_child(save_cards_grid)

	autosave_button = Button.new()
	autosave_button.custom_minimum_size = Vector2(0, 58)
	autosave_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	autosave_button.pressed.connect(_on_autosave_card_pressed)
	content.add_child(autosave_button)

	var footer := HBoxContainer.new()
	footer.alignment = BoxContainer.ALIGNMENT_CENTER
	footer.add_theme_constant_override("separation", 12)
	content.add_child(footer)

	save_dialog_primary = Button.new()
	save_dialog_primary.custom_minimum_size = Vector2(230, 48)
	UI_THEME.style_button(save_dialog_primary, Color("e9bd61"), true)
	save_dialog_primary.add_theme_font_size_override("font_size", 14)
	save_dialog_primary.pressed.connect(_on_save_dialog_primary_pressed)
	footer.add_child(save_dialog_primary)

	save_dialog_cancel = Button.new()
	save_dialog_cancel.text = "MÉGSE"
	save_dialog_cancel.custom_minimum_size = Vector2(150, 48)
	UI_THEME.style_button(save_dialog_cancel, Color("8d7770"))
	save_dialog_cancel.add_theme_font_size_override("font_size", 14)
	save_dialog_cancel.pressed.connect(_close_save_dialog)
	footer.add_child(save_dialog_cancel)

	overwrite_dialog = ConfirmationDialog.new()
	overwrite_dialog.title = "Mentés felülírása"
	overwrite_dialog.dialog_text = "A kiválasztott mentési hely már tartalmaz adatokat. Biztosan felülírod?"
	overwrite_dialog.confirmed.connect(_confirm_start_new_game)
	add_child(overwrite_dialog)


func _open_save_dialog(mode: String) -> void:
	dialog_mode = mode
	selected_save_id = 1
	save_dialog_overlay.show()
	_refresh_save_dialog()


func _refresh_save_dialog() -> void:
	var is_new_game := dialog_mode == "new"
	save_dialog_title.text = "ÚJ KALAND INDÍTÁSA" if is_new_game else "JÁTÉK BETÖLTÉSE"
	save_dialog_subtitle.text = "Válassz mentési helyet az új kalandhoz. A meglévő mentés felülíródik, ha már foglalt." if is_new_game else "Válaszd ki a betölteni kívánt mentést. Az üres vagy hibás mentési helyek nem választhatók ki."
	save_dialog_primary.text = "ÚJ JÁTÉK INDÍTÁSA" if is_new_game else "MENTÉS BETÖLTÉSE"
	for child in save_cards_grid.get_children():
		save_cards_grid.remove_child(child)
		child.queue_free()
	save_card_buttons.clear()
	var first_available := -1
	for slot in range(1, GameState.MANUAL_SAVE_SLOT_COUNT + 1):
		var summary := GameState.get_save_slot_summary(slot)
		var exists := bool(summary.get("exists", false))
		var names: Array = summary.get("characters", [])
		var character_text := ", ".join(PackedStringArray(names)) if not names.is_empty() else "Üres mentési hely"
		var save_text := "MENTÉS %d\n%s\nArany: %d" % [slot, character_text, int(summary.get("gold", 0))] if exists else "MENTÉS %d\n\nÜRES HELY" % slot
		var card := _make_save_card(slot, save_text, exists or is_new_game)
		save_cards_grid.add_child(card)
		save_card_buttons[slot] = card
		if first_available == -1 and (exists or is_new_game):
			first_available = slot
	var auto_summary := GameState.get_autosave_summary()
	var auto_exists := bool(auto_summary.get("exists", false))
	if auto_exists:
		var auto_names: Array = auto_summary.get("characters", [])
		autosave_button.text = "AUTOMATIKUS MENTÉS  ·  %s  ·  Arany: %d" % [", ".join(PackedStringArray(auto_names)), int(auto_summary.get("gold", 0))]
		autosave_button.visible = not is_new_game
		autosave_button.disabled = is_new_game
	else:
		autosave_button.text = "NINCS AUTOMATIKUS MENTÉS"
		autosave_button.visible = not is_new_game
		autosave_button.disabled = true
	if not is_new_game and first_available == -1 and auto_exists:
		first_available = 4
	if first_available != -1:
		selected_save_id = first_available
	_update_save_card_selection()
	save_dialog_primary.disabled = not is_new_game and first_available == -1


func _make_save_card(slot: int, text_value: String, enabled: bool) -> Button:
	var card := Button.new()
	card.custom_minimum_size = Vector2(190, 132)
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.text = text_value
	card.alignment = HORIZONTAL_ALIGNMENT_CENTER
	card.add_theme_font_size_override("font_size", 13)
	card.disabled = not enabled
	card.pressed.connect(_on_save_card_pressed.bind(slot))
	UI_THEME.style_button(card, Color(0.67, 0.47, 0.28, 1.0))
	card.add_theme_stylebox_override("normal", UI_THEME.make_box(Color(0.075, 0.055, 0.045, 1.0), Color(0.47, 0.34, 0.23, 1.0), 2, 5))
	card.add_theme_stylebox_override("hover", UI_THEME.make_box(Color(0.14, 0.095, 0.055, 1.0), Color(0.83, 0.62, 0.34, 1.0), 2, 5))
	card.add_theme_stylebox_override("disabled", UI_THEME.make_box(Color(0.045, 0.04, 0.035, 1.0), Color(0.22, 0.18, 0.14, 1.0), 1, 5))
	return card


func _on_save_card_pressed(slot: int) -> void:
	selected_save_id = slot
	_update_save_card_selection()


func _on_autosave_card_pressed() -> void:
	if dialog_mode == "load" and GameState.has_autosave():
		selected_save_id = 4
		_update_save_card_selection()


func _update_save_card_selection() -> void:
	for slot in save_card_buttons:
		var card := save_card_buttons[slot] as Button
		if int(slot) == selected_save_id:
			card.add_theme_stylebox_override("normal", UI_THEME.make_box(Color(0.20, 0.13, 0.065, 1.0), Color(1.0, 0.77, 0.36, 1.0), 3, 5))
		else:
			card.add_theme_stylebox_override("normal", UI_THEME.make_box(Color(0.075, 0.055, 0.045, 1.0), Color(0.47, 0.34, 0.23, 1.0), 2, 5))
	if autosave_button != null:
		var auto_selected := selected_save_id == 4
		autosave_button.add_theme_stylebox_override("normal", UI_THEME.make_box(Color(0.20, 0.13, 0.065, 1.0) if auto_selected else Color(0.075, 0.055, 0.045, 1.0), Color(1.0, 0.77, 0.36, 1.0) if auto_selected else Color(0.47, 0.34, 0.23, 1.0), 3 if auto_selected else 2, 5))


func _on_save_dialog_primary_pressed() -> void:
	if dialog_mode == "new":
		if GameState.has_save_slot(selected_save_id):
			overwrite_dialog.dialog_text = "A %d. mentési hely már tartalmaz mentést. Az új játék felülírja ezt a helyet. Folytatod?" % selected_save_id
			overwrite_dialog.popup_centered(Vector2i(500, 190))
		else:
			_confirm_start_new_game()
		return
	var loaded := GameState.load_autosave() if selected_save_id == 4 else GameState.load_from_slot(selected_save_id)
	if loaded:
		_close_save_dialog()
		_enter_lobby()
	else:
		save_dialog_subtitle.text = "A kiválasztott mentést nem sikerült betölteni. Válassz másik mentést."
		_refresh_save_dialog()


func _confirm_start_new_game() -> void:
	if GameState.start_new_game(selected_save_id):
		_close_save_dialog()
		_enter_lobby()
	else:
		save_dialog_subtitle.text = "Nem sikerült létrehozni a mentést. Ellenőrizd a kiválasztott mentési helyet."


func _close_save_dialog() -> void:
	if save_dialog_overlay != null:
		save_dialog_overlay.hide()


func _enter_lobby() -> void:
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


func _input(event: InputEvent) -> void:
	if save_dialog_overlay == null or not save_dialog_overlay.visible:
		return
	if event.is_action_pressed("ui_cancel"):
		_close_save_dialog()
		get_viewport().set_input_as_handled()
