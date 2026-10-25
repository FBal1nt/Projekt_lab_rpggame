extends Panel

const UI_THEME = preload("res://Scripts/UI/ui_theme.gd")

@onready var title_label: Label = $Title
@onready var close_button: Button = $CloseButton

var character_selector: OptionButton
var character_details: Label
var character_name_input: LineEdit
var class_selector: OptionButton
var status_label: Label
var create_button: Button

var portrait_panel: Panel
var portrait_texture: TextureRect
var portrait_fallback: Label
var class_heading: Label
var role_label: Label
var description_label: Label
var stats_heading: Label
var stats_grid: GridContainer
var skills_label: Label
var selected_class_id: StringName = &"warrior"
var _is_refreshing: bool = false


# -----------------------------------------------------------------------------
# UI construction
# -----------------------------------------------------------------------------

func _ready() -> void:
	title_label.position = Vector2(24, 18)
	title_label.size = Vector2(852, 42)
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	title_label.text = "KARAKTEREK ÉS OSZTÁLYOK"

	close_button.position = Vector2(710, 558)
	close_button.size = Vector2(160, 42)
	close_button.text = "BEZÁRÁS"

	_build_content()
	if not GameState.characters_changed.is_connected(refresh):
		GameState.characters_changed.connect(refresh)
	if not GameState.state_changed.is_connected(refresh):
		GameState.state_changed.connect(refresh)
	if not GameState.active_character_changed.is_connected(_on_active_character_changed):
		GameState.active_character_changed.connect(_on_active_character_changed)
	refresh()


func _build_content() -> void:
	var content := VBoxContainer.new()
	content.name = "CharacterManagerContent"
	content.position = Vector2(24, 72)
	content.size = Vector2(852, 472)
	content.add_theme_constant_override("separation", 6)
	add_child(content)

	# Active character row.
	var active_row := HBoxContainer.new()
	active_row.name = "ActiveCharacterRow"
	active_row.custom_minimum_size = Vector2(0, 34)
	active_row.add_theme_constant_override("separation", 10)
	content.add_child(active_row)

	var select_label := Label.new()
	select_label.text = "AKTÍV KARAKTER"
	select_label.custom_minimum_size = Vector2(145, 0)
	select_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	select_label.add_theme_color_override("font_color", UI_THEME.GOLD)
	select_label.add_theme_font_size_override("font_size", 13)
	active_row.add_child(select_label)

	character_selector = OptionButton.new()
	character_selector.custom_minimum_size = Vector2(235, 34)
	character_selector.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	character_selector.add_theme_font_size_override("font_size", 14)
	active_row.add_child(character_selector)
	character_selector.item_selected.connect(_on_character_selected)

	character_details = Label.new()
	character_details.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	character_details.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	character_details.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	character_details.add_theme_color_override("font_color", UI_THEME.IVORY)
	character_details.add_theme_font_size_override("font_size", 12)
	active_row.add_child(character_details)

	content.add_child(HSeparator.new())

	# Class preview: portrait on the left, role/stats/skills on the right.
	var preview_row := HBoxContainer.new()
	preview_row.name = "ClassPreviewRow"
	preview_row.custom_minimum_size = Vector2(0, 218)
	preview_row.add_theme_constant_override("separation", 16)
	content.add_child(preview_row)

	portrait_panel = Panel.new()
	portrait_panel.name = "ClassPortraitPanel"
	portrait_panel.custom_minimum_size = Vector2(174, 210)
	UI_THEME.style_panel(portrait_panel, UI_THEME.GOLD, UI_THEME.INK)
	preview_row.add_child(portrait_panel)

	portrait_texture = TextureRect.new()
	portrait_texture.name = "ClassPortrait"
	portrait_texture.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	portrait_texture.offset_left = 10
	portrait_texture.offset_top = 10
	portrait_texture.offset_right = -10
	portrait_texture.offset_bottom = -10
	portrait_texture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	portrait_texture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	portrait_texture.mouse_filter = Control.MOUSE_FILTER_IGNORE
	portrait_panel.add_child(portrait_texture)

	portrait_fallback = Label.new()
	portrait_fallback.name = "PortraitFallback"
	portrait_fallback.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	portrait_fallback.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	portrait_fallback.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	portrait_fallback.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	portrait_fallback.mouse_filter = Control.MOUSE_FILTER_IGNORE
	portrait_fallback.add_theme_color_override("font_color", UI_THEME.IVORY)
	portrait_fallback.add_theme_font_size_override("font_size", 15)
	portrait_panel.add_child(portrait_fallback)

	var details := VBoxContainer.new()
	details.name = "ClassDetails"
	details.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	details.add_theme_constant_override("separation", 4)
	preview_row.add_child(details)

	class_heading = Label.new()
	class_heading.add_theme_color_override("font_color", UI_THEME.GOLD)
	class_heading.add_theme_font_size_override("font_size", 23)
	details.add_child(class_heading)

	role_label = Label.new()
	role_label.add_theme_color_override("font_color", UI_THEME.MUTED)
	role_label.add_theme_font_size_override("font_size", 13)
	details.add_child(role_label)

	description_label = Label.new()
	description_label.custom_minimum_size = Vector2(0, 42)
	description_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	description_label.add_theme_color_override("font_color", UI_THEME.IVORY)
	description_label.add_theme_font_size_override("font_size", 13)
	details.add_child(description_label)

	stats_heading = Label.new()
	stats_heading.text = "ALAPSTATISZTIKÁK · 1. SZINT"
	stats_heading.add_theme_color_override("font_color", UI_THEME.GOLD)
	stats_heading.add_theme_font_size_override("font_size", 12)
	details.add_child(stats_heading)

	stats_grid = GridContainer.new()
	stats_grid.name = "ClassStatsGrid"
	stats_grid.columns = 3
	stats_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stats_grid.add_theme_constant_override("h_separation", 14)
	stats_grid.add_theme_constant_override("v_separation", 2)
	details.add_child(stats_grid)

	skills_label = Label.new()
	skills_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	skills_label.add_theme_color_override("font_color", UI_THEME.MUTED)
	skills_label.add_theme_font_size_override("font_size", 12)
	details.add_child(skills_label)

	content.add_child(HSeparator.new())

	var create_heading := Label.new()
	create_heading.text = "ÚJ KARAKTER LÉTREHOZÁSA"
	create_heading.add_theme_color_override("font_color", UI_THEME.GOLD)
	create_heading.add_theme_font_size_override("font_size", 13)
	content.add_child(create_heading)

	var create_row := HBoxContainer.new()
	create_row.name = "CreateCharacterRow"
	create_row.custom_minimum_size = Vector2(0, 38)
	create_row.add_theme_constant_override("separation", 8)
	content.add_child(create_row)

	character_name_input = LineEdit.new()
	character_name_input.placeholder_text = "Karakter neve"
	character_name_input.custom_minimum_size = Vector2(235, 38)
	character_name_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	character_name_input.max_length = 28
	create_row.add_child(character_name_input)

	class_selector = OptionButton.new()
	class_selector.custom_minimum_size = Vector2(220, 38)
	class_selector.add_theme_font_size_override("font_size", 14)
	create_row.add_child(class_selector)
	class_selector.item_selected.connect(_on_class_selected)
	_populate_class_selector()

	create_button = Button.new()
	create_button.text = "KARAKTER LÉTREHOZÁSA"
	create_button.custom_minimum_size = Vector2(255, 38)
	create_button.size_flags_horizontal = Control.SIZE_SHRINK_END
	UI_THEME.style_button(create_button, Color(0.45, 0.75, 0.52, 1.0), true)
	create_button.add_theme_font_size_override("font_size", 13)
	create_row.add_child(create_button)
	create_button.pressed.connect(_on_create_character_pressed)
	character_name_input.text_submitted.connect(_on_name_submitted)

	status_label = Label.new()
	status_label.text = "16 osztálydefiníció betöltve · A portrék és harci sprite-ok később kapcsolhatók hozzá."
	status_label.custom_minimum_size = Vector2(0, 28)
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status_label.add_theme_color_override("font_color", UI_THEME.MUTED)
	status_label.add_theme_font_size_override("font_size", 11)
	content.add_child(status_label)


# -----------------------------------------------------------------------------
# Character/class selection and preview
# -----------------------------------------------------------------------------

func _populate_class_selector() -> void:
	class_selector.clear()
	var all_classes := GameState.get_character_classes()
	for index in range(all_classes.size()):
		var class_data: CharacterClassData = all_classes[index]
		class_selector.add_item(class_data.display_name)
		class_selector.set_item_metadata(index, String(class_data.id))

	if all_classes.is_empty():
		_set_status("Nem található karakterosztály a Data/CharacterClasses mappában.", false)
		return

	var active := GameState.get_active_character()
	var default_id: StringName = active.class_id if active != null else &"warrior"
	var selected_index := 0
	for index in range(class_selector.item_count):
		if StringName(str(class_selector.get_item_metadata(index))) == default_id:
			selected_index = index
			break
	class_selector.select(selected_index)
	selected_class_id = StringName(str(class_selector.get_item_metadata(selected_index)))
	_update_class_preview()


func refresh() -> void:
	if character_selector == null or _is_refreshing:
		return
	_is_refreshing = true
	character_selector.clear()
	var selected_index := 0
	var active := GameState.get_active_character()

	for index in range(GameState.characters.size()):
		var character: CharacterProfile = GameState.characters[index]
		character_selector.add_item(character.character_name)
		character_selector.set_item_metadata(index, character.id)
		if character.id == GameState.active_character_id:
			selected_index = index

	if GameState.characters.is_empty():
		character_details.text = "Még nincs karakter. Hozz létre egyet lent."
	else:
		character_selector.select(selected_index)
		if active != null:
			var active_class := GameState.get_character_class(active.class_id)
			var stats := GameState.get_character_stats(active)
			var max_health := int(stats.get("max_health", 0))
			var class_name_text := active_class.display_name if active_class != null else String(active.class_id)
			character_details.text = "%s · %d. szint · ÉP %d/%d · Stressz %d" % [
				class_name_text,
				active.level,
				active.current_health if active.current_health >= 0 else max_health,
				max_health,
				active.stress
			]
	_is_refreshing = false


func _update_class_preview() -> void:
	if class_selector == null or class_selector.item_count == 0:
		return
	var index := class_selector.selected
	if index < 0 or index >= class_selector.item_count:
		return

	selected_class_id = StringName(str(class_selector.get_item_metadata(index)))
	var class_data := GameState.get_character_class(selected_class_id)
	if class_data == null:
		return

	class_heading.text = class_data.display_name
	role_label.text = class_data.role
	description_label.text = class_data.description
	portrait_panel.add_theme_stylebox_override(
		"panel",
		UI_THEME.make_box(UI_THEME.INK, class_data.placeholder_color, 2, 12)
	)
	portrait_texture.texture = class_data.portrait
	portrait_texture.visible = class_data.portrait != null
	portrait_fallback.visible = class_data.portrait == null
	portrait_fallback.text = "%s\n\nPORTRÉ\nHOZZÁADÁSA" % class_data.display_name.substr(0, 1).to_upper()
	portrait_fallback.add_theme_color_override("font_color", class_data.placeholder_color.lightened(0.75))

	for child in stats_grid.get_children():
		stats_grid.remove_child(child)
		child.queue_free()

	var stats := class_data.get_stats_at_level(1)
	var stat_lines: Array[String] = [
		"Életerő: %d" % int(stats.get("max_health", 0)),
		"Sebzés: %d–%d" % [int(stats.get("damage_min", 0)), int(stats.get("damage_max", 0))],
		"Védelem: %d" % int(stats.get("defense", 0)),
		"Sebesség: %d" % int(stats.get("speed", 0)),
		"Pontosság: %d%%" % int(stats.get("accuracy", 0)),
		"Kritikus: %d%%" % int(stats.get("crit_chance", 0.0)),
		"Kitérés: %d%%" % int(stats.get("dodge", 0)),
		"Gyógyítás: %d" % int(stats.get("healing_power", 0)),
		"Stressztűrés: %d%%" % int(stats.get("stress_resistance", 0))
	]
	for stat_text in stat_lines:
		var stat_label := Label.new()
		stat_label.text = stat_text
		stat_label.custom_minimum_size = Vector2(132, 21)
		stat_label.add_theme_color_override("font_color", UI_THEME.IVORY)
		stat_label.add_theme_font_size_override("font_size", 12)
		stats_grid.add_child(stat_label)

	if class_data.skill_names.is_empty():
		skills_label.text = "Képességek: később definiálhatók."
	else:
		skills_label.text = "Kezdő képességek: " + " · ".join(class_data.skill_names)


# -----------------------------------------------------------------------------
# User actions and feedback
# -----------------------------------------------------------------------------

func _on_character_selected(index: int) -> void:
	if _is_refreshing or index < 0 or index >= character_selector.item_count:
		return
	var selected_id := str(character_selector.get_item_metadata(index))
	if GameState.select_character(selected_id):
		var active := GameState.get_active_character()
		if active != null:
			_set_status("Aktív karakter: " + active.character_name, true)
	refresh()


func _on_class_selected(_index: int) -> void:
	_update_class_preview()


func _on_create_character_pressed() -> void:
	var clean_name := character_name_input.text.strip_edges()
	if clean_name.is_empty():
		_set_status("Adj nevet az új karakternek.", false)
		return

	for character in GameState.characters:
		if character.character_name.strip_edges().to_lower() == clean_name.to_lower():
			_set_status("Már létezik karakter ezzel a névvel.", false)
			return

	if GameState.create_character(clean_name, selected_class_id):
		character_name_input.clear()
		_set_status("Karakter létrehozva és aktiválva: " + clean_name, true)
		refresh()
	else:
		_set_status("Nem sikerült létrehozni a karaktert. Ellenőrizd az osztályt és a nevet.", false)


func _on_name_submitted(_text: String) -> void:
	_on_create_character_pressed()


func _on_active_character_changed(_character_id: String) -> void:
	refresh()


func _set_status(message: String, success: bool = false) -> void:
	if status_label == null:
		return
	status_label.text = message
	status_label.add_theme_color_override(
		"font_color",
		Color(0.55, 0.95, 0.55) if success else Color(1.0, 0.45, 0.4)
	)
