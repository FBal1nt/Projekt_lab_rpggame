extends Control

const UI_THEME = preload("res://Scripts/UI/ui_theme.gd")
const CHARACTER_CREATION_OVERLAY_SCENE: PackedScene = preload("res://Scenes/UI/CharacterCreationOverlay.tscn")
const AUTOSAVE_SLOT_ID := 4

@onready var menu_panel: PanelContainer = $MenuPanel
@onready var title_label: Label = $MenuPanel/MarginContainer/MenuVBox/Title
@onready var subtitle_label: Label = $MenuPanel/MarginContainer/MenuVBox/Subtitle
@onready var start_button: Button = $MenuPanel/MarginContainer/MenuVBox/StartButton
@onready var settings_button: Button = $MenuPanel/MarginContainer/MenuVBox/SettingsButton
@onready var exit_button: Button = $MenuPanel/MarginContainer/MenuVBox/ExitButton

var load_button: Button
var delete_saves_button: Button
var character_creation_overlay: CharacterCreationOverlay
var _is_changing_scene: bool = false

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
var save_slot_check_labels: Array[Label] = []
var autosave_row: Button
var autosave_status_label: Label
var autosave_detail_label: Label
var autosave_check_label: Label
var autosave_arrow_label: Label
var save_path_label: Label
var cancel_save_button: Button
var confirm_save_button: Button
var selection_hint_label: Label

var dialog_mode: String = "new"
var selected_slot_id: int = 0
var _pending_new_save_slot: int = 0
var _selected_delete_slots: Dictionary = {}
var _delete_autosave_selected: bool = false


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
	start_button.icon = load("res://Assets/UI/Icons/play_sword.png")
	start_button.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	settings_button.text = "Beállítások"
	settings_button.icon = load("res://Assets/UI/Icons/settings.png")
	settings_button.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	exit_button.text = "Kilépés"
	exit_button.icon = load("res://Assets/UI/Icons/exit.png")
	exit_button.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	_add_menu_buttons()
	_create_save_overlay()
	_create_character_creation_overlay()
	$MenuPanel/MarginContainer/MenuVBox/VersionLabel.add_theme_color_override("font_color", UI_THEME.MUTED)
	$MenuPanel/MarginContainer/MenuVBox/Divider.add_theme_color_override("color", Color(0.75, 0.57, 0.30, 0.8))


func _add_menu_buttons() -> void:
	load_button = Button.new()
	load_button.name = "LoadGameButton"
	load_button.text = "Játék betöltése"
	load_button.custom_minimum_size = Vector2(0, 58)
	load_button.icon = load("res://Assets/UI/Icons/inventory.png")
	load_button.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	UI_THEME.style_button(load_button, Color("8baac7"))
	var menu_vbox: VBoxContainer = $MenuPanel/MarginContainer/MenuVBox
	menu_vbox.add_child(load_button)
	menu_vbox.move_child(load_button, start_button.get_index() + 1)
	load_button.pressed.connect(_on_load_button_pressed)

	delete_saves_button = Button.new()
	delete_saves_button.name = "DeleteSavesButton"
	delete_saves_button.text = "Mentések törlése"
	delete_saves_button.custom_minimum_size = Vector2(0, 52)
	delete_saves_button.icon = load("res://Assets/UI/Icons/delete_saves.png")
	delete_saves_button.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	UI_THEME.style_button(delete_saves_button, Color("c77769"))
	delete_saves_button.add_theme_color_override("font_color", Color("f4d0c8"))
	menu_vbox.add_child(delete_saves_button)
	menu_vbox.move_child(delete_saves_button, load_button.get_index() + 1)
	delete_saves_button.pressed.connect(_on_delete_saves_button_pressed)


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
	emblem.texture = load("res://Assets/UI/Icons/play_sword.png")
	emblem.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
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
	autosave_row.clip_contents = true
	autosave_row.text = ""
	autosave_row.pressed.connect(_on_autosave_card_pressed)
	_create_autosave_row_content()
	content.add_child(autosave_row)

	save_path_label = Label.new()
	save_path_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	save_path_label.add_theme_color_override("font_color", Color("6f869c"))
	save_path_label.add_theme_font_size_override("font_size", 11)
	content.add_child(save_path_label)

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
	cancel_save_button.custom_minimum_size = Vector2(140, 48)
	UI_THEME.style_button(cancel_save_button, Color("718096"))
	cancel_save_button.alignment = HORIZONTAL_ALIGNMENT_CENTER
	AudioManager.mark_custom_button_sfx(cancel_save_button)
	cancel_save_button.pressed.connect(_close_save_overlay)
	footer.add_child(cancel_save_button)

	confirm_save_button = Button.new()
	confirm_save_button.text = "Tovább →"
	confirm_save_button.custom_minimum_size = Vector2(225, 48)
	UI_THEME.style_button(confirm_save_button, Color("e9bd61"), true)
	confirm_save_button.alignment = HORIZONTAL_ALIGNMENT_CENTER
	confirm_save_button.pressed.connect(_confirm_save_selection)
	footer.add_child(confirm_save_button)


func _create_character_creation_overlay() -> void:
	character_creation_overlay = CHARACTER_CREATION_OVERLAY_SCENE.instantiate() as CharacterCreationOverlay
	character_creation_overlay.name = "CharacterCreationOverlay"
	character_creation_overlay.visible = false
	character_creation_overlay.z_index = 120
	character_creation_overlay.character_confirmed.connect(_on_character_created_for_new_save)
	character_creation_overlay.back_requested.connect(_on_character_creation_back)
	add_child(character_creation_overlay)


func _create_save_slot_card(slot: int) -> void:
	var button := Button.new()
	button.name = "SaveSlot%dCard" % slot
	button.custom_minimum_size = Vector2(0, 176)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.clip_contents = true
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
	card_content.add_theme_constant_override("separation", 6)
	card_content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card_margin.add_child(card_content)

	var check_label := Label.new()
	check_label.text = "[  ]"
	check_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	check_label.add_theme_color_override("font_color", UI_THEME.MUTED)
	check_label.add_theme_font_size_override("font_size", 12)
	check_label.visible = false
	check_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card_content.add_child(check_label)

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
	status.add_theme_font_size_override("font_size", 16)
	status.custom_minimum_size.y = 32
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
	save_slot_check_labels.append(check_label)


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
	icon.texture = load("res://Assets/UI/Icons/inventory.png")
	icon.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
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

	autosave_check_label = Label.new()
	autosave_check_label.text = "[  ]"
	autosave_check_label.add_theme_color_override("font_color", UI_THEME.MUTED)
	autosave_check_label.add_theme_font_size_override("font_size", 13)
	autosave_check_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	autosave_check_label.visible = false
	autosave_check_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(autosave_check_label)

	autosave_arrow_label = Label.new()
	autosave_arrow_label.text = ">"
	autosave_arrow_label.add_theme_color_override("font_color", UI_THEME.GOLD)
	autosave_arrow_label.add_theme_font_size_override("font_size", 24)
	autosave_arrow_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	autosave_arrow_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(autosave_arrow_label)


func _open_save_overlay(mode: String) -> void:
	dialog_mode = mode
	selected_slot_id = 0
	_selected_delete_slots.clear()
	_delete_autosave_selected = false
	save_overlay.visible = true
	autosave_row.visible = mode == "load" or mode == "delete"
	save_path_label.text = "Mentési mappa: %s" % GameState.get_saves_directory()

	if mode == "new":
		save_title_label.text = "ÚJ KALAND INDÍTÁSA"
		save_subtitle_label.text = "Három külön mentési hely áll rendelkezésedre."
		save_description_label.text = "Válassz egy mentési helyet, majd a következő lépésekben add meg a karaktered nevét és osztályát."
		confirm_save_button.text = "Tovább →"
		UI_THEME.style_button(confirm_save_button, Color("e9bd61"), true)
	elif mode == "load":
		save_title_label.text = "KALAND FOLYTATÁSA"
		save_subtitle_label.text = "Válaszd ki azt a mentést, ahonnan folytatnád."
		save_description_label.text = "A betöltés a kiválasztott állapotot állítja vissza. Az üres vagy sérült mentési helyek nem tölthetők be."
		confirm_save_button.text = "Mentés betöltése"
		UI_THEME.style_button(confirm_save_button, Color("e9bd61"), true)
	else:
		save_title_label.text = "MENTÉSEK TÖRLÉSE"
		save_subtitle_label.text = "Jelöld ki a törölni kívánt mentési helyeket (több is választható)."
		save_description_label.text = "Kattints közvetlenül a törlendő kézi mentésekre vagy az automatikus mentésre. A kijelölt fájlok megerősítés után törlődnek."
		UI_THEME.style_button(confirm_save_button, Color("d96b5c"), true)

	_refresh_save_cards()
	if mode != "delete":
		var default_slot := _get_default_slot_for_mode()
		_select_save_slot(default_slot)
	else:
		_refresh_delete_controls()
	cancel_save_button.grab_focus()


func _refresh_save_cards() -> void:
	var is_delete := dialog_mode == "delete"
	for index in range(save_slot_buttons.size()):
		var slot := index + 1
		var button := save_slot_buttons[index]
		var summary: Dictionary = GameState.get_save_slot_summary(slot)
		var file_exists := GameState.has_save_slot(slot)
		var summary_valid := bool(summary.get("exists", false))

		if is_delete:
			button.disabled = not file_exists
		elif dialog_mode == "load":
			button.disabled = not file_exists or not summary_valid
		else:
			button.disabled = false

		save_slot_check_labels[index].visible = is_delete and file_exists

		if is_delete:
			if file_exists and summary_valid:
				save_slot_status_labels[index].text = "TÖRÖLHETŐ MENTÉS"
				save_slot_status_labels[index].add_theme_color_override("font_color", Color("f0c36b"))
				save_slot_detail_labels[index].text = str(summary.get("label", "Elmentett kaland"))
			elif file_exists:
				save_slot_status_labels[index].text = "SÉRÜLT MENTÉS"
				save_slot_status_labels[index].add_theme_color_override("font_color", Color("e49a8d"))
				save_slot_detail_labels[index].text = "Sérült fájl — kijelölhető törlésre."
			else:
				save_slot_status_labels[index].text = "ÜRES HELY"
				save_slot_status_labels[index].add_theme_color_override("font_color", UI_THEME.MUTED)
				save_slot_detail_labels[index].text = "Nincs mentés ezen a helyen."
		elif dialog_mode == "new":
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
	var autosave_summary: Dictionary = GameState.get_autosave_summary()
	var autosave_valid := bool(autosave_summary.get("exists", false))
	autosave_row.disabled = (not autosave_exists) or (dialog_mode == "load" and not autosave_valid)
	autosave_check_label.visible = is_delete and autosave_exists
	autosave_arrow_label.visible = not is_delete

	if autosave_exists and autosave_valid:
		autosave_status_label.text = "AUTOMATIKUS MENTÉS  ·  ELÉRHETŐ"
		autosave_status_label.add_theme_color_override("font_color", UI_THEME.IVORY)
		autosave_detail_label.text = str(autosave_summary.get("label", "A játék legutóbb automatikusan mentett állapota."))
	elif autosave_exists:
		autosave_status_label.text = "AUTOMATIKUS MENTÉS  ·  SÉRÜLT"
		autosave_status_label.add_theme_color_override("font_color", Color("e49a8d"))
		autosave_detail_label.text = "Az automatikus mentés sérült; törlési módban eltávolítható."
	else:
		autosave_status_label.text = "AUTOMATIKUS MENTÉS  ·  MÉG NINCS"
		autosave_status_label.add_theme_color_override("font_color", UI_THEME.MUTED)
		autosave_detail_label.text = "A játék során létrejövő automatikus mentés itt jelenik meg."

	_refresh_selection_styles()
	if is_delete:
		_refresh_delete_controls()


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
	var autosave_summary: Dictionary = GameState.get_autosave_summary()
	if GameState.has_autosave() and bool(autosave_summary.get("exists", false)):
		return AUTOSAVE_SLOT_ID
	return 0


func _select_save_slot(slot_id: int) -> void:
	selected_slot_id = slot_id
	_refresh_selection_styles()
	if dialog_mode == "new":
		confirm_save_button.disabled = slot_id < 1 or slot_id > GameState.MANUAL_SAVE_SLOT_COUNT
		if slot_id > 0 and GameState.has_save_slot(slot_id):
			selection_hint_label.text = "Figyelem: ez a mentési hely foglalt. A karakterkészítés után megerősítéskor felülíródik."
			selection_hint_label.add_theme_color_override("font_color", Color("f0c36b"))
		else:
			selection_hint_label.text = "A kiválasztott hely üres. A következő ablakban adhatod meg a karakter nevét és osztályát."
			selection_hint_label.add_theme_color_override("font_color", UI_THEME.MUTED)
	else:
		var selectable := false
		if slot_id == AUTOSAVE_SLOT_ID:
			var auto_summary: Dictionary = GameState.get_autosave_summary()
			selectable = GameState.has_autosave() and bool(auto_summary.get("exists", false))
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


func _refresh_selection_styles() -> void:
	var is_delete := dialog_mode == "delete"
	for index in range(save_slot_buttons.size()):
		var slot_id := index + 1
		if is_delete:
			var marked := bool(_selected_delete_slots.get(slot_id, false))
			save_slot_check_labels[index].text = "[X] KIJELÖLVE" if marked else "[  ] KATTINTS A TÖRLÉSHEZ"
			save_slot_check_labels[index].add_theme_color_override(
				"font_color",
				Color("ff9f90") if marked else UI_THEME.MUTED
			)
			_style_save_card(save_slot_buttons[index], marked, true)
		else:
			_style_save_card(save_slot_buttons[index], slot_id == selected_slot_id, false)

	if is_delete:
		autosave_check_label.text = "[X] KIJELÖLVE" if _delete_autosave_selected else "[  ] KIJELÖLÉS"
		autosave_check_label.add_theme_color_override(
			"font_color",
			Color("ff9f90") if _delete_autosave_selected else UI_THEME.MUTED
		)
		_style_save_card(autosave_row, _delete_autosave_selected, true)
	else:
		_style_save_card(autosave_row, selected_slot_id == AUTOSAVE_SLOT_ID, false)


func _style_save_card(button: Button, selected: bool, danger_mode: bool = false) -> void:
	if selected and danger_mode:
		button.add_theme_stylebox_override("normal", UI_THEME.make_box(Color(0.24, 0.085, 0.095, 0.96), Color("e57c6e"), 3, 12))
		button.add_theme_stylebox_override("hover", UI_THEME.make_box(Color(0.30, 0.11, 0.12, 0.98), Color("ffaba0"), 3, 12))
		button.add_theme_stylebox_override("pressed", UI_THEME.make_box(Color(0.18, 0.06, 0.07, 0.98), Color("e57c6e"), 3, 12))
		button.add_theme_stylebox_override("focus", UI_THEME.make_box(Color(0, 0, 0, 0), Color("e57c6e"), 2, 12))
	elif selected:
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
	if dialog_mode == "delete":
		_toggle_delete_target(slot_id)
		return
	_select_save_slot(slot_id)


func _on_autosave_card_pressed() -> void:
	if dialog_mode == "delete":
		_toggle_delete_target(AUTOSAVE_SLOT_ID)
		return
	var autosave_summary: Dictionary = GameState.get_autosave_summary()
	if GameState.has_autosave() and bool(autosave_summary.get("exists", false)):
		_select_save_slot(AUTOSAVE_SLOT_ID)


func _toggle_delete_target(slot_id: int) -> void:
	if slot_id == AUTOSAVE_SLOT_ID:
		if not GameState.has_autosave():
			return
		_delete_autosave_selected = not _delete_autosave_selected
	else:
		if not GameState.has_save_slot(slot_id):
			return
		if _selected_delete_slots.has(slot_id):
			_selected_delete_slots.erase(slot_id)
		else:
			_selected_delete_slots[slot_id] = true
	_refresh_selection_styles()
	_refresh_delete_controls()


func _refresh_delete_controls() -> void:
	var existing_count := _count_existing_saves()
	var selected_count := _get_selected_delete_count()
	confirm_save_button.text = "Kijelöltek törlése (%d)" % selected_count if selected_count > 0 else "Kijelöltek törlése"
	confirm_save_button.disabled = selected_count == 0

	if existing_count == 0:
		selection_hint_label.text = "Jelenleg egyetlen mentés sem található a Saves mappában."
		selection_hint_label.add_theme_color_override("font_color", UI_THEME.MUTED)
	elif selected_count == 0:
		selection_hint_label.text = "Kattints a fenti kártyákra a törölni kívánt mentések kijelöléséhez."
		selection_hint_label.add_theme_color_override("font_color", UI_THEME.MUTED)
	else:
		selection_hint_label.text = "%d mentés kijelölve végleges törlésre." % selected_count
		selection_hint_label.add_theme_color_override("font_color", Color("ff9f90"))


func _count_existing_saves() -> int:
	var count := 0
	for slot in range(1, GameState.MANUAL_SAVE_SLOT_COUNT + 1):
		if GameState.has_save_slot(slot):
			count += 1
	if GameState.has_autosave():
		count += 1
	return count


func _get_selected_delete_count() -> int:
	return _selected_delete_slots.size() + (1 if _delete_autosave_selected else 0)


func _confirm_save_selection() -> void:
	if dialog_mode == "delete":
		_request_delete_confirmation()
		return
	if selected_slot_id <= 0:
		return
	if dialog_mode == "new":
		if selected_slot_id < 1 or selected_slot_id > GameState.MANUAL_SAVE_SLOT_COUNT:
			return
		_begin_new_game_character_creation(selected_slot_id)
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


var _active_modal_dialog: Node = null


func _begin_new_game_character_creation(slot_id: int) -> void:
	_pending_new_save_slot = slot_id
	if GameState.has_save_slot(slot_id):
		var summary: Dictionary = GameState.get_save_slot_summary(slot_id)
		var existing_label := str(summary.get("label", "Korábbi mentés"))
		_show_custom_confirm_dialog(
			"MENTÉS FELÜLÍRÁSA",
			"A(z) %02d. mentési hely már foglalt:" % slot_id,
			existing_label,
			"Folytatod az új karakter létrehozását?\nA korábbi mentés az új kaland indításakor íródik felül.",
			"Igen, tovább",
			"Mégse",
			Color("d6a34e"),
			func() -> void:
				call_deferred("_open_character_creation_for_pending_slot")
		)
		return
	_open_character_creation_for_pending_slot()


func _open_character_creation_for_pending_slot() -> void:
	save_overlay.visible = false
	character_creation_overlay.open_for_slot(_pending_new_save_slot)


func _on_character_creation_back() -> void:
	_open_save_overlay("new")
	_select_save_slot(_pending_new_save_slot)


func _on_character_created_for_new_save(character_name: String, class_id: StringName) -> void:
	if GameState.start_new_game(_pending_new_save_slot, character_name, class_id):
		character_creation_overlay.close_overlay()
		_change_to_lobby()
	else:
		character_creation_overlay.close_overlay()
		_open_save_overlay("new")
		_select_save_slot(_pending_new_save_slot)
		_show_message("Az új játékot nem sikerült elmenteni. Ellenőrizd a megadott nevet, osztályt és a mentési mappát.")


func _request_delete_confirmation() -> void:
	var slots_to_delete: Array[int] = []
	var lines: Array[String] = []
	for slot in range(1, GameState.MANUAL_SAVE_SLOT_COUNT + 1):
		if _selected_delete_slots.get(slot, false) and GameState.has_save_slot(slot):
			slots_to_delete.append(slot)
			var summary: Dictionary = GameState.get_save_slot_summary(slot)
			var detail := str(summary.get("label", "Sérült vagy ismeretlen fájl")) if bool(summary.get("exists", false)) else "Sérült fájl"
			lines.append("• Mentési hely %02d — %s" % [slot, detail])
	var include_autosave := _delete_autosave_selected and GameState.has_autosave()
	if include_autosave:
		var auto_summary: Dictionary = GameState.get_autosave_summary()
		var auto_detail := str(auto_summary.get("label", "Automatikus mentés")) if bool(auto_summary.get("exists", false)) else "Sérült fájl"
		lines.append("• Automatikus mentés — %s" % auto_detail)

	if slots_to_delete.is_empty() and not include_autosave:
		return

	_show_custom_confirm_dialog(
		"KIJELÖLT MENTÉSEK TÖRLÉSE",
		"Biztosan véglegesen törlöd a következő mentés(eke)t?",
		"\n".join(lines),
		"Ez a művelet nem vonható vissza.",
		"Végleges törlés",
		"Mégse",
		Color("d95a4c"),
		func() -> void:
			var deleted_count := GameState.delete_saves(slots_to_delete, include_autosave)
			_selected_delete_slots.clear()
			_delete_autosave_selected = false
			_refresh_save_cards()
			if deleted_count > 0:
				selection_hint_label.text = "%d mentés sikeresen törölve." % deleted_count
				selection_hint_label.add_theme_color_override("font_color", Color("a9d4b6"))
			else:
				_show_message("A kijelölt mentéseket nem sikerült törölni.")
	)


func _close_save_overlay() -> void:
	save_overlay.visible = false
	AudioManager.sfx(&"ui_cancel", 0.96, 1.04)
	start_button.grab_focus()


func _unhandled_input(event: InputEvent) -> void:
	if not is_inside_tree():
		return
	if _active_modal_dialog != null and is_instance_valid(_active_modal_dialog):
		if event.is_action_pressed("ui_cancel"):
			_dismiss_modal_dialog()
			var vp_modal := get_viewport()
			if vp_modal != null and vp_modal.is_inside_tree():
				vp_modal.set_input_as_handled()
		return
	if character_creation_overlay != null and character_creation_overlay.visible:
		return
	if save_overlay != null and save_overlay.visible and event.is_action_pressed("ui_cancel"):
		_close_save_overlay()
		var vp := get_viewport()
		if vp != null and vp.is_inside_tree():
			vp.set_input_as_handled()


func _on_start_button_pressed() -> void:
	_open_save_overlay("new")


func _on_load_button_pressed() -> void:
	_open_save_overlay("load")


func _on_delete_saves_button_pressed() -> void:
	_open_save_overlay("delete")


func _change_to_lobby() -> void:
	if _is_changing_scene:
		return
	_is_changing_scene = true
	call_deferred("_perform_change_to_lobby")


func _perform_change_to_lobby() -> void:
	if not is_inside_tree():
		_is_changing_scene = false
		return
	var lobby_path := "res://Scenes/Lobby/Lobby.tscn"
	if SceneTransition != null:
		if not SceneTransition.transition_failed.is_connected(_on_scene_transition_failed):
			SceneTransition.transition_failed.connect(_on_scene_transition_failed)
		if SceneTransition.request_scene_change(lobby_path):
			return
	var result := get_tree().change_scene_to_file(lobby_path)
	if result != OK:
		_is_changing_scene = false
		push_error("Nem sikerült betölteni a Lobby jelenetet.")


func _on_scene_transition_failed(_scene_path: String, _reason: String) -> void:
	if is_inside_tree():
		_is_changing_scene = false


func _on_settings_button_pressed() -> void:
	SettingsManager.open_settings()


func _on_exit_button_pressed() -> void:
	get_tree().quit()


func _dismiss_modal_dialog() -> void:
	if _active_modal_dialog != null and is_instance_valid(_active_modal_dialog):
		_active_modal_dialog.queue_free()
	_active_modal_dialog = null


func _show_custom_confirm_dialog(
	title_text: String,
	lead_text: String,
	highlight_text: String,
	footer_note: String,
	confirm_text: String,
	cancel_text: String,
	accent_color: Color,
	on_confirm: Callable,
	show_cancel: bool = true
) -> void:
	_dismiss_modal_dialog()

	var modal_layer := CanvasLayer.new()
	modal_layer.name = "CustomModalLayer"
	modal_layer.layer = 120
	add_child(modal_layer)
	_active_modal_dialog = modal_layer

	var backdrop := ColorRect.new()
	backdrop.name = "CustomModalBackdrop"
	backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	backdrop.color = Color(0.015, 0.025, 0.045, 0.80)
	backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	backdrop.z_index = 500
	modal_layer.add_child(backdrop)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_PASS
	backdrop.add_child(center)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(540, 0)
	panel.add_theme_stylebox_override("panel", UI_THEME.make_box(UI_THEME.PANEL, accent_color, 2, 14))
	center.add_child(panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 26)
	margin.add_theme_constant_override("margin_right", 26)
	margin.add_theme_constant_override("margin_top", 22)
	margin.add_theme_constant_override("margin_bottom", 22)
	panel.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 14)
	margin.add_child(vbox)

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 10)
	vbox.add_child(header)

	var modal_title_label := Label.new()
	modal_title_label.text = title_text
	modal_title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	modal_title_label.add_theme_color_override("font_color", accent_color.lightened(0.18))
	modal_title_label.add_theme_font_size_override("font_size", 21)
	header.add_child(modal_title_label)

	var sep := HSeparator.new()
	sep.modulate = Color(accent_color.r, accent_color.g, accent_color.b, 0.45)
	vbox.add_child(sep)

	if not lead_text.is_empty():
		var lead_label := Label.new()
		lead_label.text = lead_text
		lead_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		lead_label.add_theme_color_override("font_color", UI_THEME.IVORY)
		lead_label.add_theme_font_size_override("font_size", 15)
		vbox.add_child(lead_label)

	if not highlight_text.is_empty():
		var detail_card := PanelContainer.new()
		detail_card.add_theme_stylebox_override(
			"panel",
			UI_THEME.make_box(Color(0.025, 0.042, 0.068, 0.96), Color(accent_color.r, accent_color.g, accent_color.b, 0.55), 1, 10)
		)
		vbox.add_child(detail_card)

		var detail_margin := MarginContainer.new()
		detail_margin.add_theme_constant_override("margin_left", 14)
		detail_margin.add_theme_constant_override("margin_right", 14)
		detail_margin.add_theme_constant_override("margin_top", 10)
		detail_margin.add_theme_constant_override("margin_bottom", 10)
		detail_card.add_child(detail_margin)

		var detail_label := Label.new()
		detail_label.text = highlight_text
		detail_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		detail_label.add_theme_color_override("font_color", Color("f7e4b4"))
		detail_label.add_theme_font_size_override("font_size", 15)
		detail_margin.add_child(detail_label)

	if not footer_note.is_empty():
		var note_label := Label.new()
		note_label.text = footer_note
		note_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		note_label.add_theme_color_override("font_color", UI_THEME.MUTED)
		note_label.add_theme_font_size_override("font_size", 14)
		vbox.add_child(note_label)

	var button_row := HBoxContainer.new()
	button_row.alignment = BoxContainer.ALIGNMENT_END
	button_row.add_theme_constant_override("separation", 12)
	vbox.add_child(button_row)

	if show_cancel:
		var cancel_btn := Button.new()
		cancel_btn.text = cancel_text
		cancel_btn.custom_minimum_size = Vector2(130, 44)
		UI_THEME.style_button(cancel_btn, UI_THEME.MUTED, false)
		cancel_btn.alignment = HORIZONTAL_ALIGNMENT_CENTER
		cancel_btn.add_theme_font_size_override("font_size", 15)
		cancel_btn.pressed.connect(_dismiss_modal_dialog)
		button_row.add_child(cancel_btn)

	var confirm_btn := Button.new()
	confirm_btn.text = confirm_text
	confirm_btn.custom_minimum_size = Vector2(160, 44)
	UI_THEME.style_button(confirm_btn, accent_color, true)
	confirm_btn.alignment = HORIZONTAL_ALIGNMENT_CENTER
	confirm_btn.add_theme_font_size_override("font_size", 15)
	confirm_btn.pressed.connect(func() -> void:
		_dismiss_modal_dialog()
		if on_confirm.is_valid():
			on_confirm.call()
	)
	button_row.add_child(confirm_btn)
	confirm_btn.grab_focus()


func _show_message(message: String) -> void:
	_show_custom_confirm_dialog(
		"ÉRTESÍTÉS",
		"",
		message,
		"",
		"Rendben",
		"",
		UI_THEME.GOLD,
		Callable(),
		false
	)
