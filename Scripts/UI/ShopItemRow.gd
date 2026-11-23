extends PanelContainer

const UI_THEME = preload("res://Scripts/UI/ui_theme.gd")

@onready var icon: TextureRect = $MarginContainer/HBoxContainer/Icon
@onready var item_name: Label = $MarginContainer/HBoxContainer/Info/Name
@onready var description: Label = $MarginContainer/HBoxContainer/Info/Description
@onready var price: Label = $MarginContainer/HBoxContainer/PricePanel/Price
@onready var price_panel: PanelContainer = $MarginContainer/HBoxContainer/PricePanel
@onready var info_box: VBoxContainer = $MarginContainer/HBoxContainer/Info

var item_data: ItemData
var _meta_label: Label = null
var _is_hovered: bool = false


func _ready() -> void:
	custom_minimum_size = Vector2(0, 86)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mouse_filter = Control.MOUSE_FILTER_PASS
	mouse_default_cursor_shape = Control.CURSOR_DRAG
	mouse_entered.connect(_on_mouse_entered)
	mouse_exited.connect(_on_mouse_exited)
	tooltip_text = "Húzd a tárgyat a karakter hátizsákjába a vásárláshoz."

	_apply_row_style(false)
	price_panel.add_theme_stylebox_override(
		"panel",
		UI_THEME.make_badge_box(Color(0.10, 0.08, 0.036, 0.96), UI_THEME.GOLD, 7)
	)
	item_name.add_theme_color_override("font_color", UI_THEME.IVORY)
	item_name.add_theme_font_size_override("font_size", 15)
	description.add_theme_color_override("font_color", UI_THEME.MUTED)
	description.add_theme_font_size_override("font_size", 12)
	price.add_theme_color_override("font_color", UI_THEME.GOLD)
	price.add_theme_font_size_override("font_size", 13)

	_meta_label = Label.new()
	_meta_label.add_theme_color_override("font_color", Color(0.62, 0.84, 0.95, 0.92))
	_meta_label.add_theme_font_size_override("font_size", 11)
	_meta_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_meta_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_meta_label.visible = false
	info_box.add_child(_meta_label)

	# The row itself must receive the input so _get_drag_data is called even
	# when the pointer is over the icon or a label.
	_set_children_mouse_filter_ignore(self)


func setup_buy(new_item_data: ItemData) -> void:
	item_data = new_item_data
	if item_data == null:
		return

	icon.texture = item_data.icon
	var fallback_label := icon.get_node_or_null("FallbackLabel") as Label
	if item_data.icon == null:
		if fallback_label == null:
			fallback_label = Label.new()
			fallback_label.name = "FallbackLabel"
			fallback_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
			fallback_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			fallback_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			fallback_label.add_theme_color_override("font_color", UI_THEME.GOLD)
			fallback_label.add_theme_font_size_override("font_size", 20)
			fallback_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
			icon.add_child(fallback_label)
		fallback_label.text = _get_initials(item_data.display_name)
		fallback_label.show()
	elif fallback_label != null:
		fallback_label.hide()

	item_name.text = item_data.display_name
	description.text = item_data.description
	price.text = "%d ARANY" % item_data.buy_price

	var affordable := GameState.gold >= item_data.buy_price
	price.add_theme_color_override("font_color", UI_THEME.GOLD if affordable else UI_THEME.CRIMSON)
	price_panel.add_theme_stylebox_override(
		"panel",
		UI_THEME.make_badge_box(
			Color(0.10, 0.08, 0.036, 0.96) if affordable else Color(0.14, 0.05, 0.05, 0.96),
			UI_THEME.GOLD if affordable else UI_THEME.CRIMSON.darkened(0.15),
			7
		)
	)

	if _meta_label != null:
		var stat_text := _format_item_stats(item_data)
		var type_text := _type_label(item_data.item_type)
		_meta_label.text = type_text + ("  ·  " + stat_text if not stat_text.is_empty() else "")
		_meta_label.visible = true

	tooltip_text = "%s\n%s\nÁr: %d arany\nHúzd a bal oldali hátizsákba a vásárláshoz." % [
		item_data.display_name,
		item_data.description,
		item_data.buy_price
	]


func _get_drag_data(_at_position: Vector2) -> Variant:
	if item_data == null:
		return null

	var preview := PanelContainer.new()
	preview.custom_minimum_size = Vector2(76, 76)
	preview.mouse_filter = Control.MOUSE_FILTER_IGNORE
	preview.add_theme_stylebox_override("panel", UI_THEME.make_card_box(UI_THEME.SURFACE_DARK, UI_THEME.GOLD, 2, 10, 6.0, 6.0))

	var preview_icon := TextureRect.new()
	preview_icon.texture = item_data.icon
	preview_icon.custom_minimum_size = Vector2(60, 60)
	preview_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	preview_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	preview_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	preview.add_child(preview_icon)
	if item_data.icon == null:
		var fallback := Label.new()
		fallback.text = _get_initials(item_data.display_name)
		fallback.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		fallback.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		fallback.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		fallback.add_theme_color_override("font_color", UI_THEME.GOLD)
		fallback.add_theme_font_size_override("font_size", 20)
		fallback.mouse_filter = Control.MOUSE_FILTER_IGNORE
		preview.add_child(fallback)
	set_drag_preview(preview)

	return {
		"kind": "shop_purchase",
		"item_data": item_data,
		"amount": 1
	}


func _apply_row_style(hovered: bool) -> void:
	_is_hovered = hovered
	add_theme_stylebox_override(
		"panel",
		UI_THEME.make_card_box(
			UI_THEME.SURFACE_ELEVATED if hovered else UI_THEME.SURFACE_CARD,
			UI_THEME.GOLD if hovered else UI_THEME.BORDER_SUBTLE,
			1,
			10,
			0.0,
			0.0
		)
	)


func _format_item_stats(data: ItemData) -> String:
	if data == null or data.base_stats.is_empty():
		return ""
	var labels := {
		"damage": "Sebzés",
		"defense": "Védelem",
		"max_health": "HP",
		"speed": "Kezd.",
		"crit_chance": "Krit%",
		"dodge": "Kitérés%",
		"accuracy": "Pont.%",
		"healing_power": "Gyógyerő",
		"heal_amount": "Gyógyít",
		"stress_resistance": "Stresszt.%"
	}
	var parts: Array[String] = []
	for key in data.base_stats.keys():
		var val := float(data.base_stats[key])
		if is_zero_approx(val):
			continue
		var label := str(labels.get(String(key), String(key)))
		var val_str := str(int(round(val))) if is_equal_approx(val, round(val)) else "%.1f" % val
		var sign_str := "+" if val >= 0.0 else ""
		parts.append("%s %s%s" % [label, sign_str, val_str])
		if parts.size() >= 3:
			break
	return " · ".join(PackedStringArray(parts))


func _type_label(item_type: StringName) -> String:
	match item_type:
		&"weapon":
			return "Fegyver"
		&"armor":
			return "Páncél"
		&"shield":
			return "Pajzs"
		&"ring":
			return "Gyűrű"
		&"earring":
			return "Fülbevaló"
		&"material":
			return "Alapanyag"
		&"consumable":
			return "Fogyóeszköz"
		&"ammo":
			return "Lőszer"
		&"tool":
			return "Eszköz"
		_:
			return "Egyéb"


func _get_initials(display_name: String) -> String:
	var initials := ""
	for word in display_name.split(" ", false):
		if not word.is_empty():
			initials += word.substr(0, 1).to_upper()
			if initials.length() >= 3:
				break
	return initials if not initials.is_empty() else "?"


func _set_children_mouse_filter_ignore(node: Node) -> void:
	for child in node.get_children():
		if child is Control:
			(child as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE
		_set_children_mouse_filter_ignore(child)


func _on_mouse_entered() -> void:
	_apply_row_style(true)


func _on_mouse_exited() -> void:
	_apply_row_style(false)
