extends PanelContainer

const UI_THEME = preload("res://Scripts/UI/ui_theme.gd")

@onready var icon: TextureRect = $MarginContainer/HBoxContainer/Icon
@onready var item_name: Label = $MarginContainer/HBoxContainer/Info/Name
@onready var description: Label = $MarginContainer/HBoxContainer/Info/Description
@onready var price: Label = $MarginContainer/HBoxContainer/PricePanel/Price

var item_data: ItemData


func _ready() -> void:
	custom_minimum_size = Vector2(0, 92)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mouse_filter = Control.MOUSE_FILTER_PASS
	mouse_entered.connect(_on_mouse_entered)
	mouse_exited.connect(_on_mouse_exited)
	tooltip_text = "Húzd a tárgyat a karakter hátizsákjába a vásárláshoz."
	UI_THEME.style_panel(self, Color(0.52, 0.62, 0.72, 1.0), Color(0.035, 0.06, 0.09, 0.98))
	UI_THEME.style_panel($MarginContainer/HBoxContainer/PricePanel, UI_THEME.GOLD, Color(0.16, 0.11, 0.045, 0.98))
	item_name.add_theme_color_override("font_color", UI_THEME.IVORY)
	description.add_theme_color_override("font_color", UI_THEME.MUTED)
	price.add_theme_color_override("font_color", UI_THEME.GOLD)
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
			fallback_label.add_theme_font_size_override("font_size", 22)
			fallback_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
			icon.add_child(fallback_label)
		fallback_label.text = _get_initials(item_data.display_name)
		fallback_label.show()
	elif fallback_label != null:
		fallback_label.hide()
	item_name.text = item_data.display_name
	description.text = item_data.description
	price.text = "%d ARANY" % item_data.buy_price
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
	UI_THEME.style_panel(preview, UI_THEME.GOLD, Color(0.035, 0.06, 0.09, 0.96))

	var preview_icon := TextureRect.new()
	preview_icon.texture = item_data.icon
	preview_icon.custom_minimum_size = Vector2(64, 64)
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
	UI_THEME.style_panel(self, UI_THEME.GOLD, Color(0.075, 0.105, 0.14, 0.99))


func _on_mouse_exited() -> void:
	UI_THEME.style_panel(self, Color(0.52, 0.62, 0.72, 1.0), Color(0.035, 0.06, 0.09, 0.98))
