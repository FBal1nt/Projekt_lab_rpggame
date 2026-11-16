extends Control
class_name ClassSelectionMenu

const UI_THEME = preload("res://Scripts/UI/ui_theme.gd")

signal class_selected(class_id: StringName)

@export var require_explicit_selection: bool = true

var selected_class_id: StringName = &""
var _classes: Array[CharacterClassData] = []
var _class_buttons: Dictionary = {}
var _current_anim: StringName = &"idle"
var _anim_buttons: Dictionary = {}
var _anim_loop_timer: Timer

var _prompt_placeholder: Control
var _inspector_content: Control
var _details_scroll: ScrollContainer
var _preview_stage_panel: PanelContainer
var _preview_viewport: SubViewport
var _preview_sprite: AnimatedSprite2D
var _anim_buttons_row: HFlowContainer
var _class_title_label: Label
var _class_role_label: Label
var _tags_row: HFlowContainer
var _class_desc_label: Label
var _stat_bars_grid: GridContainer
var _secondary_stats_grid: GridContainer
var _skills_row: HFlowContainer
var _special_note_label: Label
var _class_list_vbox: VBoxContainer

const ANIM_OPTIONS := [
	{"id": &"idle", "label": "Állás"},
	{"id": &"walk", "label": "Séta"},
	{"id": &"attack_1", "label": "Támadás"},
	{"id": &"block", "label": "Védekezés"},
	{"id": &"heal", "label": "Gyógyítás"}
]


func _ready() -> void:
	_build_ui()
	reload_classes(not require_explicit_selection)


func _build_ui() -> void:
	_anim_loop_timer = Timer.new()
	_anim_loop_timer.one_shot = true
	_anim_loop_timer.wait_time = 0.35
	_anim_loop_timer.timeout.connect(_on_anim_replay_timeout)
	add_child(_anim_loop_timer)

	var split := HBoxContainer.new()
	split.name = "ClassSplit"
	split.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	split.add_theme_constant_override("separation", 14)
	add_child(split)

	# Left pane: scrollable class card selector
	var left_panel := PanelContainer.new()
	left_panel.name = "ClassListPanel"
	left_panel.custom_minimum_size = Vector2(292, 0)
	left_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left_panel.clip_contents = true
	left_panel.add_theme_stylebox_override(
		"panel",
		UI_THEME.make_box(Color(0.03, 0.055, 0.085, 0.94), Color(0.35, 0.45, 0.56, 0.9), 2, 10)
	)
	split.add_child(left_panel)

	var left_margin := MarginContainer.new()
	left_margin.add_theme_constant_override("margin_left", 10)
	left_margin.add_theme_constant_override("margin_top", 10)
	left_margin.add_theme_constant_override("margin_right", 10)
	left_margin.add_theme_constant_override("margin_bottom", 10)
	left_panel.add_child(left_margin)

	var left_vbox := VBoxContainer.new()
	left_vbox.add_theme_constant_override("separation", 8)
	left_margin.add_child(left_vbox)

	var list_heading := Label.new()
	list_heading.text = "VÁLASZTHATÓ OSZTÁLYOK"
	list_heading.add_theme_color_override("font_color", UI_THEME.GOLD)
	list_heading.add_theme_font_size_override("font_size", 13)
	left_vbox.add_child(list_heading)

	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left_vbox.add_child(scroll)

	_class_list_vbox = VBoxContainer.new()
	_class_list_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_class_list_vbox.add_theme_constant_override("separation", 7)
	scroll.add_child(_class_list_vbox)

	# Right pane: detailed visual & stat inspector
	var right_panel := PanelContainer.new()
	right_panel.name = "ClassInspectorPanel"
	right_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right_panel.clip_contents = true
	right_panel.add_theme_stylebox_override(
		"panel",
		UI_THEME.make_box(Color(0.035, 0.06, 0.095, 0.95), Color(0.55, 0.45, 0.25, 0.9), 2, 10)
	)
	split.add_child(right_panel)

	var right_margin := MarginContainer.new()
	right_margin.add_theme_constant_override("margin_left", 16)
	right_margin.add_theme_constant_override("margin_top", 12)
	right_margin.add_theme_constant_override("margin_right", 14)
	right_margin.add_theme_constant_override("margin_bottom", 12)
	right_panel.add_child(right_margin)

	var right_stack := Control.new()
	right_stack.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right_stack.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right_stack.clip_contents = true
	right_margin.add_child(right_stack)

	_build_empty_prompt(right_stack)
	_build_inspector_content(right_stack)


func _build_empty_prompt(parent: Control) -> void:
	_prompt_placeholder = CenterContainer.new()
	_prompt_placeholder.name = "PromptPlaceholder"
	_prompt_placeholder.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	parent.add_child(_prompt_placeholder)

	var vbox := VBoxContainer.new()
	vbox.custom_minimum_size = Vector2(460, 0)
	vbox.add_theme_constant_override("separation", 10)
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	_prompt_placeholder.add_child(vbox)

	var emblem := TextureRect.new()
	emblem.custom_minimum_size = Vector2(56, 56)
	emblem.texture = load("res://Assets/UI/Icons/character.png")
	emblem.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	emblem.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	emblem.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	vbox.add_child(emblem)

	var title := Label.new()
	title.text = "VÁLASSZ EGY KARAKTEROSZTÁLYT"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_color_override("font_color", UI_THEME.GOLD)
	title.add_theme_font_size_override("font_size", 22)
	vbox.add_child(title)

	var hint := Label.new()
	hint.text = "Kattints a bal oldali listából bármelyik hősosztályra, hogy megtekintsd a megjelenését, az élő animációit, a leírását, a képességeit és a harci értékeit."
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.add_theme_color_override("font_color", UI_THEME.MUTED)
	hint.add_theme_font_size_override("font_size", 14)
	vbox.add_child(hint)


func _build_inspector_content(parent: Control) -> void:
	_inspector_content = VBoxContainer.new()
	_inspector_content.name = "InspectorContent"
	_inspector_content.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_inspector_content.add_theme_constant_override("separation", 10)
	_inspector_content.visible = false
	parent.add_child(_inspector_content)

	# Fixed top visual & identity section (never clipped or broken by scrolling)
	var top_row := HBoxContainer.new()
	top_row.add_theme_constant_override("separation", 16)
	_inspector_content.add_child(top_row)

	var preview_col := VBoxContainer.new()
	preview_col.custom_minimum_size = Vector2(216, 0)
	preview_col.add_theme_constant_override("separation", 8)
	top_row.add_child(preview_col)

	_preview_stage_panel = PanelContainer.new()
	_preview_stage_panel.custom_minimum_size = Vector2(216, 136)
	_preview_stage_panel.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_preview_stage_panel.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	_preview_stage_panel.add_theme_stylebox_override("panel", _make_stage_box(UI_THEME.GOLD))
	preview_col.add_child(_preview_stage_panel)

	var stage_margin := MarginContainer.new()
	stage_margin.add_theme_constant_override("margin_left", 4)
	stage_margin.add_theme_constant_override("margin_top", 4)
	stage_margin.add_theme_constant_override("margin_right", 4)
	stage_margin.add_theme_constant_override("margin_bottom", 4)
	_preview_stage_panel.add_child(stage_margin)

	var vp_container := SubViewportContainer.new()
	vp_container.stretch = true
	vp_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vp_container.focus_mode = Control.FOCUS_NONE
	vp_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vp_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	stage_margin.add_child(vp_container)
	vp_container.set_process_input(false)
	vp_container.set_process_unhandled_input(false)
	vp_container.set_process_unhandled_key_input(false)

	_preview_viewport = SubViewport.new()
	_preview_viewport.transparent_bg = true
	_preview_viewport.handle_input_locally = false
	_preview_viewport.gui_disable_input = true
	_preview_viewport.physics_object_picking = false
	_preview_viewport.canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST
	_preview_viewport.size = Vector2i(208, 128)
	_preview_viewport.size_changed.connect(_center_preview_sprite)
	vp_container.add_child(_preview_viewport)

	_preview_sprite = AnimatedSprite2D.new()
	_preview_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_preview_sprite.scale = Vector2(3.6, 3.6)
	_preview_sprite.position = Vector2(104, 64)
	_preview_sprite.animation_finished.connect(_on_preview_animation_finished)
	_preview_viewport.add_child(_preview_sprite)

	_anim_buttons_row = HFlowContainer.new()
	_anim_buttons_row.alignment = FlowContainer.ALIGNMENT_CENTER
	_anim_buttons_row.add_theme_constant_override("h_separation", 6)
	_anim_buttons_row.add_theme_constant_override("v_separation", 6)
	preview_col.add_child(_anim_buttons_row)

	for opt in ANIM_OPTIONS:
		var anim_id: StringName = opt["id"]
		var btn := Button.new()
		btn.text = str(opt["label"])
		btn.custom_minimum_size = Vector2(0, 28)
		btn.add_theme_font_size_override("font_size", 11)
		btn.focus_mode = Control.FOCUS_NONE
		btn.pressed.connect(_select_preview_animation.bind(anim_id))
		_anim_buttons_row.add_child(btn)
		_anim_buttons[anim_id] = btn

	var identity_col := VBoxContainer.new()
	identity_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	identity_col.add_theme_constant_override("separation", 5)
	top_row.add_child(identity_col)

	_class_title_label = Label.new()
	_class_title_label.add_theme_color_override("font_color", UI_THEME.IVORY)
	_class_title_label.add_theme_font_size_override("font_size", 24)
	identity_col.add_child(_class_title_label)

	_class_role_label = Label.new()
	_class_role_label.add_theme_color_override("font_color", UI_THEME.GOLD)
	_class_role_label.add_theme_font_size_override("font_size", 13)
	identity_col.add_child(_class_role_label)

	_tags_row = HFlowContainer.new()
	_tags_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_tags_row.add_theme_constant_override("h_separation", 6)
	_tags_row.add_theme_constant_override("v_separation", 4)
	identity_col.add_child(_tags_row)

	_class_desc_label = Label.new()
	_class_desc_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_class_desc_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_class_desc_label.add_theme_color_override("font_color", UI_THEME.IVORY)
	_class_desc_label.add_theme_font_size_override("font_size", 13)
	identity_col.add_child(_class_desc_label)

	var sep1 := HSeparator.new()
	sep1.add_theme_color_override("color", Color(0.32, 0.42, 0.54, 0.7))
	_inspector_content.add_child(sep1)

	# Scrollable lower details (stats, skills & special mechanics)
	_details_scroll = ScrollContainer.new()
	_details_scroll.name = "DetailsScroll"
	_details_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_details_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_details_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_details_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	_inspector_content.add_child(_details_scroll)

	var details_margin := MarginContainer.new()
	details_margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	details_margin.add_theme_constant_override("margin_right", 8)
	details_margin.add_theme_constant_override("margin_bottom", 4)
	_details_scroll.add_child(details_margin)

	var details_vbox := VBoxContainer.new()
	details_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	details_vbox.add_theme_constant_override("separation", 8)
	details_margin.add_child(details_vbox)

	var stats_heading := Label.new()
	stats_heading.text = "HARCI ÉRTÉKEK · 1. SZINT"
	stats_heading.add_theme_color_override("font_color", UI_THEME.GOLD)
	stats_heading.add_theme_font_size_override("font_size", 12)
	details_vbox.add_child(stats_heading)

	_stat_bars_grid = GridContainer.new()
	_stat_bars_grid.columns = 2
	_stat_bars_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_stat_bars_grid.add_theme_constant_override("h_separation", 18)
	_stat_bars_grid.add_theme_constant_override("v_separation", 6)
	details_vbox.add_child(_stat_bars_grid)

	_secondary_stats_grid = GridContainer.new()
	_secondary_stats_grid.columns = 2
	_secondary_stats_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_secondary_stats_grid.add_theme_constant_override("h_separation", 18)
	_secondary_stats_grid.add_theme_constant_override("v_separation", 4)
	details_vbox.add_child(_secondary_stats_grid)

	var sep2 := HSeparator.new()
	sep2.add_theme_color_override("color", Color(0.32, 0.42, 0.54, 0.7))
	details_vbox.add_child(sep2)

	var skills_heading := Label.new()
	skills_heading.text = "KÉPESSÉGEK ÉS KÜLÖNLEGESSÉG"
	skills_heading.add_theme_color_override("font_color", UI_THEME.GOLD)
	skills_heading.add_theme_font_size_override("font_size", 12)
	details_vbox.add_child(skills_heading)

	_skills_row = HFlowContainer.new()
	_skills_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_skills_row.add_theme_constant_override("h_separation", 8)
	_skills_row.add_theme_constant_override("v_separation", 6)
	details_vbox.add_child(_skills_row)

	_special_note_label = Label.new()
	_special_note_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_special_note_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_special_note_label.add_theme_color_override("font_color", Color("d8e2ec"))
	_special_note_label.add_theme_font_size_override("font_size", 12)
	details_vbox.add_child(_special_note_label)


func reload_classes(auto_select_first: bool = false) -> void:
	_classes = GameState.get_character_classes()
	_rebuild_class_list()
	if auto_select_first and not _classes.is_empty():
		select_class(_classes[0].id)
	else:
		clear_selection()


func clear_selection() -> void:
	selected_class_id = &""
	_anim_loop_timer.stop()
	if _preview_sprite:
		_preview_sprite.stop()
	_update_card_selection_styles()
	if _prompt_placeholder:
		_prompt_placeholder.visible = true
	if _inspector_content:
		_inspector_content.visible = false
	if _details_scroll:
		_details_scroll.scroll_vertical = 0


func get_selected_class_id() -> StringName:
	return selected_class_id


func _rebuild_class_list() -> void:
	for child in _class_list_vbox.get_children():
		child.queue_free()
	_class_buttons.clear()

	for class_data in _classes:
		var card := Button.new()
		card.name = "ClassCard_%s" % String(class_data.id)
		card.custom_minimum_size = Vector2(0, 58)
		card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		card.clip_contents = true
		card.text = ""
		card.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		card.pressed.connect(select_class.bind(class_data.id))
		_class_list_vbox.add_child(card)
		_class_buttons[class_data.id] = card

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

		var thumb_box := UI_THEME.make_box(Color(0.02, 0.03, 0.05, 0.95), class_data.placeholder_color, 2, 6)
		thumb_box.content_margin_left = 3
		thumb_box.content_margin_right = 3
		thumb_box.content_margin_top = 3
		thumb_box.content_margin_bottom = 3
		thumb_box.shadow_size = 0
		var thumb_frame := PanelContainer.new()
		thumb_frame.custom_minimum_size = Vector2(46, 46)
		thumb_frame.add_theme_stylebox_override("panel", thumb_box)
		thumb_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(thumb_frame)

		var thumb := TextureRect.new()
		thumb.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		thumb.texture = ClassVisualHelper.get_portrait_texture(class_data.id, class_data)
		thumb.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		thumb.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		thumb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		thumb.size_flags_vertical = Control.SIZE_EXPAND_FILL
		thumb.mouse_filter = Control.MOUSE_FILTER_IGNORE
		thumb_frame.add_child(thumb)

		var text_col := VBoxContainer.new()
		text_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		text_col.alignment = BoxContainer.ALIGNMENT_CENTER
		text_col.add_theme_constant_override("separation", 1)
		text_col.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(text_col)

		var name_label := Label.new()
		name_label.text = class_data.display_name
		name_label.add_theme_color_override("font_color", UI_THEME.IVORY)
		name_label.add_theme_font_size_override("font_size", 15)
		name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		text_col.add_child(name_label)

		var sub_label := Label.new()
		sub_label.text = class_data.role
		sub_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		sub_label.add_theme_color_override("font_color", UI_THEME.MUTED)
		sub_label.add_theme_font_size_override("font_size", 11)
		sub_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		text_col.add_child(sub_label)

	_update_card_selection_styles()


func select_class(class_id: StringName) -> void:
	var class_data := GameState.get_character_class(class_id)
	if class_data == null:
		return
	selected_class_id = class_id
	_prompt_placeholder.visible = false
	_inspector_content.visible = true
	if _details_scroll:
		_details_scroll.scroll_vertical = 0
	_update_card_selection_styles()
	_populate_inspector(class_data)
	class_selected.emit(class_id)


func _update_card_selection_styles() -> void:
	for key in _class_buttons:
		var cid: StringName = StringName(key)
		var card := _class_buttons[key] as Button
		var cls := GameState.get_character_class(cid)
		var accent: Color = cls.placeholder_color.lightened(0.25) if cls != null else UI_THEME.GOLD
		var is_selected: bool = cid == selected_class_id
		if is_selected:
			card.add_theme_stylebox_override("normal", UI_THEME.make_box(Color("1c2d3e"), UI_THEME.GOLD, 3, 8))
			card.add_theme_stylebox_override("hover", UI_THEME.make_box(Color("24394d"), Color("ffe39e"), 3, 8))
			card.add_theme_stylebox_override("pressed", UI_THEME.make_box(Color("142230"), UI_THEME.GOLD, 3, 8))
			card.add_theme_stylebox_override("focus", UI_THEME.make_box(Color(0, 0, 0, 0), accent, 2, 8))
		else:
			card.add_theme_stylebox_override("normal", UI_THEME.make_box(Color("0d1723"), Color("324456"), 1, 8))
			card.add_theme_stylebox_override("hover", UI_THEME.make_box(Color("172738"), accent, 2, 8))
			card.add_theme_stylebox_override("pressed", UI_THEME.make_box(Color("091019"), accent, 2, 8))
			card.add_theme_stylebox_override("focus", UI_THEME.make_box(Color(0, 0, 0, 0), accent, 1, 8))


func _populate_inspector(class_data: CharacterClassData) -> void:
	var accent := class_data.placeholder_color.lightened(0.25)
	_preview_stage_panel.add_theme_stylebox_override("panel", _make_stage_box(accent))

	var frames := ClassVisualHelper.get_sprite_frames(class_data.id)
	_preview_sprite.sprite_frames = frames
	_update_anim_buttons_availability(frames)
	_select_preview_animation(&"idle")
	call_deferred("_center_preview_sprite")

	_class_title_label.text = class_data.display_name.to_upper()
	_class_role_label.text = class_data.role
	_class_desc_label.text = class_data.description

	for child in _tags_row.get_children():
		child.queue_free()

	var meta := ClassVisualHelper.get_class_gameplay_meta(class_data.id)
	_add_tag_pill("🎯 Lőtáv: " + str(meta.get("range_text", "1 mező")), Color("8db7d8"))
	_add_tag_pill("⚡ " + str(meta.get("mobility_text", "")), Color("a7cf9c"))

	for child in _stat_bars_grid.get_children():
		child.queue_free()

	var stats := class_data.get_stats_at_level(1)
	var hp := int(stats.get("max_health", 0))
	var dmg_min := int(stats.get("damage_min", 0))
	var dmg_max := int(stats.get("damage_max", 0))
	var def := int(stats.get("defense", 0))
	var spd := int(stats.get("speed", 0))

	_add_stat_bar("❤️ Életerő", float(hp), 160.0, "%d HP" % hp, Color("d96b6b"))
	_add_stat_bar("⚔️ Sebzés", float(dmg_max), 30.0, "%d–%d" % [dmg_min, dmg_max], Color("e9a452"))
	_add_stat_bar("🛡️ Védelem", float(def), 5.0, "%d" % def, Color("6ca8dc"))
	_add_stat_bar("⚡ Kezdeményezés", float(spd), 16.0, "%d" % spd, Color("7bd19b"))

	for child in _secondary_stats_grid.get_children():
		child.queue_free()

	var secondary_items: Array[String] = [
		"🎯 Pontosság: %d%%" % int(stats.get("accuracy", 0)),
		"💥 Kritikus: %d%%" % int(round(float(stats.get("crit_chance", 0.0)))),
		"💨 Kitérés: %d%%" % int(stats.get("dodge", 0)),
		"💚 Gyógyerő: %d" % int(stats.get("healing_power", 0)),
		"🧠 Stressztűrés: %d%%" % int(stats.get("stress_resistance", 0)),
		"📈 Szintlépés: +%d HP / +%d sebzés" % [class_data.health_per_level, class_data.damage_max_per_level]
	]
	for item_text in secondary_items:
		var lbl := Label.new()
		lbl.text = item_text
		lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		lbl.add_theme_color_override("font_color", Color("cfd8e3"))
		lbl.add_theme_font_size_override("font_size", 12)
		_secondary_stats_grid.add_child(lbl)

	for child in _skills_row.get_children():
		child.queue_free()

	if class_data.skill_names.is_empty():
		_add_tag_pill("Alap támadás", UI_THEME.MUTED)
	else:
		for skill_name in class_data.skill_names:
			_add_skill_chip("✦ " + skill_name)

	var note := str(meta.get("special_note", ""))
	_special_note_label.text = ("💡 " + note) if not note.is_empty() else ""
	_special_note_label.visible = not note.is_empty()


func _add_tag_pill(text_value: String, accent: Color) -> void:
	var pill := PanelContainer.new()
	var box := UI_THEME.make_box(Color(0.06, 0.10, 0.16, 0.95), accent, 1, 6)
	box.content_margin_left = 8
	box.content_margin_right = 8
	box.content_margin_top = 3
	box.content_margin_bottom = 3
	box.shadow_size = 0
	pill.add_theme_stylebox_override("panel", box)
	_tags_row.add_child(pill)

	var lbl := Label.new()
	lbl.text = text_value
	lbl.add_theme_color_override("font_color", UI_THEME.IVORY)
	lbl.add_theme_font_size_override("font_size", 11)
	pill.add_child(lbl)


func _add_skill_chip(text_value: String) -> void:
	var chip := PanelContainer.new()
	var box := UI_THEME.make_box(Color(0.14, 0.11, 0.05, 0.95), UI_THEME.GOLD, 1, 6)
	box.content_margin_left = 10
	box.content_margin_right = 10
	box.content_margin_top = 4
	box.content_margin_bottom = 4
	box.shadow_size = 0
	chip.add_theme_stylebox_override("panel", box)
	_skills_row.add_child(chip)

	var lbl := Label.new()
	lbl.text = text_value
	lbl.add_theme_color_override("font_color", UI_THEME.IVORY)
	lbl.add_theme_font_size_override("font_size", 12)
	chip.add_child(lbl)


func _add_stat_bar(title_text: String, value: float, max_val: float, value_label_text: String, bar_color: Color) -> void:
	var row := VBoxContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_theme_constant_override("separation", 2)
	_stat_bars_grid.add_child(row)

	var header := HBoxContainer.new()
	row.add_child(header)

	var name_lbl := Label.new()
	name_lbl.text = title_text
	name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_lbl.add_theme_color_override("font_color", UI_THEME.MUTED)
	name_lbl.add_theme_font_size_override("font_size", 12)
	header.add_child(name_lbl)

	var val_lbl := Label.new()
	val_lbl.text = value_label_text
	val_lbl.add_theme_color_override("font_color", UI_THEME.IVORY)
	val_lbl.add_theme_font_size_override("font_size", 12)
	header.add_child(val_lbl)

	var bar := ProgressBar.new()
	bar.custom_minimum_size = Vector2(0, 10)
	bar.max_value = max_val
	bar.value = clampf(value, 0.0, max_val)
	bar.show_percentage = false

	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.02, 0.035, 0.06, 0.95)
	bg.set_corner_radius_all(3)
	bg.border_color = Color(0.24, 0.32, 0.42, 0.8)
	bg.set_border_width_all(1)
	bar.add_theme_stylebox_override("background", bg)

	var fill := StyleBoxFlat.new()
	fill.bg_color = bar_color
	fill.set_corner_radius_all(3)
	bar.add_theme_stylebox_override("fill", fill)
	row.add_child(bar)


func _update_anim_buttons_availability(frames: SpriteFrames) -> void:
	for key in _anim_buttons:
		var anim_id: StringName = StringName(key)
		var btn := _anim_buttons[key] as Button
		var exists: bool = frames != null and frames.has_animation(anim_id)
		btn.visible = exists


func _select_preview_animation(anim_id: StringName) -> void:
	_anim_loop_timer.stop()
	var frames := _preview_sprite.sprite_frames
	if frames == null:
		return
	var target := anim_id
	if not frames.has_animation(target):
		target = &"idle" if frames.has_animation(&"idle") else &"default"
	_current_anim = target
	_update_anim_button_styles()
	_center_preview_sprite()
	if frames.has_animation(_current_anim):
		_preview_sprite.play(_current_anim)


func _update_anim_button_styles() -> void:
	for key in _anim_buttons:
		var anim_id: StringName = StringName(key)
		var btn := _anim_buttons[key] as Button
		var active: bool = anim_id == _current_anim
		var border := UI_THEME.GOLD if active else Color("3b4f63")
		var bg := Color("1f3145") if active else Color("0d1723")
		var hover_bg := Color("28405a") if active else Color("162638")
		var pressed_bg := Color("152433") if active else Color("08101a")

		var normal_box := UI_THEME.make_box(bg, border, 2 if active else 1, 6)
		normal_box.content_margin_left = 10
		normal_box.content_margin_right = 10
		normal_box.content_margin_top = 4
		normal_box.content_margin_bottom = 4
		normal_box.shadow_size = 0

		var hover_box := UI_THEME.make_box(hover_bg, Color("ffe39e") if active else UI_THEME.GOLD, 2 if active else 1, 6)
		hover_box.content_margin_left = 10
		hover_box.content_margin_right = 10
		hover_box.content_margin_top = 4
		hover_box.content_margin_bottom = 4
		hover_box.shadow_size = 0

		var pressed_box := UI_THEME.make_box(pressed_bg, border, 2 if active else 1, 6)
		pressed_box.content_margin_left = 10
		pressed_box.content_margin_right = 10
		pressed_box.content_margin_top = 4
		pressed_box.content_margin_bottom = 4
		pressed_box.shadow_size = 0

		btn.add_theme_stylebox_override("normal", normal_box)
		btn.add_theme_stylebox_override("hover", hover_box)
		btn.add_theme_stylebox_override("pressed", pressed_box)
		btn.add_theme_color_override("font_color", UI_THEME.IVORY if active else UI_THEME.MUTED)


func _make_stage_box(border_color: Color) -> StyleBoxFlat:
	var box := UI_THEME.make_box(Color(0.02, 0.03, 0.055, 0.98), border_color, 2, 10)
	box.content_margin_left = 2.0
	box.content_margin_right = 2.0
	box.content_margin_top = 2.0
	box.content_margin_bottom = 2.0
	box.shadow_size = 0
	return box


func _center_preview_sprite() -> void:
	if _preview_viewport == null or _preview_sprite == null:
		return
	var vp_size := Vector2(_preview_viewport.size)
	if vp_size.x <= 0.0 or vp_size.y <= 0.0:
		return
	var center_offset := ClassVisualHelper.get_visual_center_offset(selected_class_id, &"idle")
	_preview_sprite.position = vp_size * 0.5 - center_offset * _preview_sprite.scale


func _on_preview_animation_finished() -> void:
	if not visible or selected_class_id == &"" or _preview_sprite.sprite_frames == null:
		return
	if not _preview_sprite.sprite_frames.get_animation_loop(_current_anim):
		_anim_loop_timer.start()


func _on_anim_replay_timeout() -> void:
	if visible and selected_class_id != &"" and _preview_sprite.sprite_frames != null:
		if _preview_sprite.sprite_frames.has_animation(_current_anim):
			_preview_sprite.play(_current_anim)
