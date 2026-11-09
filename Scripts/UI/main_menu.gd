extends Control

const UI_THEME = preload("res://Scripts/UI/ui_theme.gd")
const AUTOSAVE_SLOT_ID := 4

@onready var menu_panel: PanelContainer = $MenuPanel
@onready var title_label: Label = $MenuPanel/MarginContainer/MenuVBox/Title
@onready var subtitle_label: Label = $MenuPanel/MarginContainer/MenuVBox/Subtitle
@onready var start_button: Button = $MenuPanel/MarginContainer/MenuVBox/StartButton
@onready var settings_button: Button = $MenuPanel/MarginContainer/MenuVBox/SettingsButton
@onready var exit_button: Button = $MenuPanel/MarginContainer/MenuVBox/ExitButton

var load_button: Button

# Custom save picker. A purpose-built Control overlay gives the save screen the
# same visual language as the rest of the game's dark-and-gold UI.
var save_overlay: Control
var save_title_label: Label
var save_subtitle_label: Label
var save_description_label: Label
var save_cards_container: HBoxContainer
var save_slot_buttons: Array[Button] = []
var save_slot_status_labels: Array[Label] = []
var save_slot_detail_labels: Array[Label] = []
var autosave_row: Button
var autosave_status_label: Label
var autosave_detail_label: Label
var cancel_save_button: Button
var confirm_save_button: Button
var selection_hint_label: Label

var dialog_mode: String = "new"
var selected_slot_id: int = 0


func _ready() -> void:
	UI_THEME.style_panel(menu_panel, Color("d8b56c"), Color(0.025, 0.045, 0.075, 0.94))
	UI_THEME.style_button(start_button, Color("e9bd61"), true)
	UI_THEME.style_button(settings_button, Color("8baac7"))
	UI_THEME.style_button(exit_button, Color("c77769"))
	title_label.add_theme_color_override("font_color", UI_THEME.IVORY)
	title_label.add_theme_font_size_override("font_size", 40)
	subtitle_label.add_theme_color_override("font_color", UI_THEME.GOLD)
	exit_button.add_theme_color_override("font_color", Color("f1c6bc"))
	start_button.text = "Új játék"
	start_button.icon = load("res://Arts/UI/Icons/play_sword.png")
	settings_button.text = "Beállítások"
	settings_button.icon = load("res://Arts/UI/Icons/settings.png")
	exit_button.text = "Kilépés"
	exit_button.icon = load("res://Arts/UI/Icons/exit.png")
	_add_load_button()
	_create_save_overlay()
	$MenuPanel/MarginContainer/MenuVBox/VersionLabel.add_theme_color_override("font_color", UI_THEME.MUTED)
	$MenuPanel/MarginContainer/MenuVBox/Divider.add_theme_color_override("color", Color(0.75, 0.57, 0.30, 0.8))


func _add_load_button() -> void:
	load_button = Button.new()
	load_button.name = "LoadGameButton"
	load_button.text = "Játék betöltése"
	load_button.custom_minimum_size = Vector2(0, 58)
	load_button.icon = load("res://Arts/UI/Icons/inventory.png")
	UI_THEME.style_button(load_button, Color("8baac7"))
	var menu_vbox: VBoxContainer = $MenuPanel/MarginContainer/MenuVBox
	menu_vbox.add_child(load_button)
	menu_vbox.move_child(load_button, start_button.get_index() + 1)
	load_button.pressed.connect(_on_load_button_pressed)


func _create_save_overlay() -> void:
	save_overlay = Control.new()
	save_overlay.name = "SavePickerOverlay"
	save_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	save_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	save_overlay.visible = false
	save_overlay.z_index = 100
	add_child(save_overlay)

	var dimmer := ColorRect.new()
	dimmer.name = "Dimmer"
	dimmer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dimmer.color = Color(0.008, 0.015, 0.028, 0.84)
	dimmer.mouse_filter = Control.MOUSE_FILTER_STOP
	save_overlay.add_child(dimmer)

	var center := CenterContainer.new()
	center.name = "Center"
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	save_overlay.add_child(center)

	var panel := PanelContainer.new()
	panel.name = "SavePickerPanel"
	panel.custom_minimum_size = Vector2(900, 0)
	panel.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	panel.add_theme_stylebox_override(
		"panel",
		UI_THEME.make_box(Color("0b1420"), Color("d8b56c"), 2, 16)
	)
	center.add_child(panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 28)
	margin.add_theme_constant_override("margin_top", 24)
	margin.add_theme_constant_override("margin_right", 28)
	margin.add_theme_constant_override("margin_bottom", 24)
	panel.add_child(margin)

	var content := VBoxContainer.new()
	content.name = "Content"
	content.add_theme_constant_override("separation", 13)
	margin.add_child(content)

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 16)
	content.add_child(header)

	var emblem := TextureRect.new()
	emblem.custom_minimum_size = Vector2(52, 52)
	emblem.texture = load("res://Arts/UI/Icons/play_sword.png")
	emblem.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	emblem.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	emblem.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	header.add_child(emblem)

	var heading_column := VBoxContainer.new()
	heading_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	heading_column.add_theme_constant_override("separation", 4)
	header.add_child(heading_column)

	save_title_label = Label.new()
	save_title_label.text = "ÚJ KALAND INDÍTÁSA"
	save_title_label.add_theme_color_override("font_color", UI_THEME.IVORY)
	save_title_label.add_theme_font_size_override("font_size", 27)
	heading_column.add_child(save_title_label)

	save_subtitle_label = Label.new()
	save_subtitle_label.text = "Válaszd ki, hol kezdődjön a történeted."
	save_subtitle_label.add_theme_color_override("font_color", UI_THEME.GOLD)
	save_subtitle_label.add_theme_font_size_override("font_size", 14)
	heading_column.add_child(save_subtitle_label)

	var separator := HSeparator.new()
	separator.add_theme_color_override("color", Color(0.58, 0.43, 0.23, 0.9))
	content.add_child(separator)

	save_description_label = Label.new()
	save_description_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	save_description_label.add_theme_color_override("font_color", UI_THEME.MUTED)
	save_description_label.add_theme_font_size_override("font_size", 14)
	content.add_child(save_description_label)

	save_cards_container = HBoxContainer.new()
	save_cards_container.add_theme_constant_override("separation", 12)
	content.add_child(save_cards_container)
	for slot in range(1, GameState.MANUAL_SAVE_SLOT_COUNT + 1):
		_create_save_slot_card(slot)

	autosave_row = Button.new()
	autosave_row.name = "AutosaveCard"
	autosave_row.custom_minimum_size = Vector2(0, 76)
	autosave_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	autosave_row.text = ""
	autosave_row.pressed.connect(_on_autosave_card_pressed)
	_create_autosave_row_content()
	content.add_child(autosave_row)

	selection_hint_label = Label.new()
	selection_hint_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	selection_hint_label.add_theme_color_override("font_color", UI_THEME.MUTED)
	selection_hint_label.add_theme_font_size_override("font_size", 12)
	content.add_child(selection_hint_label)

	var footer_separator := HSeparator.new()
	footer_separator.add_theme_color_override("color", Color(0.28, 0.36, 0.45, 0.8))
	content.add_child(footer_separator)

	var footer := HBoxContainer.new()
	footer.alignment = BoxContainer.ALIGNMENT_END
	footer.add_theme_constant_override("separation", 12)
	content.add_child(footer)

	cancel_save_button = Button.new()
	cancel_save_button.text = "Mégse"
	cancel_save_button.custom_minimum_size = Vector2(140, 52)
	UI_THEME.style_button(cancel_save_button, Color("718096"))
	cancel_save_button.alignment = HORIZONTAL_ALIGNMENT_CENTER
	cancel_save_button.pressed.connect(_close_save_overlay)
	footer.add_child(cancel_save_button)

	confirm_save_button = Button.new()
	confirm_save_button.text = "Kaland indítása"
	confirm_save_button.custom_minimum_size = Vector2(210, 52)
	UI_THEME.style_button(confirm_save_button, Color("e9bd61"), true)
	confirm_save_button.alignment = HORIZONTAL_ALIGNMENT_CENTER
	confirm_save_button.pressed.connect(_confirm_save_selection)
	footer.add_child(confirm_save_button)


func _create_save_slot_card(slot: int) -> void:
	var button := Button.new()
	button.name = "SaveSlot%dCard" % slot
	button.custom_minimum_size = Vector2(0, 150)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.text = ""
	button.pressed.connect(_on_save_slot_card_pressed.bind(slot))
	save_cards_container.add_child(button)

	var card_margin := MarginContainer.new()
	card_margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	card_margin.add_theme_constant_override("margin_left", 10)
	card_margin.add_theme_constant_override("margin_top", 10)
	card_margin.add_theme_constant_override("margin_right", 10)
	card_margin.add_theme_constant_override("margin_bottom", 10)
	card_margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	button.add_child(card_margin)

	var card_content := VBoxContainer.new()
	card_content.alignment = BoxContainer.ALIGNMENT_CENTER
	card_content.add_theme_constant_override("separation", 7)
	card_content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card_margin.add_child(card_content)

	var slot_number := Label.new()
	slot_number.text = "MENTÉSI HELY  %02d" % slot
	slot_number.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	slot_number.add_theme_color_override("font_color", UI_THEME.GOLD)
	slot_number.add_theme_font_size_override("font_size", 12)
	slot_number.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card_content.add_child(slot_number)

	var status := Label.new()
	status.text = "Szabad hely"
	status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	status.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status.add_theme_color_override("font_color", UI_THEME.IVORY)
	status.add_theme_font_size_override("font_size", 17)
	status.custom_minimum_size.y = 34
	status.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card_content.add_child(status)

	var detail := Label.new()
	detail.text = "Itt kezdheted el az új kalandot."
	detail.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	detail.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	detail.add_theme_color_override("font_color", UI_THEME.MUTED)
	detail.add_theme_font_size_override("font_size", 12)
	detail.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card_content.add_child(detail)

	save_slot_buttons.append(button)
	save_slot_status_labels.append(status)
	save_slot_detail_labels.append(detail)


func _create_autosave_row_content() -> void:
	var row_margin := MarginContainer.new()
	row_margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	row_margin.add_theme_constant_override("margin_left", 16)
	row_margin.add_theme_constant_override("margin_top", 8)
	row_margin.add_theme_constant_override("margin_right", 16)
	row_margin.add_theme_constant_override("margin_bottom", 8)
	row_margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	autosave_row.add_child(row_margin)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row_margin.add_child(row)

	var icon := TextureRect.new()
	icon.custom_minimum_size = Vector2(42, 42)
	icon.texture = load("res://Arts/UI/Icons/inventory.png")
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(icon)

	var text_column := VBoxContainer.new()
	text_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text_column.alignment = BoxContainer.ALIGNMENT_CENTER
	text_column.add_theme_constant_override("separation", 3)
	text_column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(text_column)

	autosave_status_label = Label.new()
	autosave_status_label.text = "AUTOMATIKUS MENTÉS"
	autosave_status_label.add_theme_color_override("font_color", UI_THEME.IVORY)
	autosave_status_label.add_theme_font_size_override("font_size", 16)
	autosave_status_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	text_column.add_child(autosave_status_label)

	autosave_detail_label = Label.new()
	autosave_detail_label.text = "A játék legutóbb automatikusan mentett állapota."
	autosave_detail_label.add_theme_color_override("font_color", UI_THEME.MUTED)
	autosave_detail_label.add_theme_font_size_override("font_size", 12)
	autosave_detail_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	text_column.add_child(autosave_detail_label)

	var arrow := Label.new()
	arrow.text = "›"
	arrow.add_theme_color_override("font_color", UI_THEME.GOLD)
	arrow.add_theme_font_size_override("font_size", 32)
	arrow.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	arrow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(arrow)


func _open_save_overlay(mode: String) -> void:
	dialog_mode = mode
	selected_slot_id = 0
	save_overlay.visible = true
	autosave_row.visible = mode == "load"
	if mode == "new":
		save_title_label.text = "ÚJ KALAND INDÍTÁSA"
		save_subtitle_label.text = "Három külön mentési hely áll rendelkezésedre."
		save_description_label.text = "Válassz egy helyet az új karaktereknek. A foglalt hely kiválasztásakor a régi kézi mentés felülíródik; az automatikus mentés külön fájlban marad."
		confirm_save_button.text = "Kaland indítása"
	else:
		save_title_label.text = "KALAND FOLYTATÁSA"
		save_subtitle_label.text = "Válaszd ki azt a mentést, ahonnan folytatnád."
		save_description_label.text = "A betöltés a kiválasztott állapotot állítja vissza. Az üres vagy sérült mentési helyek nem tölthetők be."
		confirm_save_button.text = "Mentés betöltése"

	_refresh_save_cards()
	var default_slot := _get_default_slot_for_mode()
	_select_save_slot(default_slot)
	cancel_save_button.grab_focus()


func _refresh_save_cards() -> void:
	for index in range(save_slot_buttons.size()):
		var slot := index + 1
		var button := save_slot_buttons[index]
		var summary: Dictionary = GameState.get_save_slot_summary(slot)
		var file_exists := GameState.has_save_slot(slot)
		var summary_valid := bool(summary.get("exists", false))
		button.disabled = dialog_mode == "load" and (not file_exists or not summary_valid)

		if dialog_mode == "new":
			if file_exists and summary_valid:
				save_slot_status_labels[index].text = "MENTÉS FELÜLÍRÁSRA"
				save_slot_status_labels[index].add_theme_color_override("font_color", Color("f0c36b"))
				save_slot_detail_labels[index].text = str(summary.get("label", "Korábbi mentés"))
			elif file_exists:
				save_slot_status_labels[index].text = "NEM OLVASHATÓ FÁJL"
				save_slot_status_labels[index].add_theme_color_override("font_color", Color("e49a8d"))
				save_slot_detail_labels[index].text = "Az új játék felülírhatja ezt a fájlt."
			else:
				save_slot_status_labels[index].text = "SZABAD HELY"
				save_slot_status_labels[index].add_theme_color_override("font_color", Color("a9d4b6"))
				save_slot_detail_labels[index].text = "Itt kezdheted el az új kalandot."
		else:
			if file_exists and summary_valid:
				save_slot_status_labels[index].text = "MENTÉS ELÉRHETŐ"
				save_slot_status_labels[index].add_theme_color_override("font_color", Color("a9d4b6"))
				save_slot_detail_labels[index].text = str(summary.get("label", "Elmentett kaland"))
			elif file_exists:
				save_slot_status_labels[index].text = "SÉRÜLT MENTÉS"
				save_slot_status_labels[index].add_theme_color_override("font_color", Color("e49a8d"))
				save_slot_detail_labels[index].text = "A fájl nem olvasható, ezért nem tölthető be."
			else:
				save_slot_status_labels[index].text = "ÜRES HELY"
				save_slot_status_labels[index].add_theme_color_override("font_color", UI_THEME.MUTED)
				save_slot_detail_labels[index].text = "Ezen a helyen nincs mentés."

	var autosave_exists := GameState.has_autosave()
	autosave_row.disabled = not autosave_exists
	if autosave_exists:
		autosave_status_label.text = "AUTOMATIKUS MENTÉS  ·  ELÉRHETŐ"
		autosave_status_label.add_theme_color_override("font_color", UI_THEME.IVORY)
		autosave_detail_label.text = "A játék legutóbb automatikusan mentett állapota."
	else:
		autosave_status_label.text = "AUTOMATIKUS MENTÉS  ·  MÉG NINCS"
		autosave_status_label.add_theme_color_override("font_color", UI_THEME.MUTED)
		autosave_detail_label.text = "A játék során létrejövő automatikus mentés itt jelenik meg."
	_refresh_selection_styles()


func _get_default_slot_for_mode() -> int:
	if dialog_mode == "new":
		for slot in range(1, GameState.MANUAL_SAVE_SLOT_COUNT + 1):
			if not GameState.has_save_slot(slot):
				return slot
		return 1

	for slot in range(1, GameState.MANUAL_SAVE_SLOT_COUNT + 1):
		var summary: Dictionary = GameState.get_save_slot_summary(slot)
		if GameState.has_save_slot(slot) and bool(summary.get("exists", false)):
			return slot
	if GameState.has_autosave():
		return AUTOSAVE_SLOT_ID
	return 0


func _select_save_slot(slot_id: int) -> void:
	selected_slot_id = slot_id
	_refresh_selection_styles()
	if dialog_mode == "new":
		confirm_save_button.disabled = slot_id < 1 or slot_id > GameState.MANUAL_SAVE_SLOT_COUNT
		if slot_id > 0 and GameState.has_save_slot(slot_id):
			selection_hint_label.text = "Figyelem: a kiválasztott kézi mentés az új játék indításakor felülíródik."
			selection_hint_label.add_theme_color_override("font_color", Color("f0c36b"))
		else:
			selection_hint_label.text = "A kiválasztott hely üres, az új kaland új mentésként kerül elmentésre."
			selection_hint_label.add_theme_color_override("font_color", UI_THEME.MUTED)
	else:
		var selectable := false
		if slot_id == AUTOSAVE_SLOT_ID:
			selectable = GameState.has_autosave()
		elif slot_id >= 1 and slot_id <= GameState.MANUAL_SAVE_SLOT_COUNT:
			var summary: Dictionary = GameState.get_save_slot_summary(slot_id)
			selectable = GameState.has_save_slot(slot_id) and bool(summary.get("exists", false))
		confirm_save_button.disabled = not selectable
		if selectable:
			selection_hint_label.text = "A kiválasztott mentés betöltésre kész."
			selection_hint_label.add_theme_color_override("font_color", UI_THEME.MUTED)
		else:
			selection_hint_label.text = "Nincs betölthető mentés. Válassz egy elérhető mentési helyet."
			selection_hint_label.add_theme_color_override("font_color", Color("e49a8d"))
	_refresh_selection_styles()


func _refresh_selection_styles() -> void:
	for index in range(save_slot_buttons.size()):
		var slot_id := index + 1
		_style_save_card(save_slot_buttons[index], slot_id == selected_slot_id)
	_style_save_card(autosave_row, selected_slot_id == AUTOSAVE_SLOT_ID)


func _style_save_card(button: Button, selected: bool) -> void:
	if selected:
		button.add_theme_stylebox_override("normal", UI_THEME.make_box(Color("1c2a38"), UI_THEME.GOLD, 3, 12))
		button.add_theme_stylebox_override("hover", UI_THEME.make_box(Color("26394a"), Color("ffe0a0"), 3, 12))
		button.add_theme_stylebox_override("pressed", UI_THEME.make_box(Color("111d2a"), UI_THEME.GOLD, 3, 12))
		button.add_theme_stylebox_override("focus", UI_THEME.make_box(Color(0, 0, 0, 0), UI_THEME.GOLD, 2, 12))
	else:
		button.add_theme_stylebox_override("normal", UI_THEME.make_box(Color("101b29"), Color("3d5064"), 1, 12))
		button.add_theme_stylebox_override("hover", UI_THEME.make_box(Color("1c2a38"), Color("91aec8"), 2, 12))
		button.add_theme_stylebox_override("pressed", UI_THEME.make_box(Color("0b1420"), Color("91aec8"), 2, 12))
		button.add_theme_stylebox_override("focus", UI_THEME.make_box(Color(0, 0, 0, 0), Color("91aec8"), 2, 12))
	button.add_theme_stylebox_override("disabled", UI_THEME.make_box(Color("0b1119"), Color("2d3844"), 1, 12))


func _on_save_slot_card_pressed(slot_id: int) -> void:
	_select_save_slot(slot_id)


func _on_autosave_card_pressed() -> void:
	if GameState.has_autosave():
		_select_save_slot(AUTOSAVE_SLOT_ID)


func _confirm_save_selection() -> void:
	if selected_slot_id <= 0:
		return
	if dialog_mode == "new":
		if selected_slot_id < 1 or selected_slot_id > GameState.MANUAL_SAVE_SLOT_COUNT:
			return
		if GameState.start_new_game(selected_slot_id):
			_close_save_overlay()
			_change_to_lobby()
		else:
			_show_message("Az új játékot nem sikerült elmenteni. Ellenőrizd a mentési helyet, majd próbáld újra.")
		return

	if selected_slot_id == AUTOSAVE_SLOT_ID:
		if GameState.load_autosave():
			_close_save_overlay()
			_change_to_lobby()
		else:
			_show_message("Az automatikus mentést nem sikerült betölteni.")
		return

	if not GameState.has_save_slot(selected_slot_id):
		_show_message("Ez a mentési hely üres vagy nem olvasható.")
		return
	if GameState.load_from_slot(selected_slot_id):
		_close_save_overlay()
		_change_to_lobby()
	else:
		_show_message("A mentést nem sikerült betölteni.")


func _close_save_overlay() -> void:
	save_overlay.visible = false
	start_button.grab_focus()


func _unhandled_input(event: InputEvent) -> void:
	if save_overlay != null and save_overlay.visible and event.is_action_pressed("ui_cancel"):
		_close_save_overlay()
		get_viewport().set_input_as_handled()


func _on_start_button_pressed() -> void:
	_open_save_overlay("new")


func _on_load_button_pressed() -> void:
	_open_save_overlay("load")


func _change_to_lobby() -> void:
	var result := get_tree().change_scene_to_file("res://Scenes/Lobby/Lobby.tscn")
	if result != OK:
		push_error("Nem sikerült betölteni a Lobby jelenetet.")


func _on_settings_button_pressed() -> void:
	SettingsManager.open_settings()


func _on_exit_button_pressed() -> void:
	get_tree().quit()


func _show_message(message: String) -> void:
	var dialog := AcceptDialog.new()
	dialog.dialog_text = message
	add_child(dialog)
	dialog.confirmed.connect(dialog.queue_free)
	dialog.canceled.connect(dialog.queue_free)
	dialog.popup_centered()
