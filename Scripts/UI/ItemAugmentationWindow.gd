extends Panel

const UI_THEME = preload("res://Scripts/UI/ui_theme.gd")
const GOLD_ICON_PATH := "res://Assets/Items/Currency/gold_coins.png"
const SHARED_MATERIAL_IDS: Array[StringName] = [
	&"iron_ingot",
	&"silver_ingot",
	&"leather_strip",
	&"arcane_dust"
]

var workshop_type: StringName = &""
var workshop_title: String = "MŰHELY"
var workshop_subtitle: String = ""
var workshop_icon_path: String = ""
var accent_color: Color = UI_THEME.GOLD
var option_configs: Array[Dictionary] = []

var _mode: StringName = &""
var _selected_item: InventoryItem
var _items_container: VBoxContainer
var _items_count_badge: Label
var _action_content: VBoxContainer
var _mode_buttons_row: HBoxContainer
var _mode_button_map: Dictionary = {}
var _status_label: Label
var _resource_strip: HBoxContainer
var _gold_value_label: Label
var _material_value_labels: Dictionary = {}

# Active character card controls (live animated hero portrait + fallback)
var _character_stage_panel: PanelContainer
var _character_viewport: SubViewport
var _character_sprite: AnimatedSprite2D
var _character_portrait_fallback: TextureRect
var _character_name_label: Label
var _character_class_label: Label
var _character_hp_bar: ProgressBar
var _character_hp_text: Label
var _character_stats_row: HBoxContainer

@onready var _title: Label = $Title
@onready var _close_button: Button = $CloseButton


# -----------------------------------------------------------------------------
# Workshop-specific configuration and lifecycle
# -----------------------------------------------------------------------------

func _configure_workshop() -> void:
	# Overridden by BlacksmithWindow.gd and WizardWindow.gd.
	pass


func _ready() -> void:
	_configure_workshop()
	if option_configs.is_empty():
		push_warning("Nincs megadva egyetlen műhelyopció sem: " + name)
	else:
		_mode = StringName(option_configs[0].get("id", ""))

	anchor_left = 0.03
	anchor_top = 0.04
	anchor_right = 0.97
	anchor_bottom = 0.96
	offset_left = 0.0
	offset_top = 0.0
	offset_right = 0.0
	offset_bottom = 0.0
	grow_horizontal = Control.GROW_DIRECTION_BOTH
	grow_vertical = Control.GROW_DIRECTION_BOTH
	UI_THEME.style_window_shell(self, accent_color)

	# Hide legacy absolute title node and rebuild a clean responsive header bar;
	# keep _close_button alive so Lobby.tscn's pressed connection stays intact.
	_title.visible = false
	_close_button.anchor_left = 1.0
	_close_button.anchor_right = 1.0
	_close_button.anchor_top = 0.0
	_close_button.anchor_bottom = 0.0
	_close_button.offset_left = -132.0
	_close_button.offset_right = -18.0
	_close_button.offset_top = 15.0
	_close_button.offset_bottom = 51.0
	_close_button.text = "BEZÁRÁS"
	UI_THEME.style_compact_button(_close_button, accent_color, false, 36.0, 13)
	AudioManager.mark_custom_button_sfx(_close_button)

	_build_interface()
	_close_button.move_to_front()

	if not GameState.state_changed.is_connected(_refresh_all):
		GameState.state_changed.connect(_refresh_all)
	if not GameState.active_character_changed.is_connected(_on_active_character_changed):
		GameState.active_character_changed.connect(_on_active_character_changed)
	if not visibility_changed.is_connected(_on_visibility_changed):
		visibility_changed.connect(_on_visibility_changed)
	_refresh_all()


func refresh() -> void:
	_refresh_all()
	call_deferred("_center_character_sprite")


func _on_visibility_changed() -> void:
	if visible:
		_refresh_all()
		call_deferred("_center_character_sprite")


# -----------------------------------------------------------------------------
# Layout construction
# -----------------------------------------------------------------------------

func _build_interface() -> void:
	var body := MarginContainer.new()
	body.name = "GeneratedAugmentationUI"
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

	# --- Header bar (Icon + Title/Subtitle + Shared Materials & Gold + Space for CloseButton) ---
	var header_row := HBoxContainer.new()
	header_row.custom_minimum_size = Vector2(0, 44)
	header_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header_row.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	header_row.add_theme_constant_override("separation", 12)
	outer.add_child(header_row)

	var brand_box := HBoxContainer.new()
	brand_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	brand_box.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	brand_box.add_theme_constant_override("separation", 10)
	header_row.add_child(brand_box)

	if not workshop_icon_path.is_empty() and ResourceLoader.exists(workshop_icon_path):
		var icon_frame := PanelContainer.new()
		icon_frame.custom_minimum_size = Vector2(40, 40)
		icon_frame.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		var icon_sb := UI_THEME.make_card_box(Color(0.05, 0.07, 0.11, 0.96), accent_color, 1, 9, 5.0, 5.0)
		icon_frame.add_theme_stylebox_override("panel", icon_sb)
		brand_box.add_child(icon_frame)

		var icon_rect := TextureRect.new()
		icon_rect.texture = load(workshop_icon_path) as Texture2D
		icon_rect.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
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

	var header_title := _make_label(workshop_title, 22, UI_THEME.GOLD)
	header_title.autowrap_mode = TextServer.AUTOWRAP_OFF
	title_col.add_child(header_title)

	if not workshop_subtitle.is_empty():
		var subtitle_lbl := _make_label(workshop_subtitle, 12, UI_THEME.MUTED)
		subtitle_lbl.autowrap_mode = TextServer.AUTOWRAP_OFF
		subtitle_lbl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		title_col.add_child(subtitle_lbl)

	# Shared materials + gold resource pills
	_resource_strip = HBoxContainer.new()
	_resource_strip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_resource_strip.add_theme_constant_override("separation", 6)
	header_row.add_child(_resource_strip)
	_build_resource_strip()

	# Spacer reserving room for top-right CloseButton
	var close_spacer := Control.new()
	close_spacer.custom_minimum_size = Vector2(124, 36)
	header_row.add_child(close_spacer)

	var header_sep := ColorRect.new()
	header_sep.custom_minimum_size = Vector2(0, 1)
	header_sep.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header_sep.color = Color(accent_color.r, accent_color.g, accent_color.b, 0.36)
	outer.add_child(header_sep)

	# --- Main two-column split ---
	var content := HBoxContainer.new()
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", 14)
	outer.add_child(content)

	# Left column: Active Character card + Equipment list
	var left_panel := PanelContainer.new()
	left_panel.custom_minimum_size.x = 390
	left_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left_panel.size_flags_stretch_ratio = 0.86
	left_panel.add_theme_stylebox_override(
		"panel",
		UI_THEME.make_card_box(UI_THEME.SURFACE_DARK, Color(accent_color.r, accent_color.g, accent_color.b, 0.45), 1, 12, 12.0, 12.0)
	)
	content.add_child(left_panel)

	var left_column := VBoxContainer.new()
	left_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left_column.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left_column.add_theme_constant_override("separation", 10)
	left_panel.add_child(left_column)

	left_column.add_child(_make_section_heading("AKTÍV KARAKTER", accent_color.lightened(0.18)))
	left_column.add_child(_build_character_card())

	var eq_header := HBoxContainer.new()
	eq_header.add_theme_constant_override("separation", 8)
	left_column.add_child(eq_header)

	var eq_title := _make_section_heading("FEGYVEREK ÉS FELSZERELÉSEK", UI_THEME.GOLD)
	eq_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	eq_header.add_child(eq_title)

	var eq_count_pill := PanelContainer.new()
	eq_count_pill.add_theme_stylebox_override("panel", UI_THEME.make_badge_box(Color(0.06, 0.09, 0.14, 0.95), UI_THEME.BORDER_SUBTLE, 6))
	eq_header.add_child(eq_count_pill)
	_items_count_badge = _make_label("0 tárgy", 11, UI_THEME.MUTED)
	_items_count_badge.autowrap_mode = TextServer.AUTOWRAP_OFF
	eq_count_pill.add_child(_items_count_badge)

	var eq_hint := _make_label("Válassz tárgyat fejlesztéshez vagy bűvöléshez.", 12, UI_THEME.MUTED, true)
	left_column.add_child(eq_hint)

	var item_scroll := ScrollContainer.new()
	item_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	item_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	item_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	left_column.add_child(item_scroll)

	_items_container = VBoxContainer.new()
	_items_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_items_container.add_theme_constant_override("separation", 7)
	item_scroll.add_child(_items_container)

	# Right column: Mode tabs + Action content + Status banner
	var right_panel := PanelContainer.new()
	right_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right_panel.size_flags_stretch_ratio = 1.14
	right_panel.add_theme_stylebox_override(
		"panel",
		UI_THEME.make_card_box(UI_THEME.SURFACE_DARK, Color(accent_color.r, accent_color.g, accent_color.b, 0.45), 1, 12, 14.0, 12.0)
	)
	content.add_child(right_panel)

	var right_column := VBoxContainer.new()
	right_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right_column.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right_column.add_theme_constant_override("separation", 10)
	right_panel.add_child(right_column)

	_mode_buttons_row = HBoxContainer.new()
	_mode_buttons_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_mode_buttons_row.add_theme_constant_override("separation", 7)
	right_column.add_child(_mode_buttons_row)

	_mode_button_map.clear()
	for option in option_configs:
		var opt_id := StringName(option.get("id", ""))
		var option_button := Button.new()
		option_button.text = str(option.get("label", "Opció"))
		option_button.tooltip_text = str(option.get("description", ""))
		option_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		UI_THEME.style_compact_button(option_button, accent_color, opt_id == _mode, 38.0, 13)
		option_button.pressed.connect(_set_mode.bind(opt_id))
		_mode_buttons_row.add_child(option_button)
		_mode_button_map[opt_id] = option_button

	var action_scroll := ScrollContainer.new()
	action_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	action_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	action_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	right_column.add_child(action_scroll)

	_action_content = VBoxContainer.new()
	_action_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_action_content.add_theme_constant_override("separation", 10)
	action_scroll.add_child(_action_content)

	var status_bar := PanelContainer.new()
	status_bar.add_theme_stylebox_override(
		"panel",
		UI_THEME.make_card_box(Color(0.025, 0.04, 0.068, 0.96), UI_THEME.BORDER_SUBTLE, 1, 8, 12.0, 7.0)
	)
	right_column.add_child(status_bar)

	_status_label = _make_label("Válassz tárgyat és műveletet.", 13, UI_THEME.MUTED, true)
	_status_label.custom_minimum_size.y = 20
	status_bar.add_child(_status_label)


func _build_resource_strip() -> void:
	_material_value_labels.clear()
	for mat_id in SHARED_MATERIAL_IDS:
		var item_data := GameState.get_item_data(mat_id)
		var pill := PanelContainer.new()
		pill.add_theme_stylebox_override(
			"panel",
			UI_THEME.make_badge_box(Color(0.05, 0.075, 0.12, 0.96), UI_THEME.BORDER_SUBTLE, 8)
		)
		pill.tooltip_text = (item_data.display_name if item_data != null else String(mat_id)) + " (közös tár + hátizsák)"
		_resource_strip.add_child(pill)

		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 5)
		pill.add_child(row)

		var icon := TextureRect.new()
		icon.custom_minimum_size = Vector2(20, 20)
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
		if item_data != null and item_data.icon != null:
			icon.texture = item_data.icon
		row.add_child(icon)

		var count_lbl := _make_label("0", 13, UI_THEME.IVORY)
		count_lbl.autowrap_mode = TextServer.AUTOWRAP_OFF
		row.add_child(count_lbl)
		_material_value_labels[mat_id] = count_lbl

	# Gold pill
	var gold_pill := PanelContainer.new()
	gold_pill.add_theme_stylebox_override(
		"panel",
		UI_THEME.make_badge_box(Color(0.09, 0.075, 0.04, 0.96), UI_THEME.GOLD, 8)
	)
	gold_pill.tooltip_text = "Közös aranykészlet"
	_resource_strip.add_child(gold_pill)

	var gold_row := HBoxContainer.new()
	gold_row.add_theme_constant_override("separation", 6)
	gold_pill.add_child(gold_row)

	if ResourceLoader.exists(GOLD_ICON_PATH):
		var gold_icon := TextureRect.new()
		gold_icon.custom_minimum_size = Vector2(20, 20)
		gold_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		gold_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		gold_icon.texture = load(GOLD_ICON_PATH) as Texture2D
		gold_row.add_child(gold_icon)

	_gold_value_label = _make_label("0", 14, UI_THEME.GOLD)
	_gold_value_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	gold_row.add_child(_gold_value_label)


func _build_character_card() -> PanelContainer:
	var character_card := PanelContainer.new()
	character_card.add_theme_stylebox_override(
		"panel",
		UI_THEME.make_card_box(UI_THEME.SURFACE_CARD, Color(accent_color.r, accent_color.g, accent_color.b, 0.62), 1, 11, 12.0, 10.0)
	)
	character_card.custom_minimum_size.y = 122

	var character_row := HBoxContainer.new()
	character_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	character_row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	character_row.add_theme_constant_override("separation", 12)
	character_card.add_child(character_row)

	# Framed live animated hero portrait stage (same technique as CharacterWindow)
	_character_stage_panel = PanelContainer.new()
	_character_stage_panel.custom_minimum_size = Vector2(96, 96)
	_character_stage_panel.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_character_stage_panel.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_character_stage_panel.add_theme_stylebox_override("panel", _make_portrait_stage_box(accent_color))
	character_row.add_child(_character_stage_panel)

	var stage_stack := Control.new()
	stage_stack.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stage_stack.size_flags_vertical = Control.SIZE_EXPAND_FILL
	stage_stack.clip_contents = true
	_character_stage_panel.add_child(stage_stack)

	var vp_container := SubViewportContainer.new()
	vp_container.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	vp_container.stretch = true
	vp_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vp_container.focus_mode = Control.FOCUS_NONE
	stage_stack.add_child(vp_container)
	vp_container.set_process_input(false)
	vp_container.set_process_unhandled_input(false)
	vp_container.set_process_unhandled_key_input(false)

	_character_viewport = SubViewport.new()
	_character_viewport.transparent_bg = true
	_character_viewport.handle_input_locally = false
	_character_viewport.gui_disable_input = true
	_character_viewport.physics_object_picking = false
	_character_viewport.canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST
	_character_viewport.size = Vector2i(88, 88)
	_character_viewport.size_changed.connect(_center_character_sprite)
	vp_container.add_child(_character_viewport)

	_character_sprite = AnimatedSprite2D.new()
	_character_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_character_sprite.scale = Vector2(2.7, 2.7)
	_character_sprite.position = Vector2(44, 44)
	_character_viewport.add_child(_character_sprite)

	_character_portrait_fallback = TextureRect.new()
	_character_portrait_fallback.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_character_portrait_fallback.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_character_portrait_fallback.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_character_portrait_fallback.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_character_portrait_fallback.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_character_portrait_fallback.visible = false
	stage_stack.add_child(_character_portrait_fallback)

	var character_details := VBoxContainer.new()
	character_details.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	character_details.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	character_details.add_theme_constant_override("separation", 5)
	character_row.add_child(character_details)

	_character_name_label = _make_label("Nincs karakter", 18, UI_THEME.IVORY)
	_character_name_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	_character_name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	character_details.add_child(_character_name_label)

	_character_class_label = _make_label("Válassz karaktert a Táborban.", 12, accent_color.lightened(0.22))
	_character_class_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	_character_class_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	character_details.add_child(_character_class_label)

	# Sleek HP bar with overlaid label
	var hp_holder := Control.new()
	hp_holder.custom_minimum_size = Vector2(0, 18)
	hp_holder.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	character_details.add_child(hp_holder)

	_character_hp_bar = ProgressBar.new()
	_character_hp_bar.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_character_hp_bar.show_percentage = false
	var hp_bg := StyleBoxFlat.new()
	hp_bg.bg_color = Color(0.06, 0.08, 0.12, 0.96)
	hp_bg.border_color = Color(0.26, 0.34, 0.44, 0.8)
	hp_bg.set_border_width_all(1)
	hp_bg.set_corner_radius_all(5)
	var hp_fill := StyleBoxFlat.new()
	hp_fill.bg_color = Color(0.76, 0.22, 0.24, 0.95)
	hp_fill.set_corner_radius_all(4)
	_character_hp_bar.add_theme_stylebox_override("background", hp_bg)
	_character_hp_bar.add_theme_stylebox_override("fill", hp_fill)
	hp_holder.add_child(_character_hp_bar)

	_character_hp_text = _make_label("HP: 0 / 0", 11, UI_THEME.IVORY)
	_character_hp_text.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_character_hp_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_character_hp_text.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_character_hp_text.autowrap_mode = TextServer.AUTOWRAP_OFF
	hp_holder.add_child(_character_hp_text)

	_character_stats_row = HBoxContainer.new()
	_character_stats_row.add_theme_constant_override("separation", 6)
	character_details.add_child(_character_stats_row)

	return character_card


func _make_portrait_stage_box(border_color: Color) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = Color(0.018, 0.030, 0.052, 0.98)
	box.border_color = border_color
	box.set_border_width_all(2)
	box.set_corner_radius_all(10)
	box.content_margin_left = 3.0
	box.content_margin_right = 3.0
	box.content_margin_top = 3.0
	box.content_margin_bottom = 3.0
	box.shadow_color = Color(0.0, 0.0, 0.0, 0.4)
	box.shadow_size = 4
	return box


func _center_character_sprite() -> void:
	if _character_viewport == null or _character_sprite == null:
		return
	var vp_size := Vector2(_character_viewport.size)
	if vp_size.x <= 0.0 or vp_size.y <= 0.0:
		return
	var active := GameState.get_active_character()
	var center_offset := ClassVisualHelper.get_visual_center_offset(active.class_id, &"idle") if active != null else Vector2.ZERO
	_character_sprite.position = vp_size * 0.5 - center_offset * _character_sprite.scale


# -----------------------------------------------------------------------------
# Selection and panel refresh
# -----------------------------------------------------------------------------

func _set_mode(mode: StringName) -> void:
	_mode = mode
	for key in _mode_button_map.keys():
		var opt_id := key as StringName
		var btn := _mode_button_map[key] as Button
		if btn != null:
			UI_THEME.style_compact_button(btn, accent_color, opt_id == _mode, 38.0, 13)
	_refresh_all()


func _on_active_character_changed(_character_id: String) -> void:
	_selected_item = null
	if _status_label != null:
		_status_label.text = "Karakterváltás történt. Válassz tárgyat."
		_status_label.add_theme_color_override("font_color", UI_THEME.MUTED)
	_refresh_all()


func _refresh_all() -> void:
	if not is_node_ready() or _items_container == null:
		return
	_update_resource_strip()
	_update_character_card()

	var inventory := GameState.get_active_inventory()
	var equipped_items := GameState.get_character_equipment()
	var selected_is_owned := inventory != null and inventory.items.has(_selected_item)
	if not selected_is_owned:
		for equipped_item in equipped_items.values():
			if equipped_item == _selected_item:
				selected_is_owned = true
				break
	if _selected_item != null and not selected_is_owned:
		_selected_item = null

	_clear_children(_items_container)
	var items_to_display: Array[InventoryItem] = []
	for equipped_item in equipped_items.values():
		if equipped_item is InventoryItem and equipped_item.item_data != null and _is_equipment(equipped_item) and not items_to_display.has(equipped_item):
			items_to_display.append(equipped_item)
	if inventory != null:
		for item in inventory.items:
			if item != null and item.item_data != null and _is_equipment(item) and not items_to_display.has(item):
				items_to_display.append(item)

	if _items_count_badge != null:
		_items_count_badge.text = "%d tárgy" % items_to_display.size()

	for item in items_to_display:
		var is_equipped := equipped_items.values().has(item)
		_items_container.add_child(_create_equipment_list_card(item, is_equipped, item == _selected_item))

	if items_to_display.is_empty():
		var empty_card := PanelContainer.new()
		empty_card.add_theme_stylebox_override(
			"panel",
			UI_THEME.make_card_box(Color(0.03, 0.045, 0.072, 0.9), UI_THEME.BORDER_SUBTLE, 1, 9, 12.0, 14.0)
		)
		var empty_lbl := _make_label("Nincs fejleszthető fegyver vagy felszerelés a hátizsákban vagy a felszerelési helyeken.", 13, UI_THEME.MUTED, true)
		empty_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		empty_card.add_child(empty_lbl)
		_items_container.add_child(empty_card)

	_refresh_action_panel()


func _update_resource_strip() -> void:
	if _gold_value_label != null:
		_gold_value_label.text = "%d" % GameState.gold
	for key in _material_value_labels.keys():
		var mat_id := key as StringName
		var lbl := _material_value_labels[key] as Label
		if lbl != null:
			var count := GameState.get_item_count(mat_id, true)
			lbl.text = "%d" % count
			lbl.add_theme_color_override("font_color", UI_THEME.IVORY if count > 0 else UI_THEME.MUTED.darkened(0.25))


func _update_character_card() -> void:
	_clear_children(_character_stats_row)
	var character := GameState.get_active_character()
	if character == null:
		_character_name_label.text = "Nincs karakter"
		_character_class_label.text = "Válassz karaktert a Táborban."
		_character_hp_bar.max_value = 100.0
		_character_hp_bar.value = 0.0
		_character_hp_text.text = "HP: —"
		_character_sprite.sprite_frames = null
		_character_sprite.stop()
		_character_portrait_fallback.texture = null
		_character_portrait_fallback.visible = false
		_character_stage_panel.add_theme_stylebox_override("panel", _make_portrait_stage_box(UI_THEME.BORDER_SUBTLE))
		return

	var class_data := GameState.get_character_class(character.class_id)
	var class_display_name := class_data.display_name if class_data != null else String(character.class_id)
	var portrait_accent: Color = class_data.placeholder_color.lightened(0.25) if class_data != null else accent_color
	_character_stage_panel.add_theme_stylebox_override("panel", _make_portrait_stage_box(portrait_accent))

	var frames := ClassVisualHelper.get_sprite_frames(character.class_id)
	if frames != null:
		_character_sprite.sprite_frames = frames
		_character_portrait_fallback.visible = false
		_center_character_sprite()
		call_deferred("_center_character_sprite")
		if frames.has_animation(&"idle"):
			_character_sprite.play(&"idle")
		elif frames.has_animation(&"default"):
			_character_sprite.play(&"default")
	else:
		_character_sprite.sprite_frames = null
		_character_sprite.stop()
		_character_portrait_fallback.texture = ClassVisualHelper.get_portrait_texture(character.class_id, class_data)
		_character_portrait_fallback.visible = _character_portrait_fallback.texture != null

	var display_name := GameState.get_character_display_name(character)
	_character_name_label.text = display_name
	_character_name_label.tooltip_text = display_name
	_character_name_label.add_theme_font_size_override("font_size", 15 if display_name.length() > 24 else 18)

	_character_class_label.text = "%s  ·  %d. szint" % [class_display_name, character.level]

	var stats := GameState.get_character_stats(character)
	var max_hp := maxi(1, int(round(float(stats.get("max_health", character.current_health)))))
	var cur_hp := clampi(character.current_health if character.current_health >= 0 else max_hp, 0, max_hp)
	_character_hp_bar.max_value = float(max_hp)
	_character_hp_bar.value = float(cur_hp)
	_character_hp_text.text = "HP: %d / %d" % [cur_hp, max_hp]

	var dmg_min := int(round(float(stats.get("damage_min", 0))))
	var dmg_max := int(round(float(stats.get("damage_max", 0))))
	var def_val := int(round(float(stats.get("defense", 0))))
	var spd_val := snappedf(float(stats.get("speed", 0.0)), 0.1)

	_character_stats_row.add_child(_make_mini_stat_chip("Sebzés", "%d–%d" % [dmg_min, dmg_max], Color(0.95, 0.62, 0.42, 1.0)))
	_character_stats_row.add_child(_make_mini_stat_chip("Véd.", "%d" % def_val, Color(0.55, 0.80, 0.96, 1.0)))
	_character_stats_row.add_child(_make_mini_stat_chip("Kezd.", "%s" % _format_number(spd_val), UI_THEME.GOLD))


func _create_equipment_list_card(item: InventoryItem, is_equipped: bool, is_selected: bool) -> Button:
	var card := Button.new()
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.custom_minimum_size = Vector2(0, 62)
	card.focus_mode = Control.FOCUS_NONE
	card.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	card.tooltip_text = item.item_data.description + "\n" + _format_stats(GameState.get_item_stats(item))

	var bg_normal := Color(0.085, 0.095, 0.135, 0.98) if is_selected else UI_THEME.SURFACE_CARD
	var border_normal := accent_color if is_selected else (Color(0.32, 0.56, 0.42, 0.82) if is_equipped else UI_THEME.BORDER_SUBTLE)
	var border_w := 2 if is_selected else 1
	card.add_theme_stylebox_override("normal", UI_THEME.make_card_box(bg_normal, border_normal, border_w, 10, 0.0, 0.0))
	card.add_theme_stylebox_override("hover", UI_THEME.make_card_box(UI_THEME.SURFACE_ELEVATED, accent_color.lightened(0.18), border_w, 10, 0.0, 0.0))
	card.add_theme_stylebox_override("pressed", UI_THEME.make_card_box(Color(0.03, 0.05, 0.085, 1.0), accent_color, 2, 10, 0.0, 0.0))
	card.pressed.connect(_select_item.bind(item))

	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 9)
	margin.add_theme_constant_override("margin_right", 10)
	margin.add_theme_constant_override("margin_top", 7)
	margin.add_theme_constant_override("margin_bottom", 7)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(margin)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_child(row)

	var icon_well := PanelContainer.new()
	icon_well.custom_minimum_size = Vector2(46, 46)
	icon_well.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	icon_well.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon_well.add_theme_stylebox_override(
		"panel",
		UI_THEME.make_card_box(Color(0.02, 0.032, 0.056, 0.98), accent_color if is_selected else UI_THEME.BORDER_SUBTLE, 1, 8, 4.0, 4.0)
	)
	row.add_child(icon_well)

	var icon_rect := TextureRect.new()
	icon_rect.texture = item.item_data.icon
	icon_rect.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	icon_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon_rect.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	icon_rect.size_flags_vertical = Control.SIZE_EXPAND_FILL
	icon_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon_well.add_child(icon_rect)

	var text_col := VBoxContainer.new()
	text_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text_col.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	text_col.add_theme_constant_override("separation", 3)
	text_col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(text_col)

	var top_line := HBoxContainer.new()
	top_line.add_theme_constant_override("separation", 6)
	top_line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	text_col.add_child(top_line)

	var name_lbl := _make_label(_get_item_display_name(item), 14, UI_THEME.GOLD if is_selected else UI_THEME.IVORY)
	name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_lbl.autowrap_mode = TextServer.AUTOWRAP_OFF
	name_lbl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	name_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top_line.add_child(name_lbl)

	if is_equipped:
		var eq_badge := PanelContainer.new()
		eq_badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
		eq_badge.add_theme_stylebox_override(
			"panel",
			UI_THEME.make_badge_box(Color(0.06, 0.18, 0.11, 0.96), UI_THEME.EMERALD.darkened(0.15), 5)
		)
		top_line.add_child(eq_badge)
		var eq_lbl := _make_label("FELSZERELVE", 10, UI_THEME.EMERALD)
		eq_lbl.autowrap_mode = TextServer.AUTOWRAP_OFF
		eq_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		eq_badge.add_child(eq_lbl)

	var stats_summary := _format_stats_compact(GameState.get_item_stats(item))
	var sub_text := _get_item_type_label(item.item_data.item_type)
	if not stats_summary.is_empty():
		sub_text += "  ·  " + stats_summary
	var sub_lbl := _make_label(sub_text, 11, UI_THEME.MUTED)
	sub_lbl.autowrap_mode = TextServer.AUTOWRAP_OFF
	sub_lbl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	sub_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	text_col.add_child(sub_lbl)

	return card


func _select_item(item: InventoryItem) -> void:
	_selected_item = item
	_status_label.text = "Kiválasztva: %s" % _get_item_display_name(item)
	_status_label.add_theme_color_override("font_color", UI_THEME.IVORY)
	_refresh_all()


# -----------------------------------------------------------------------------
# Data-driven crafting, upgrade and enchant panels
# -----------------------------------------------------------------------------

func _refresh_action_panel() -> void:
	if _action_content == null:
		return
	_clear_children(_action_content)

	var mode_config := _get_current_option()
	var mode_header := PanelContainer.new()
	mode_header.add_theme_stylebox_override(
		"panel",
		UI_THEME.make_card_box(Color(0.038, 0.056, 0.092, 0.92), Color(accent_color.r, accent_color.g, accent_color.b, 0.42), 1, 10, 12.0, 9.0)
	)
	_action_content.add_child(mode_header)

	var mode_box := VBoxContainer.new()
	mode_box.add_theme_constant_override("separation", 3)
	mode_header.add_child(mode_box)
	mode_box.add_child(_make_label(str(mode_config.get("label", "FEJLESZTÉS")), 18, UI_THEME.GOLD))
	var intro := _make_label(str(mode_config.get("description", "Válassz egy műveletet.")), 13, UI_THEME.MUTED, true)
	intro.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mode_box.add_child(intro)

	match _mode:
		&"craft":
			_refresh_crafting_options()
			return
		&"upgrade":
			_refresh_upgrade_options()
			return
		_:
			pass

	if _selected_item == null or _selected_item.item_data == null:
		_add_empty_selection_banner("Válassz egy fegyvert vagy felszerelést a bal oldali listából a bűvöléshez.")
		return

	_action_content.add_child(_build_selected_item_showcase(_selected_item))

	var enchantments := GameState.get_enchantments_for_workshop(workshop_type, _mode)
	var compatible_count := 0
	for enchantment in enchantments:
		var is_applicable := enchantment.applicable_item_types.is_empty() or enchantment.applicable_item_types.has(String(_selected_item.item_data.item_type))
		if not is_applicable:
			continue
		compatible_count += 1
		_add_enchantment_card(enchantment)
	if compatible_count == 0:
		_add_empty_selection_banner("Ehhez a tárgytípushoz ebben a kategóriában nincs megfelelő fejlesztés.")


func _build_selected_item_showcase(item: InventoryItem) -> PanelContainer:
	var card := PanelContainer.new()
	card.add_theme_stylebox_override(
		"panel",
		UI_THEME.make_card_box(Color(0.055, 0.080, 0.125, 0.96), accent_color, 1, 10, 12.0, 10.0)
	)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	card.add_child(row)

	var icon_well := PanelContainer.new()
	icon_well.custom_minimum_size = Vector2(56, 56)
	icon_well.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	icon_well.add_theme_stylebox_override(
		"panel",
		UI_THEME.make_card_box(Color(0.02, 0.032, 0.056, 0.98), accent_color.lightened(0.1), 1, 9, 5.0, 5.0)
	)
	row.add_child(icon_well)

	var icon_rect := TextureRect.new()
	icon_rect.texture = item.item_data.icon
	icon_rect.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	icon_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon_rect.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	icon_rect.size_flags_vertical = Control.SIZE_EXPAND_FILL
	icon_well.add_child(icon_rect)

	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.add_theme_constant_override("separation", 4)
	row.add_child(info)

	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 8)
	info.add_child(head)

	var title_lbl := _make_label(_get_item_display_name(item), 17, UI_THEME.IVORY)
	title_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_lbl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	title_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	head.add_child(title_lbl)

	var type_pill := PanelContainer.new()
	type_pill.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	type_pill.add_theme_stylebox_override("panel", UI_THEME.make_badge_box(Color(0.08, 0.11, 0.18, 0.95), accent_color.darkened(0.1), 6))
	head.add_child(type_pill)
	var type_lbl := _make_label(_get_item_type_label(item.item_data.item_type), 11, accent_color.lightened(0.22))
	type_pill.add_child(type_lbl)

	info.add_child(_make_label("Aktuális statok: %s" % _format_stats(GameState.get_item_stats(item)), 13, UI_THEME.IVORY, true))

	if not item.enchantment_ids.is_empty():
		var applied_names: Array[String] = []
		for applied_id in item.enchantment_ids:
			var applied_data := GameState.get_enchantment(StringName(applied_id))
			applied_names.append(applied_data.display_name if applied_data != null else applied_id)
		info.add_child(_make_label("Rúnák / fejlesztések: " + ", ".join(PackedStringArray(applied_names)), 12, UI_THEME.GOLD, true))

	return card


func _refresh_crafting_options() -> void:
	var recipes := GameState.get_smithing_recipes(&"craft")
	if recipes.is_empty():
		_add_empty_selection_banner("Nincs elérhető kovácsolási recept.")
		return
	for recipe in recipes:
		_add_recipe_card(recipe)


func _refresh_upgrade_options() -> void:
	if _selected_item == null or _selected_item.item_data == null:
		_add_empty_selection_banner("Válassz egy fejleszthető fegyvert vagy felszerelést a bal oldali listából.\nA fejlesztés +1-től +5-ig működik.")
		return

	_action_content.add_child(_build_selected_item_showcase(_selected_item))

	var next_level := _selected_item.upgrade_level + 1
	if not _selected_item.item_data.can_upgrade or _selected_item.amount != 1:
		_add_empty_selection_banner("Ez a tárgy nem fejleszthető tovább.")
		return
	if next_level > mini(_selected_item.item_data.max_upgrade_level, 5):
		_add_empty_selection_banner("A tárgy elérte a maximális (+%d) fejlesztési szintet!" % _selected_item.upgrade_level, UI_THEME.GOLD)
		return
	var recipe := _get_upgrade_recipe(next_level)
	if recipe == null:
		_add_empty_selection_banner("Hiányzik a +%d fejlesztési recept." % next_level)
		return

	var upgrade_card := PanelContainer.new()
	upgrade_card.add_theme_stylebox_override(
		"panel",
		UI_THEME.make_card_box(UI_THEME.SURFACE_CARD, accent_color.darkened(0.08), 1, 10, 14.0, 12.0)
	)
	_action_content.add_child(upgrade_card)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	upgrade_card.add_child(vbox)

	var tier_row := HBoxContainer.new()
	tier_row.add_theme_constant_override("separation", 8)
	vbox.add_child(tier_row)

	var tier_caption := _make_label("KÖVETKEZŐ SZINT:", 13, UI_THEME.MUTED)
	tier_caption.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	tier_row.add_child(tier_caption)
	var tier_pill := PanelContainer.new()
	tier_pill.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	tier_pill.add_theme_stylebox_override(
		"panel",
		UI_THEME.make_badge_box(Color(0.16, 0.11, 0.05, 0.96), accent_color, 6)
	)
	tier_row.add_child(tier_pill)
	var tier_lbl := _make_label("+%d  →  +%d" % [_selected_item.upgrade_level, next_level], 14, accent_color.lightened(0.24))
	tier_pill.add_child(tier_lbl)

	if not recipe.description.is_empty():
		vbox.add_child(_make_label(recipe.description, 13, UI_THEME.MUTED, true))

	vbox.add_child(_build_cost_chips(recipe.ingredient_item_ids, recipe.ingredient_amounts, recipe.gold_cost))

	var can_upgrade := GameState.can_upgrade_item(_selected_item)
	var action_row := HBoxContainer.new()
	action_row.add_theme_constant_override("separation", 10)
	vbox.add_child(action_row)

	var upgrade_button := Button.new()
	upgrade_button.text = "FEJLESZTÉS +%d" % next_level
	upgrade_button.custom_minimum_size = Vector2(210, 42)
	UI_THEME.style_compact_button(upgrade_button, accent_color, true, 42.0, 15)
	upgrade_button.disabled = not can_upgrade
	upgrade_button.pressed.connect(_on_upgrade_pressed)
	AudioManager.mark_custom_button_sfx(upgrade_button)
	action_row.add_child(upgrade_button)

	if not can_upgrade:
		var warn := _make_label("Nincs elég arany vagy alapanyag.", 13, UI_THEME.CRIMSON, true)
		warn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		warn.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		action_row.add_child(warn)


func _add_recipe_card(recipe: SmithingRecipeData) -> void:
	var can_craft := GameState.can_craft_recipe(recipe)
	var card := PanelContainer.new()
	card.add_theme_stylebox_override(
		"panel",
		UI_THEME.make_card_box(UI_THEME.SURFACE_CARD, accent_color.darkened(0.12) if can_craft else UI_THEME.BORDER_SUBTLE, 1, 10, 12.0, 10.0)
	)
	_action_content.add_child(card)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	card.add_child(row)

	var result_data := GameState.get_item_data(recipe.result_item_id)
	var icon_well := PanelContainer.new()
	icon_well.custom_minimum_size = Vector2(54, 54)
	icon_well.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	icon_well.add_theme_stylebox_override(
		"panel",
		UI_THEME.make_card_box(Color(0.02, 0.032, 0.056, 0.98), accent_color.darkened(0.15), 1, 9, 5.0, 5.0)
	)
	row.add_child(icon_well)

	var icon_rect := TextureRect.new()
	icon_rect.texture = result_data.icon if result_data != null else null
	icon_rect.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	icon_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon_rect.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	icon_rect.size_flags_vertical = Control.SIZE_EXPAND_FILL
	icon_well.add_child(icon_rect)

	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.add_theme_constant_override("separation", 5)
	row.add_child(info)

	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 8)
	info.add_child(head)
	var recipe_title := _make_label(recipe.display_name, 16, UI_THEME.IVORY)
	recipe_title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	head.add_child(recipe_title)
	if result_data != null:
		var type_pill := PanelContainer.new()
		type_pill.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		type_pill.add_theme_stylebox_override("panel", UI_THEME.make_badge_box(Color(0.07, 0.10, 0.15, 0.95), UI_THEME.BORDER_SUBTLE, 5))
		head.add_child(type_pill)
		var type_lbl := _make_label(_get_item_type_label(result_data.item_type), 11, accent_color.lightened(0.22))
		type_pill.add_child(type_lbl)

	if not recipe.description.is_empty():
		info.add_child(_make_label(recipe.description, 12, UI_THEME.MUTED, true))

	info.add_child(_build_cost_chips(recipe.ingredient_item_ids, recipe.ingredient_amounts, recipe.gold_cost))

	var btn_col := VBoxContainer.new()
	btn_col.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	btn_col.alignment = BoxContainer.ALIGNMENT_CENTER
	btn_col.add_theme_constant_override("separation", 4)
	row.add_child(btn_col)

	var craft_button := Button.new()
	craft_button.text = "KÉSZÍTÉS"
	craft_button.custom_minimum_size = Vector2(132, 42)
	UI_THEME.style_compact_button(craft_button, accent_color, true, 42.0, 14)
	craft_button.disabled = not can_craft
	craft_button.pressed.connect(_on_craft_pressed.bind(recipe.id))
	AudioManager.mark_custom_button_sfx(craft_button)
	btn_col.add_child(craft_button)

	if not can_craft:
		var miss_lbl := _make_label("Hiányzó feltétel", 11, UI_THEME.CRIMSON)
		miss_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		btn_col.add_child(miss_lbl)


func _add_enchantment_card(enchantment: EnchantmentData) -> void:
	var already_applied := _selected_item.enchantment_ids.has(String(enchantment.id))
	var can_apply := GameState.can_apply_enchantment(_selected_item, enchantment.id)
	var border_col := UI_THEME.EMERALD.darkened(0.15) if already_applied else (accent_color.darkened(0.10) if can_apply else UI_THEME.BORDER_SUBTLE)

	var card := PanelContainer.new()
	card.add_theme_stylebox_override(
		"panel",
		UI_THEME.make_card_box(UI_THEME.SURFACE_CARD, border_col, 1, 10, 12.0, 10.0)
	)
	_action_content.add_child(card)

	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 12)
	card.add_child(line)

	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.add_theme_constant_override("separation", 5)
	line.add_child(info)

	var title_row := HBoxContainer.new()
	title_row.add_theme_constant_override("separation", 8)
	info.add_child(title_row)
	var ench_title := _make_label(enchantment.display_name, 16, UI_THEME.EMERALD if already_applied else UI_THEME.IVORY)
	ench_title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	title_row.add_child(ench_title)

	if already_applied:
		var applied_pill := PanelContainer.new()
		applied_pill.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		applied_pill.add_theme_stylebox_override("panel", UI_THEME.make_badge_box(Color(0.06, 0.18, 0.11, 0.96), UI_THEME.EMERALD, 5))
		title_row.add_child(applied_pill)
		var applied_lbl := _make_label("AKTÍV", 10, UI_THEME.EMERALD)
		applied_pill.add_child(applied_lbl)

	if not enchantment.description.is_empty():
		info.add_child(_make_label(enchantment.description, 12, UI_THEME.MUTED, true))

	var effect_pill := PanelContainer.new()
	effect_pill.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	effect_pill.add_theme_stylebox_override(
		"panel",
		UI_THEME.make_badge_box(Color(0.06, 0.08, 0.13, 0.95), Color(accent_color.r, accent_color.g, accent_color.b, 0.55), 6)
	)
	info.add_child(effect_pill)
	effect_pill.add_child(_make_label("Hatás: %s" % _format_stats(enchantment.stat_modifiers), 12, accent_color.lightened(0.24), true))

	info.add_child(_build_cost_chips(enchantment.ingredient_item_ids, enchantment.ingredient_amounts, enchantment.gold_cost))

	var btn_col := VBoxContainer.new()
	btn_col.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	btn_col.alignment = BoxContainer.ALIGNMENT_CENTER
	btn_col.add_theme_constant_override("separation", 4)
	line.add_child(btn_col)

	var apply_button := Button.new()
	apply_button.custom_minimum_size = Vector2(138, 42)
	apply_button.text = "ALKALMAZVA" if already_applied else "ALKALMAZÁS"
	UI_THEME.style_compact_button(apply_button, accent_color, not already_applied, 42.0, 14)
	apply_button.disabled = already_applied or not can_apply
	apply_button.pressed.connect(_on_apply_pressed.bind(enchantment.id))
	AudioManager.mark_custom_button_sfx(apply_button)
	btn_col.add_child(apply_button)

	if not already_applied and not can_apply:
		var miss_lbl := _make_label("Nincs elég forrás", 11, UI_THEME.CRIMSON)
		miss_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		btn_col.add_child(miss_lbl)


func _build_cost_chips(item_ids: PackedStringArray, amounts: PackedInt32Array, gold_cost: int) -> HFlowContainer:
	var flow := HFlowContainer.new()
	flow.add_theme_constant_override("h_separation", 6)
	flow.add_theme_constant_override("v_separation", 5)

	for i in range(mini(item_ids.size(), amounts.size())):
		var item_id := StringName(item_ids[i])
		var needed := int(amounts[i])
		var owned := GameState.get_item_count(item_id, true)
		var enough := owned >= needed
		var data := GameState.get_item_data(item_id)
		var item_name := data.display_name if data != null else item_ids[i]
		var chip := _make_cost_chip(
			data.icon if data != null else null,
			"%s %d/%d" % [item_name, owned, needed],
			enough
		)
		flow.add_child(chip)

	var gold_tex: Texture2D = load(GOLD_ICON_PATH) as Texture2D if ResourceLoader.exists(GOLD_ICON_PATH) else null
	var gold_enough := GameState.gold >= gold_cost
	flow.add_child(_make_cost_chip(gold_tex, "%d arany" % gold_cost, gold_enough, true))
	return flow


func _make_cost_chip(icon_tex: Texture2D, text_val: String, affordable: bool, is_gold: bool = false) -> PanelContainer:
	var chip := PanelContainer.new()
	var border_col := (UI_THEME.GOLD if is_gold else UI_THEME.EMERALD.darkened(0.2)) if affordable else UI_THEME.CRIMSON.darkened(0.15)
	var bg_col := Color(0.05, 0.11, 0.08, 0.94) if (affordable and not is_gold) else (Color(0.11, 0.09, 0.04, 0.94) if (affordable and is_gold) else Color(0.14, 0.05, 0.05, 0.94))
	chip.add_theme_stylebox_override("panel", UI_THEME.make_badge_box(bg_col, border_col, 6))

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 5)
	chip.add_child(row)

	if icon_tex != null:
		var tex_rect := TextureRect.new()
		tex_rect.texture = icon_tex
		tex_rect.custom_minimum_size = Vector2(16, 16)
		tex_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tex_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		row.add_child(tex_rect)

	var text_col := (UI_THEME.GOLD if is_gold else UI_THEME.EMERALD) if affordable else UI_THEME.CRIMSON
	var lbl := _make_label(text_val, 12, text_col)
	row.add_child(lbl)
	return chip


func _add_empty_selection_banner(text_value: String, text_color: Color = UI_THEME.MUTED) -> void:
	var box := PanelContainer.new()
	box.add_theme_stylebox_override(
		"panel",
		UI_THEME.make_card_box(Color(0.032, 0.048, 0.078, 0.94), UI_THEME.BORDER_SUBTLE, 1, 10, 16.0, 22.0)
	)
	var lbl := _make_label(text_value, 14, text_color, true)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(lbl)
	_action_content.add_child(box)


func _get_upgrade_recipe(target_level: int) -> SmithingRecipeData:
	for recipe in GameState.get_smithing_recipes(&"upgrade"):
		if recipe.target_upgrade_level == target_level:
			return recipe
	return null


func _on_craft_pressed(recipe_id: StringName) -> void:
	for recipe in GameState.get_smithing_recipes(&"craft"):
		if recipe.id != recipe_id:
			continue
		if GameState.craft_recipe(recipe):
			AudioManager.sfx(&"smith_craft", 0.96, 1.05)
			_status_label.text = "Sikeres készítés: %s" % recipe.display_name
			_status_label.add_theme_color_override("font_color", UI_THEME.EMERALD)
		else:
			AudioManager.sfx(&"ui_error", 0.96, 1.04)
			_status_label.text = "Nem sikerült a készítés. Ellenőrizd az alapanyagokat, az aranyat és a szabad helyet."
			_status_label.add_theme_color_override("font_color", UI_THEME.CRIMSON)
		_refresh_all()
		return


func _on_upgrade_pressed() -> void:
	if _selected_item == null:
		return
	var target_level := _selected_item.upgrade_level + 1
	if GameState.upgrade_item(_selected_item):
		AudioManager.sfx(&"smith_upgrade", 0.96, 1.05)
		_status_label.text = "Sikeres fejlesztés: %s +%d" % [_selected_item.item_data.display_name, target_level]
		_status_label.add_theme_color_override("font_color", UI_THEME.EMERALD)
	else:
		AudioManager.sfx(&"ui_error", 0.96, 1.04)
		_status_label.text = "Nem sikerült a fejlesztés. Ellenőrizd az alapanyagokat és az aranyat."
		_status_label.add_theme_color_override("font_color", UI_THEME.CRIMSON)
	_refresh_all()


func _on_apply_pressed(enchantment_id: StringName) -> void:
	var enchantment := GameState.get_enchantment(enchantment_id)
	if _selected_item == null:
		return
	if GameState.apply_enchantment(_selected_item, enchantment_id):
		AudioManager.sfx(&"enchant_apply", 0.96, 1.05)
		_status_label.text = "Sikeresen alkalmazva: %s" % (enchantment.display_name if enchantment != null else String(enchantment_id))
		_status_label.add_theme_color_override("font_color", UI_THEME.EMERALD)
	else:
		AudioManager.sfx(&"ui_error", 0.96, 1.04)
		_status_label.text = "Nem sikerült. Ellenőrizd az aranyat, az alapanyagokat és a tárgytípust."
		_status_label.add_theme_color_override("font_color", UI_THEME.CRIMSON)
	_refresh_all()


# -----------------------------------------------------------------------------
# Presentation helpers
# -----------------------------------------------------------------------------

func _get_current_option() -> Dictionary:
	for option in option_configs:
		if StringName(option.get("id", "")) == _mode:
			return option
	return {}


func _is_equipment(item: InventoryItem) -> bool:
	if item == null or item.item_data == null:
		return false
	return item.item_data.item_type != &"material" and item.item_data.item_type != &"consumable" and item.item_data.item_type != &"ammo" and item.item_data.item_type != &"other"


func _get_item_display_name(item: InventoryItem) -> String:
	if item == null or item.item_data == null:
		return "Ismeretlen tárgy"
	var result := item.item_data.display_name
	if item.upgrade_level > 0:
		result += " +%d" % item.upgrade_level
	if not item.enchantment_ids.is_empty():
		result += " [%d rúna]" % item.enchantment_ids.size()
	if item.amount > 1:
		result += " ×%d" % item.amount
	return result


func _get_item_type_label(item_type: StringName) -> String:
	match item_type:
		&"weapon":
			return "Fegyver"
		&"armor":
			return "Páncél"
		&"ring":
			return "Gyűrű"
		&"earring":
			return "Fülbevaló"
		&"tool":
			return "Eszköz"
		&"shield":
			return "Pajzs"
		&"helmet":
			return "Sisak"
		&"boots":
			return "Csizma"
		&"gloves":
			return "Kesztyű"
		_:
			return String(item_type)


func _format_stats(stats: Dictionary) -> String:
	if stats.is_empty():
		return "Nincs megadott statbónusz."
	var keys: Array = stats.keys()
	keys.sort()
	var parts: Array[String] = []
	for key in keys:
		var value := float(stats[key])
		var sign_text := "+" if value >= 0.0 else ""
		parts.append("%s %s%s" % [_stat_label(String(key)), sign_text, _format_number(value)])
	return ", ".join(PackedStringArray(parts))


func _format_stats_compact(stats: Dictionary) -> String:
	if stats.is_empty():
		return ""
	var keys: Array = stats.keys()
	keys.sort()
	var parts: Array[String] = []
	for i in range(mini(keys.size(), 3)):
		var key := String(keys[i])
		var value := float(stats[key])
		var sign_text := "+" if value >= 0.0 else ""
		parts.append("%s %s%s" % [_stat_label(key), sign_text, _format_number(value)])
	if keys.size() > 3:
		parts.append("+%d" % (keys.size() - 3))
	return " · ".join(PackedStringArray(parts))


func _format_number(value: float) -> String:
	if is_equal_approx(value, round(value)):
		return str(int(round(value)))
	return "%.1f" % value


func _stat_label(key: String) -> String:
	var labels := {
		"damage": "Sebzés",
		"crit_chance": "Kritikus esély",
		"defense": "Védelem",
		"bleed_chance": "Vérzés esélye",
		"bleed_damage": "Vérzés sebzése",
		"max_bleed_stacks": "Max. vérzésréteg",
		"fire_damage": "Tűzsebzés",
		"ice_damage": "Jégsebzés",
		"poison_damage": "Méregsebzés",
		"fire_attack_bonus": "Tűztámadás bónusz",
		"ice_attack_bonus": "Jégtámadás bónusz",
		"poison_attack_bonus": "Méregtámadás bónusz",
		"fire_proc_chance": "Tűzhatás esélye",
		"ice_slow_chance": "Lassítás esélye",
		"poison_chance": "Mérgezés esélye",
		"fire_extra_attack_chance": "Tűz extra támadás esélye",
		"ice_extra_attack_chance": "Jég extra támadás esélye",
		"poison_extra_attack_chance": "Méreg extra támadás esélye",
		"lightning_damage": "Villámsebzés",
		"lightning_attack_bonus": "Villámtámadás bónusz",
		"lightning_extra_attack_chance": "Villám extra támadás esélye",
		"shock_chance": "Kábítás esélye",
		"fire_resistance": "Tűzellenállás",
		"ice_resistance": "Jégellenállás",
		"poison_resistance": "Méregellenállás",
		"max_health": "Max. életerő",
		"out_of_combat_hp_regen": "Harcon kívüli HP-regen.",
		"speed": "Sebesség"
	}
	return str(labels.get(key, key.replace("_", " ")))


func _make_section_heading(text_value: String, color: Color) -> Label:
	var lbl := Label.new()
	lbl.text = text_value
	lbl.add_theme_font_size_override("font_size", 12)
	lbl.add_theme_color_override("font_color", color)
	return lbl


func _make_mini_stat_chip(label_text: String, value_text: String, accent: Color) -> PanelContainer:
	var chip := PanelContainer.new()
	chip.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	chip.add_theme_stylebox_override(
		"panel",
		UI_THEME.make_badge_box(Color(0.032, 0.050, 0.082, 0.96), Color(accent.r, accent.g, accent.b, 0.45), 6)
	)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 4)
	chip.add_child(row)

	var l := _make_label(label_text + ":", 11, UI_THEME.MUTED)
	l.autowrap_mode = TextServer.AUTOWRAP_OFF
	row.add_child(l)
	var v := _make_label(value_text, 11, accent)
	v.autowrap_mode = TextServer.AUTOWRAP_OFF
	row.add_child(v)
	return chip


func _make_label(text_value: String, font_size: int, color: Color, wrap: bool = false) -> Label:
	var label := Label.new()
	label.text = text_value
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART if wrap else TextServer.AUTOWRAP_OFF
	return label


func _clear_children(parent: Node) -> void:
	for child in parent.get_children():
		parent.remove_child(child)
		child.queue_free()
