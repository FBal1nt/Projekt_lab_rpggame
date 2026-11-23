extends Panel

const UI_THEME = preload("res://Scripts/UI/ui_theme.gd")
const CLASS_VISUAL_HELPER = preload("res://Scripts/Utils/ClassVisualHelper.gd")
const CHARACTER_CREATION_OVERLAY_SCENE: PackedScene = preload("res://Scenes/UI/CharacterCreationOverlay.tscn")
const CHARACTER_ICON_PATH := "res://Assets/UI/Icons/character.png"

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
var extra_stats_label: Label
var equipment_label: Label
var skills_label: Label
var titles_heading_label: Label
var titles_clear_button: Button
var titles_preview_label: Label
var titles_buff_label: Label
var titles_grid: GridContainer
var titles_hint_label: Label

var _creation_layer: CanvasLayer
var _creation_overlay: CharacterCreationOverlay
var _is_refreshing: bool = false


func _ready() -> void:
	anchor_left = 0.045
	anchor_top = 0.045
	anchor_right = 0.955
	anchor_bottom = 0.955
	offset_left = 0.0
	offset_top = 0.0
	offset_right = 0.0
	offset_bottom = 0.0
	grow_horizontal = Control.GROW_DIRECTION_BOTH
	grow_vertical = Control.GROW_DIRECTION_BOTH
	UI_THEME.style_window_shell(self, UI_THEME.GOLD)

	title_label.visible = false

	close_button.anchor_left = 1.0
	close_button.anchor_right = 1.0
	close_button.anchor_top = 0.0
	close_button.anchor_bottom = 0.0
	close_button.offset_left = -132.0
	close_button.offset_right = -18.0
	close_button.offset_top = 15.0
	close_button.offset_bottom = 51.0
	close_button.text = "BEZÁRÁS"
	UI_THEME.style_compact_button(close_button, UI_THEME.GOLD, false, 36.0, 13)
	AudioManager.mark_custom_button_sfx(close_button)

	_build_content()
	close_button.move_to_front()

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
	var body := MarginContainer.new()
	body.name = "CharacterRosterContent"
	add_child(body)
	body.set_anchors_preset(Control.PRESET_FULL_RECT)
	body.offset_left = 18.0
	body.offset_top = 12.0
	body.offset_right = -18.0
	body.offset_bottom = -16.0
	body.grow_horizontal = Control.GROW_DIRECTION_BOTH
	body.grow_vertical = Control.GROW_DIRECTION_BOTH

	var outer := VBoxContainer.new()
	outer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	outer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	outer.add_theme_constant_override("separation", 10)
	body.add_child(outer)

	# --- Unified Header Bar ---
	var header_row := HBoxContainer.new()
	header_row.custom_minimum_size = Vector2(0, 44)
	header_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header_row.add_theme_constant_override("separation", 12)
	outer.add_child(header_row)

	var brand_box := HBoxContainer.new()
	brand_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	brand_box.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	brand_box.add_theme_constant_override("separation", 10)
	header_row.add_child(brand_box)

	if ResourceLoader.exists(CHARACTER_ICON_PATH):
		var icon_frame := PanelContainer.new()
		icon_frame.custom_minimum_size = Vector2(40, 40)
		icon_frame.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		icon_frame.add_theme_stylebox_override(
			"panel",
			UI_THEME.make_card_box(Color(0.05, 0.07, 0.11, 0.96), UI_THEME.GOLD, 1, 9, 5.0, 5.0)
		)
		brand_box.add_child(icon_frame)

		var icon_rect := TextureRect.new()
		icon_rect.texture = load(CHARACTER_ICON_PATH) as Texture2D
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

	var header_title := Label.new()
	header_title.text = "KARAKTEREK ÉS TITULUSOK"
	header_title.add_theme_color_override("font_color", UI_THEME.GOLD)
	header_title.add_theme_font_size_override("font_size", 22)
	title_col.add_child(header_title)

	roster_summary_label = Label.new()
	roster_summary_label.add_theme_color_override("font_color", UI_THEME.MUTED)
	roster_summary_label.add_theme_font_size_override("font_size", 12)
	title_col.add_child(roster_summary_label)

	var close_spacer := Control.new()
	close_spacer.custom_minimum_size = Vector2(124, 36)
	header_row.add_child(close_spacer)

	var header_sep := ColorRect.new()
	header_sep.custom_minimum_size = Vector2(0, 1)
	header_sep.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header_sep.color = Color(UI_THEME.GOLD.r, UI_THEME.GOLD.g, UI_THEME.GOLD.b, 0.36)
	outer.add_child(header_sep)

	# --- Two-column split ---
	var split := HBoxContainer.new()
	split.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	split.add_theme_constant_override("separation", 14)
	outer.add_child(split)

	# Left pane: Saved characters + Create button
	var list_panel := PanelContainer.new()
	list_panel.custom_minimum_size = Vector2(315, 0)
	list_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	list_panel.clip_contents = true
	list_panel.add_theme_stylebox_override(
		"panel",
		UI_THEME.make_card_box(UI_THEME.SURFACE_DARK, Color(UI_THEME.GOLD.r, UI_THEME.GOLD.g, UI_THEME.GOLD.b, 0.42), 1, 12, 12.0, 12.0)
	)
	split.add_child(list_panel)

	var list_vbox := VBoxContainer.new()
	list_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list_vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	list_vbox.add_theme_constant_override("separation", 10)
	list_panel.add_child(list_vbox)

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

	new_character_button = Button.new()
	new_character_button.name = "CreateNewCharacterButton"
	new_character_button.text = "ÚJ KARAKTER LÉTREHOZÁSA"
	new_character_button.icon = load("res://Assets/UI/Icons/play_sword.png")
	new_character_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	UI_THEME.style_compact_button(new_character_button, UI_THEME.EMERALD, true, 42.0, 13)
	new_character_button.pressed.connect(_open_character_creation_overlay)
	list_vbox.add_child(new_character_button)

	# Right pane: Active character inspector
	var detail_panel := PanelContainer.new()
	detail_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	detail_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	detail_panel.clip_contents = true
	detail_panel.add_theme_stylebox_override(
		"panel",
		UI_THEME.make_card_box(UI_THEME.SURFACE_DARK, Color(UI_THEME.GOLD.r, UI_THEME.GOLD.g, UI_THEME.GOLD.b, 0.48), 1, 12, 16.0, 14.0)
	)
	split.add_child(detail_panel)

	var detail_stack := Control.new()
	detail_stack.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	detail_stack.size_flags_vertical = Control.SIZE_EXPAND_FILL
	detail_stack.clip_contents = true
	detail_panel.add_child(detail_stack)

	detail_empty_label = Label.new()
	detail_empty_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	detail_empty_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	detail_empty_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	detail_empty_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	detail_empty_label.text = "Ebben a mentésben még nincs karakter.\nKattints bal oldalon az 'Új karakter létrehozása' gombra!"
	detail_empty_label.add_theme_color_override("font_color", UI_THEME.MUTED)
	detail_empty_label.add_theme_font_size_override("font_size", 15)
	detail_stack.add_child(detail_empty_label)

	detail_content = VBoxContainer.new()
	detail_content.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	detail_content.add_theme_constant_override("separation", 10)
	detail_content.visible = false
	detail_stack.add_child(detail_content)

	# Hero Header Card
	var hero_card := PanelContainer.new()
	hero_card.add_theme_stylebox_override(
		"panel",
		UI_THEME.make_card_box(UI_THEME.SURFACE_CARD, Color(UI_THEME.GOLD.r, UI_THEME.GOLD.g, UI_THEME.GOLD.b, 0.40), 1, 11, 12.0, 10.0)
	)
	detail_content.add_child(hero_card)

	var hero_header := HBoxContainer.new()
	hero_header.add_theme_constant_override("separation", 14)
	hero_card.add_child(hero_header)

	preview_stage_panel = PanelContainer.new()
	preview_stage_panel.custom_minimum_size = Vector2(102, 102)
	preview_stage_panel.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	preview_stage_panel.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	preview_stage_panel.add_theme_stylebox_override("panel", _make_stage_box(UI_THEME.GOLD))
	hero_header.add_child(preview_stage_panel)

	var vp_margin := MarginContainer.new()
	vp_margin.add_theme_constant_override("margin_left", 3)
	vp_margin.add_theme_constant_override("margin_top", 3)
	vp_margin.add_theme_constant_override("margin_right", 3)
	vp_margin.add_theme_constant_override("margin_bottom", 3)
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
	hero_name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hero_name_label.add_theme_color_override("font_color", UI_THEME.IVORY)
	hero_name_label.add_theme_font_size_override("font_size", 22)
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

	var stats_scroll := ScrollContainer.new()
	stats_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stats_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	stats_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	detail_content.add_child(stats_scroll)

	var stats_vbox := VBoxContainer.new()
	stats_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stats_vbox.add_theme_constant_override("separation", 10)
	stats_scroll.add_child(stats_vbox)

	var stats_heading := Label.new()
	stats_heading.text = "KARAKTER STATISZTIKÁK"
	stats_heading.add_theme_color_override("font_color", UI_THEME.GOLD)
	stats_heading.add_theme_font_size_override("font_size", 12)
	stats_vbox.add_child(stats_heading)

	stats_grid = GridContainer.new()
	stats_grid.columns = 4
	stats_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stats_grid.add_theme_constant_override("h_separation", 8)
	stats_grid.add_theme_constant_override("v_separation", 8)
	stats_vbox.add_child(stats_grid)

	extra_stats_label = Label.new()
	extra_stats_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	extra_stats_label.add_theme_color_override("font_color", UI_THEME.MUTED)
	extra_stats_label.add_theme_font_size_override("font_size", 12)
	stats_vbox.add_child(extra_stats_label)

	# Equipment & skills summary card
	var gear_card := PanelContainer.new()
	gear_card.add_theme_stylebox_override(
		"panel",
		UI_THEME.make_card_box(UI_THEME.SURFACE_CARD, UI_THEME.BORDER_SUBTLE, 1, 9, 12.0, 9.0)
	)
	stats_vbox.add_child(gear_card)

	var gear_vbox := VBoxContainer.new()
	gear_vbox.add_theme_constant_override("separation", 4)
	gear_card.add_child(gear_vbox)

	equipment_label = Label.new()
	equipment_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	equipment_label.add_theme_color_override("font_color", UI_THEME.IVORY)
	equipment_label.add_theme_font_size_override("font_size", 12)
	gear_vbox.add_child(equipment_label)

	skills_label = Label.new()
	skills_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	skills_label.add_theme_color_override("font_color", UI_THEME.MUTED)
	skills_label.add_theme_font_size_override("font_size", 12)
	gear_vbox.add_child(skills_label)

	# Titles section
	var titles_header := HBoxContainer.new()
	titles_header.add_theme_constant_override("separation", 8)
	stats_vbox.add_child(titles_header)

	titles_heading_label = Label.new()
	titles_heading_label.text = "AKTÍV TITULUS (0 / 0)"
	titles_heading_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	titles_heading_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	titles_heading_label.add_theme_color_override("font_color", UI_THEME.GOLD)
	titles_heading_label.add_theme_font_size_override("font_size", 12)
	titles_header.add_child(titles_heading_label)

	titles_clear_button = Button.new()
	titles_clear_button.text = "LEVÉTEL"
	titles_clear_button.custom_minimum_size = Vector2(96, 30)
	UI_THEME.style_compact_button(titles_clear_button, Color(0.55, 0.65, 0.75, 1.0), false, 30.0, 11)
	titles_clear_button.pressed.connect(_on_clear_titles_pressed)
	titles_header.add_child(titles_clear_button)

	var preview_card := PanelContainer.new()
	preview_card.add_theme_stylebox_override(
		"panel",
		UI_THEME.make_card_box(Color(0.025, 0.042, 0.072, 0.96), Color(UI_THEME.GOLD.r, UI_THEME.GOLD.g, UI_THEME.GOLD.b, 0.55), 1, 8, 12.0, 8.0)
	)
	stats_vbox.add_child(preview_card)

	var preview_vbox := VBoxContainer.new()
	preview_vbox.add_theme_constant_override("separation", 2)
	preview_card.add_child(preview_vbox)

	titles_preview_label = Label.new()
	titles_preview_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	titles_preview_label.add_theme_color_override("font_color", Color("f7e4b4"))
	titles_preview_label.add_theme_font_size_override("font_size", 13)
	preview_vbox.add_child(titles_preview_label)

	titles_buff_label = Label.new()
	titles_buff_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	titles_buff_label.add_theme_color_override("font_color", UI_THEME.EMERALD)
	titles_buff_label.add_theme_font_size_override("font_size", 12)
	preview_vbox.add_child(titles_buff_label)

	titles_hint_label = Label.new()
	titles_hint_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	titles_hint_label.add_theme_color_override("font_color", UI_THEME.MUTED)
	titles_hint_label.add_theme_font_size_override("font_size", 11)
	titles_hint_label.text = "Győzz le titulusos ellenfeleket, majd lépj ki a kijárati kapun a titulusok feloldásához! Egyszerre 1 titulus aktiválható."
	stats_vbox.add_child(titles_hint_label)

	titles_grid = GridContainer.new()
	titles_grid.columns = 2
	titles_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	titles_grid.add_theme_constant_override("h_separation", 8)
	titles_grid.add_theme_constant_override("v_separation", 7)
	stats_vbox.add_child(titles_grid)

	# Bottom status strip
	var status_bar := PanelContainer.new()
	status_bar.add_theme_stylebox_override(
		"panel",
		UI_THEME.make_card_box(Color(0.024, 0.038, 0.064, 0.96), UI_THEME.BORDER_SUBTLE, 1, 8, 12.0, 6.0)
	)
	outer.add_child(status_bar)

	status_label = Label.new()
	status_label.text = "Válassz karaktert bal oldalon, vagy kezelj egy aktív titulust."
	status_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	status_label.add_theme_color_override("font_color", UI_THEME.MUTED)
	status_label.add_theme_font_size_override("font_size", 12)
	status_bar.add_child(status_label)


func refresh() -> void:
	if character_list_vbox == null or _is_refreshing:
		return
	_is_refreshing = true

	for child in character_list_vbox.get_children():
		child.queue_free()

	var count := GameState.characters.size()
	var active := GameState.get_active_character()
	var active_name := active.character_name if active != null else "Nincs"
	roster_summary_label.text = "%d mentett hős  ·  Aktív karakter: %s" % [count, active_name]

	for character in GameState.characters:
		_add_character_card(character)

	_refresh_active_character_details(active)
	_is_refreshing = false


func _add_character_card(character: CharacterProfile) -> void:
	var class_data := GameState.get_character_class(character.class_id)
	var is_active: bool = character.id == GameState.active_character_id
	var accent: Color = class_data.placeholder_color.lightened(0.2) if class_data != null else UI_THEME.GOLD

	var card := Button.new()
	card.custom_minimum_size = Vector2(0, 60)
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.clip_contents = true
	card.text = ""
	card.focus_mode = Control.FOCUS_NONE
	card.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	card.pressed.connect(_on_character_card_pressed.bind(character.id))
	if is_active:
		card.add_theme_stylebox_override("normal", UI_THEME.make_card_box(Color(0.085, 0.125, 0.18, 0.98), UI_THEME.GOLD, 2, 10, 0.0, 0.0))
		card.add_theme_stylebox_override("hover", UI_THEME.make_card_box(Color(0.11, 0.16, 0.22, 0.99), UI_THEME.GOLD.lightened(0.2), 2, 10, 0.0, 0.0))
		card.add_theme_stylebox_override("pressed", UI_THEME.make_card_box(Color(0.06, 0.095, 0.14, 1.0), UI_THEME.GOLD, 2, 10, 0.0, 0.0))
	else:
		card.add_theme_stylebox_override("normal", UI_THEME.make_card_box(UI_THEME.SURFACE_CARD, UI_THEME.BORDER_SUBTLE, 1, 10, 0.0, 0.0))
		card.add_theme_stylebox_override("hover", UI_THEME.make_card_box(UI_THEME.SURFACE_ELEVATED, accent, 1, 10, 0.0, 0.0))
		card.add_theme_stylebox_override("pressed", UI_THEME.make_card_box(Color(0.03, 0.05, 0.085, 1.0), accent, 1, 10, 0.0, 0.0))
	character_list_vbox.add_child(card)

	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 8)
	margin.add_theme_constant_override("margin_top", 6)
	margin.add_theme_constant_override("margin_right", 10)
	margin.add_theme_constant_override("margin_bottom", 6)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(margin)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_child(row)

	var thumb_frame := PanelContainer.new()
	thumb_frame.custom_minimum_size = Vector2(46, 46)
	thumb_frame.add_theme_stylebox_override("panel", UI_THEME.make_card_box(Color(0.02, 0.032, 0.056, 0.98), accent, 1, 8, 3.0, 3.0))
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
		var badge_pill := PanelContainer.new()
		badge_pill.mouse_filter = Control.MOUSE_FILTER_IGNORE
		badge_pill.add_theme_stylebox_override("panel", UI_THEME.make_badge_box(Color(0.06, 0.18, 0.11, 0.96), UI_THEME.EMERALD.darkened(0.15), 5))
		title_row.add_child(badge_pill)
		var badge := Label.new()
		badge.text = "AKTÍV"
		badge.add_theme_color_override("font_color", UI_THEME.EMERALD)
		badge.add_theme_font_size_override("font_size", 10)
		badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
		badge_pill.add_child(badge)

	var class_name_text := class_data.display_name if class_data != null else String(character.class_id)
	var sub_lbl := Label.new()
	sub_lbl.text = "%s  ·  %d. szint" % [class_name_text, character.level]
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
	var full_display_name := GameState.get_character_display_name(active)
	hero_name_label.text = full_display_name
	hero_name_label.tooltip_text = full_display_name
	var name_font_size: int = 22
	if full_display_name.length() > 68:
		name_font_size = 14
	elif full_display_name.length() > 38:
		name_font_size = 17
	hero_name_label.add_theme_font_size_override("font_size", name_font_size)
	hero_sub_label.text = "%s%s  ·  %d. szint  ·  Aktív hős" % [
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

	stats_grid.add_child(_make_stat_tile("ÉLETERŐ", "%d / %d" % [current_health, max_health], Color(0.92, 0.45, 0.45, 1.0)))
	stats_grid.add_child(_make_stat_tile("SEBZÉS", "%d–%d" % [damage_min, damage_max], Color(0.95, 0.64, 0.42, 1.0)))
	stats_grid.add_child(_make_stat_tile("VÉDELEM", "%d" % defense, Color(0.55, 0.80, 0.96, 1.0)))
	stats_grid.add_child(_make_stat_tile("KEZDEMÉNYEZÉS", "%s" % _format_stat_value(stats.get("speed", 0)), UI_THEME.GOLD))
	stats_grid.add_child(_make_stat_tile("KRITIKUS", "%s%%" % _format_stat_value(stats.get("crit_chance", 0)), Color(0.96, 0.78, 0.36, 1.0)))
	stats_grid.add_child(_make_stat_tile("KITÉRÉS", "%s%%" % _format_stat_value(stats.get("dodge", 0)), UI_THEME.EMERALD))
	stats_grid.add_child(_make_stat_tile("PONTOSSÁG", "%s%%" % _format_stat_value(stats.get("accuracy", 0)), Color(0.76, 0.86, 0.96, 1.0)))
	stats_grid.add_child(_make_stat_tile("STRESSZ", "%d" % active.stress, Color(0.76, 0.64, 0.94, 1.0)))

	extra_stats_label.text = "Gyógyerő: %s   ·   Stressztűrés: %s%%" % [
		_format_stat_value(stats.get("healing_power", 0)),
		_format_stat_value(stats.get("stress_resistance", 0))
	]

	var eq_parts: Array[String] = []
	for slot in SLOT_ORDER:
		var slot_title := str(SLOT_LABELS.get(slot, String(slot)))
		var equipped_item := active.equipment.get(slot, null) as InventoryItem
		if equipped_item != null and equipped_item.item_data != null:
			var plus := (" +%d" % equipped_item.upgrade_level) if equipped_item.upgrade_level > 0 else ""
			eq_parts.append("%s: %s%s" % [slot_title, equipped_item.item_data.display_name, plus])
		else:
			eq_parts.append("%s: —" % slot_title)
	equipment_label.text = "Felszerelés: " + "  ·  ".join(eq_parts)

	if class_data != null and not class_data.skill_names.is_empty():
		skills_label.text = "Képességek: " + "  ·  ".join(class_data.skill_names)
	else:
		skills_label.text = "Képességek: Alap támadás"

	_refresh_titles_section(active)


func _make_stat_tile(caption_text: String, value_text: String, value_color: Color) -> PanelContainer:
	var card := PanelContainer.new()
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.add_theme_stylebox_override(
		"panel",
		UI_THEME.make_card_box(UI_THEME.SURFACE_CARD, UI_THEME.BORDER_SUBTLE, 1, 8, 8.0, 6.0)
	)
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 2)
	card.add_child(vbox)

	var cap := Label.new()
	cap.text = caption_text
	cap.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cap.add_theme_color_override("font_color", UI_THEME.MUTED)
	cap.add_theme_font_size_override("font_size", 10)
	vbox.add_child(cap)

	var val := Label.new()
	val.text = value_text
	val.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	val.add_theme_color_override("font_color", value_color)
	val.add_theme_font_size_override("font_size", 15)
	vbox.add_child(val)
	return card


func _refresh_titles_section(active: CharacterProfile) -> void:
	if titles_grid == null:
		return
	for child in titles_grid.get_children():
		child.queue_free()

	var catalog := GameState.get_all_collectible_titles()
	var display_entries: Array[Dictionary] = catalog.duplicate(true)
	var catalog_titles: Array[String] = []
	for entry in display_entries:
		catalog_titles.append(String(entry.get("title", "")))
	for unlocked in active.unlocked_titles:
		var u_str := String(unlocked)
		if not catalog_titles.has(u_str):
			display_entries.append({"title": u_str, "monster_name": "Különleges ellenfél", "tier": 4})

	var total_count := display_entries.size()
	var unlocked_count := active.unlocked_titles.size()
	var active_title := GameState.get_active_title(active)
	titles_heading_label.text = "AKTÍV TITULUS (%d / %d feloldva · max. 1 aktív)" % [unlocked_count, total_count]
	titles_preview_label.text = "Megjelenő név: " + GameState.get_character_display_name(active)
	if not active_title.is_empty():
		titles_buff_label.text = "Aktív bónusz: " + GameState.format_title_buff_summary(active_title)
		titles_buff_label.add_theme_color_override("font_color", UI_THEME.EMERALD)
	else:
		titles_buff_label.text = "Aktív bónusz: Nincs (válassz egy feloldott titulust)"
		titles_buff_label.add_theme_color_override("font_color", UI_THEME.MUTED)
	titles_clear_button.disabled = active_title.is_empty()
	titles_hint_label.visible = unlocked_count == 0

	for entry in display_entries:
		var title_text := String(entry.get("title", ""))
		var monster_name := String(entry.get("monster_name", "Ellenség"))
		var buff_summary := GameState.format_title_buff_summary(title_text)
		var is_unlocked := active.unlocked_titles.has(title_text)
		var is_selected := active_title == title_text

		var btn := Button.new()
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.clip_contents = true
		btn.text = ""
		if is_unlocked:
			var accent := UI_THEME.GOLD if is_selected else Color(0.45, 0.58, 0.72, 0.9)
			UI_THEME.style_button(btn, accent, is_selected, 48.0)
			btn.tooltip_text = "Forrás: %s\nBónusz: %s\nKattints az aktiváláshoz / levételhez (egyszerre csak 1 aktív)." % [monster_name, buff_summary]
			btn.pressed.connect(_on_title_toggle_pressed.bind(title_text, not is_selected))
		else:
			UI_THEME.style_button(btn, Color(0.32, 0.36, 0.42, 0.65), false, 48.0)
			btn.disabled = true
			btn.tooltip_text = "Zárolva — győzd le: %s, majd lépj ki a kijárati kapun!\nBónusz: %s" % [monster_name, buff_summary]

		for state_name in ["normal", "hover", "pressed", "focus", "disabled"]:
			var sb: StyleBox = btn.get_theme_stylebox(state_name)
			if sb is StyleBoxFlat:
				var c_sb := sb.duplicate() as StyleBoxFlat
				c_sb.content_margin_left = 0.0
				c_sb.content_margin_right = 0.0
				c_sb.content_margin_top = 0.0
				c_sb.content_margin_bottom = 0.0
				btn.add_theme_stylebox_override(state_name, c_sb)
		btn.custom_minimum_size = Vector2(0, 48)
		btn.focus_mode = Control.FOCUS_NONE

		var btn_margin := MarginContainer.new()
		btn_margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		btn_margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
		btn_margin.add_theme_constant_override("margin_left", 10)
		btn_margin.add_theme_constant_override("margin_right", 8)
		btn_margin.add_theme_constant_override("margin_top", 5)
		btn_margin.add_theme_constant_override("margin_bottom", 5)
		btn.add_child(btn_margin)

		var btn_vbox := VBoxContainer.new()
		btn_vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
		btn_vbox.alignment = BoxContainer.ALIGNMENT_CENTER
		btn_vbox.add_theme_constant_override("separation", 1)
		btn_margin.add_child(btn_vbox)

		var name_lbl := Label.new()
		name_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		name_lbl.clip_text = true
		name_lbl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		name_lbl.add_theme_font_size_override("font_size", 12)
		if is_unlocked:
			name_lbl.text = ("★  " if is_selected else "○  ") + title_text
			name_lbl.add_theme_color_override("font_color", UI_THEME.GOLD if is_selected else UI_THEME.IVORY)
		else:
			name_lbl.text = "Zárolva: " + title_text
			name_lbl.add_theme_color_override("font_color", Color(0.55, 0.60, 0.66, 0.85))
		btn_vbox.add_child(name_lbl)

		var buff_lbl := Label.new()
		buff_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		buff_lbl.clip_text = true
		buff_lbl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		buff_lbl.text = buff_summary
		buff_lbl.add_theme_font_size_override("font_size", 10)
		if is_unlocked:
			buff_lbl.add_theme_color_override("font_color", UI_THEME.EMERALD if is_selected else Color(0.54, 0.80, 0.64, 0.92))
		else:
			buff_lbl.add_theme_color_override("font_color", Color(0.46, 0.52, 0.58, 0.75))
		btn_vbox.add_child(buff_lbl)

		titles_grid.add_child(btn)


func _on_title_toggle_pressed(title_text: String, select_state: bool) -> void:
	if GameState.set_character_title_selected(title_text, select_state):
		if select_state:
			var buff_summary := GameState.format_title_buff_summary(title_text)
			_set_status("Aktív titulus: %s (%s)" % [title_text, buff_summary], true)
		else:
			_set_status("Titulus levéve: %s" % title_text, true)
		refresh()


func _on_clear_titles_pressed() -> void:
	if GameState.clear_selected_character_titles():
		_set_status("Aktív titulus levéve.", true)
		refresh()


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
	var box := UI_THEME.make_box(Color(0.018, 0.030, 0.052, 0.98), border_color, 2, 10)
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
		UI_THEME.EMERALD if success else UI_THEME.CRIMSON
	)
