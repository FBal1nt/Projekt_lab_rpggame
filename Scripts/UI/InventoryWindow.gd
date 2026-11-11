extends Panel

const UI_THEME = preload("res://Scripts/UI/ui_theme.gd")

const SLOT_ORDER: Array[StringName] = [&"weapon", &"armor", &"ring", &"earring"]
const CHARACTER_FALLBACK_ICON: Texture2D = preload("res://Arts/UI/Icons/character.svg")
const SLOT_FALLBACK_ICONS := {
	&"weapon": preload("res://Arts/UI/Icons/equipment_weapon.svg"),
	&"armor": preload("res://Arts/UI/Icons/equipment_armor.svg"),
	&"ring": preload("res://Arts/UI/Icons/equipment_ring.svg"),
	&"earring": preload("res://Arts/UI/Icons/equipment_earring.svg")
}
const SLOT_LABELS := {
	&"weapon": "Fegyver",
	&"armor": "Páncél",
	&"ring": "Gyűrű",
	&"earring": "Fülbevaló"
}

var backpack_grid: InventoryGrid
var stash_grid: InventoryGrid
var title_label: Label
var character_label: Label
var stats_label: Label
var feedback_label: Label
var item_details_label: Label
var equip_button: Button
var unequip_button: Button
var close_button: Button
var equipment_buttons: Dictionary = {}
var equipment_portrait: TextureRect
var equipment_portrait_back: ColorRect
var selected_equipment_slot: StringName = &""
var selected_backpack_item: InventoryItem = null
var selected_stash_item: InventoryItem = null
var _is_refreshing: bool = false


func _ready() -> void:
	_build_interface()
	_bind_inventories()
	if not GameState.active_character_changed.is_connected(_on_active_character_changed):
		GameState.active_character_changed.connect(_on_active_character_changed)
	if not GameState.state_changed.is_connected(_on_state_changed):
		GameState.state_changed.connect(_on_state_changed)
	_refresh_all()


func _build_interface() -> void:
	UI_THEME.style_panel(self, Color(0.64, 0.43, 0.24, 1.0), Color(0.035, 0.027, 0.026, 0.99))

	var margin := MarginContainer.new()
	margin.name = "InventoryMargin"
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 18)
	margin.add_theme_constant_override("margin_top", 14)
	margin.add_theme_constant_override("margin_right", 18)
	margin.add_theme_constant_override("margin_bottom", 14)
	add_child(margin)

	var layout := VBoxContainer.new()
	layout.name = "InventoryLayout"
	layout.add_theme_constant_override("separation", 9)
	margin.add_child(layout)

	var header := HBoxContainer.new()
	header.custom_minimum_size.y = 34
	layout.add_child(header)

	title_label = _make_label("FELSZERELÉS ÉS RAKTÁR", 25, UI_THEME.GOLD)
	title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title_label)

	close_button = Button.new()
	close_button.text = "BEZÁRÁS"
	close_button.custom_minimum_size = Vector2(132, 38)
	UI_THEME.style_button(close_button, Color(0.73, 0.45, 0.29, 1.0), true)
	close_button.add_theme_font_size_override("font_size", 13)
	close_button.pressed.connect(_on_close_button_pressed)
	header.add_child(close_button)

	var character_panel := _make_panel(Color(0.25, 0.18, 0.13, 1.0), Color(0.68, 0.49, 0.28, 1.0))
	character_panel.custom_minimum_size.y = 82
	layout.add_child(character_panel)
	var character_content := VBoxContainer.new()
	character_content.add_theme_constant_override("separation", 3)
	_get_panel_content(character_panel).add_child(character_content)
	character_label = _make_label("AKTÍV KARAKTER", 17, UI_THEME.IVORY)
	character_content.add_child(character_label)
	stats_label = _make_label("A felszerelésből származó értékek itt jelennek meg.", 12, Color(0.83, 0.77, 0.66, 1.0))
	stats_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	character_content.add_child(stats_label)

	var main_row := HBoxContainer.new()
	main_row.name = "InventoryMainRow"
	main_row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	main_row.add_theme_constant_override("separation", 10)
	layout.add_child(main_row)

	_build_equipment_panel(main_row)
	_build_inventory_panel(main_row, "HÁTIZSÁK", false)
	_build_inventory_panel(main_row, "KÖZÖS STASH", true)

	var footer_panel := _make_panel(Color(0.065, 0.052, 0.047, 1.0), Color(0.43, 0.31, 0.21, 1.0))
	footer_panel.custom_minimum_size.y = 78
	layout.add_child(footer_panel)
	var footer := HBoxContainer.new()
	footer.add_theme_constant_override("separation", 10)
	_get_panel_content(footer_panel).add_child(footer)

	item_details_label = _make_label("Válassz ki egy tárgyat a hátizsákból vagy a felszerelési helyek közül.", 12, UI_THEME.IVORY)
	item_details_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	item_details_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	item_details_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	footer.add_child(item_details_label)

	equip_button = Button.new()
	equip_button.text = "FELSZEREL"
	equip_button.custom_minimum_size = Vector2(138, 48)
	UI_THEME.style_button(equip_button, Color(0.66, 0.57, 0.32, 1.0), true)
	equip_button.add_theme_font_size_override("font_size", 13)
	equip_button.pressed.connect(_on_equip_pressed)
	footer.add_child(equip_button)

	unequip_button = Button.new()
	unequip_button.text = "LEVÉTEL"
	unequip_button.custom_minimum_size = Vector2(118, 48)
	UI_THEME.style_button(unequip_button, Color(0.70, 0.42, 0.32, 1.0))
	unequip_button.add_theme_font_size_override("font_size", 13)
	unequip_button.pressed.connect(_on_unequip_pressed)
	footer.add_child(unequip_button)

	feedback_label = _make_label("Válassz ki egy felszerelhető tárgyat, majd nyomd meg a FELSZEREL gombot.", 11, UI_THEME.MUTED)
	feedback_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	layout.add_child(feedback_label)


func _build_equipment_panel(parent: HBoxContainer) -> void:
	var panel := _make_panel(Color(0.075, 0.058, 0.052, 1.0), Color(0.68, 0.49, 0.28, 1.0))
	panel.custom_minimum_size.x = 292
	panel.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	parent.add_child(panel)

	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 8)
	_get_panel_content(panel).add_child(content)
	content.add_child(_make_label("HŐS FELSZERELÉSE", 15, UI_THEME.GOLD))

	# A karakter középen áll, a négy felszerelési hely pedig körülötte jelenik meg.
	# A gombokon csak ikon látható; a pontos tárgynév és bónusz az eszköztippben van.
	var slots_grid := GridContainer.new()
	slots_grid.columns = 3
	slots_grid.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	slots_grid.add_theme_constant_override("h_separation", 7)
	slots_grid.add_theme_constant_override("v_separation", 7)
	content.add_child(slots_grid)

	_add_equipment_spacer(slots_grid)
	_add_equipment_slot(slots_grid, &"ring")
	_add_equipment_spacer(slots_grid)
	_add_equipment_slot(slots_grid, &"weapon")
	_add_equipment_character(slots_grid)
	_add_equipment_slot(slots_grid, &"armor")
	_add_equipment_spacer(slots_grid)
	_add_equipment_slot(slots_grid, &"earring")
	_add_equipment_spacer(slots_grid)

	var slot_note := _make_label("Válassz egy ikont a felszerelés kijelöléséhez. A levett tárgy a hátizsákba kerül vissza.", 10, UI_THEME.MUTED)
	slot_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content.add_child(slot_note)


func _add_equipment_spacer(parent: GridContainer) -> void:
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(76, 76)
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(spacer)


func _add_equipment_slot(parent: GridContainer, slot: StringName) -> void:
	var slot_button := Button.new()
	slot_button.custom_minimum_size = Vector2(76, 76)
	slot_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	slot_button.text = ""
	slot_button.icon = SLOT_FALLBACK_ICONS.get(slot, CHARACTER_FALLBACK_ICON)
	slot_button.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	slot_button.expand_icon = true
	slot_button.add_theme_constant_override("icon_max_width", 52)
	UI_THEME.style_button(slot_button, Color(0.67, 0.49, 0.29, 1.0))
	slot_button.pressed.connect(_on_equipment_slot_pressed.bind(slot))
	parent.add_child(slot_button)
	equipment_buttons[slot] = slot_button


func _add_equipment_character(parent: GridContainer) -> void:
	var portrait_frame := PanelContainer.new()
	portrait_frame.custom_minimum_size = Vector2(92, 116)
	portrait_frame.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	portrait_frame.add_theme_stylebox_override("panel", UI_THEME.make_box(Color(0.11, 0.085, 0.065, 1.0), Color(0.82, 0.61, 0.34, 1.0), 2, 8))
	parent.add_child(portrait_frame)

	var portrait_holder := Control.new()
	portrait_holder.custom_minimum_size = Vector2(82, 106)
	portrait_holder.clip_contents = true
	portrait_frame.add_child(portrait_holder)
	equipment_portrait_back = ColorRect.new()
	equipment_portrait_back.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	equipment_portrait_back.color = Color(0.27, 0.20, 0.14, 1.0)
	equipment_portrait_back.mouse_filter = Control.MOUSE_FILTER_IGNORE
	portrait_holder.add_child(equipment_portrait_back)
	equipment_portrait = TextureRect.new()
	equipment_portrait.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	equipment_portrait.set_offsets_preset(Control.PRESET_FULL_RECT)
	equipment_portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	equipment_portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	equipment_portrait.texture = CHARACTER_FALLBACK_ICON
	equipment_portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
	portrait_holder.add_child(equipment_portrait)


func _build_inventory_panel(parent: HBoxContainer, heading: String, is_stash: bool) -> void:
	var accent := Color(0.58, 0.40, 0.26, 1.0) if not is_stash else Color(0.48, 0.39, 0.31, 1.0)
	var panel := _make_panel(Color(0.055, 0.044, 0.041, 1.0), accent)
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(panel)

	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 7)
	_get_panel_content(panel).add_child(content)
	var heading_label := _make_label(heading, 15, UI_THEME.GOLD)
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
	grid.action_feedback.connect(_on_action_feedback)


func _make_panel(background: Color, border: Color) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", UI_THEME.make_box(background, border, 2, 5))
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 10)
	margin.add_theme_constant_override("margin_top", 9)
	margin.add_theme_constant_override("margin_right", 10)
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
	# A tartalomcsomópont közvetlen referenciáját tároljuk. Így nem függünk
	# a Godot által automatikusan kiosztott node-nevektől vagy NodePath-tól.
	panel.set_meta("content_node", content)
	return panel


func _get_panel_content(panel: PanelContainer) -> VBoxContainer:
	if panel == null or not is_instance_valid(panel):
		push_error("InventoryWindow: érvénytelen PanelContainer a tartalom lekérésekor.")
		return null
	var content := panel.get_meta("content_node", null) as VBoxContainer
	if content != null and is_instance_valid(content):
		return content
	# Biztonsági visszaesés régebbi vagy kézzel szerkesztett jelenetekhez:
	# a tartalmat típus alapján keressük meg, nem név szerinti útvonallal.
	content = _find_panel_content(panel)
	if content != null:
		panel.set_meta("content_node", content)
		return content
	# Végső önjavító ág: ha egy régi/átalakított panelből hiányzik a belső
	# tartalomkonténer, hozzuk létre, így a hívó add_child() sem kap nullt.
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
	backpack_grid.set_peer_grid(stash_grid)
	stash_grid.set_peer_grid(backpack_grid)


func _refresh_all() -> void:
	if _is_refreshing:
		return
	_is_refreshing = true
	var active := GameState.get_active_character()
	if active != null:
		backpack_grid.set_inventory(active.inventory)
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
	character_label.text = "%s  ·  %s  ·  %d. szint  ·  Stressz: %d" % [character.character_name.to_upper(), class_label_text, character.level, character.stress]
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
		if item == null or item.item_data == null:
			button.icon = slot_icon
			button.tooltip_text = slot_name + " – üres felszerelési hely"
		else:
			button.icon = item.item_data.icon if item.item_data.icon != null else slot_icon
			button.tooltip_text = _item_tooltip(item)
		button.text = ""
		button.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
		button.expand_icon = true
		button.add_theme_constant_override("icon_max_width", 52)
		var selected := selected_equipment_slot == slot
		if selected:
			button.add_theme_stylebox_override("normal", UI_THEME.make_box(Color(0.22, 0.15, 0.09, 1.0), Color(1.0, 0.78, 0.36, 1.0), 3, 8))
		else:
			UI_THEME.style_button(button, Color(0.67, 0.49, 0.29, 1.0))
		button.custom_minimum_size = Vector2(76, 76)


func _refresh_equipment_portrait(character: CharacterProfile) -> void:
	if equipment_portrait == null or not is_instance_valid(equipment_portrait):
		return
	if character == null:
		equipment_portrait.texture = CHARACTER_FALLBACK_ICON
		equipment_portrait_back.color = Color(0.20, 0.20, 0.20, 1.0)
		equipment_portrait.tooltip_text = "Nincs aktív karakter"
		return
	var class_data := GameState.get_character_class(character.class_id)
	if class_data != null:
		equipment_portrait.texture = class_data.portrait if class_data.portrait != null else CHARACTER_FALLBACK_ICON
		equipment_portrait_back.color = class_data.placeholder_color
	else:
		equipment_portrait.texture = CHARACTER_FALLBACK_ICON
		equipment_portrait_back.color = Color(0.27, 0.20, 0.14, 1.0)
	equipment_portrait.tooltip_text = character.character_name + " – " + String(character.class_id)


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
		item_details_label.text = "Válassz ki egy tárgyat. A hátizsákból felszerelhető eszközt a FELSZEREL gombbal adhatod a hősnek."
	else:
		var source_text := "Felszerelve" if _is_selected_equipped() else ("Stash" if selected == selected_stash_item else "Hátizsák")
		var stats := GameState.get_item_stats(selected)
		var parts: Array[String] = []
		for key in stats:
			parts.append("%s %s" % [_stat_name(String(key)), _format_bonus(int(round(float(stats[key])))) if float(stats[key]) >= 0 else _format_stat(stats[key])])
		var bonus_text := " · ".join(parts) if not parts.is_empty() else "Nincs statbónusz"
		item_details_label.text = "%s  ·  %s  ·  %s" % [selected.item_data.display_name, source_text, bonus_text]
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


func _on_equip_pressed() -> void:
	if selected_backpack_item == null:
		return
	var item_name := selected_backpack_item.item_data.display_name if selected_backpack_item.item_data != null else "tárgy"
	if GameState.equip_item(selected_backpack_item):
		selected_backpack_item = null
		selected_equipment_slot = &""
		feedback_label.text = "Felszerelve: " + item_name
		feedback_label.add_theme_color_override("font_color", Color(0.58, 0.85, 0.53, 1.0))
		_refresh_all()
	else:
		feedback_label.text = "Nem lehet felszerelni: ellenőrizd a tárgy típusát és a hátizsákban lévő szabad helyet."
		feedback_label.add_theme_color_override("font_color", Color(0.88, 0.48, 0.39, 1.0))


func _on_unequip_pressed() -> void:
	if selected_equipment_slot == &"":
		return
	var slot_name := str(SLOT_LABELS.get(selected_equipment_slot, selected_equipment_slot))
	if GameState.unequip_item(selected_equipment_slot):
		selected_equipment_slot = &""
		feedback_label.text = slot_name + " levéve és visszahelyezve a hátizsákba."
		feedback_label.add_theme_color_override("font_color", Color(0.58, 0.85, 0.53, 1.0))
		_refresh_all()
	else:
		feedback_label.text = "Nincs elég hely a hátizsákban a felszerelés levételéhez."
		feedback_label.add_theme_color_override("font_color", Color(0.88, 0.48, 0.39, 1.0))


func _on_action_feedback(message: String, success: bool) -> void:
	feedback_label.text = message
	feedback_label.add_theme_color_override("font_color", Color(0.58, 0.85, 0.53, 1.0) if success else Color(0.88, 0.48, 0.39, 1.0))


func _input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventMouseMotion:
		backpack_grid.maybe_begin_drag_from_global_motion()
		stash_grid.maybe_begin_drag_from_global_motion()
		return
	if not (event is InputEventMouseButton):
		return
	if event.button_index != MOUSE_BUTTON_LEFT or event.pressed:
		return
	var source_grid: InventoryGrid = null
	if backpack_grid.dragging_item != null:
		source_grid = backpack_grid
	elif stash_grid.dragging_item != null:
		source_grid = stash_grid
	if source_grid == null or source_grid.peer_grid == null:
		return
	if source_grid.get_global_rect().has_point(event.global_position):
		return
	var target_grid: InventoryGrid = source_grid.peer_grid
	if target_grid.get_global_rect().has_point(event.global_position):
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
	hide()

