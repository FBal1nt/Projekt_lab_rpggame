extends CanvasLayer
class_name DungeonLootOverlay

const UI_THEME = preload("res://Scripts/UI/ui_theme.gd")
const GOLD_ICON: Texture2D = preload("res://Assets/Items/Currency/gold_coins.png")

const SLOT_SIZE := Vector2(82, 82)
const GRID_COLUMNS: int = 4

var _backdrop: ColorRect
var _bag_icon_rect: TextureRect
var _source_label: Label
var _grid_container: GridContainer
var _details_panel: PanelContainer
var _details_icon: TextureRect
var _details_title: Label
var _details_desc: Label
var _details_qty_badge: Label
var _details_dest_label: Label
var _collect_button: Button

var _entries: Array[Dictionary] = []
var _slot_buttons: Array[Button] = []
var _selected_index: int = -1
var _was_paused_before: bool = false
var _opened_frame: int = -1


func _ready() -> void:
	add_to_group("dungeon_loot")
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 112
	visible = false
	_build_ui()


func _input(event: InputEvent) -> void:
	if not visible or not is_inside_tree():
		return
	if Engine.get_process_frames() == _opened_frame:
		return
	if not (event is InputEventKey):
		return
	var key_event := event as InputEventKey
	if not key_event.pressed or key_event.echo:
		return

	var is_confirm: bool = (
		key_event.keycode == KEY_ESCAPE
		or key_event.physical_keycode == KEY_ESCAPE
		or key_event.keycode == KEY_ENTER
		or key_event.physical_keycode == KEY_ENTER
		or key_event.keycode == KEY_KP_ENTER
		or key_event.keycode == KEY_SPACE
		or _matches_interact_key(key_event)
	)
	if is_confirm:
		var vp := get_viewport()
		if vp != null:
			vp.set_input_as_handled()
		close_loot_window()


func _matches_interact_key(key_event: InputEventKey) -> bool:
	var sm := get_node_or_null("/root/SettingsManager")
	if sm != null and sm.has_method("matches_keybind"):
		return bool(sm.matches_keybind(key_event, "interact"))
	return key_event.keycode == KEY_E or key_event.physical_keycode == KEY_E


func _build_ui() -> void:
	_backdrop = ColorRect.new()
	_backdrop.name = "LootBackdrop"
	_backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_backdrop.color = Color(0.012, 0.02, 0.036, 0.78)
	_backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_backdrop)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_PASS
	_backdrop.add_child(center)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(440, 0)
	panel.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	UI_THEME.style_panel(panel, UI_THEME.GOLD, Color(0.03, 0.05, 0.085, 0.99))
	center.add_child(panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 24)
	margin.add_theme_constant_override("margin_top", 20)
	margin.add_theme_constant_override("margin_right", 24)
	margin.add_theme_constant_override("margin_bottom", 20)
	panel.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 12)
	margin.add_child(vbox)

	# Fejléc zsákikonnal + címmel
	var header := HBoxContainer.new()
	header.alignment = BoxContainer.ALIGNMENT_CENTER
	header.add_theme_constant_override("separation", 12)
	vbox.add_child(header)

	var icon_badge := PanelContainer.new()
	icon_badge.custom_minimum_size = Vector2(46, 46)
	icon_badge.add_theme_stylebox_override(
		"panel",
		UI_THEME.make_card_box(Color(0.06, 0.08, 0.13, 0.96), UI_THEME.GOLD, 1, 8, 4.0, 4.0)
	)
	header.add_child(icon_badge)

	_bag_icon_rect = TextureRect.new()
	_bag_icon_rect.custom_minimum_size = Vector2(34, 34)
	_bag_icon_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_bag_icon_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_bag_icon_rect.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	icon_badge.add_child(_bag_icon_rect)

	var title_box := VBoxContainer.new()
	title_box.add_theme_constant_override("separation", 2)
	header.add_child(title_box)

	var headline := Label.new()
	headline.text = "TALÁLT ZSÁKMÁNY"
	headline.add_theme_color_override("font_color", UI_THEME.GOLD)
	headline.add_theme_font_size_override("font_size", 22)
	title_box.add_child(headline)

	_source_label = Label.new()
	_source_label.text = "Ellenség  •  Kisebb zsák"
	_source_label.add_theme_color_override("font_color", UI_THEME.MUTED)
	_source_label.add_theme_font_size_override("font_size", 13)
	title_box.add_child(_source_label)

	var sep := HSeparator.new()
	sep.modulate = Color(UI_THEME.GOLD.r, UI_THEME.GOLD.g, UI_THEME.GOLD.b, 0.45)
	vbox.add_child(sep)

	# Négyzetes zsákmányrács (görgetés nélkül)
	var tray := PanelContainer.new()
	tray.add_theme_stylebox_override(
		"panel",
		UI_THEME.make_card_box(Color(0.018, 0.028, 0.052, 0.96), UI_THEME.BORDER_SUBTLE, 1, 10, 10.0, 10.0)
	)
	vbox.add_child(tray)

	var grid_center := CenterContainer.new()
	tray.add_child(grid_center)

	_grid_container = GridContainer.new()
	_grid_container.columns = GRID_COLUMNS
	_grid_container.add_theme_constant_override("h_separation", 8)
	_grid_container.add_theme_constant_override("v_separation", 8)
	grid_center.add_child(_grid_container)

	# Kijelölt elem részletei kártya
	_details_panel = PanelContainer.new()
	_details_panel.add_theme_stylebox_override(
		"panel",
		UI_THEME.make_card_box(Color(0.022, 0.036, 0.065, 0.96), Color(UI_THEME.GOLD.r, UI_THEME.GOLD.g, UI_THEME.GOLD.b, 0.55), 1, 9, 12.0, 10.0)
	)
	vbox.add_child(_details_panel)

	var details_row := HBoxContainer.new()
	details_row.add_theme_constant_override("separation", 12)
	_details_panel.add_child(details_row)

	var d_icon_box := PanelContainer.new()
	d_icon_box.custom_minimum_size = Vector2(46, 46)
	d_icon_box.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	d_icon_box.add_theme_stylebox_override(
		"panel",
		UI_THEME.make_card_box(Color(0.05, 0.07, 0.11, 0.96), Color(0.32, 0.38, 0.52, 0.85), 1, 7, 4.0, 4.0)
	)
	details_row.add_child(d_icon_box)

	_details_icon = TextureRect.new()
	_details_icon.custom_minimum_size = Vector2(34, 34)
	_details_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_details_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_details_icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	d_icon_box.add_child(_details_icon)

	var d_text_col := VBoxContainer.new()
	d_text_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	d_text_col.add_theme_constant_override("separation", 3)
	details_row.add_child(d_text_col)

	var d_top_row := HBoxContainer.new()
	d_top_row.add_theme_constant_override("separation", 8)
	d_text_col.add_child(d_top_row)

	_details_title = Label.new()
	_details_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_details_title.add_theme_color_override("font_color", UI_THEME.IVORY)
	_details_title.add_theme_font_size_override("font_size", 15)
	d_top_row.add_child(_details_title)

	_details_qty_badge = Label.new()
	_details_qty_badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_details_qty_badge.add_theme_color_override("font_color", UI_THEME.GOLD)
	_details_qty_badge.add_theme_font_size_override("font_size", 14)
	d_top_row.add_child(_details_qty_badge)

	_details_desc = Label.new()
	_details_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_details_desc.add_theme_color_override("font_color", UI_THEME.MUTED)
	_details_desc.add_theme_font_size_override("font_size", 12)
	d_text_col.add_child(_details_desc)

	_details_dest_label = Label.new()
	_details_dest_label.add_theme_color_override("font_color", Color(0.62, 0.88, 0.70, 1.0))
	_details_dest_label.add_theme_font_size_override("font_size", 11)
	d_text_col.add_child(_details_dest_label)

	var hint_lbl := Label.new()
	hint_lbl.text = "Kattints egy mezőre a zsákmány részleteinek megtekintéséhez."
	hint_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint_lbl.add_theme_color_override("font_color", UI_THEME.MUTED)
	hint_lbl.add_theme_font_size_override("font_size", 11)
	vbox.add_child(hint_lbl)

	_collect_button = Button.new()
	_collect_button.text = "BESZEDÉS [E / ESC]"
	UI_THEME.style_button(_collect_button, UI_THEME.GOLD, true, 42.0)
	_collect_button.custom_minimum_size = Vector2(240, 42)
	_collect_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_collect_button.alignment = HORIZONTAL_ALIGNMENT_CENTER
	_collect_button.add_theme_font_size_override("font_size", 14)
	_collect_button.pressed.connect(close_loot_window)
	vbox.add_child(_collect_button)


func show_loot(payload: Dictionary) -> void:
	if not is_inside_tree():
		return

	var enemy_name: String = String(payload.get("enemy_name", "Ellenség"))
	var bag_name: String = String(payload.get("bag_name", "Zsákmányzsák"))
	var bag_icon := payload.get("bag_icon", null) as Texture2D
	var gold_val: int = maxi(0, int(payload.get("gold", 0)))
	var items_arr: Array = payload.get("items", []) as Array

	if _source_label:
		_source_label.text = "%s  •  %s" % [enemy_name, bag_name]
	if _bag_icon_rect and bag_icon != null:
		_bag_icon_rect.texture = bag_icon

	_entries.clear()
	if gold_val > 0:
		_entries.append({
			"icon": GOLD_ICON,
			"name": "Aranyérme",
			"description": "Pénznem — felhasználható a táborban, a boltban és a műhelyekben.",
			"badge_text": "+%d" % gold_val,
			"detail_qty": "+%d arany" % gold_val,
			"dest": "Bekerült: Pénztárca",
			"accent": UI_THEME.GOLD
		})

	for entry in items_arr:
		if not (entry is Dictionary):
			continue
		var d: Dictionary = entry as Dictionary
		var item_name: String = String(d.get("display_name", "Alapanyag"))
		var desc: String = String(d.get("description", "Kovácsolási / bűvölési alapanyag."))
		var amt: int = int(d.get("amount", 0))
		var icon_tex := d.get("icon", null) as Texture2D
		var to_bp: int = int(d.get("added_to_backpack", 0))
		var to_stash: int = int(d.get("added_to_stash", 0))
		var dest_text := "Bekerült: Hátizsák"
		if to_stash > 0 and to_bp > 0:
			dest_text = "Bekerült: Hátizsák (%d) + Tábori raktár (%d)" % [to_bp, to_stash]
		elif to_stash > 0:
			dest_text = "Bekerült: Tábori raktár (a hátizsák megtelt)"
		_entries.append({
			"icon": icon_tex,
			"name": item_name,
			"description": desc,
			"badge_text": "×%d" % amt,
			"detail_qty": "+%d db" % amt,
			"dest": dest_text,
			"accent": Color(0.62, 0.90, 1.0, 1.0)
		})

	_rebuild_grid()
	_select_entry(0 if not _entries.is_empty() else -1)

	if not visible:
		_was_paused_before = get_tree().paused
		get_tree().paused = true
		visible = true

	_opened_frame = Engine.get_process_frames()
	AudioManager.sfx(&"ui_window_open", 0.98, 1.05)
	if _collect_button:
		_collect_button.grab_focus()


func _rebuild_grid() -> void:
	for child in _grid_container.get_children():
		child.queue_free()
	_slot_buttons.clear()

	var total_slots: int = maxi(GRID_COLUMNS, ceili(float(maxi(1, _entries.size())) / float(GRID_COLUMNS)) * GRID_COLUMNS)
	for idx in range(total_slots):
		var slot_btn := Button.new()
		slot_btn.custom_minimum_size = SLOT_SIZE
		slot_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		slot_btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		slot_btn.focus_mode = Control.FOCUS_NONE
		slot_btn.text = ""
		slot_btn.icon = null

		var has_entry: bool = idx < _entries.size()
		slot_btn.disabled = not has_entry
		slot_btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND if has_entry else Control.CURSOR_ARROW

		if has_entry:
			var entry: Dictionary = _entries[idx]
			slot_btn.tooltip_text = String(entry.get("name", ""))
			slot_btn.pressed.connect(_on_slot_pressed.bind(idx))

			var inner_margin := MarginContainer.new()
			inner_margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
			inner_margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
			inner_margin.add_theme_constant_override("margin_left", 8)
			inner_margin.add_theme_constant_override("margin_top", 8)
			inner_margin.add_theme_constant_override("margin_right", 8)
			inner_margin.add_theme_constant_override("margin_bottom", 8)
			slot_btn.add_child(inner_margin)

			var icon_rect := TextureRect.new()
			icon_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			icon_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			icon_rect.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
			icon_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
			var tex := entry.get("icon", null) as Texture2D
			if tex != null:
				icon_rect.texture = tex
			inner_margin.add_child(icon_rect)

			var qty_badge := Label.new()
			qty_badge.text = String(entry.get("badge_text", ""))
			qty_badge.anchor_left = 1.0
			qty_badge.anchor_top = 1.0
			qty_badge.anchor_right = 1.0
			qty_badge.anchor_bottom = 1.0
			qty_badge.offset_left = -46.0
			qty_badge.offset_top = -20.0
			qty_badge.offset_right = -5.0
			qty_badge.offset_bottom = -3.0
			qty_badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
			qty_badge.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
			qty_badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
			qty_badge.add_theme_font_size_override("font_size", 12)
			qty_badge.add_theme_color_override("font_color", entry.get("accent", UI_THEME.IVORY) as Color)
			qty_badge.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.95))
			qty_badge.add_theme_constant_override("shadow_offset_x", 1)
			qty_badge.add_theme_constant_override("shadow_offset_y", 1)
			slot_btn.add_child(qty_badge)

		_grid_container.add_child(slot_btn)
		_slot_buttons.append(slot_btn)

	_refresh_slot_styles()


func _refresh_slot_styles() -> void:
	for idx in range(_slot_buttons.size()):
		var btn: Button = _slot_buttons[idx]
		var has_entry: bool = idx < _entries.size()
		if not has_entry:
			var empty_box := UI_THEME.make_card_box(Color(0.02, 0.03, 0.05, 0.55), Color(0.20, 0.25, 0.34, 0.45), 1, 9, 0.0, 0.0)
			btn.add_theme_stylebox_override("normal", empty_box)
			btn.add_theme_stylebox_override("disabled", empty_box)
			continue

		var is_sel: bool = idx == _selected_index
		var accent: Color = UI_THEME.GOLD if is_sel else Color(0.36, 0.46, 0.62, 0.85)
		var normal_bg := Color(0.11, 0.088, 0.040, 0.98) if is_sel else Color(0.036, 0.058, 0.094, 0.96)
		var hover_bg := Color(0.15, 0.12, 0.055, 0.99) if is_sel else Color(0.075, 0.115, 0.172, 0.98)
		var pressed_bg := Color(0.08, 0.06, 0.03, 1.0) if is_sel else Color(0.024, 0.042, 0.072, 1.0)
		var w: int = 2 if is_sel else 1
		btn.add_theme_stylebox_override("normal", UI_THEME.make_card_box(normal_bg, accent, w, 9, 0.0, 0.0))
		btn.add_theme_stylebox_override("hover", UI_THEME.make_card_box(hover_bg, accent.lightened(0.24), w, 9, 0.0, 0.0))
		btn.add_theme_stylebox_override("pressed", UI_THEME.make_card_box(pressed_bg, accent.darkened(0.08), w, 9, 0.0, 0.0))
		btn.add_theme_stylebox_override("focus", UI_THEME.make_card_box(normal_bg, accent.lightened(0.20), w, 9, 0.0, 0.0))


func _on_slot_pressed(idx: int) -> void:
	AudioManager.sfx(&"ui_click", 0.96, 1.04)
	_select_entry(idx)


func _select_entry(idx: int) -> void:
	_selected_index = idx if (idx >= 0 and idx < _entries.size()) else -1
	_refresh_slot_styles()

	if _selected_index < 0:
		_details_icon.texture = null
		_details_title.text = "A zsák üres volt"
		_details_qty_badge.text = ""
		_details_desc.text = "Nem találtál felhasználható zsákmányt ebben a zsákban."
		_details_dest_label.text = ""
		return

	var entry: Dictionary = _entries[_selected_index]
	var tex := entry.get("icon", null) as Texture2D
	var accent: Color = entry.get("accent", UI_THEME.GOLD) as Color
	_details_icon.texture = tex
	_details_title.text = String(entry.get("name", ""))
	_details_qty_badge.text = String(entry.get("detail_qty", ""))
	_details_qty_badge.add_theme_color_override("font_color", accent)
	_details_desc.text = String(entry.get("description", ""))
	_details_dest_label.text = String(entry.get("dest", ""))


func close_loot_window() -> void:
	if not visible:
		return
	visible = false
	AudioManager.sfx(&"ui_window_close", 0.98, 1.04)
	if is_inside_tree():
		get_tree().paused = _was_paused_before
