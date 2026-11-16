extends Panel

const UI_THEME = preload("res://Scripts/UI/ui_theme.gd")

var _title: Label
var _close_button: Button
var _dungeon_list_container: HBoxContainer
var _difficulty_list_container: HBoxContainer
var _dungeon_buttons: Dictionary = {}
var _difficulty_buttons: Dictionary = {}
var _dungeon_description: Label
var _difficulty_summary_label: Label
var _stat_value_labels: Dictionary = {}
var _enemies_roster_label: Label
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
	anchor_left = 0.08
	anchor_top = 0.065
	anchor_right = 0.92
	anchor_bottom = 0.935
	offset_left = 0.0
	offset_top = 0.0
	offset_right = 0.0
	offset_bottom = 0.0
	custom_minimum_size = Vector2(720, 480)
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
		_close_button.alignment = HORIZONTAL_ALIGNMENT_CENTER
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
	content.offset_top = 68.0
	content.offset_right = -24.0
	content.offset_bottom = -16.0
	content.add_theme_constant_override("separation", 10)
	add_child(content)

	var intro := Label.new()
	intro.name = "DungeonIntro"
	intro.text = "Válaszd ki a felfedezni kívánt helyszínt és a kihívás szintjét."
	intro.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	intro.add_theme_color_override("font_color", UI_THEME.MUTED)
	intro.add_theme_font_size_override("font_size", 13)
	content.add_child(intro)

	# 1. DUNGEON LISTA (kártyás választó legördülő helyett)
	content.add_child(_make_section_label("DUNGEONOK", 13, UI_THEME.GOLD))
	var dungeon_scroll := ScrollContainer.new()
	dungeon_scroll.name = "DungeonListScroll"
	dungeon_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	dungeon_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	dungeon_scroll.custom_minimum_size.y = 66
	dungeon_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_child(dungeon_scroll)

	_dungeon_list_container = HBoxContainer.new()
	_dungeon_list_container.name = "DungeonList"
	_dungeon_list_container.add_theme_constant_override("separation", 10)
	_dungeon_list_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	dungeon_scroll.add_child(_dungeon_list_container)

	# Kiválasztott dungeon leíró kártyája
	var desc_panel := PanelContainer.new()
	desc_panel.add_theme_stylebox_override(
		"panel",
		UI_THEME.make_box(Color(0.028, 0.045, 0.072, 0.94), Color(0.45, 0.37, 0.22, 0.65), 1, 10)
	)
	content.add_child(desc_panel)

	var desc_margin := MarginContainer.new()
	desc_margin.add_theme_constant_override("margin_left", 14)
	desc_margin.add_theme_constant_override("margin_right", 14)
	desc_margin.add_theme_constant_override("margin_top", 8)
	desc_margin.add_theme_constant_override("margin_bottom", 8)
	desc_panel.add_child(desc_margin)

	_dungeon_description = _make_body_label("Válassz egy dungeont a leírás megjelenítéséhez.", 14)
	_dungeon_description.add_theme_color_override("font_color", UI_THEME.IVORY)
	_dungeon_description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc_margin.add_child(_dungeon_description)

	# 2. NEHÉZSÉGI FOKOZAT (színes kártya-gombok legördülő helyett)
	content.add_child(_make_section_label("NEHÉZSÉGI FOKOZAT", 13, UI_THEME.GOLD))
	_difficulty_list_container = HBoxContainer.new()
	_difficulty_list_container.name = "DifficultyList"
	_difficulty_list_container.add_theme_constant_override("separation", 10)
	_difficulty_list_container.custom_minimum_size.y = 46
	content.add_child(_difficulty_list_container)

	# 3. NEHÉZSÉG RÉSZLETEI (strukturált stat kártyák + ellenféllista)
	content.add_child(_make_section_label("A KIVÁLASZTOTT NEHÉZSÉG RÉSZLETEI", 13, UI_THEME.GOLD))
	var details_panel := PanelContainer.new()
	details_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	details_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	details_panel.add_theme_stylebox_override(
		"panel",
		UI_THEME.make_box(Color(0.025, 0.04, 0.068, 0.96), Color(0.55, 0.44, 0.25, 0.65), 1, 10)
	)
	content.add_child(details_panel)

	var detail_scroll := ScrollContainer.new()
	detail_scroll.name = "DifficultyDetailsScroll"
	detail_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	detail_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	detail_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	details_panel.add_child(detail_scroll)

	var detail_margin := MarginContainer.new()
	detail_margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	detail_margin.add_theme_constant_override("margin_left", 14)
	detail_margin.add_theme_constant_override("margin_right", 14)
	detail_margin.add_theme_constant_override("margin_top", 10)
	detail_margin.add_theme_constant_override("margin_bottom", 12)
	detail_scroll.add_child(detail_margin)

	var detail_vbox := VBoxContainer.new()
	detail_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	detail_vbox.add_theme_constant_override("separation", 10)
	detail_margin.add_child(detail_vbox)

	_difficulty_summary_label = _make_body_label("Válassz nehézségi fokozatot.", 14)
	_difficulty_summary_label.add_theme_color_override("font_color", UI_THEME.IVORY)
	_difficulty_summary_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	detail_vbox.add_child(_difficulty_summary_label)

	var stats_grid := GridContainer.new()
	stats_grid.columns = 4
	stats_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stats_grid.add_theme_constant_override("h_separation", 8)
	stats_grid.add_theme_constant_override("v_separation", 8)
	detail_vbox.add_child(stats_grid)

	stats_grid.add_child(_make_stat_card("spawn", "SPAWN GYAKORISÁG", Color("d6a34e")))
	stats_grid.add_child(_make_stat_card("encounters", "TALÁLKOZÁSOK", Color("7fb8e8")))
	stats_grid.add_child(_make_stat_card("level", "ELLENSÉGSZINT", Color("e88e7f")))
	stats_grid.add_child(_make_stat_card("elite", "ELIT ESÉLY", Color("c996f0")))

	_enemies_roster_label = _make_body_label("Lehetséges ellenfelek: —", 14)
	_enemies_roster_label.add_theme_color_override("font_color", Color("dce4ee"))
	_enemies_roster_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	detail_vbox.add_child(_enemies_roster_label)

	# 4. LÁBLÉC
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
	_start_button.alignment = HORIZONTAL_ALIGNMENT_CENTER
	_start_button.add_theme_font_size_override("font_size", 15)
	_start_button.pressed.connect(_on_start_pressed)
	footer.add_child(_start_button)


func _make_stat_card(key: String, title_text: String, value_color: Color) -> PanelContainer:
	var card := PanelContainer.new()
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.add_theme_stylebox_override(
		"panel",
		UI_THEME.make_box(Color(0.04, 0.06, 0.095, 0.95), Color(0.28, 0.34, 0.44, 0.7), 1, 8)
	)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 10)
	margin.add_theme_constant_override("margin_right", 10)
	margin.add_theme_constant_override("margin_top", 6)
	margin.add_theme_constant_override("margin_bottom", 6)
	card.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 2)
	margin.add_child(vbox)

	var caption := Label.new()
	caption.text = title_text
	caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	caption.add_theme_color_override("font_color", UI_THEME.MUTED)
	caption.add_theme_font_size_override("font_size", 11)
	vbox.add_child(caption)

	var val_label := Label.new()
	val_label.text = "—"
	val_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	val_label.add_theme_color_override("font_color", value_color)
	val_label.add_theme_font_size_override("font_size", 16)
	vbox.add_child(val_label)
	_stat_value_labels[key] = val_label

	return card


# -----------------------------------------------------------------------------
# Data-driven dungeon and difficulty selection
# -----------------------------------------------------------------------------

func refresh() -> void:
	if not _ui_built or _dungeon_list_container == null or _difficulty_list_container == null:
		return

	var preferred_dungeon := StringName(str(GameState.run_state.get("dungeon_id", "forgotten_crypt")))
	var preferred_difficulty := StringName(str(GameState.run_state.get("difficulty_id", "normal")))
	if _selected_dungeon_id != &"":
		preferred_dungeon = _selected_dungeon_id
	if _selected_difficulty_id != &"":
		preferred_difficulty = _selected_difficulty_id

	for child in _dungeon_list_container.get_children():
		child.queue_free()
	_dungeon_buttons.clear()

	var available_dungeons := DungeonManager.get_available_dungeons()
	var matched_dungeon_id: StringName = &""
	for dungeon in available_dungeons:
		var btn := _create_dungeon_card_button(dungeon)
		_dungeon_list_container.add_child(btn)
		_dungeon_buttons[dungeon.id] = btn
		if dungeon.id == preferred_dungeon:
			matched_dungeon_id = dungeon.id

	if matched_dungeon_id == &"" and not available_dungeons.is_empty():
		matched_dungeon_id = available_dungeons[0].id

	if matched_dungeon_id == &"":
		_selected_dungeon_id = &""
		_selected_difficulty_id = &""
		_dungeon_description.text = "Nem található dungeon-definíció. Ellenőrizd a Data/Dungeons mappát."
		_clear_difficulty_buttons()
		_difficulty_summary_label.text = "Nem érhető el nehézségi beállítás."
		_enemies_roster_label.text = ""
		_start_button.disabled = true
		return

	_selected_dungeon_id = matched_dungeon_id
	_update_dungeon_button_styles()
	_load_selected_dungeon(preferred_difficulty)


func _create_dungeon_card_button(dungeon: DungeonDefinition) -> Button:
	var btn := Button.new()
	btn.name = "DungeonBtn_%s" % String(dungeon.id)
	btn.custom_minimum_size = Vector2(260, 62)
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn.text = "%s\nAjánlott csapatszint: %d–%d" % [
		dungeon.display_name,
		dungeon.recommended_level_min,
		dungeon.recommended_level_max
	]
	btn.pressed.connect(_on_dungeon_card_pressed.bind(dungeon.id))
	return btn


func _update_dungeon_button_styles() -> void:
	for dungeon_id in _dungeon_buttons.keys():
		var btn: Button = _dungeon_buttons[dungeon_id] as Button
		if btn == null or not is_instance_valid(btn):
			continue
		var is_selected: bool = (dungeon_id == _selected_dungeon_id)
		var accent := UI_THEME.GOLD if is_selected else Color(0.35, 0.42, 0.54, 0.85)
		UI_THEME.style_button(btn, accent, is_selected)
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		btn.add_theme_font_size_override("font_size", 15)
		btn.custom_minimum_size = Vector2(260, 62)


func _on_dungeon_card_pressed(dungeon_id: StringName) -> void:
	if _selected_dungeon_id == dungeon_id:
		return
	_selected_dungeon_id = dungeon_id
	_update_dungeon_button_styles()
	_load_selected_dungeon(&"normal")
	_update_status_line()


func _load_selected_dungeon(preferred_difficulty: StringName) -> void:
	var dungeon := DungeonManager.get_dungeon(_selected_dungeon_id)
	if dungeon == null:
		_dungeon_description.text = "A kiválasztott dungeon definíciója nem tölthető be."
		_clear_difficulty_buttons()
		_difficulty_summary_label.text = "Nincs elérhető nehézségi konfiguráció."
		_enemies_roster_label.text = ""
		_start_button.disabled = true
		return

	_dungeon_description.text = dungeon.description
	_populate_difficulties(preferred_difficulty)


func _clear_difficulty_buttons() -> void:
	for child in _difficulty_list_container.get_children():
		child.queue_free()
	_difficulty_buttons.clear()


func _populate_difficulties(preferred_difficulty: StringName) -> void:
	_clear_difficulty_buttons()
	var available := DungeonManager.get_available_difficulties(_selected_dungeon_id)
	var matched_id: StringName = &""

	for difficulty in available:
		var btn := Button.new()
		btn.name = "DifficultyBtn_%s" % String(difficulty.id)
		btn.text = difficulty.display_name
		btn.custom_minimum_size = Vector2(140, 44)
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.pressed.connect(_on_difficulty_button_pressed.bind(difficulty.id))
		_difficulty_list_container.add_child(btn)
		_difficulty_buttons[difficulty.id] = btn
		if difficulty.id == preferred_difficulty:
			matched_id = difficulty.id

	if matched_id == &"":
		for difficulty in available:
			if String(difficulty.id) == "normal":
				matched_id = difficulty.id
				break
	if matched_id == &"" and not available.is_empty():
		matched_id = available[0].id

	if matched_id == &"":
		_selected_difficulty_id = &""
		_difficulty_summary_label.text = "Ehhez a dungeonhoz még nincs nehézségi szint konfigurálva. Adj hozzá adatfájlt a Data/DungeonDifficulties mappában."
		_enemies_roster_label.text = ""
		_start_button.disabled = true
		return

	_selected_difficulty_id = matched_id
	_update_difficulty_button_styles()
	_refresh_details()
	_update_start_button()
	_update_status_line()


func _difficulty_accent_color(diff_id: StringName) -> Color:
	var key := String(diff_id).to_lower()
	if "easy" in key:
		return Color("59b878")
	if "hard" in key:
		return Color("d95a4c")
	return Color("d6a34e")


func _update_difficulty_button_styles() -> void:
	for diff_id in _difficulty_buttons.keys():
		var btn: Button = _difficulty_buttons[diff_id] as Button
		if btn == null or not is_instance_valid(btn):
			continue
		var is_selected: bool = (diff_id == _selected_difficulty_id)
		var accent := _difficulty_accent_color(diff_id) if is_selected else Color(0.32, 0.38, 0.48, 0.85)
		UI_THEME.style_button(btn, accent, is_selected)
		btn.alignment = HORIZONTAL_ALIGNMENT_CENTER
		btn.add_theme_font_size_override("font_size", 15)
		btn.custom_minimum_size = Vector2(140, 44)


func _on_difficulty_button_pressed(difficulty_id: StringName) -> void:
	if _selected_difficulty_id == difficulty_id:
		return
	_selected_difficulty_id = difficulty_id
	_update_difficulty_button_styles()
	_refresh_details()
	_update_start_button()
	_update_status_line()


func _update_status_line() -> void:
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
		_difficulty_summary_label.text = "Válassz egy elérhető nehézségi szintet."
		_enemies_roster_label.text = ""
		return

	var display_names := PackedStringArray()
	for i in range(difficulty.enemy_type_ids.size()):
		if i < difficulty.enemy_type_names.size() and not difficulty.enemy_type_names[i].strip_edges().is_empty():
			display_names.append(difficulty.enemy_type_names[i])
		else:
			display_names.append(String(difficulty.enemy_type_ids[i]).replace("_", " ").capitalize())

	var combined_spawn_rate: float = dungeon.base_spawn_rate_multiplier * difficulty.spawn_rate_multiplier
	_difficulty_summary_label.text = difficulty.description

	var spawn_lbl: Label = _stat_value_labels.get("spawn", null) as Label
	if spawn_lbl:
		spawn_lbl.text = "×%.2f" % combined_spawn_rate
	var enc_lbl: Label = _stat_value_labels.get("encounters", null) as Label
	if enc_lbl:
		enc_lbl.text = "×%.2f" % difficulty.encounter_count_multiplier
	var lvl_lbl: Label = _stat_value_labels.get("level", null) as Label
	if lvl_lbl:
		lvl_lbl.text = "%d–%d" % [difficulty.enemy_level_min, maxi(difficulty.enemy_level_min, difficulty.enemy_level_max)]
	var elite_lbl: Label = _stat_value_labels.get("elite", null) as Label
	if elite_lbl:
		elite_lbl.text = "%d%%" % roundi(difficulty.elite_spawn_chance * 100.0)

	_enemies_roster_label.text = "Lehetséges ellenfelek: %s" % (
		", ".join(display_names) if not display_names.is_empty() else "Nincs megadva"
	)


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
