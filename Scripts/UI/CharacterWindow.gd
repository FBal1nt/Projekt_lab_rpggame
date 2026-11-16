extends Panel

const UI_THEME = preload("res://Scripts/UI/ui_theme.gd")
const CLASS_VISUAL_HELPER = preload("res://Scripts/Utils/ClassVisualHelper.gd")
const CHARACTER_CREATION_OVERLAY_SCENE: PackedScene = preload("res://Scenes/UI/CharacterCreationOverlay.tscn")

const SLOT_ORDER: Array[StringName] = [&"weapon", &"shield", &"armor", &"ring", &"earring"]
const SLOT_LABELS := {
	&"weapon": "Fegyver",
	&"shield": "Pajzs",
	&"armor": "Páncél",
	&"ring": "Gyűrű",
	&"earring": "Fülbevaló"
}

@onready var title_label: Label = $Title
@onready var close_button: Button = $CloseButton

var roster_summary_label: Label
var status_label: Label
var new_character_button: Button
var character_list_vbox: VBoxContainer
var detail_empty_label: Label
var detail_content: VBoxContainer
var preview_stage_panel: PanelContainer
var preview_viewport: SubViewport
var preview_sprite: AnimatedSprite2D
var hero_name_label: Label
var hero_sub_label: Label
var hero_desc_label: Label
var stats_grid: GridContainer
var equipment_label: Label
var skills_label: Label

var _creation_layer: CanvasLayer
var _creation_overlay: CharacterCreationOverlay
var _is_refreshing: bool = false


func _ready() -> void:
	title_label.position = Vector2(24, 18)
	title_label.size = Vector2(852, 42)
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	title_label.text = "MENTETT KARAKTEREK"

	close_button.position = Vector2(710, 558)
	close_button.size = Vector2(160, 42)
	close_button.text = "BEZÁRÁS"

	_build_content()
	_build_bottom_create_button()

	if not GameState.characters_changed.is_connected(refresh):
		GameState.characters_changed.connect(refresh)
	if not GameState.state_changed.is_connected(refresh):
		GameState.state_changed.connect(refresh)
	if not GameState.active_character_changed.is_connected(_on_active_character_changed):
		GameState.active_character_changed.connect(_on_active_character_changed)
	if not visibility_changed.is_connected(_on_visibility_changed):
		visibility_changed.connect(_on_visibility_changed)
	refresh()


func _build_content() -> void:
	var content := VBoxContainer.new()
	content.name = "CharacterRosterContent"
	content.position = Vector2(24, 70)
	content.size = Vector2(852, 474)
	content.add_theme_constant_override("separation", 10)
	add_child(content)

	var top_bar := HBoxContainer.new()
	top_bar.add_theme_constant_override("separation", 12)
	content.add_child(top_bar)

	roster_summary_label = Label.new()
	roster_summary_label.add_theme_color_override("font_color", UI_THEME.GOLD)
	roster_summary_label.add_theme_font_size_override("font_size", 13)
	top_bar.add_child(roster_summary_label)

	status_label = Label.new()
	status_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	status_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	status_label.add_theme_color_override("font_color", UI_THEME.MUTED)
	status_label.add_theme_font_size_override("font_size", 12)
	top_bar.add_child(status_label)

	var split := HBoxContainer.new()
	split.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	split.add_theme_constant_override("separation", 14)
	content.add_child(split)

	# Left pane: Saved characters in current save
	var list_panel := PanelContainer.new()
	list_panel.custom_minimum_size = Vector2(300, 0)
	list_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	list_panel.clip_contents = true
	list_panel.add_theme_stylebox_override(
		"panel",
		UI_THEME.make_box(Color(0.03, 0.055, 0.085, 0.94), Color(0.35, 0.45, 0.56, 0.9), 2, 10)
	)
	split.add_child(list_panel)

	var list_margin := MarginContainer.new()
	list_margin.add_theme_constant_override("margin_left", 10)
	list_margin.add_theme_constant_override("margin_top", 10)
	list_margin.add_theme_constant_override("margin_right", 10)
	list_margin.add_theme_constant_override("margin_bottom", 10)
	list_panel.add_child(list_margin)

	var list_vbox := VBoxContainer.new()
	list_vbox.add_theme_constant_override("separation", 8)
	list_margin.add_child(list_vbox)

	var list_heading := Label.new()
	list_heading.text = "MENTÉS KARAKTEREI"
	list_heading.add_theme_color_override("font_color", UI_THEME.GOLD)
	list_heading.add_theme_font_size_override("font_size", 12)
	list_vbox.add_child(list_heading)

	var list_scroll := ScrollContainer.new()
	list_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	list_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	list_vbox.add_child(list_scroll)

	character_list_vbox = VBoxContainer.new()
	character_list_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	character_list_vbox.add_theme_constant_override("separation", 7)
	list_scroll.add_child(character_list_vbox)

	# Right pane: Selected/Active character inspector
	var detail_panel := PanelContainer.new()
	detail_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	detail_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	detail_panel.clip_contents = true
	detail_panel.add_theme_stylebox_override(
		"panel",
		UI_THEME.make_box(Color(0.035, 0.06, 0.095, 0.95), Color(0.55, 0.45, 0.25, 0.9), 2, 10)
	)
	split.add_child(detail_panel)

	var detail_margin := MarginContainer.new()
	detail_margin.add_theme_constant_override("margin_left", 16)
	detail_margin.add_theme_constant_override("margin_top", 14)
	detail_margin.add_theme_constant_override("margin_right", 16)
	detail_margin.add_theme_constant_override("margin_bottom", 14)
	detail_panel.add_child(detail_margin)

	var detail_stack := Control.new()
	detail_stack.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	detail_stack.size_flags_vertical = Control.SIZE_EXPAND_FILL
	detail_stack.clip_contents = true
	detail_margin.add_child(detail_stack)

	detail_empty_label = Label.new()
	detail_empty_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	detail_empty_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	detail_empty_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	detail_empty_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	detail_empty_label.text = "Ebben a mentésben még nincs karakter.\nKattints lent az 'Új karakter létrehozása' gombra!"
	detail_empty_label.add_theme_color_override("font_color", UI_THEME.MUTED)
	detail_empty_label.add_theme_font_size_override("font_size", 15)
	detail_stack.add_child(detail_empty_label)

	detail_content = VBoxContainer.new()
	detail_content.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	detail_content.add_theme_constant_override("separation", 10)
	detail_content.visible = false
	detail_stack.add_child(detail_content)

	var hero_header := HBoxContainer.new()
	hero_header.add_theme_constant_override("separation", 14)
	detail_content.add_child(hero_header)

	preview_stage_panel = PanelContainer.new()
	preview_stage_panel.custom_minimum_size = Vector2(104, 104)
	preview_stage_panel.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	preview_stage_panel.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	preview_stage_panel.add_theme_stylebox_override("panel", _make_stage_box(UI_THEME.GOLD))
	hero_header.add_child(preview_stage_panel)

	var vp_margin := MarginContainer.new()
	vp_margin.add_theme_constant_override("margin_left", 4)
	vp_margin.add_theme_constant_override("margin_top", 4)
	vp_margin.add_theme_constant_override("margin_right", 4)
	vp_margin.add_theme_constant_override("margin_bottom", 4)
	preview_stage_panel.add_child(vp_margin)

	var vp_container := SubViewportContainer.new()
	vp_container.stretch = true
	vp_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vp_container.focus_mode = Control.FOCUS_NONE
	vp_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vp_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vp_margin.add_child(vp_container)
	vp_container.set_process_input(false)
	vp_container.set_process_unhandled_input(false)
	vp_container.set_process_unhandled_key_input(false)

	preview_viewport = SubViewport.new()
	preview_viewport.transparent_bg = true
	preview_viewport.handle_input_locally = false
	preview_viewport.gui_disable_input = true
	preview_viewport.physics_object_picking = false
	preview_viewport.canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST
	preview_viewport.size = Vector2i(92, 92)
	preview_viewport.size_changed.connect(_center_preview_sprite)
	vp_container.add_child(preview_viewport)

	preview_sprite = AnimatedSprite2D.new()
	preview_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	preview_sprite.scale = Vector2(2.8, 2.8)
	preview_sprite.position = Vector2(46, 46)
	preview_viewport.add_child(preview_sprite)

	var hero_info := VBoxContainer.new()
	hero_info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hero_info.alignment = BoxContainer.ALIGNMENT_CENTER
	hero_info.add_theme_constant_override("separation", 3)
	hero_header.add_child(hero_info)

	hero_name_label = Label.new()
	hero_name_label.add_theme_color_override("font_color", UI_THEME.IVORY)
	hero_name_label.add_theme_font_size_override("font_size", 23)
	hero_info.add_child(hero_name_label)

	hero_sub_label = Label.new()
	hero_sub_label.add_theme_color_override("font_color", UI_THEME.GOLD)
	hero_sub_label.add_theme_font_size_override("font_size", 13)
	hero_info.add_child(hero_sub_label)

	hero_desc_label = Label.new()
	hero_desc_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hero_desc_label.add_theme_color_override("font_color", UI_THEME.MUTED)
	hero_desc_label.add_theme_font_size_override("font_size", 12)
	hero_info.add_child(hero_desc_label)

	var sep1 := HSeparator.new()
	sep1.add_theme_color_override("color", Color(0.32, 0.42, 0.54, 0.7))
	detail_content.add_child(sep1)

	var stats_scroll := ScrollContainer.new()
	stats_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stats_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	stats_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	detail_content.add_child(stats_scroll)

	var stats_vbox := VBoxContainer.new()
	stats_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stats_vbox.add_theme_constant_override("separation", 8)
	stats_scroll.add_child(stats_vbox)

	var stats_heading := Label.new()
	stats_heading.text = "KARAKTER STATISZTIKÁK"
	stats_heading.add_theme_color_override("font_color", UI_THEME.GOLD)
	stats_heading.add_theme_font_size_override("font_size", 12)
	stats_vbox.add_child(stats_heading)

	stats_grid = GridContainer.new()
	stats_grid.columns = 2
	stats_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stats_grid.add_theme_constant_override("h_separation", 20)
	stats_grid.add_theme_constant_override("v_separation", 6)
	stats_vbox.add_child(stats_grid)

	var sep2 := HSeparator.new()
	sep2.add_theme_color_override("color", Color(0.32, 0.42, 0.54, 0.7))
	stats_vbox.add_child(sep2)

	equipment_label = Label.new()
	equipment_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	equipment_label.add_theme_color_override("font_color", Color("cfd8e3"))
	equipment_label.add_theme_font_size_override("font_size", 12)
	stats_vbox.add_child(equipment_label)

	skills_label = Label.new()
	skills_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	skills_label.add_theme_color_override("font_color", UI_THEME.MUTED)
	skills_label.add_theme_font_size_override("font_size", 12)
	stats_vbox.add_child(skills_label)


func _build_bottom_create_button() -> void:
	new_character_button = Button.new()
	new_character_button.name = "CreateNewCharacterButton"
	new_character_button.position = Vector2(24, 558)
	new_character_button.size = Vector2(280, 42)
	new_character_button.text = "ÚJ KARAKTER LÉTREHOZÁSA"
	new_character_button.icon = load("res://Assets/UI/Icons/play_sword.png")
	UI_THEME.style_button(new_character_button, Color(0.45, 0.78, 0.52, 1.0), true)
	new_character_button.alignment = HORIZONTAL_ALIGNMENT_CENTER
	new_character_button.pressed.connect(_open_character_creation_overlay)
	add_child(new_character_button)


func refresh() -> void:
	if character_list_vbox == null or _is_refreshing:
		return
	_is_refreshing = true

	for child in character_list_vbox.get_children():
		child.queue_free()

	var count := GameState.characters.size()
	var active := GameState.get_active_character()
	var active_name := active.character_name if active != null else "Nincs"
	roster_summary_label.text = "%d mentett karakter · Aktív hős: %s" % [count, active_name]

	for character in GameState.characters:
		_add_character_card(character)

	_refresh_active_character_details(active)
	_is_refreshing = false


func _add_character_card(character: CharacterProfile) -> void:
	var class_data := GameState.get_character_class(character.class_id)
	var is_active: bool = character.id == GameState.active_character_id
	var accent: Color = class_data.placeholder_color.lightened(0.2) if class_data != null else UI_THEME.GOLD

	var card := Button.new()
	card.custom_minimum_size = Vector2(0, 58)
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.clip_contents = true
	card.text = ""
	card.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	card.pressed.connect(_on_character_card_pressed.bind(character.id))
	if is_active:
		card.add_theme_stylebox_override("normal", UI_THEME.make_box(Color("1c2d3e"), UI_THEME.GOLD, 3, 8))
		card.add_theme_stylebox_override("hover", UI_THEME.make_box(Color("24394d"), Color("ffe39e"), 3, 8))
		card.add_theme_stylebox_override("pressed", UI_THEME.make_box(Color("142230"), UI_THEME.GOLD, 3, 8))
		card.add_theme_stylebox_override("focus", UI_THEME.make_box(Color(0, 0, 0, 0), accent, 2, 8))
	else:
		card.add_theme_stylebox_override("normal", UI_THEME.make_box(Color("0d1723"), Color("324456"), 1, 8))
		card.add_theme_stylebox_override("hover", UI_THEME.make_box(Color("172738"), accent, 2, 8))
		card.add_theme_stylebox_override("pressed", UI_THEME.make_box(Color("091019"), accent, 2, 8))
		card.add_theme_stylebox_override("focus", UI_THEME.make_box(Color(0, 0, 0, 0), accent, 1, 8))
	character_list_vbox.add_child(card)

	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 8)
	margin.add_theme_constant_override("margin_top", 6)
	margin.add_theme_constant_override("margin_right", 8)
	margin.add_theme_constant_override("margin_bottom", 6)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(margin)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_child(row)

	var thumb_box := UI_THEME.make_box(Color(0.02, 0.03, 0.05, 0.95), accent, 2, 6)
	thumb_box.content_margin_left = 3
	thumb_box.content_margin_right = 3
	thumb_box.content_margin_top = 3
	thumb_box.content_margin_bottom = 3
	thumb_box.shadow_size = 0
	var thumb_frame := PanelContainer.new()
	thumb_frame.custom_minimum_size = Vector2(44, 44)
	thumb_frame.add_theme_stylebox_override("panel", thumb_box)
	thumb_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(thumb_frame)

	var thumb := TextureRect.new()
	thumb.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	thumb.texture = CLASS_VISUAL_HELPER.get_portrait_texture(character.class_id, class_data)
	thumb.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	thumb.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	thumb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	thumb.size_flags_vertical = Control.SIZE_EXPAND_FILL
	thumb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	thumb_frame.add_child(thumb)

	var text_col := VBoxContainer.new()
	text_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text_col.alignment = BoxContainer.ALIGNMENT_CENTER
	text_col.add_theme_constant_override("separation", 2)
	text_col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(text_col)

	var title_row := HBoxContainer.new()
	title_row.add_theme_constant_override("separation", 6)
	title_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	text_col.add_child(title_row)

	var name_lbl := Label.new()
	name_lbl.text = character.character_name
	name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_lbl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	name_lbl.add_theme_color_override("font_color", UI_THEME.GOLD if is_active else UI_THEME.IVORY)
	name_lbl.add_theme_font_size_override("font_size", 15)
	name_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	title_row.add_child(name_lbl)

	if is_active:
		var badge := Label.new()
		badge.text = "AKTÍV"
		badge.add_theme_color_override("font_color", Color("a9d4b6"))
		badge.add_theme_font_size_override("font_size", 11)
		badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
		title_row.add_child(badge)

	var class_name_text := class_data.display_name if class_data != null else String(character.class_id)
	var sub_lbl := Label.new()
	sub_lbl.text = "%s · %d. szint" % [class_name_text, character.level]
	sub_lbl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	sub_lbl.add_theme_color_override("font_color", UI_THEME.MUTED)
	sub_lbl.add_theme_font_size_override("font_size", 11)
	sub_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	text_col.add_child(sub_lbl)


func _refresh_active_character_details(active: CharacterProfile) -> void:
	if active == null:
		detail_empty_label.visible = true
		detail_content.visible = false
		if preview_sprite:
			preview_sprite.stop()
		return

	detail_empty_label.visible = false
	detail_content.visible = true

	var class_data := GameState.get_character_class(active.class_id)
	var accent: Color = class_data.placeholder_color.lightened(0.25) if class_data != null else UI_THEME.GOLD
	preview_stage_panel.add_theme_stylebox_override("panel", _make_stage_box(accent))

	var frames := ClassVisualHelper.get_sprite_frames(active.class_id)
	preview_sprite.sprite_frames = frames
	_center_preview_sprite()
	call_deferred("_center_preview_sprite")
	if frames != null:
		if frames.has_animation(&"idle"):
			preview_sprite.play(&"idle")
		elif frames.has_animation(&"default"):
			preview_sprite.play(&"default")

	var class_title := class_data.display_name if class_data != null else String(active.class_id)
	var role_text := class_data.role if class_data != null else ""
	hero_name_label.text = active.character_name
	hero_sub_label.text = "%s%s · %d. szint · Aktív karakter" % [
		class_title,
		(" (" + role_text + ")") if not role_text.is_empty() else "",
		active.level
	]
	hero_desc_label.text = class_data.description if class_data != null else ""

	for child in stats_grid.get_children():
		child.queue_free()

	var stats := GameState.get_character_stats(active)
	var max_health := int(round(float(stats.get("max_health", 0))))
	var current_health := active.current_health if active.current_health >= 0 else max_health
	var damage_min := int(round(float(stats.get("damage_min", 0))))
	var damage_max := int(round(float(stats.get("damage_max", 0))))
	var defense := int(round(float(stats.get("defense", 0))))

	var stat_items: Array[String] = [
		"Életerő: %d / %d HP" % [current_health, max_health],
		"Stressz: %d" % active.stress,
		"Sebzés: %d–%d" % [damage_min, damage_max],
		"Védelem: %d" % defense,
		"Sebesség: %s" % _format_stat_value(stats.get("speed", 0)),
		"Pontosság: %s%%" % _format_stat_value(stats.get("accuracy", 0)),
		"Kritikus: %s%%" % _format_stat_value(stats.get("crit_chance", 0)),
		"Kitérés: %s%%" % _format_stat_value(stats.get("dodge", 0)),
		"Gyógyerő: %s" % _format_stat_value(stats.get("healing_power", 0)),
		"Stressztűrés: %s%%" % _format_stat_value(stats.get("stress_resistance", 0))
	]
	for item_text in stat_items:
		var lbl := Label.new()
		lbl.text = item_text
		lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		lbl.add_theme_color_override("font_color", UI_THEME.IVORY)
		lbl.add_theme_font_size_override("font_size", 13)
		stats_grid.add_child(lbl)

	var eq_parts: Array[String] = []
	for slot in SLOT_ORDER:
		var slot_title := str(SLOT_LABELS.get(slot, String(slot)))
		var equipped_item := active.equipment.get(slot, null) as InventoryItem
		if equipped_item != null and equipped_item.item_data != null:
			var plus := (" +%d" % equipped_item.upgrade_level) if equipped_item.upgrade_level > 0 else ""
			eq_parts.append("%s: %s%s" % [slot_title, equipped_item.item_data.display_name, plus])
		else:
			eq_parts.append("%s: —" % slot_title)
	equipment_label.text = "Felszerelés: " + " · ".join(eq_parts)

	if class_data != null and not class_data.skill_names.is_empty():
		skills_label.text = "Képességek: " + " · ".join(class_data.skill_names)
	else:
		skills_label.text = "Képességek: Alap támadás"


func _format_stat_value(value: Variant) -> String:
	var number := float(value)
	return str(int(round(number))) if is_equal_approx(number, round(number)) else String.num(number, 1)


func _on_character_card_pressed(character_id: String) -> void:
	if GameState.select_character(character_id):
		var active := GameState.get_active_character()
		if active != null:
			_set_status("Aktív karakter: " + active.character_name, true)
	refresh()


func _open_character_creation_overlay() -> void:
	_ensure_creation_overlay()
	_creation_layer.visible = true
	_creation_overlay.open_for_new_character()


func _ensure_creation_overlay() -> void:
	if _creation_layer != null:
		return
	_creation_layer = CanvasLayer.new()
	_creation_layer.name = "InGameCharacterCreationLayer"
	_creation_layer.layer = 60
	_creation_layer.visible = false
	add_child(_creation_layer)

	_creation_overlay = CHARACTER_CREATION_OVERLAY_SCENE.instantiate() as CharacterCreationOverlay
	_creation_overlay.name = "CharacterCreationOverlay"
	_creation_overlay.character_confirmed.connect(_on_new_character_confirmed)
	_creation_overlay.back_requested.connect(_close_character_creation_overlay)
	_creation_layer.add_child(_creation_overlay)


func _close_character_creation_overlay() -> void:
	if _creation_overlay != null:
		_creation_overlay.close_overlay()
	if _creation_layer != null:
		_creation_layer.visible = false


func _on_new_character_confirmed(character_name: String, class_id: StringName) -> void:
	if GameState.create_character(character_name, class_id):
		_close_character_creation_overlay()
		_set_status("Új karakter létrehozva és aktiválva: " + character_name, true)
		refresh()
	else:
		_close_character_creation_overlay()
		_set_status("Nem sikerült létrehozni a karaktert.", false)


func _on_active_character_changed(_character_id: String) -> void:
	refresh()


func _on_visibility_changed() -> void:
	if not visible:
		_close_character_creation_overlay()
	else:
		call_deferred("_center_preview_sprite")


func _make_stage_box(border_color: Color) -> StyleBoxFlat:
	var box := UI_THEME.make_box(Color(0.02, 0.03, 0.055, 0.98), border_color, 2, 10)
	box.content_margin_left = 2.0
	box.content_margin_right = 2.0
	box.content_margin_top = 2.0
	box.content_margin_bottom = 2.0
	box.shadow_size = 0
	return box


func _center_preview_sprite() -> void:
	if preview_viewport == null or preview_sprite == null:
		return
	var vp_size := Vector2(preview_viewport.size)
	if vp_size.x <= 0.0 or vp_size.y <= 0.0:
		return
	var active := GameState.get_active_character()
	var center_offset := ClassVisualHelper.get_visual_center_offset(active.class_id, &"idle") if active != null else Vector2.ZERO
	preview_sprite.position = vp_size * 0.5 - center_offset * preview_sprite.scale


func _set_status(message: String, success: bool = false) -> void:
	if status_label == null:
		return
	status_label.text = message
	status_label.add_theme_color_override(
		"font_color",
		Color(0.55, 0.95, 0.55) if success else Color(1.0, 0.45, 0.4)
	)
