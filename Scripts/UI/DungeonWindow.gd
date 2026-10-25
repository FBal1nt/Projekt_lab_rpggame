extends Panel

const UI_THEME = preload("res://Scripts/UI/ui_theme.gd")

var _title: Label
var _close_button: Button
var _dungeon_option: OptionButton
var _difficulty_option: OptionButton
var _dungeon_description: Label
var _dungeon_meta: Label
var _difficulty_details: Label
var _status_label: Label
var _start_button: Button
var _selected_dungeon_id: StringName = &""
var _selected_difficulty_id: StringName = &"normal"
var _ui_built: bool = false


# -----------------------------------------------------------------------------
# Window layout and control creation
# -----------------------------------------------------------------------------

func _ready() -> void:
	_set_window_layout()
	_build_ui()
	refresh()


func _set_window_layout() -> void:
	# Keep the complete dialog inside the viewport on typical 720p and larger screens.
	anchor_left = 0.08
	anchor_top = 0.075
	anchor_right = 0.92
	anchor_bottom = 0.925
	offset_left = 0.0
	offset_top = 0.0
	offset_right = 0.0
	offset_bottom = 0.0
	custom_minimum_size = Vector2(680, 440)
	clip_contents = true

	_title = get_node_or_null("Title") as Label
	if _title != null:
		_title.anchor_left = 0.0
		_title.anchor_top = 0.0
		_title.anchor_right = 1.0
		_title.anchor_bottom = 0.0
		_title.offset_left = 24.0
		_title.offset_top = 14.0
		_title.offset_right = -210.0
		_title.offset_bottom = 58.0
		_title.text = "DUNGEONVÁLASZTÁS"
		_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		_title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		_title.add_theme_font_size_override("font_size", 26)

	_close_button = get_node_or_null("CloseButton") as Button
	if _close_button != null:
		_close_button.anchor_left = 1.0
		_close_button.anchor_top = 0.0
		_close_button.anchor_right = 1.0
		_close_button.anchor_bottom = 0.0
		_close_button.offset_left = -154.0
		_close_button.offset_top = 14.0
		_close_button.offset_right = -20.0
		_close_button.offset_bottom = 56.0
		_close_button.text = "BEZÁRÁS"
		_close_button.custom_minimum_size = Vector2(134, 42)
		UI_THEME.style_button(_close_button, Color("c28f4a"), false)
		_close_button.add_theme_font_size_override("font_size", 15)


func _build_ui() -> void:
	if _ui_built:
		return
	_ui_built = true

	var content := VBoxContainer.new()
	content.name = "DungeonContent"
	content.anchor_left = 0.0
	content.anchor_top = 0.0
	content.anchor_right = 1.0
	content.anchor_bottom = 1.0
	content.offset_left = 24.0
	content.offset_top = 72.0
	content.offset_right = -24.0
	content.offset_bottom = -18.0
	content.add_theme_constant_override("separation", 7)
	add_child(content)

	var intro := Label.new()
	intro.name = "DungeonIntro"
	intro.text = "Válaszd ki a felfedezni kívánt helyszínt és a kihívás szintjét. A részletek a választás alapján frissülnek."
	intro.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	intro.custom_minimum_size.y = 28
	intro.add_theme_color_override("font_color", UI_THEME.MUTED)
	intro.add_theme_font_size_override("font_size", 14)
	content.add_child(intro)

	_dungeon_option = _create_option_button("DungeonOption", "Válassz dungeont…")
	_dungeon_option.item_selected.connect(_on_dungeon_option_selected)
	content.add_child(_make_selection_row("DUNGEON", _dungeon_option))

	_difficulty_option = _create_option_button("DifficultyOption", "Válassz nehézséget…")
	_difficulty_option.item_selected.connect(_on_difficulty_option_selected)
	content.add_child(_make_selection_row("NEHÉZSÉG", _difficulty_option))

	content.add_child(HSeparator.new())

	_dungeon_meta = _make_body_label("Ajánlott csapatszint: —", 14)
	_dungeon_meta.add_theme_color_override("font_color", UI_THEME.GOLD)
	content.add_child(_dungeon_meta)

	_dungeon_description = _make_body_label("Válassz egy dungeont a leírás megjelenítéséhez.", 15)
	_dungeon_description.custom_minimum_size.y = 42
	_dungeon_description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content.add_child(_dungeon_description)

	content.add_child(_make_section_label("A KIVÁLASZTOTT NEHÉZSÉG RÉSZLETEI", 14, UI_THEME.GOLD))
	var detail_scroll := ScrollContainer.new()
	detail_scroll.name = "DifficultyDetailsScroll"
	detail_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	detail_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	detail_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	detail_scroll.custom_minimum_size.y = 80
	content.add_child(detail_scroll)

	_difficulty_details = _make_body_label("Válassz nehézségi fokozatot a spawnráták, az ellenfélszintek és az ellenféltípusok megtekintéséhez.", 15)
	_difficulty_details.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_difficulty_details.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	detail_scroll.add_child(_difficulty_details)

	var footer := HBoxContainer.new()
	footer.name = "DungeonFooter"
	footer.add_theme_constant_override("separation", 12)
	footer.custom_minimum_size.y = 50
	content.add_child(footer)

	_status_label = _make_body_label("Válassz dungeont és nehézséget.", 13)
	_status_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_status_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	footer.add_child(_status_label)

	_start_button = Button.new()
	_start_button.name = "StartDungeonButton"
	_start_button.text = "KALAND ELŐKÉSZÍTÉSE"
	_start_button.custom_minimum_size = Vector2(246, 50)
	_start_button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	UI_THEME.style_button(_start_button, Color("d6a34e"), true)
	_start_button.add_theme_font_size_override("font_size", 15)
	_start_button.pressed.connect(_on_start_pressed)
	footer.add_child(_start_button)


func _create_option_button(node_name: String, placeholder_text: String) -> OptionButton:
	var option := OptionButton.new()
	option.name = node_name
	option.custom_minimum_size = Vector2(0, 44)
	option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	option.fit_to_longest_item = false
	option.clip_text = true
	UI_THEME.style_button(option, Color("c28f4a"), false)
	option.add_theme_font_size_override("font_size", 16)
	option.text = placeholder_text
	return option


func _make_selection_row(label_text: String, option: OptionButton) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.name = label_text.to_pascal_case() + "Row"
	row.add_theme_constant_override("separation", 14)
	row.custom_minimum_size.y = 44
	var label := _make_section_label(label_text, 14, UI_THEME.GOLD)
	label.custom_minimum_size.x = 112
	label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(label)
	row.add_child(option)
	return row


# -----------------------------------------------------------------------------
# Data-driven dungeon and difficulty selection
# -----------------------------------------------------------------------------

func refresh() -> void:
	if not _ui_built or _dungeon_option == null or _difficulty_option == null:
		return

	var preferred_dungeon := StringName(str(GameState.run_state.get("dungeon_id", "forgotten_crypt")))
	var preferred_difficulty := StringName(str(GameState.run_state.get("difficulty_id", "normal")))
	if _selected_dungeon_id != &"":
		preferred_dungeon = _selected_dungeon_id
		if _selected_difficulty_id != &"":
			preferred_difficulty = _selected_difficulty_id
	if _selected_difficulty_id != &"":
		preferred_difficulty = _selected_difficulty_id

	_dungeon_option.clear()
	var available_dungeons := DungeonManager.get_available_dungeons()
	var selected_index := -1
	for i in range(available_dungeons.size()):
		var dungeon := available_dungeons[i]
		_dungeon_option.add_item(dungeon.display_name)
		_dungeon_option.set_item_metadata(i, String(dungeon.id))
		if dungeon.id == preferred_dungeon:
			selected_index = i

	if selected_index < 0 and not available_dungeons.is_empty():
		selected_index = 0

	if selected_index < 0:
		_selected_dungeon_id = &""
		_selected_difficulty_id = &""
		_dungeon_description.text = "Nem található dungeon-definíció. Ellenőrizd a Data/Dungeons mappát."
		_dungeon_meta.text = "Ajánlott csapatszint: —"
		_difficulty_option.clear()
		_difficulty_details.text = "Nem érhető el nehézségi beállítás."
		_start_button.disabled = true
		return

	_dungeon_option.select(selected_index)
	_load_selected_dungeon(preferred_difficulty)


func _on_dungeon_option_selected(index: int) -> void:
	if index < 0 or index >= _dungeon_option.item_count:
		return
	_selected_dungeon_id = StringName(str(_dungeon_option.get_item_metadata(index)))
	_load_selected_dungeon(&"normal")
	_status_label.text = "Dungeon kiválasztva. Válassz nehézségi fokozatot."
	_status_label.add_theme_color_override("font_color", UI_THEME.MUTED)


func _load_selected_dungeon(preferred_difficulty: StringName) -> void:
	if _dungeon_option.selected < 0 or _dungeon_option.selected >= _dungeon_option.item_count:
		return
	_selected_dungeon_id = StringName(str(_dungeon_option.get_item_metadata(_dungeon_option.selected)))
	var dungeon := DungeonManager.get_dungeon(_selected_dungeon_id)
	if dungeon == null:
		_dungeon_description.text = "A kiválasztott dungeon definíciója nem tölthető be."
		_dungeon_meta.text = "Ajánlott csapatszint: —"
		_difficulty_option.clear()
		_difficulty_details.text = "Nincs elérhető nehézségi konfiguráció."
		_start_button.disabled = true
		return

	_dungeon_description.text = dungeon.description
	_dungeon_meta.text = "Ajánlott csapatszint: %d–%d" % [dungeon.recommended_level_min, dungeon.recommended_level_max]
	_populate_difficulties(preferred_difficulty)


func _populate_difficulties(preferred_difficulty: StringName) -> void:
	_difficulty_option.clear()
	var available := DungeonManager.get_available_difficulties(_selected_dungeon_id)
	var selected_index := -1
	for i in range(available.size()):
		var difficulty := available[i]
		_difficulty_option.add_item(difficulty.display_name)
		_difficulty_option.set_item_metadata(i, String(difficulty.id))
		if difficulty.id == preferred_difficulty:
			selected_index = i

	if selected_index < 0:
		for i in range(available.size()):
			if String(available[i].id) == "normal":
				selected_index = i
				break
	if selected_index < 0 and not available.is_empty():
		selected_index = 0

	if selected_index < 0:
		_selected_difficulty_id = &""
		_difficulty_details.text = "Ehhez a dungeonhoz még nincs nehézségi szint konfigurálva. Adj hozzá adatfájlt a Data/DungeonDifficulties mappában."
		_start_button.disabled = true
		return

	_difficulty_option.select(selected_index)
	_selected_difficulty_id = StringName(str(_difficulty_option.get_item_metadata(selected_index)))
	_refresh_details()
	_update_start_button()


func _on_difficulty_option_selected(index: int) -> void:
	if index < 0 or index >= _difficulty_option.item_count:
		return
	_selected_difficulty_id = StringName(str(_difficulty_option.get_item_metadata(index)))
	_refresh_details()
	_update_start_button()
	var dungeon := DungeonManager.get_dungeon(_selected_dungeon_id)
	var difficulty := DungeonManager.get_difficulty(_selected_dungeon_id, _selected_difficulty_id)
	if dungeon != null and difficulty != null:
		_status_label.text = "Kiválasztva: %s — %s" % [dungeon.display_name, difficulty.display_name]
		_status_label.add_theme_color_override("font_color", UI_THEME.MUTED)


# -----------------------------------------------------------------------------
# Details panel and launch feedback
# -----------------------------------------------------------------------------

func _refresh_details() -> void:
	var difficulty := DungeonManager.get_difficulty(_selected_dungeon_id, _selected_difficulty_id)
	var dungeon := DungeonManager.get_dungeon(_selected_dungeon_id)
	if difficulty == null or dungeon == null:
		_difficulty_details.text = "Válassz egy elérhető nehézségi szintet."
		return

	var display_names := PackedStringArray()
	for i in range(difficulty.enemy_type_ids.size()):
		if i < difficulty.enemy_type_names.size() and not difficulty.enemy_type_names[i].strip_edges().is_empty():
			display_names.append(difficulty.enemy_type_names[i])
		else:
			display_names.append(String(difficulty.enemy_type_ids[i]).replace("_", " ").capitalize())

	var combined_spawn_rate: float = dungeon.base_spawn_rate_multiplier * difficulty.spawn_rate_multiplier
	_difficulty_details.text = "%s\n\nSpawn gyakoriság: ×%.2f\nTalálkozások mennyisége: ×%.2f\nEllenségszint: %d–%d\nElit megjelenési esély: %d%%\nLehetséges ellenfelek: %s" % [
		difficulty.description,
		combined_spawn_rate,
		difficulty.encounter_count_multiplier,
		difficulty.enemy_level_min,
		maxi(difficulty.enemy_level_min, difficulty.enemy_level_max),
		roundi(difficulty.elite_spawn_chance * 100.0),
		", ".join(display_names) if not display_names.is_empty() else "Nincs megadva"
	]
	_difficulty_details.add_theme_color_override("font_color", UI_THEME.IVORY)


func _on_start_pressed() -> void:
	if _selected_dungeon_id == &"" or _selected_difficulty_id == &"":
		return
	var result: Dictionary = DungeonManager.start_dungeon(_selected_dungeon_id, _selected_difficulty_id)
	_status_label.text = str(result.get("message", "A művelet befejeződött."))
	_status_label.add_theme_color_override(
		"font_color",
		UI_THEME.GOLD if bool(result.get("ok", false)) else Color("e38d82")
	)


func _update_start_button() -> void:
	if _start_button == null:
		return
	var dungeon := DungeonManager.get_dungeon(_selected_dungeon_id)
	_start_button.disabled = dungeon == null or _selected_difficulty_id == &""
	if dungeon != null and not dungeon.scene_path.is_empty() and ResourceLoader.exists(dungeon.scene_path):
		_start_button.text = "DUNGEON INDÍTÁSA"
	else:
		_start_button.text = "KALAND ELŐKÉSZÍTÉSE"


func _make_section_label(text_value: String, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text_value
	label.add_theme_color_override("font_color", color)
	label.add_theme_font_size_override("font_size", font_size)
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	return label


func _make_body_label(text_value: String, font_size: int) -> Label:
	var label := Label.new()
	label.text = text_value
	label.add_theme_color_override("font_color", UI_THEME.MUTED)
	label.add_theme_font_size_override("font_size", font_size)
	label.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	return label
