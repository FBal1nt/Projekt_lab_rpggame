extends Panel

const UI_THEME = preload("res://Scripts/UI/ui_theme.gd")

var workshop_type: StringName = &""
var workshop_title: String = "MŰHELY"
var accent_color: Color = UI_THEME.GOLD
var option_configs: Array[Dictionary] = []

var _mode: StringName = &""
var _selected_item: InventoryItem
var _items_container: VBoxContainer
var _action_content: VBoxContainer
var _mode_buttons: HBoxContainer
var _status_label: Label
var _gold_label: Label
var _character_name_label: Label
var _character_detail_label: Label
var _character_portrait: TextureRect
var _character_fallback: Label
var _character_portrait_back: ColorRect

@onready var _title: Label = $Title
@onready var _close_button: Button = $CloseButton


func _configure_workshop() -> void:
	# Overridden by BlacksmithWindow.gd and WizardWindow.gd.
	pass


func _ready() -> void:
	_configure_workshop()
	if option_configs.is_empty():
		push_warning("Nincs megadva egyetlen műhelyopció sem: " + name)
	else:
		_mode = StringName(option_configs[0].get("id", ""))

	# A műhelyablak a tényleges viewporthoz igazodik, nem egy fix 1160x650-es
	# mérethez. Így kisebb ablakban sem lóg ki a fejléc vagy a Bezárás gomb.
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	offset_left = 8.0
	offset_top = 8.0
	offset_right = -8.0
	offset_bottom = -8.0
	UI_THEME.style_panel(self, accent_color, Color(0.025, 0.035, 0.05, 0.98))

	_title.text = workshop_title
	_title.anchor_left = 0.0
	_title.anchor_top = 0.0
	_title.anchor_right = 0.0
	_title.anchor_bottom = 0.0
	_title.position = Vector2(24, 12)
	_title.size = Vector2(720, 36)
	_title.autowrap_mode = TextServer.AUTOWRAP_OFF
	_title.add_theme_color_override("font_color", UI_THEME.GOLD)
	_title.add_theme_font_size_override("font_size", 26)
	_close_button.anchor_left = 1.0
	_close_button.anchor_top = 0.0
	_close_button.anchor_right = 1.0
	_close_button.anchor_bottom = 0.0
	_close_button.offset_left = -122.0
	_close_button.offset_top = 13.0
	_close_button.offset_right = -22.0
	_close_button.offset_bottom = 49.0
	_close_button.text = "BEZÁRÁS"
	_close_button.autowrap_mode = TextServer.AUTOWRAP_OFF
	UI_THEME.style_button(_close_button, accent_color)
	_close_button.custom_minimum_size = Vector2(100, 36)

	_build_interface()
	if not GameState.state_changed.is_connected(_refresh_all):
		GameState.state_changed.connect(_refresh_all)
	if not GameState.active_character_changed.is_connected(_on_active_character_changed):
		GameState.active_character_changed.connect(_on_active_character_changed)
	_refresh_all()


func _build_interface() -> void:
	var body := MarginContainer.new()
	body.name = "GeneratedAugmentationUI"
	body.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	body.offset_left = 20
	body.offset_top = 56
	body.offset_right = -20
	body.offset_bottom = -18
	add_child(body)

	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 8)
	body.add_child(outer)

	var top_info := HBoxContainer.new()
	top_info.custom_minimum_size.y = 28
	top_info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top_info.add_theme_constant_override("separation", 12)
	outer.add_child(top_info)
	var workshop_hint := _make_label("TÁRGYFEJLESZTÉS  /  VÁLASSZ KARAKTERTÁRGYAT ÉS MŰVELETET", 13, UI_THEME.MUTED)
	workshop_hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	workshop_hint.autowrap_mode = TextServer.AUTOWRAP_OFF
	top_info.add_child(workshop_hint)
	_gold_label = _make_label("Arany: 0", 17, UI_THEME.GOLD)
	_gold_label.custom_minimum_size = Vector2(140, 28)
	_gold_label.size_flags_horizontal = Control.SIZE_SHRINK_END
	_gold_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_gold_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_gold_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	_gold_label.clip_text = false
	top_info.add_child(_gold_label)

	var content := HBoxContainer.new()
	content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", 12)
	outer.add_child(content)

	# Left column: active character card above the inventory equipment list.
	var left_panel := PanelContainer.new()
	left_panel.custom_minimum_size.x = 370
	left_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	UI_THEME.style_panel(left_panel, accent_color.darkened(0.18), Color(0.04, 0.055, 0.075, 0.98))
	content.add_child(left_panel)
	var left_margin := MarginContainer.new()
	left_margin.add_theme_constant_override("margin_left", 4)
	left_margin.add_theme_constant_override("margin_right", 4)
	left_margin.add_theme_constant_override("margin_top", 4)
	left_margin.add_theme_constant_override("margin_bottom", 4)
	left_panel.add_child(left_margin)
	var left_column := VBoxContainer.new()
	left_column.add_theme_constant_override("separation", 8)
	left_margin.add_child(left_column)
	left_column.add_child(_make_label("AKTÍV KARAKTER", 16, UI_THEME.GOLD))

	var character_card := PanelContainer.new()
	UI_THEME.style_panel(character_card, accent_color.darkened(0.1), Color(0.025, 0.04, 0.06, 0.98))
	character_card.custom_minimum_size.y = 112
	left_column.add_child(character_card)
	var character_row := HBoxContainer.new()
	character_row.add_theme_constant_override("separation", 12)
	character_card.add_child(character_row)

	var portrait_holder := Control.new()
	portrait_holder.custom_minimum_size = Vector2(88, 92)
	portrait_holder.clip_contents = true
	character_row.add_child(portrait_holder)
	_character_portrait_back = ColorRect.new()
	_character_portrait_back.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_character_portrait_back.color = Color(0.20, 0.26, 0.31, 1.0)
	_character_portrait_back.mouse_filter = Control.MOUSE_FILTER_IGNORE
	portrait_holder.add_child(_character_portrait_back)
	_character_portrait = TextureRect.new()
	_character_portrait.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_character_portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_character_portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_character_portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
	portrait_holder.add_child(_character_portrait)
	_character_fallback = _make_label("?", 26, UI_THEME.IVORY)
	_character_fallback.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_character_fallback.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_character_fallback.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_character_fallback.mouse_filter = Control.MOUSE_FILTER_IGNORE
	portrait_holder.add_child(_character_fallback)

	var character_details := VBoxContainer.new()
	character_details.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	character_details.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	character_details.add_theme_constant_override("separation", 5)
	character_row.add_child(character_details)
	_character_name_label = _make_label("Nincs karakter", 20, UI_THEME.IVORY)
	character_details.add_child(_character_name_label)
	_character_detail_label = _make_label("Válassz karaktert a Lobbyban.", 12, UI_THEME.MUTED)
	_character_detail_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	character_details.add_child(_character_detail_label)

	left_column.add_child(_make_label("FEGYVEREK ÉS FELSZERELÉSEK", 15, UI_THEME.GOLD))
	left_column.add_child(_make_label("Válaszd ki azt a tárgyat, amelyre a fejlesztést alkalmazod.", 12, UI_THEME.MUTED))
	var item_scroll := ScrollContainer.new()
	item_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	item_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	item_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	left_column.add_child(item_scroll)
	_items_container = VBoxContainer.new()
	_items_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_items_container.add_theme_constant_override("separation", 5)
	item_scroll.add_child(_items_container)

	# Right column: exactly three workshop options and the selected option's effects.
	var right_panel := PanelContainer.new()
	right_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	UI_THEME.style_panel(right_panel, accent_color.darkened(0.18), Color(0.035, 0.05, 0.07, 0.98))
	content.add_child(right_panel)
	var right_margin := MarginContainer.new()
	right_margin.add_theme_constant_override("margin_left", 4)
	right_margin.add_theme_constant_override("margin_right", 4)
	right_margin.add_theme_constant_override("margin_top", 4)
	right_margin.add_theme_constant_override("margin_bottom", 4)
	right_panel.add_child(right_margin)
	var right_column := VBoxContainer.new()
	right_column.add_theme_constant_override("separation", 8)
	right_margin.add_child(right_column)
	right_column.add_child(_make_label(workshop_title, 18, UI_THEME.GOLD))
	_mode_buttons = HBoxContainer.new()
	_mode_buttons.add_theme_constant_override("separation", 7)
	right_column.add_child(_mode_buttons)
	for option in option_configs:
		var option_button := Button.new()
		option_button.text = str(option.get("label", "Opció"))
		option_button.tooltip_text = str(option.get("description", ""))
		option_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		option_button.custom_minimum_size.y = 50
		UI_THEME.style_button(option_button, accent_color, StringName(option.get("id", "")) == _mode)
		option_button.pressed.connect(_set_mode.bind(StringName(option.get("id", ""))))
		_mode_buttons.add_child(option_button)

	var action_scroll := ScrollContainer.new()
	action_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	action_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	action_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	right_column.add_child(action_scroll)
	_action_content = VBoxContainer.new()
	_action_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_action_content.add_theme_constant_override("separation", 9)
	action_scroll.add_child(_action_content)

	_status_label = _make_label("Válassz tárgyat, majd fejlesztést.", 13, UI_THEME.MUTED)
	_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status_label.custom_minimum_size.y = 24
	right_column.add_child(_status_label)


func _set_mode(mode: StringName) -> void:
	_mode = mode
	for child in _mode_buttons.get_children():
		if child is Button:
			var button := child as Button
			var button_mode: StringName = &""
			for option in option_configs:
				if str(option.get("label", "")) == button.text:
					button_mode = StringName(option.get("id", ""))
					break
			UI_THEME.style_button(button, accent_color, button_mode == _mode)
	_refresh_all()


func _on_active_character_changed(_character_id: String) -> void:
	_selected_item = null
	_status_label.text = "Karakterváltás történt. Válassz tárgyat."
	_refresh_all()


func _refresh_all() -> void:
	if not is_node_ready() or _items_container == null:
		return
	_update_character_card()
	_gold_label.text = "Arany: %d" % GameState.gold

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
	var eligible_item_count := 0
	var items_to_display: Array[InventoryItem] = []
	if inventory != null:
		for item in inventory.items:
			if item != null and item.item_data != null and _is_equipment(item):
				items_to_display.append(item)
	for equipped_item in equipped_items.values():
		if equipped_item is InventoryItem and equipped_item.item_data != null and _is_equipment(equipped_item) and not items_to_display.has(equipped_item):
			items_to_display.append(equipped_item)

	for item in items_to_display:
		eligible_item_count += 1
		var item_button := Button.new()
		item_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		item_button.custom_minimum_size.y = 48
		var is_equipped := equipped_items.values().has(item)
		item_button.text = _get_item_display_name(item) + ("  ·  FELSZERELVE" if is_equipped else "")
		item_button.tooltip_text = item.item_data.description + "\n" + _format_stats(GameState.get_item_stats(item))
		if item.item_data.icon != null:
			item_button.icon = item.item_data.icon
			item_button.expand_icon = true
			item_button.add_theme_constant_override("icon_max_width", 36)
		UI_THEME.style_button(item_button, accent_color, item == _selected_item)
		item_button.pressed.connect(_select_item.bind(item))
		_items_container.add_child(item_button)
	if eligible_item_count == 0:
		_items_container.add_child(_make_label("Nincs fejleszthető fegyver vagy felszerelés a hátizsákban vagy a felszerelési helyeken.", 13, UI_THEME.MUTED))
	_refresh_action_panel()


func _update_character_card() -> void:
	var character := GameState.get_active_character()
	if character == null:
		_character_name_label.text = "Nincs karakter"
		_character_detail_label.text = "Válassz karaktert a Lobbyban."
		_character_portrait.texture = null
		_character_portrait_back.color = Color(0.20, 0.26, 0.31, 1.0)
		_character_fallback.text = "?"
		_character_fallback.visible = true
		return
	var class_data := GameState.get_character_class(character.class_id)
	var class_display_name := class_data.display_name if class_data != null else String(character.class_id)
	var stats := GameState.get_character_stats(character)
	_character_name_label.text = character.character_name
	_character_detail_label.text = "%s  •  Szint %d\nHP: %d / %d" % [class_display_name, character.level, character.current_health, int(stats.get("max_health", character.current_health))]
	_character_portrait.texture = class_data.portrait if class_data != null else null
	_character_portrait_back.color = class_data.placeholder_color if class_data != null else Color(0.20, 0.26, 0.31, 1.0)
	_character_fallback.visible = _character_portrait.texture == null
	_character_fallback.text = class_display_name.substr(0, mini(2, class_display_name.length())).to_upper()


func _select_item(item: InventoryItem) -> void:
	_selected_item = item
	_status_label.text = "Kiválasztottad: %s" % _get_item_display_name(item)
	_status_label.add_theme_color_override("font_color", UI_THEME.MUTED)
	_refresh_all()


func _refresh_action_panel() -> void:
	if _action_content == null:
		return
	_clear_children(_action_content)
	var mode_config := _get_current_option()
	_action_content.add_child(_make_label(str(mode_config.get("label", "FEJLESZTÉS")), 21, UI_THEME.GOLD))
	_action_content.add_child(_make_label(str(mode_config.get("description", "Válassz egy fejlesztést.")), 13, UI_THEME.MUTED))

	if _selected_item == null or _selected_item.item_data == null:
		_action_content.add_child(_make_label("Válassz egy fegyvert vagy felszerelést a bal oldali listából.", 16, UI_THEME.IVORY))
		return

	_action_content.add_child(_make_label("KIVÁLASZTVA: " + _get_item_display_name(_selected_item), 17, UI_THEME.IVORY))
	_action_content.add_child(_make_label("Tárgytípus: %s" % _get_item_type_label(_selected_item.item_data.item_type), 12, UI_THEME.MUTED))
	_action_content.add_child(_make_label("Aktuális statok: %s" % _format_stats(GameState.get_item_stats(_selected_item)), 12, UI_THEME.IVORY))
	if not _selected_item.enchantment_ids.is_empty():
		var applied_names: Array[String] = []
		for applied_id in _selected_item.enchantment_ids:
			var applied_data := GameState.get_enchantment(StringName(applied_id))
			applied_names.append(applied_data.display_name if applied_data != null else applied_id)
		_action_content.add_child(_make_label("Már alkalmazva: " + ", ".join(PackedStringArray(applied_names)), 12, UI_THEME.GOLD))

	var enchantments := GameState.get_enchantments_for_workshop(workshop_type, _mode)
	var compatible_count := 0
	for enchantment in enchantments:
		var is_applicable := enchantment.applicable_item_types.is_empty() or enchantment.applicable_item_types.has(String(_selected_item.item_data.item_type))
		if not is_applicable:
			continue
		compatible_count += 1
		_add_enchantment_card(enchantment)
	if compatible_count == 0:
		_action_content.add_child(_make_label("Ehhez a tárgytípushoz ebben a kategóriában nincs megfelelő fejlesztés.", 14, Color(1.0, 0.68, 0.48, 1.0)))


func _add_enchantment_card(enchantment: EnchantmentData) -> void:
	var already_applied := _selected_item.enchantment_ids.has(String(enchantment.id))
	var can_apply := GameState.can_apply_enchantment(_selected_item, enchantment.id)
	var card := PanelContainer.new()
	UI_THEME.style_panel(card, accent_color.darkened(0.10), Color(0.055, 0.07, 0.09, 0.98))
	_action_content.add_child(card)
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 10)
	card.add_child(line)
	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.add_theme_constant_override("separation", 4)
	line.add_child(info)
	info.add_child(_make_label(enchantment.display_name, 16, UI_THEME.IVORY))
	var description := _make_label(enchantment.description, 12, UI_THEME.MUTED)
	description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info.add_child(description)
	info.add_child(_make_label("Hatás: %s" % _format_stats(enchantment.stat_modifiers), 12, accent_color.lightened(0.22)))
	info.add_child(_make_label(_cost_text(enchantment.ingredient_item_ids, enchantment.ingredient_amounts, enchantment.gold_cost), 12, UI_THEME.GOLD))
	var apply_button := Button.new()
	apply_button.custom_minimum_size = Vector2(132, 46)
	apply_button.text = "ALKALMAZVA" if already_applied else "ALKALMAZÁS"
	UI_THEME.style_button(apply_button, accent_color, true)
	apply_button.disabled = already_applied or not can_apply
	apply_button.pressed.connect(_on_apply_pressed.bind(enchantment.id))
	line.add_child(apply_button)
	if not already_applied and not can_apply:
		info.add_child(_make_label("Nem elég az arany/alapanyag, vagy a tárgy nem alkalmazható.", 11, Color(1.0, 0.58, 0.48, 1.0)))


func _on_apply_pressed(enchantment_id: StringName) -> void:
	var enchantment := GameState.get_enchantment(enchantment_id)
	if _selected_item == null:
		return
	if GameState.apply_enchantment(_selected_item, enchantment_id):
		_status_label.text = "Sikeresen alkalmazva: %s" % (enchantment.display_name if enchantment != null else String(enchantment_id))
		_status_label.add_theme_color_override("font_color", Color(0.48, 0.88, 0.60, 1.0))
	else:
		_status_label.text = "Nem sikerült. Ellenőrizd az aranyat, az alapanyagokat és a tárgytípust."
		_status_label.add_theme_color_override("font_color", Color(1.0, 0.55, 0.45, 1.0))
	_refresh_all()


func _get_current_option() -> Dictionary:
	for option in option_configs:
		if StringName(option.get("id", "")) == _mode:
			return option
	return {}


func _is_equipment(item: InventoryItem) -> bool:
	if item == null or item.item_data == null:
		return false
	return item.item_data.item_type != &"material" and item.item_data.item_type != &"consumable" and item.item_data.item_type != &"other"


func _get_item_display_name(item: InventoryItem) -> String:
	if item == null or item.item_data == null:
		return "Ismeretlen tárgy"
	var result := item.item_data.display_name
	if item.upgrade_level > 0:
		result += " +%d" % item.upgrade_level
	if not item.enchantment_ids.is_empty():
		result += "  ✦%d" % item.enchantment_ids.size()
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


func _cost_text(item_ids: PackedStringArray, amounts: PackedInt32Array, gold_cost: int) -> String:
	var parts: Array[String] = []
	for i in range(mini(item_ids.size(), amounts.size())):
		var data := GameState.get_item_data(StringName(item_ids[i]))
		var item_name := data.display_name if data != null else item_ids[i]
		parts.append("%s ×%d" % [item_name, amounts[i]])
	parts.append("%d arany" % gold_cost)
	return "Költség: " + ", ".join(PackedStringArray(parts))


func _format_stats(stats: Dictionary) -> String:
	if stats.is_empty():
		return "Nincs megadott statbónusz."
	var keys: Array = stats.keys()
	keys.sort()
	var parts: Array[String] = []
	for key in keys:
		var value := float(stats[key])
		var sign_text := "+" if value >= 0.0 else ""
		parts.append("%s %s%s" % [_stat_label(String(key)), sign_text, str(value)])
	return ", ".join(PackedStringArray(parts))


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
		"out_of_combat_hp_regen": "Harcon kívüli HP-regeneráció",
		"speed": "Sebesség"
	}
	return str(labels.get(key, key.replace("_", " ")))


func _make_label(text_value: String, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text_value
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return label


func _clear_children(parent: Node) -> void:
	for child in parent.get_children():
		parent.remove_child(child)
		child.queue_free()
