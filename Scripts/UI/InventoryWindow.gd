extends Panel

signal close_requested

const UI_THEME = preload("res://Scripts/UI/ui_theme.gd")
const CLASS_VISUAL_HELPER = preload("res://Scripts/Utils/ClassVisualHelper.gd")
const INVENTORY_ICON_PATH := "res://Assets/UI/Icons/inventory.png"
const GOLD_ICON_PATH := "res://Assets/Items/Currency/gold_coins.png"

const SLOT_ORDER: Array[StringName] = [&"weapon", &"shield", &"armor", &"ring", &"earring"]
const CHARACTER_FALLBACK_ICON: Texture2D = preload("res://Assets/UI/Icons/character.svg")
const SLOT_FALLBACK_ICONS := {
	&"weapon": preload("res://Assets/UI/Icons/equipment_weapon.svg"),
	&"shield": preload("res://Assets/UI/Icons/equipment_shield.svg"),
	&"armor": preload("res://Assets/UI/Icons/equipment_armor.svg"),
	&"ring": preload("res://Assets/UI/Icons/equipment_ring.svg"),
	&"earring": preload("res://Assets/UI/Icons/equipment_earring.svg")
}
const SLOT_LABELS := {
	&"weapon": "Fegyver",
	&"shield": "Pajzs",
	&"armor": "Páncél",
	&"ring": "Gyűrű",
	&"earring": "Fülbevaló"
}

var backpack_grid: InventoryGrid
var stash_grid: InventoryGrid
var stash_panel: PanelContainer = null
var title_label: Label
var gold_value_label: Label
var character_label: Label
var stats_label: Label
var feedback_label: Label
var item_details_label: Label
var use_button: Button
var equip_button: Button
var unequip_button: Button
var close_button: Button
var equipment_buttons: Dictionary = {}
var equipment_portrait_frame: PanelContainer
var equipment_portrait: TextureRect
var equipment_portrait_back: ColorRect
var selected_equipment_slot: StringName = &""
var selected_backpack_item: InventoryItem = null
var selected_stash_item: InventoryItem = null
var dungeon_mode: bool = false
var _is_refreshing: bool = false


func _ready() -> void:
	_build_interface()
	_bind_inventories()
	_apply_mode_layout()
	if not GameState.active_character_changed.is_connected(_on_active_character_changed):
		GameState.active_character_changed.connect(_on_active_character_changed)
	if not GameState.state_changed.is_connected(_on_state_changed):
		GameState.state_changed.connect(_on_state_changed)
	_refresh_all()


func set_dungeon_mode(enabled: bool) -> void:
	dungeon_mode = enabled
	_apply_mode_layout()
	if is_inside_tree():
		_refresh_all()


func refresh_window() -> void:
	if not is_inside_tree():
		return
	var active := GameState.get_active_character()
	if backpack_grid != null and active != null and backpack_grid.inventory != active.inventory:
		backpack_grid.clear_selection()
		backpack_grid.set_inventory(active.inventory)
		selected_backpack_item = null
	_apply_mode_layout()
	_refresh_all()


func _apply_mode_layout() -> void:
	if stash_panel != null:
		stash_panel.visible = not dungeon_mode
	if title_label != null:
		title_label.text = "HÁTIZSÁK ÉS FELSZERELÉS" if dungeon_mode else "FELSZERELÉS ÉS RAKTÁR"
	if backpack_grid != null:
		backpack_grid.set_peer_grid(null if dungeon_mode else stash_grid)
		backpack_grid.size_flags_horizontal = Control.SIZE_SHRINK_CENTER if dungeon_mode else Control.SIZE_SHRINK_BEGIN
	if stash_grid != null:
		stash_grid.set_peer_grid(null if dungeon_mode else backpack_grid)
		if dungeon_mode:
			stash_grid.clear_selection()
			selected_stash_item = null


func _build_interface() -> void:
	UI_THEME.style_window_shell(self, UI_THEME.GOLD)

	var margin := MarginContainer.new()
	margin.name = "InventoryMargin"
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 18)
	margin.add_theme_constant_override("margin_top", 12)
	margin.add_theme_constant_override("margin_right", 18)
	margin.add_theme_constant_override("margin_bottom", 14)
	add_child(margin)

	var layout := VBoxContainer.new()
	layout.name = "InventoryLayout"
	layout.add_theme_constant_override("separation", 9)
	margin.add_child(layout)

	# --- Unified Header Bar ---
	var header := HBoxContainer.new()
	header.custom_minimum_size.y = 42
	header.add_theme_constant_override("separation", 10)
	layout.add_child(header)

	if ResourceLoader.exists(INVENTORY_ICON_PATH):
		var icon_frame := PanelContainer.new()
		icon_frame.custom_minimum_size = Vector2(40, 40)
		icon_frame.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		icon_frame.add_theme_stylebox_override(
			"panel",
			UI_THEME.make_card_box(Color(0.05, 0.07, 0.11, 0.96), UI_THEME.GOLD, 1, 9, 5.0, 5.0)
		)
		header.add_child(icon_frame)

		var icon_rect := TextureRect.new()
		icon_rect.texture = load(INVENTORY_ICON_PATH) as Texture2D
		icon_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon_rect.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		icon_rect.size_flags_vertical = Control.SIZE_EXPAND_FILL
		icon_frame.add_child(icon_rect)

	title_label = _make_label("FELSZERELÉS ÉS RAKTÁR", 22, UI_THEME.GOLD)
	title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	header.add_child(title_label)

	# Gold pill
	var gold_pill := PanelContainer.new()
	gold_pill.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	gold_pill.add_theme_stylebox_override(
		"panel",
		UI_THEME.make_badge_box(Color(0.10, 0.08, 0.036, 0.96), UI_THEME.GOLD, 8)
	)
	header.add_child(gold_pill)
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
	gold_value_label = _make_label("0 arany", 14, UI_THEME.GOLD)
	gold_row.add_child(gold_value_label)

	close_button = Button.new()
	close_button.text = "BEZÁRÁS"
	close_button.custom_minimum_size = Vector2(120, 36)
	close_button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	UI_THEME.style_compact_button(close_button, UI_THEME.GOLD, false, 36.0, 13)
	close_button.pressed.connect(_on_close_button_pressed)
	AudioManager.mark_custom_button_sfx(close_button)
	header.add_child(close_button)

	var header_sep := ColorRect.new()
	header_sep.custom_minimum_size = Vector2(0, 1)
	header_sep.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header_sep.color = Color(UI_THEME.GOLD.r, UI_THEME.GOLD.g, UI_THEME.GOLD.b, 0.36)
	layout.add_child(header_sep)

	# --- Active Character Summary Banner ---
	var character_panel := _make_panel(UI_THEME.SURFACE_CARD, Color(UI_THEME.GOLD.r, UI_THEME.GOLD.g, UI_THEME.GOLD.b, 0.45))
	character_panel.custom_minimum_size.y = 72
	layout.add_child(character_panel)
	var character_content := VBoxContainer.new()
	character_content.add_theme_constant_override("separation", 3)
	_get_panel_content(character_panel).add_child(character_content)
	character_label = _make_label("AKTÍV KARAKTER", 16, UI_THEME.IVORY)
	character_content.add_child(character_label)
	stats_label = _make_label("A felszerelésből származó értékek itt jelennek meg.", 12, UI_THEME.MUTED)
	stats_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	character_content.add_child(stats_label)

	# --- Main 3-column workspace ---
	var main_row := HBoxContainer.new()
	main_row.name = "InventoryMainRow"
	main_row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	main_row.add_theme_constant_override("separation", 10)
	layout.add_child(main_row)

	_build_equipment_panel(main_row)
	_build_inventory_panel(main_row, "HÁTIZSÁK", false)
	stash_panel = _build_inventory_panel(main_row, "KÖZÖS RAKTÁR", true)

	# --- Footer Action Strip ---
	var footer_panel := _make_panel(UI_THEME.SURFACE_DARK, UI_THEME.BORDER_SUBTLE)
	footer_panel.custom_minimum_size.y = 66
	layout.add_child(footer_panel)
	var footer := HBoxContainer.new()
	footer.add_theme_constant_override("separation", 8)
	_get_panel_content(footer_panel).add_child(footer)

	item_details_label = _make_label("Válassz ki egy tárgyat a hátizsákból vagy a felszerelési helyek közül.", 12, UI_THEME.IVORY)
	item_details_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	item_details_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	item_details_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	footer.add_child(item_details_label)

	use_button = Button.new()
	use_button.text = "HASZNÁLAT"
	use_button.custom_minimum_size = Vector2(118, 40)
	use_button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	UI_THEME.style_compact_button(use_button, UI_THEME.EMERALD, true, 40.0, 13)
	use_button.pressed.connect(_on_use_pressed)
	AudioManager.mark_custom_button_sfx(use_button)
	footer.add_child(use_button)

	equip_button = Button.new()
	equip_button.text = "FELSZEREL"
	equip_button.custom_minimum_size = Vector2(118, 40)
	equip_button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	UI_THEME.style_compact_button(equip_button, UI_THEME.GOLD, true, 40.0, 13)
	equip_button.pressed.connect(_on_equip_pressed)
	AudioManager.mark_custom_button_sfx(equip_button)
	footer.add_child(equip_button)

	unequip_button = Button.new()
	unequip_button.text = "LEVÉTEL"
	unequip_button.custom_minimum_size = Vector2(106, 40)
	unequip_button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	UI_THEME.style_compact_button(unequip_button, UI_THEME.CRIMSON, false, 40.0, 13)
	unequip_button.pressed.connect(_on_unequip_pressed)
	AudioManager.mark_custom_button_sfx(unequip_button)
	footer.add_child(unequip_button)

	feedback_label = _make_label("Válassz ki egy tárgyat: gyógyitalhoz HASZNÁLAT (vagy jobb klikk), felszereléshez FELSZEREL.", 11, UI_THEME.MUTED)
	feedback_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	layout.add_child(feedback_label)


func _build_equipment_panel(parent: HBoxContainer) -> void:
	var panel := _make_panel(UI_THEME.SURFACE_DARK, Color(UI_THEME.GOLD.r, UI_THEME.GOLD.g, UI_THEME.GOLD.b, 0.48))
	panel.custom_minimum_size.x = 294
	panel.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	parent.add_child(panel)

	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 10)
	_get_panel_content(panel).add_child(content)

	var title_lbl := _make_label("HŐS FELSZERELÉSE", 14, UI_THEME.GOLD)
	title_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	content.add_child(title_lbl)

	var slots_grid := GridContainer.new()
	slots_grid.columns = 3
	slots_grid.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	slots_grid.add_theme_constant_override("h_separation", 10)
	slots_grid.add_theme_constant_override("v_separation", 10)
	content.add_child(slots_grid)

	# 1. sor: Fegyver  |  Hős portré  |  Gyűrű
	_add_equipment_slot(slots_grid, &"weapon")
	_add_equipment_character(slots_grid)
	_add_equipment_slot(slots_grid, &"ring")

	# 2. sor: Pajzs    |  Páncél      |  Fülbevaló
	_add_equipment_slot(slots_grid, &"shield")
	_add_equipment_slot(slots_grid, &"armor")
	_add_equipment_slot(slots_grid, &"earring")

	var slot_note := _make_label("Kattints egy helyre a felszerelt tárgy kijelöléséhez. A levett tárgy a hátizsákba kerül vissza.", 11, UI_THEME.MUTED)
	slot_note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	slot_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content.add_child(slot_note)


func _add_equipment_slot(parent: GridContainer, slot: StringName) -> void:
	var slot_button := Button.new()
	slot_button.custom_minimum_size = Vector2(78, 84)
	slot_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	slot_button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	slot_button.focus_mode = Control.FOCUS_NONE
	slot_button.text = ""
	slot_button.icon = null
	slot_button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_apply_equipment_slot_style(slot_button, UI_THEME.BORDER_SUBTLE, false)
	slot_button.pressed.connect(_on_equipment_slot_pressed.bind(slot))
	parent.add_child(slot_button)

	var margin := MarginContainer.new()
	margin.name = "SlotMargin"
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_theme_constant_override("margin_left", 6)
	margin.add_theme_constant_override("margin_top", 6)
	margin.add_theme_constant_override("margin_right", 6)
	margin.add_theme_constant_override("margin_bottom", 5)
	slot_button.add_child(margin)

	var slot_vbox := VBoxContainer.new()
	slot_vbox.name = "SlotVBox"
	slot_vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	slot_vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	slot_vbox.add_theme_constant_override("separation", 3)
	margin.add_child(slot_vbox)

	var icon_rect := TextureRect.new()
	icon_rect.name = "SlotIcon"
	icon_rect.custom_minimum_size = Vector2(46, 46)
	icon_rect.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	icon_rect.size_flags_vertical = Control.SIZE_EXPAND_FILL
	icon_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon_rect.texture = SLOT_FALLBACK_ICONS.get(slot, CHARACTER_FALLBACK_ICON)
	icon_rect.modulate = Color(0.75, 0.82, 0.94, 0.45)
	icon_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	slot_vbox.add_child(icon_rect)

	var caption := Label.new()
	caption.name = "SlotCaption"
	caption.text = str(SLOT_LABELS.get(slot, slot))
	caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	caption.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
	caption.add_theme_font_size_override("font_size", 10)
	caption.add_theme_color_override("font_color", UI_THEME.MUTED)
	slot_vbox.add_child(caption)

	var upgrade_badge := Label.new()
	upgrade_badge.name = "SlotUpgradeBadge"
	upgrade_badge.visible = false
	upgrade_badge.anchor_left = 1.0
	upgrade_badge.anchor_top = 0.0
	upgrade_badge.anchor_right = 1.0
	upgrade_badge.anchor_bottom = 0.0
	upgrade_badge.offset_left = -28.0
	upgrade_badge.offset_top = 3.0
	upgrade_badge.offset_right = -5.0
	upgrade_badge.offset_bottom = 17.0
	upgrade_badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	upgrade_badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	upgrade_badge.add_theme_font_size_override("font_size", 10)
	upgrade_badge.add_theme_color_override("font_color", UI_THEME.GOLD)
	slot_button.add_child(upgrade_badge)

	equipment_buttons[slot] = slot_button


func _apply_equipment_slot_style(button: Button, accent: Color, selected: bool) -> void:
	var normal_bg := Color(0.10, 0.08, 0.038, 0.96) if selected else Color(0.036, 0.060, 0.096, 0.95)
	var hover_bg := Color(0.14, 0.11, 0.052, 0.98) if selected else Color(0.075, 0.115, 0.172, 0.98)
	var pressed_bg := Color(0.06, 0.05, 0.028, 1.0) if selected else Color(0.024, 0.042, 0.072, 1.0)
	button.add_theme_stylebox_override("normal", UI_THEME.make_card_box(normal_bg, accent, 2, 10, 0.0, 0.0))
	button.add_theme_stylebox_override("hover", UI_THEME.make_card_box(hover_bg, accent.lightened(0.24), 2, 10, 0.0, 0.0))
	button.add_theme_stylebox_override("pressed", UI_THEME.make_card_box(pressed_bg, accent.darkened(0.08), 2, 10, 0.0, 0.0))
	button.add_theme_stylebox_override("focus", UI_THEME.make_card_box(Color(0.0, 0.0, 0.0, 0.0), accent.lightened(0.20), 2, 10, 0.0, 0.0))


func _add_equipment_character(parent: GridContainer) -> void:
	equipment_portrait_frame = PanelContainer.new()
	equipment_portrait_frame.custom_minimum_size = Vector2(96, 84)
	equipment_portrait_frame.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	equipment_portrait_frame.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	equipment_portrait_frame.add_theme_stylebox_override(
		"panel",
		UI_THEME.make_card_box(Color(0.018, 0.030, 0.052, 0.98), UI_THEME.GOLD, 2, 10, 4.0, 4.0)
	)
	parent.add_child(equipment_portrait_frame)

	var portrait_holder := Control.new()
	portrait_holder.custom_minimum_size = Vector2(86, 74)
	portrait_holder.clip_contents = true
	equipment_portrait_frame.add_child(portrait_holder)
	equipment_portrait_back = ColorRect.new()
	equipment_portrait_back.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	equipment_portrait_back.color = Color(0.03, 0.048, 0.082, 1.0)
	equipment_portrait_back.mouse_filter = Control.MOUSE_FILTER_IGNORE
	portrait_holder.add_child(equipment_portrait_back)
	equipment_portrait = TextureRect.new()
	equipment_portrait.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	equipment_portrait.offset_left = 6.0
	equipment_portrait.offset_top = 5.0
	equipment_portrait.offset_right = -6.0
	equipment_portrait.offset_bottom = -5.0
	equipment_portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	equipment_portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	equipment_portrait.texture = CHARACTER_FALLBACK_ICON
	equipment_portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
	portrait_holder.add_child(equipment_portrait)


func _build_inventory_panel(parent: HBoxContainer, heading: String, is_stash: bool) -> PanelContainer:
	var accent := Color(0.45, 0.66, 0.72, 0.55) if not is_stash else Color(0.55, 0.48, 0.76, 0.55)
	var panel := _make_panel(UI_THEME.SURFACE_DARK, accent)
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(panel)

	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 7)
	_get_panel_content(panel).add_child(content)
	var heading_label := _make_label(heading, 14, UI_THEME.GOLD)
	content.add_child(heading_label)

	var grid := InventoryGrid.new()
	grid.cell_size = 42
	grid.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	grid.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	content.add_child(grid)
	if is_stash:
		stash_grid = grid
		grid.item_selected.connect(_on_stash_item_selected)
	else:
		backpack_grid = grid
		grid.item_selected.connect(_on_backpack_item_selected)
		grid.item_right_clicked.connect(_on_backpack_item_right_clicked)
	grid.action_feedback.connect(_on_action_feedback)
	return panel


func _make_panel(background: Color, border: Color) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", UI_THEME.make_card_box(background, border, 1, 11, 0.0, 0.0))
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 11)
	margin.add_theme_constant_override("margin_top", 9)
	margin.add_theme_constant_override("margin_right", 11)
	margin.add_theme_constant_override("margin_bottom", 9)
	panel.add_child(margin)
	return _panel_content_container(panel)


func _panel_content_container(panel: PanelContainer) -> PanelContainer:
	# The VBox is attached to the inner MarginContainer, leaving the outer PanelContainer styled.
	var margin := panel.get_child(0) as MarginContainer
	if margin == null:
		push_error("InventoryWindow: a PanelContainer belső MarginContainer eleme hiányzik.")
		return panel
	var content := VBoxContainer.new()
	content.name = "PanelContent"
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	margin.add_child(content)
	panel.set_meta("content_node", content)
	return panel


func _get_panel_content(panel: PanelContainer) -> VBoxContainer:
	if panel == null or not is_instance_valid(panel):
		push_error("InventoryWindow: érvénytelen PanelContainer a tartalom lekérésekor.")
		return null
	var content := panel.get_meta("content_node", null) as VBoxContainer
	if content != null and is_instance_valid(content):
		return content
	content = _find_panel_content(panel)
	if content != null:
		panel.set_meta("content_node", content)
		return content
	var margin: MarginContainer = null
	for child in panel.get_children():
		if child is MarginContainer:
			margin = child as MarginContainer
			break
	if margin == null:
		margin = MarginContainer.new()
		margin.name = "PanelMargin"
		panel.add_child(margin)
	var repaired_content := VBoxContainer.new()
	repaired_content.name = "PanelContent"
	repaired_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	repaired_content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	margin.add_child(repaired_content)
	panel.set_meta("content_node", repaired_content)
	push_warning("InventoryWindow: hiányzó paneltartalom automatikusan létrehozva.")
	return repaired_content


func _find_panel_content(node: Node) -> VBoxContainer:
	for child in node.get_children():
		if child is VBoxContainer:
			return child as VBoxContainer
		var nested := _find_panel_content(child)
		if nested != null:
			return nested
	return null


func _make_label(value: String, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = value
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	return label


func _bind_inventories() -> void:
	backpack_grid.set_inventory(GameState.get_active_inventory())
	stash_grid.set_inventory(GameState.stash)
	backpack_grid.set_peer_grid(null if dungeon_mode else stash_grid)
	stash_grid.set_peer_grid(null if dungeon_mode else backpack_grid)


func _refresh_all() -> void:
	if _is_refreshing:
		return
	_is_refreshing = true
	if gold_value_label != null:
		gold_value_label.text = "%d arany" % GameState.gold
	var active := GameState.get_active_character()
	if active != null:
		if backpack_grid.inventory != active.inventory:
			backpack_grid.set_inventory(active.inventory)
		if selected_backpack_item != null and not active.inventory.items.has(selected_backpack_item):
			selected_backpack_item = null
	else:
		selected_backpack_item = null
	if selected_stash_item != null and (GameState.stash == null or not GameState.stash.items.has(selected_stash_item)):
		selected_stash_item = null
	stats_label.text = _format_character_stats(active)
	_refresh_equipment_slots(active)
	_refresh_selection_details()
	_is_refreshing = false


func _format_character_stats(character: CharacterProfile) -> String:
	if character == null:
		character_label.text = "NINCS AKTÍV KARAKTER"
		return "Hozz létre vagy válassz ki egy karaktert."
	var class_data := GameState.get_character_class(character.class_id)
	var class_label_text := class_data.display_name if class_data != null else String(character.class_id)
	var full_name := GameState.get_character_display_name(character)
	character_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	character_label.text = "%s  ·  %s  ·  %d. szint  ·  Stressz: %d" % [full_name.to_upper(), class_label_text, character.level, character.stress]
	var derived := GameState.get_character_stats(character)
	var base := character.base_stats
	var max_hp := int(round(float(derived.get("max_health", 0))))
	var base_max_hp := int(round(float(base.get("max_health", max_hp))))
	var current_hp := mini(character.current_health, max_hp)
	var base_damage_min := int(round(float(base.get("damage_min", 0))))
	var base_damage_max := int(round(float(base.get("damage_max", 0))))
	var final_damage_min := int(round(float(derived.get("damage_min", 0))))
	var final_damage_max := int(round(float(derived.get("damage_max", 0))))
	var damage_bonus := final_damage_min - base_damage_min
	var defense := int(round(float(derived.get("defense", 0))))
	var base_defense := int(round(float(base.get("defense", 0))))
	var defense_bonus := defense - base_defense
	var summary := "ÉP %d/%d (alap %d → %d)   ·   Sebzés %d–%d → %d–%d%s   ·   Védelem %d → %d%s   ·   Sebesség %s   ·   Pontosság %s%%   ·   Kritikus %s%%   ·   Kitérés %s%%   ·   Gyógyítás %s   ·   Stressztűrés %s%%" % [
		current_hp, max_hp, base_max_hp, max_hp,
		base_damage_min, base_damage_max, final_damage_min, final_damage_max, _format_bonus(damage_bonus),
		base_defense, defense, _format_bonus(defense_bonus),
		_format_stat(derived.get("speed", 0)),
		_format_stat(derived.get("accuracy", 0)),
		_format_stat(derived.get("crit_chance", 0)),
		_format_stat(derived.get("dodge", 0)),
		_format_stat(derived.get("healing_power", 0)),
		_format_stat(derived.get("stress_resistance", 0))
	]
	var core_stats := ["max_health", "damage_min", "damage_max", "damage", "defense", "speed", "accuracy", "crit_chance", "dodge", "healing_power", "stress_resistance"]
	var extra_parts: Array[String] = []
	for stat_key in derived.keys():
		if core_stats.has(String(stat_key)):
			continue
		var value := float(derived[stat_key])
		if not is_zero_approx(value):
			extra_parts.append("%s %s" % [_stat_name(String(stat_key)), _format_stat(value)])
	if not extra_parts.is_empty():
		summary += "   ·   " + "   ·   ".join(PackedStringArray(extra_parts))
	return summary


func _format_stat(value: Variant) -> String:
	var number := float(value)
	return str(int(round(number))) if is_equal_approx(number, round(number)) else String.num(number, 1)


func _format_bonus(value: int) -> String:
	if value > 0:
		return " (+%d)" % value
	if value < 0:
		return " (%d)" % value
	return ""


func _refresh_equipment_slots(character: CharacterProfile) -> void:
	_refresh_equipment_portrait(character)
	for slot in SLOT_ORDER:
		var button := equipment_buttons[slot] as Button
		var item: InventoryItem = GameState.get_equipped_item(slot, character) if character != null else null
		var slot_name := str(SLOT_LABELS[slot])
		var slot_icon: Texture2D = SLOT_FALLBACK_ICONS.get(slot, CHARACTER_FALLBACK_ICON)
		var has_item := item != null and item.item_data != null
		var has_custom_icon := has_item and item.item_data.icon != null

		var icon_rect := button.find_child("SlotIcon", true, false) as TextureRect
		var caption_lbl := button.find_child("SlotCaption", true, false) as Label
		var upgrade_lbl := button.find_child("SlotUpgradeBadge", true, false) as Label
		var slot_restricted: bool = (slot == &"shield" and character != null and not GameState.can_character_use_shield(character) and not has_item)

		if icon_rect != null:
			icon_rect.texture = item.item_data.icon if has_custom_icon else slot_icon
			icon_rect.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST if has_custom_icon else CanvasItem.TEXTURE_FILTER_PARENT_NODE
			if slot_restricted:
				icon_rect.modulate = Color(0.65, 0.36, 0.38, 0.32)
			else:
				icon_rect.modulate = Color.WHITE if has_item else Color(0.75, 0.82, 0.94, 0.45)
		if caption_lbl != null:
			caption_lbl.text = "Tiltva" if slot_restricted else slot_name
			if slot_restricted:
				caption_lbl.add_theme_color_override("font_color", Color(0.78, 0.45, 0.45, 0.85))
			else:
				caption_lbl.add_theme_color_override("font_color", UI_THEME.IVORY if has_item else UI_THEME.MUTED)
		if upgrade_lbl != null:
			if has_item and item.upgrade_level > 0:
				upgrade_lbl.text = "+%d" % item.upgrade_level
				upgrade_lbl.visible = true
			else:
				upgrade_lbl.visible = false

		if slot_restricted:
			var cls_data := GameState.get_character_class(character.class_id)
			var cls_name := cls_data.display_name if cls_data != null else String(character.class_id)
			button.tooltip_text = "%s – A(z) %s osztály nem használhat pajzsot (nincs blokkolás animáció)." % [slot_name, cls_name]
		else:
			button.tooltip_text = _item_tooltip(item) if has_item else (slot_name + " – üres felszerelési hely")
		button.text = ""
		button.icon = null
		var selected := selected_equipment_slot == slot
		var slot_accent: Color
		if slot_restricted:
			slot_accent = Color(0.55, 0.25, 0.28, 0.72) if selected else Color(0.35, 0.20, 0.24, 0.55)
		else:
			slot_accent = UI_THEME.GOLD if (selected or has_item) else UI_THEME.BORDER_SUBTLE
		_apply_equipment_slot_style(button, slot_accent, selected)
		button.focus_mode = Control.FOCUS_NONE
		button.custom_minimum_size = Vector2(78, 84)


func _refresh_equipment_portrait(character: CharacterProfile) -> void:
	if equipment_portrait == null or not is_instance_valid(equipment_portrait):
		return
	if character == null:
		equipment_portrait.texture_filter = CanvasItem.TEXTURE_FILTER_PARENT_NODE
		equipment_portrait.texture = CHARACTER_FALLBACK_ICON
		equipment_portrait_back.color = Color(0.03, 0.048, 0.082, 1.0)
		if equipment_portrait_frame != null:
			equipment_portrait_frame.add_theme_stylebox_override(
				"panel",
				UI_THEME.make_card_box(Color(0.018, 0.030, 0.052, 0.98), UI_THEME.BORDER_SUBTLE, 2, 10, 4.0, 4.0)
			)
		equipment_portrait.tooltip_text = "Nincs aktív karakter"
		return
	var class_data := GameState.get_character_class(character.class_id)
	var portrait := CLASS_VISUAL_HELPER.get_portrait_texture(character.class_id, class_data)
	if portrait != null:
		equipment_portrait.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		equipment_portrait.texture = portrait
	else:
		equipment_portrait.texture_filter = CanvasItem.TEXTURE_FILTER_PARENT_NODE
		equipment_portrait.texture = CHARACTER_FALLBACK_ICON
	var accent := class_data.placeholder_color.lightened(0.25) if class_data != null else UI_THEME.GOLD
	equipment_portrait_back.color = Color(accent.r * 0.16, accent.g * 0.18, accent.b * 0.24, 1.0)
	if equipment_portrait_frame != null:
		equipment_portrait_frame.add_theme_stylebox_override(
			"panel",
			UI_THEME.make_card_box(Color(0.018, 0.030, 0.052, 0.98), accent, 2, 10, 4.0, 4.0)
		)
	var class_label := class_data.display_name if class_data != null else String(character.class_id)
	equipment_portrait.tooltip_text = "%s – %s" % [character.character_name, class_label]


func _item_tooltip(item: InventoryItem) -> String:
	if item == null or item.item_data == null:
		return ""
	var result := item.item_data.display_name + "\n" + item.item_data.description
	var stats := GameState.get_item_stats(item)
	for key in stats:
		result += "\n%s: %s" % [_stat_name(String(key)), _format_stat(stats[key])]
	if item.upgrade_level > 0:
		result += "\nFejlesztés: +%d" % item.upgrade_level
	return result


func _stat_name(key: String) -> String:
	var names := {
		"damage": "Sebzés",
		"damage_min": "Min. sebzés",
		"damage_max": "Max. sebzés",
		"defense": "Védelem",
		"max_health": "Max. életerő",
		"speed": "Sebesség",
		"accuracy": "Pontosság",
		"crit_chance": "Kritikus esély",
		"dodge": "Kitérés",
		"healing_power": "Gyógyító erő",
		"heal_amount": "Gyógyítás",
		"stress_resistance": "Stressztűrés",
		"out_of_combat_hp_regen": "Harcon kívüli HP-regeneráció",
		"fire_resistance": "Tűzellenállás",
		"ice_resistance": "Jégellenállás",
		"poison_resistance": "Méregellenállás",
		"fire_damage": "Tűzsebzés",
		"ice_damage": "Jégsebzés",
		"poison_damage": "Méregsebzés",
		"lightning_damage": "Villámsebzés",
		"bleed_chance": "Vérzés esély",
		"bleed_damage": "Vérzés sebzés",
		"max_bleed_stacks": "Max. vérzésréteg",
		"fire_attack_bonus": "Tűztámadás bónusz",
		"ice_attack_bonus": "Jégtámadás bónusz",
		"poison_attack_bonus": "Méregtámadás bónusz",
		"lightning_attack_bonus": "Villámtámadás bónusz",
		"fire_proc_chance": "Tűz aktiválási esély",
		"ice_slow_chance": "Lassítás esély",
		"poison_chance": "Mérgezés esély",
		"shock_chance": "Sokkolás esély",
		"fire_extra_attack_chance": "Extra tűztámadás esély",
		"ice_extra_attack_chance": "Extra jégtámadás esély",
		"poison_extra_attack_chance": "Extra méregtámadás esély",
		"lightning_extra_attack_chance": "Extra villámtámadás esély"
	}
	return str(names.get(key, key.capitalize()))


func _refresh_selection_details() -> void:
	var selected: InventoryItem = selected_backpack_item if selected_backpack_item != null else selected_stash_item
	if selected_equipment_slot != &"":
		selected = GameState.get_equipped_item(selected_equipment_slot)
	if selected == null or selected.item_data == null:
		if selected_equipment_slot == &"shield" and not GameState.can_character_use_shield():
			var cls_active := GameState.get_active_character()
			var cls_data: CharacterClassData = GameState.get_character_class(cls_active.class_id) if cls_active != null else null
			var cls_name := cls_data.display_name if cls_data != null else "ez az osztály"
			item_details_label.text = "Pajzs  ·  A(z) %s osztály nem használhat pajzsot (nincs blokkolás animációja)." % cls_name
		else:
			item_details_label.text = "Válassz ki egy tárgyat. Fogyóeszközökhöz használd a HASZNÁLAT gombot (vagy jobb klikket), felszereléshez a FELSZEREL gombot."
	else:
		var source_text := "Felszerelve" if _is_selected_equipped() else ("Raktár" if selected == selected_stash_item else "Hátizsák")
		var stats := GameState.get_item_stats(selected)
		var parts: Array[String] = []
		for key in stats:
			parts.append("%s %s" % [_stat_name(String(key)), _format_bonus(int(round(float(stats[key])))) if float(stats[key]) >= 0 else _format_stat(stats[key])])
		var bonus_text := " · ".join(parts) if not parts.is_empty() else "Nincs statbónusz"
		var amount_suffix := " (×%d)" % selected.amount if selected.amount > 1 else ""
		var extra_hint := ""
		if selected == selected_backpack_item and GameState.is_consumable_item(selected) and not GameState.can_use_consumable_item(selected):
			var reason := GameState.get_use_consumable_failure_reason(selected)
			if not reason.is_empty():
				extra_hint = "  ·  [%s]" % reason
		elif selected == selected_backpack_item and selected.item_data.equipment_slot != &"" and selected.item_data.equipment_slot != &"none" and not GameState.can_equip_item(selected):
			var eq_reason := GameState.get_equip_item_failure_reason(selected)
			if not eq_reason.is_empty():
				extra_hint = "  ·  [%s]" % eq_reason
		item_details_label.text = "%s%s  ·  %s  ·  %s%s" % [selected.item_data.display_name, amount_suffix, source_text, bonus_text, extra_hint]
	if use_button != null:
		use_button.disabled = selected_backpack_item == null or not GameState.is_consumable_item(selected_backpack_item)
	equip_button.disabled = selected_backpack_item == null or not GameState.can_equip_item(selected_backpack_item)
	unequip_button.disabled = selected_equipment_slot == &"" or not GameState.can_unequip_item(selected_equipment_slot)


func _is_selected_equipped() -> bool:
	return selected_equipment_slot != &"" and GameState.get_equipped_item(selected_equipment_slot) != null


func _on_backpack_item_selected(item: InventoryItem) -> void:
	selected_backpack_item = item
	selected_stash_item = null
	selected_equipment_slot = &""
	_refresh_equipment_slots(GameState.get_active_character())
	_refresh_selection_details()


func _on_stash_item_selected(item: InventoryItem) -> void:
	selected_stash_item = item
	selected_backpack_item = null
	selected_equipment_slot = &""
	_refresh_equipment_slots(GameState.get_active_character())
	_refresh_selection_details()


func _on_equipment_slot_pressed(slot: StringName) -> void:
	selected_equipment_slot = slot
	selected_backpack_item = null
	selected_stash_item = null
	_refresh_equipment_slots(GameState.get_active_character())
	_refresh_selection_details()


func _on_backpack_item_right_clicked(item: InventoryItem) -> void:
	if item == null or item.item_data == null:
		return
	selected_backpack_item = item
	selected_stash_item = null
	selected_equipment_slot = &""
	if GameState.is_consumable_item(item):
		_use_consumable_item(item)
	elif GameState.can_equip_item(item):
		_on_equip_pressed()
	elif item.item_data.equipment_slot != &"" and item.item_data.equipment_slot != &"none":
		var reason := GameState.get_equip_item_failure_reason(item)
		AudioManager.sfx(&"ui_error", 0.96, 1.04)
		feedback_label.text = reason if not reason.is_empty() else "Nem lehet felszerelni."
		feedback_label.add_theme_color_override("font_color", UI_THEME.CRIMSON)
		_refresh_equipment_slots(GameState.get_active_character())
		_refresh_selection_details()
	else:
		_refresh_equipment_slots(GameState.get_active_character())
		_refresh_selection_details()


func _on_use_pressed() -> void:
	if selected_backpack_item == null:
		return
	_use_consumable_item(selected_backpack_item)


func _use_consumable_item(item: InventoryItem) -> void:
	if item == null:
		return
	var result: Dictionary = GameState.use_consumable_item(item)
	var ok := bool(result.get("ok", false))
	var msg := String(result.get("message", ""))
	if ok:
		AudioManager.sfx(&"potion_drink", 0.96, 1.06)
		if bool(result.get("consumed_stack", false)):
			selected_backpack_item = null
			backpack_grid.clear_selection()
		else:
			selected_backpack_item = item
			backpack_grid.select_item(item)
		feedback_label.text = msg
		feedback_label.add_theme_color_override("font_color", UI_THEME.EMERALD)
		_refresh_all()
	else:
		AudioManager.sfx(&"ui_error", 0.96, 1.04)
		feedback_label.text = msg if not msg.is_empty() else "A tárgy most nem használható."
		feedback_label.add_theme_color_override("font_color", UI_THEME.CRIMSON)
		_refresh_selection_details()


func _on_equip_pressed() -> void:
	if selected_backpack_item == null:
		return
	var item_name := selected_backpack_item.item_data.display_name if selected_backpack_item.item_data != null else "tárgy"
	if GameState.equip_item(selected_backpack_item):
		AudioManager.sfx(&"item_equip", 0.96, 1.05)
		selected_backpack_item = null
		selected_equipment_slot = &""
		feedback_label.text = "Felszerelve: " + item_name
		feedback_label.add_theme_color_override("font_color", UI_THEME.EMERALD)
		_refresh_all()
	else:
		var reason := GameState.get_equip_item_failure_reason(selected_backpack_item)
		AudioManager.sfx(&"ui_error", 0.96, 1.04)
		feedback_label.text = reason if not reason.is_empty() else "Nem lehet felszerelni: ellenőrizd a tárgy típusát és a hátizsákban lévő szabad helyet."
		feedback_label.add_theme_color_override("font_color", UI_THEME.CRIMSON)


func _on_unequip_pressed() -> void:
	if selected_equipment_slot == &"":
		return
	var slot_name := str(SLOT_LABELS.get(selected_equipment_slot, selected_equipment_slot))
	if GameState.unequip_item(selected_equipment_slot):
		AudioManager.sfx(&"item_unequip", 0.96, 1.05)
		selected_equipment_slot = &""
		feedback_label.text = slot_name + " levéve és visszahelyezve a hátizsákba."
		feedback_label.add_theme_color_override("font_color", UI_THEME.EMERALD)
		_refresh_all()
	else:
		AudioManager.sfx(&"ui_error", 0.96, 1.04)
		feedback_label.text = "Nincs elég hely a hátizsákban a felszerelés levételéhez."
		feedback_label.add_theme_color_override("font_color", UI_THEME.CRIMSON)


func _on_action_feedback(message: String, success: bool) -> void:
	feedback_label.text = message
	feedback_label.add_theme_color_override("font_color", UI_THEME.EMERALD if success else UI_THEME.CRIMSON)


func _input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventMouseMotion:
		backpack_grid.maybe_begin_drag_from_global_motion()
		if stash_grid != null and stash_grid.visible:
			stash_grid.maybe_begin_drag_from_global_motion()
		return
	if not (event is InputEventMouseButton):
		return
	if event.button_index != MOUSE_BUTTON_LEFT or event.pressed:
		return
	var source_grid: InventoryGrid = null
	if backpack_grid.dragging_item != null:
		source_grid = backpack_grid
	elif stash_grid != null and stash_grid.visible and stash_grid.dragging_item != null:
		source_grid = stash_grid
	if source_grid == null:
		return
	if source_grid.get_global_rect().has_point(event.global_position):
		return
	var target_grid: InventoryGrid = source_grid.peer_grid
	if target_grid != null and target_grid.visible and target_grid.get_global_rect().has_point(event.global_position):
		var target_mouse_position := target_grid.get_local_mouse_position()
		var hovered_cell := target_grid.get_cell_from_mouse_position(target_mouse_position)
		var target_cell := hovered_cell - source_grid.drag_offset
		target_grid.accept_external_drag(source_grid, target_cell, hovered_cell)
	else:
		source_grid.cancel_external_drag()


func _bind_active_inventories() -> void:
	var active := GameState.get_active_character()
	backpack_grid.clear_selection()
	stash_grid.clear_selection()
	backpack_grid.set_inventory(active.inventory if active != null else null)
	stash_grid.set_inventory(GameState.stash)
	selected_backpack_item = null
	selected_stash_item = null
	selected_equipment_slot = &""
	_refresh_all()


func _on_active_character_changed(_character_id: String) -> void:
	_bind_active_inventories()
	feedback_label.text = "Aktív karakter cserélve. A felszerelés és a statisztikák az adott hőshöz tartoznak."


func _on_state_changed() -> void:
	if not is_inside_tree() or _is_refreshing:
		return
	_refresh_all()


func _on_close_button_pressed() -> void:
	AudioManager.sfx(&"ui_window_close", 0.96, 1.04)
	if backpack_grid != null:
		backpack_grid.cancel_external_drag()
	if stash_grid != null:
		stash_grid.cancel_external_drag()
	close_requested.emit()
	hide()
