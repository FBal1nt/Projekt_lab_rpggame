extends Panel

const UI_THEME = preload("res://Scripts/UI/ui_theme.gd")
const CLASS_VISUAL_HELPER = preload("res://Scripts/Utils/ClassVisualHelper.gd")
const DUNGEON_ICON_PATH := "res://Assets/UI/Icons/dungeon.png"
const PLAY_ICON_PATH := "res://Assets/UI/Icons/play_sword.png"

var _title: Label
var _close_button: Button
var _hero_portrait_rect: TextureRect
var _hero_pill_name: Label
var _hero_pill_meta: Label
var _dungeon_list_container: HBoxContainer
var _difficulty_list_container: HBoxContainer
var _dungeon_buttons: Dictionary = {}
var _difficulty_buttons: Dictionary = {}
var _dungeon_description: Label
var _difficulty_summary_label: Label
var _stat_value_labels: Dictionary = {}
var _enemies_flow: HFlowContainer
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
	if _close_button != null:
		_close_button.move_to_front()
	if not GameState.active_character_changed.is_connected(_on_active_character_changed):
		GameState.active_character_changed.connect(_on_active_character_changed)
	if not GameState.state_changed.is_connected(_refresh_hero_pill):
		GameState.state_changed.connect(_refresh_hero_pill)
	if not visibility_changed.is_connected(_on_visibility_changed):
		visibility_changed.connect(_on_visibility_changed)
	refresh()


func _on_active_character_changed(_character_id: String) -> void:
	_refresh_hero_pill()
	if _ui_built:
		_refresh_details()


func _on_visibility_changed() -> void:
	if visible:
		refresh()


func _set_window_layout() -> void:
	anchor_left = 0.055
	anchor_top = 0.05
	anchor_right = 0.945
	anchor_bottom = 0.95
	offset_left = 0.0
	offset_top = 0.0
	offset_right = 0.0
	offset_bottom = 0.0
	custom_minimum_size = Vector2(720, 480)
	clip_contents = true
	UI_THEME.style_window_shell(self, UI_THEME.GOLD)

	_title = get_node_or_null("Title") as Label
	if _title != null:
		_title.visible = false

	_close_button = get_node_or_null("CloseButton") as Button
	if _close_button != null:
		_close_button.anchor_left = 1.0
		_close_button.anchor_top = 0.0
		_close_button.anchor_right = 1.0
		_close_button.anchor_bottom = 0.0
		_close_button.offset_left = -132.0
		_close_button.offset_top = 15.0
		_close_button.offset_right = -18.0
		_close_button.offset_bottom = 51.0
		_close_button.text = "BEZÁRÁS"
		UI_THEME.style_compact_button(_close_button, UI_THEME.GOLD, false, 36.0, 13)
		AudioManager.mark_custom_button_sfx(_close_button)


func _build_ui() -> void:
	if _ui_built:
		return
	_ui_built = true

	var body := MarginContainer.new()
	body.name = "DungeonContent"
	add_child(body)
	body.set_anchors_preset(Control.PRESET_FULL_RECT)
	body.offset_left = 20.0
	body.offset_top = 12.0
	body.offset_right = -20.0
	body.offset_bottom = -16.0
	body.grow_horizontal = Control.GROW_DIRECTION_BOTH
	body.grow_vertical = Control.GROW_DIRECTION_BOTH

	var content := VBoxContainer.new()
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", 10)
	body.add_child(content)

	# --- Unified Header Bar with Active Hero Readiness Pill ---
	var header_row := HBoxContainer.new()
	header_row.custom_minimum_size = Vector2(0, 44)
	header_row.add_theme_constant_override("separation", 12)
	content.add_child(header_row)

	var brand_box := HBoxContainer.new()
	brand_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	brand_box.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	brand_box.add_theme_constant_override("separation", 10)
	header_row.add_child(brand_box)

	if ResourceLoader.exists(DUNGEON_ICON_PATH):
		var icon_frame := PanelContainer.new()
		icon_frame.custom_minimum_size = Vector2(40, 40)
		icon_frame.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		icon_frame.add_theme_stylebox_override(
			"panel",
			UI_THEME.make_card_box(Color(0.05, 0.07, 0.11, 0.96), UI_THEME.GOLD, 1, 9, 5.0, 5.0)
		)
		brand_box.add_child(icon_frame)

		var icon_rect := TextureRect.new()
		icon_rect.texture = load(DUNGEON_ICON_PATH) as Texture2D
		icon_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon_rect.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		icon_rect.size_flags_vertical = Control.SIZE_EXPAND_FILL
		icon_frame.add_child(icon_rect)

	var title_col := VBoxContainer.new()
	title_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_col.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	title_col.add_theme_constant_override("separation", 1)
	brand_box.add_child(title_col)

	var header_title := _make_section_label("DUNGEONVÁLASZTÁS", 22, UI_THEME.GOLD)
	title_col.add_child(header_title)

	var intro := Label.new()
	intro.name = "DungeonIntro"
	intro.text = "Válaszd ki a felfedezni kívánt kazamatát és a kihívás fokozatát."
	intro.add_theme_color_override("font_color", UI_THEME.MUTED)
	intro.add_theme_font_size_override("font_size", 12)
	title_col.add_child(intro)

	# Active Hero Readiness Pill
	var hero_pill := PanelContainer.new()
	hero_pill.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	hero_pill.add_theme_stylebox_override(
		"panel",
		UI_THEME.make_card_box(UI_THEME.SURFACE_CARD, Color(UI_THEME.GOLD.r, UI_THEME.GOLD.g, UI_THEME.GOLD.b, 0.55), 1, 9, 10.0, 4.0)
	)
	header_row.add_child(hero_pill)

	var hero_pill_row := HBoxContainer.new()
	hero_pill_row.add_theme_constant_override("separation", 8)
	hero_pill.add_child(hero_pill_row)

	var portrait_well := PanelContainer.new()
	portrait_well.custom_minimum_size = Vector2(32, 32)
	portrait_well.add_theme_stylebox_override("panel", UI_THEME.make_card_box(Color(0.02, 0.032, 0.056, 0.98), UI_THEME.GOLD, 1, 6, 2.0, 2.0))
	hero_pill_row.add_child(portrait_well)

	_hero_portrait_rect = TextureRect.new()
	_hero_portrait_rect.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_hero_portrait_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_hero_portrait_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_hero_portrait_rect.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_hero_portrait_rect.size_flags_vertical = Control.SIZE_EXPAND_FILL
	portrait_well.add_child(_hero_portrait_rect)

	var hero_pill_col := VBoxContainer.new()
	hero_pill_col.alignment = BoxContainer.ALIGNMENT_CENTER
	hero_pill_col.add_theme_constant_override("separation", 0)
	hero_pill_row.add_child(hero_pill_col)

	_hero_pill_name = Label.new()
	_hero_pill_name.text = "Aktív hős"
	_hero_pill_name.add_theme_color_override("font_color", UI_THEME.IVORY)
	_hero_pill_name.add_theme_font_size_override("font_size", 13)
	hero_pill_col.add_child(_hero_pill_name)

	_hero_pill_meta = Label.new()
	_hero_pill_meta.text = "HP: —"
	_hero_pill_meta.add_theme_color_override("font_color", UI_THEME.MUTED)
	_hero_pill_meta.add_theme_font_size_override("font_size", 11)
	hero_pill_col.add_child(_hero_pill_meta)

	var close_spacer := Control.new()
	close_spacer.custom_minimum_size = Vector2(124, 36)
	header_row.add_child(close_spacer)

	var header_sep := ColorRect.new()
	header_sep.custom_minimum_size = Vector2(0, 1)
	header_sep.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header_sep.color = Color(UI_THEME.GOLD.r, UI_THEME.GOLD.g, UI_THEME.GOLD.b, 0.36)
	content.add_child(header_sep)

	# 1. DUNGEON LISTA
	content.add_child(_make_section_label("DUNGEONOK", 12, UI_THEME.GOLD))
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
		UI_THEME.make_card_box(UI_THEME.SURFACE_CARD, Color(UI_THEME.GOLD.r, UI_THEME.GOLD.g, UI_THEME.GOLD.b, 0.40), 1, 10, 14.0, 9.0)
	)
	content.add_child(desc_panel)

	_dungeon_description = _make_body_label("Válassz egy dungeont a leírás megjelenítéséhez.", 13)
	_dungeon_description.add_theme_color_override("font_color", UI_THEME.IVORY)
	_dungeon_description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc_panel.add_child(_dungeon_description)

	# 2. NEHÉZSÉGI FOKOZAT
	content.add_child(_make_section_label("NEHÉZSÉGI FOKOZAT", 12, UI_THEME.GOLD))
	_difficulty_list_container = HBoxContainer.new()
	_difficulty_list_container.name = "DifficultyList"
	_difficulty_list_container.add_theme_constant_override("separation", 10)
	_difficulty_list_container.custom_minimum_size.y = 42
	content.add_child(_difficulty_list_container)

	# 3. NEHÉZSÉG RÉSZLETEI
	content.add_child(_make_section_label("A KIVÁLASZTOTT NEHÉZSÉG RÉSZLETEI", 12, UI_THEME.GOLD))
	var details_panel := PanelContainer.new()
	details_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	details_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	details_panel.add_theme_stylebox_override(
		"panel",
		UI_THEME.make_card_box(UI_THEME.SURFACE_DARK, Color(UI_THEME.GOLD.r, UI_THEME.GOLD.g, UI_THEME.GOLD.b, 0.42), 1, 12, 14.0, 12.0)
	)
	content.add_child(details_panel)

	var detail_scroll := ScrollContainer.new()
	detail_scroll.name = "DifficultyDetailsScroll"
	detail_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	detail_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	detail_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	details_panel.add_child(detail_scroll)

	var detail_vbox := VBoxContainer.new()
	detail_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	detail_vbox.add_theme_constant_override("separation", 12)
	detail_scroll.add_child(detail_vbox)

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

	stats_grid.add_child(_make_stat_card("spawn", "SPAWN GYAKORISÁG", UI_THEME.GOLD))
	stats_grid.add_child(_make_stat_card("encounters", "TALÁLKOZÁSOK", Color("7fb8e8")))
	stats_grid.add_child(_make_stat_card("level", "ELLENSÉGSZINT", UI_THEME.CRIMSON))
	stats_grid.add_child(_make_stat_card("elite", "ELIT ESÉLY", UI_THEME.ARCANE_VIOLET))

	var enemies_heading := _make_section_label("LEHETSÉGES ELLENFELEK", 11, UI_THEME.MUTED)
	detail_vbox.add_child(enemies_heading)

	_enemies_flow = HFlowContainer.new()
	_enemies_flow.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_enemies_flow.add_theme_constant_override("h_separation", 7)
	_enemies_flow.add_theme_constant_override("v_separation", 6)
	detail_vbox.add_child(_enemies_flow)

	# 4. LÁBLÉC
	var footer_panel := PanelContainer.new()
	footer_panel.add_theme_stylebox_override(
		"panel",
		UI_THEME.make_card_box(Color(0.025, 0.040, 0.068, 0.96), UI_THEME.BORDER_SUBTLE, 1, 10, 12.0, 8.0)
	)
	content.add_child(footer_panel)

	var footer := HBoxContainer.new()
	footer.name = "DungeonFooter"
	footer.add_theme_constant_override("separation", 12)
	footer_panel.add_child(footer)

	_status_label = _make_body_label("Válassz dungeont és nehézséget.", 13)
	_status_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_status_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	footer.add_child(_status_label)

	_start_button = Button.new()
	_start_button.name = "StartDungeonButton"
	_start_button.text = "KALAND ELŐKÉSZÍTÉSE"
	if ResourceLoader.exists(PLAY_ICON_PATH):
		_start_button.icon = load(PLAY_ICON_PATH) as Texture2D
	_start_button.custom_minimum_size = Vector2(246, 46)
	_start_button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	UI_THEME.style_compact_button(_start_button, UI_THEME.GOLD, true, 46.0, 15)
	_start_button.pressed.connect(_on_start_pressed)
	footer.add_child(_start_button)


func _make_stat_card(key: String, title_text: String, value_color: Color) -> PanelContainer:
	var card := PanelContainer.new()
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.add_theme_stylebox_override(
		"panel",
		UI_THEME.make_card_box(UI_THEME.SURFACE_CARD, Color(value_color.r, value_color.g, value_color.b, 0.42), 1, 9, 10.0, 8.0)
	)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 3)
	card.add_child(vbox)

	var caption := Label.new()
	caption.text = title_text
	caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	caption.add_theme_color_override("font_color", UI_THEME.MUTED)
	caption.add_theme_font_size_override("font_size", 10)
	vbox.add_child(caption)

	var val_label := Label.new()
	val_label.text = "—"
	val_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	val_label.add_theme_color_override("font_color", value_color)
	val_label.add_theme_font_size_override("font_size", 17)
	vbox.add_child(val_label)
	_stat_value_labels[key] = val_label

	return card


func _refresh_hero_pill() -> void:
	if _hero_pill_name == null or _hero_pill_meta == null:
		return
	var active := GameState.get_active_character()
	if active == null:
		_hero_portrait_rect.texture = null
		_hero_pill_name.text = "Nincs aktív hős"
		_hero_pill_meta.text = "Válassz a Karakter menüben"
		return
	var class_data := GameState.get_character_class(active.class_id)
	_hero_portrait_rect.texture = CLASS_VISUAL_HELPER.get_portrait_texture(active.class_id, class_data)
	var stats := GameState.get_character_stats(active)
	var max_hp := int(round(float(stats.get("max_health", active.current_health))))
	var cur_hp := active.current_health if active.current_health >= 0 else max_hp
	var class_name_str := class_data.display_name if class_data != null else String(active.class_id)
	_hero_pill_name.text = active.character_name
	_hero_pill_meta.text = "%s · %d. sz. · HP %d/%d" % [class_name_str, active.level, cur_hp, max_hp]


# -----------------------------------------------------------------------------
# Data-driven dungeon and difficulty selection
# -----------------------------------------------------------------------------

func refresh() -> void:
	if not _ui_built or _dungeon_list_container == null or _difficulty_list_container == null:
		return
	_refresh_hero_pill()

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
		_clear_enemies_flow()
		_start_button.disabled = true
		return

	_selected_dungeon_id = matched_dungeon_id
	_update_dungeon_button_styles()
	_load_selected_dungeon(preferred_difficulty)


func _create_dungeon_card_button(dungeon: DungeonDefinition) -> Button:
	var btn := Button.new()
	btn.name = "DungeonBtn_%s" % String(dungeon.id)
	btn.custom_minimum_size = Vector2(260, 60)
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
		var accent := UI_THEME.GOLD if is_selected else Color(0.35, 0.44, 0.56, 0.85)
		UI_THEME.style_button(btn, accent, is_selected, 60.0)
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		btn.focus_mode = Control.FOCUS_NONE
		btn.add_theme_font_size_override("font_size", 14)
		btn.custom_minimum_size = Vector2(260, 60)


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
		_clear_enemies_flow()
		_start_button.disabled = true
		return

	_dungeon_description.text = dungeon.description
	_populate_difficulties(preferred_difficulty)


func _clear_difficulty_buttons() -> void:
	for child in _difficulty_list_container.get_children():
		_difficulty_list_container.remove_child(child)
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
		btn.custom_minimum_size = Vector2(140, 42)
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
		_clear_enemies_flow()
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
		return UI_THEME.EMERALD
	if "hard" in key:
		return UI_THEME.CRIMSON
	return UI_THEME.GOLD


func _update_difficulty_button_styles() -> void:
	for diff_id in _difficulty_buttons.keys():
		var btn: Button = _difficulty_buttons[diff_id] as Button
		if btn == null or not is_instance_valid(btn):
			continue
		var is_selected: bool = (diff_id == _selected_difficulty_id)
		var accent := _difficulty_accent_color(diff_id) if is_selected else Color(0.32, 0.40, 0.52, 0.85)
		UI_THEME.style_compact_button(btn, accent, is_selected, 42.0, 14)
		btn.custom_minimum_size = Vector2(140, 42)


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

func _clear_enemies_flow() -> void:
	if _enemies_flow == null:
		return
	for child in _enemies_flow.get_children():
		child.queue_free()


func _refresh_details() -> void:
	var difficulty := DungeonManager.get_difficulty(_selected_dungeon_id, _selected_difficulty_id)
	var dungeon := DungeonManager.get_dungeon(_selected_dungeon_id)
	_clear_enemies_flow()
	if difficulty == null or dungeon == null:
		_difficulty_summary_label.text = "Válassz egy elérhető nehézségi szintet."
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
		var scaled_levels: Vector2i = DungeonManager.get_scaled_enemy_level_range(difficulty)
		lvl_lbl.text = "%d–%d" % [scaled_levels.x, scaled_levels.y]
	var elite_lbl: Label = _stat_value_labels.get("elite", null) as Label
	if elite_lbl:
		elite_lbl.text = "%d%%" % roundi(difficulty.elite_spawn_chance * 100.0)

	if display_names.is_empty():
		var empty_lbl := _make_body_label("Nincs megadva ellenféllista.", 13)
		_enemies_flow.add_child(empty_lbl)
	else:
		var chip_accent := _difficulty_accent_color(_selected_difficulty_id)
		for enemy_name in display_names:
			var chip := PanelContainer.new()
			chip.add_theme_stylebox_override(
				"panel",
				UI_THEME.make_badge_box(Color(0.055, 0.075, 0.115, 0.96), Color(chip_accent.r, chip_accent.g, chip_accent.b, 0.50), 7)
			)
			var lbl := Label.new()
			lbl.text = enemy_name
			lbl.add_theme_color_override("font_color", UI_THEME.IVORY)
			lbl.add_theme_font_size_override("font_size", 12)
			chip.add_child(lbl)
			_enemies_flow.add_child(chip)


func _on_start_pressed() -> void:
	if _selected_dungeon_id == &"" or _selected_difficulty_id == &"":
		return
	var result: Dictionary = DungeonManager.start_dungeon(_selected_dungeon_id, _selected_difficulty_id)
	AudioManager.sfx(&"portal_enter" if bool(result.get("ok", false)) else &"ui_error")
	_status_label.text = str(result.get("message", "A művelet befejeződött."))
	_status_label.add_theme_color_override(
		"font_color",
		UI_THEME.GOLD if bool(result.get("ok", false)) else UI_THEME.CRIMSON
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
