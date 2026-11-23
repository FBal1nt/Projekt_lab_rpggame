extends Panel

const UI_THEME = preload("res://Scripts/UI/ui_theme.gd")
const RESOURCE_CATALOG := preload("res://Scripts/Utils/ResourceCatalog.gd")
const SHOP_ITEM_ROW_SCENE = preload("res://Scenes/Shop/ShopItemRow.tscn")
const ITEM_DATA_DIRECTORY := "res://Data/Items"
const SHOP_ICON_PATH := "res://Assets/UI/Icons/shop.png"

const FILTER_TABS: Array[Dictionary] = [
	{"id": &"all", "label": "MIND"},
	{"id": &"weapon", "label": "FEGYVER"},
	{"id": &"gear", "label": "FELSZERELÉS"},
	{"id": &"material", "label": "ALAPANYAG"},
	{"id": &"consumable", "label": "ITAL / EGYÉB"}
]

@onready var header_row: HBoxContainer = $MarginContainer/VBoxContainer/Header
@onready var title_label: Label = $MarginContainer/VBoxContainer/Header/TitleBlock/Title
@onready var subtitle_label: Label = $MarginContainer/VBoxContainer/Header/TitleBlock/Subtitle
@onready var gold_panel: PanelContainer = $MarginContainer/VBoxContainer/Header/GoldPanel
@onready var gold_label: Label = $MarginContainer/VBoxContainer/Header/GoldPanel/GoldLabel
@onready var close_button: Button = $MarginContainer/VBoxContainer/Header/CloseButton
@onready var inventory_panel: PanelContainer = $MarginContainer/VBoxContainer/Content/InventoryPanel
@onready var inventory_title: Label = $MarginContainer/VBoxContainer/Content/InventoryPanel/InventoryMargin/InventoryVBox/InventoryHeader/InventoryTitle
@onready var character_label: Label = $MarginContainer/VBoxContainer/Content/InventoryPanel/InventoryMargin/InventoryVBox/InventoryHeader/CharacterLabel
@onready var inventory_grid: InventoryGrid = $MarginContainer/VBoxContainer/Content/InventoryPanel/InventoryMargin/InventoryVBox/GridCenter/BackpackGrid
@onready var selected_item_label: Label = $MarginContainer/VBoxContainer/Content/InventoryPanel/InventoryMargin/InventoryVBox/SelectedItemLabel
@onready var sell_button: Button = $MarginContainer/VBoxContainer/Content/InventoryPanel/InventoryMargin/InventoryVBox/SellButton
@onready var shop_panel: PanelContainer = $MarginContainer/VBoxContainer/Content/ShopPanel
@onready var shop_vbox: VBoxContainer = $MarginContainer/VBoxContainer/Content/ShopPanel/ShopMargin/ShopVBox
@onready var shop_title_label: Label = $MarginContainer/VBoxContainer/Content/ShopPanel/ShopMargin/ShopVBox/ShopHeader/ShopTitle
@onready var shop_hint_label: Label = $MarginContainer/VBoxContainer/Content/ShopPanel/ShopMargin/ShopVBox/ShopHeader/ShopHint
@onready var shop_scroll: ScrollContainer = $MarginContainer/VBoxContainer/Content/ShopPanel/ShopMargin/ShopVBox/ShopScroll
@onready var shop_list: VBoxContainer = $MarginContainer/VBoxContainer/Content/ShopPanel/ShopMargin/ShopVBox/ShopScroll/ShopList
@onready var feedback_label: Label = $MarginContainer/VBoxContainer/FeedbackLabel

var shop_items: Array[ItemData] = []
var selected_inventory_item: InventoryItem = null
var _active_filter: StringName = &"all"
var _filter_buttons: Dictionary = {}


# -----------------------------------------------------------------------------
# Initialization and data binding
# -----------------------------------------------------------------------------

func _ready() -> void:
	_style_ui()
	_build_filter_bar()
	_load_shop_items()
	inventory_grid.set_inventory(GameState.get_active_inventory())
	inventory_grid.item_selected.connect(_on_inventory_item_selected)
	inventory_grid.action_feedback.connect(_on_action_feedback)

	if not GameState.state_changed.is_connected(_on_game_state_changed):
		GameState.state_changed.connect(_on_game_state_changed)
	if not GameState.active_character_changed.is_connected(_on_active_character_changed):
		GameState.active_character_changed.connect(_on_active_character_changed)
	if not close_button.pressed.is_connected(_on_close_button_pressed):
		close_button.pressed.connect(_on_close_button_pressed)
	if not sell_button.pressed.is_connected(_on_sell_button_pressed):
		sell_button.pressed.connect(_on_sell_button_pressed)
	AudioManager.mark_custom_button_sfx(close_button)
	AudioManager.mark_custom_button_sfx(sell_button)

	refresh()


func refresh() -> void:
	# Called when the shop is opened. The inventory grid is rebound only if the
	# active character changed, so opening the shop doesn't reset a selection.
	var active_inventory := GameState.get_active_inventory()
	if inventory_grid.inventory != active_inventory:
		inventory_grid.clear_selection()
		inventory_grid.set_inventory(active_inventory)
		selected_inventory_item = null
	refresh_gold()
	refresh_character_label()
	refresh_selection_details()
	refresh_shop_list()


func _on_game_state_changed() -> void:
	refresh_gold()
	refresh_selection_details()
	refresh_shop_list()


func _process(_delta: float) -> void:
	# Local inventory moves clear InventoryGrid.selected_item. Keep the optional
	# sell action in sync so it never refers to a no-longer-selected object.
	if selected_inventory_item != null and inventory_grid.selected_item != selected_inventory_item:
		selected_inventory_item = null
		refresh_selection_details()


func refresh_gold() -> void:
	gold_label.text = "%d ARANY" % GameState.gold


func refresh_character_label() -> void:
	var character := GameState.get_active_character()
	if character == null:
		character_label.text = "Nincs aktív karakter"
		inventory_title.text = "KARAKTER HÁTIZSÁK"
		return
	var class_data := GameState.get_character_class(character.class_id)
	var class_name_str := class_data.display_name if class_data != null else String(character.class_id)
	character_label.text = "%s · %s" % [character.character_name, class_name_str]
	inventory_title.text = "HÁTIZSÁK"


func _on_active_character_changed(_character_id: String) -> void:
	selected_inventory_item = null
	inventory_grid.clear_selection()
	inventory_grid.set_inventory(GameState.get_active_inventory())
	refresh_character_label()
	refresh_selection_details()
	_set_feedback("Aktív karakter hátizsákja betöltve.", true)


# -----------------------------------------------------------------------------
# Category filter tabs and catalog-driven shop stock
# -----------------------------------------------------------------------------

func _build_filter_bar() -> void:
	var filter_bar := HBoxContainer.new()
	filter_bar.name = "ShopCategoryFilterBar"
	filter_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	filter_bar.add_theme_constant_override("separation", 6)
	shop_vbox.add_child(filter_bar)
	shop_vbox.move_child(filter_bar, shop_scroll.get_index())

	_filter_buttons.clear()
	for tab in FILTER_TABS:
		var filter_id := StringName(tab["id"])
		var btn := Button.new()
		btn.text = String(tab["label"])
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		UI_THEME.style_compact_button(btn, UI_THEME.GOLD, filter_id == _active_filter, 32.0, 11)
		btn.pressed.connect(_on_filter_pressed.bind(filter_id))
		filter_bar.add_child(btn)
		_filter_buttons[filter_id] = btn


func _on_filter_pressed(filter_id: StringName) -> void:
	if _active_filter == filter_id:
		return
	_active_filter = filter_id
	for key in _filter_buttons.keys():
		var tab_id := key as StringName
		var btn := _filter_buttons[key] as Button
		if btn != null:
			UI_THEME.style_compact_button(btn, UI_THEME.GOLD, tab_id == _active_filter, 32.0, 11)
	refresh_shop_list()


func _matches_filter(item_data: ItemData) -> bool:
	if item_data == null:
		return false
	match _active_filter:
		&"all":
			return true
		&"weapon":
			return item_data.item_type == &"weapon"
		&"gear":
			return item_data.item_type in [&"armor", &"shield", &"ring", &"earring", &"helmet", &"boots", &"gloves", &"tool"]
		&"material":
			return item_data.item_type == &"material"
		&"consumable":
			return item_data.item_type in [&"consumable", &"ammo", &"other"]
		_:
			return true


func _load_shop_items() -> void:
	shop_items.clear()
	var paths: Array[String] = RESOURCE_CATALOG.collect_resource_paths(ITEM_DATA_DIRECTORY)

	var seen_ids: Dictionary = {}
	for resource_path in paths:
		var resource: Resource = load(resource_path)
		if not resource is ItemData:
			continue
		var item_data := resource as ItemData
		if String(item_data.id).is_empty() or seen_ids.has(item_data.id):
			continue
		if item_data.buy_price < 0:
			continue
		seen_ids[item_data.id] = true
		shop_items.append(item_data)

	shop_items.sort_custom(_sort_items_by_name)


func _sort_items_by_name(a: ItemData, b: ItemData) -> bool:
	return a.display_name.naturalnocasecmp_to(b.display_name) < 0


func refresh_shop_list() -> void:
	for child in shop_list.get_children():
		child.queue_free()

	var shown_count := 0
	for item_data in shop_items:
		if not _matches_filter(item_data):
			continue
		shown_count += 1
		var row = SHOP_ITEM_ROW_SCENE.instantiate()
		row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		shop_list.add_child(row)
		row.setup_buy(item_data)

	if shown_count == 0:
		var empty_label := Label.new()
		empty_label.text = "Ebben a kategóriában jelenleg nincs áru."
		empty_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		empty_label.add_theme_color_override("font_color", UI_THEME.MUTED)
		empty_label.add_theme_font_size_override("font_size", 13)
		shop_list.add_child(empty_label)


func _on_inventory_item_selected(item: InventoryItem) -> void:
	selected_inventory_item = item
	refresh_selection_details()


func refresh_selection_details() -> void:
	var active_inventory := GameState.get_active_inventory()
	if (
		selected_inventory_item == null
		or active_inventory == null
		or not active_inventory.items.has(selected_inventory_item)
		or selected_inventory_item.item_data == null
	):
		selected_inventory_item = null
		selected_item_label.text = "Kijelölt tárgy eladáshoz: nincs"
		sell_button.text = "TÁRGY ELADÁSA"
		sell_button.disabled = true
		return

	var item_data := selected_inventory_item.item_data
	if item_data.id == &"gold_coin":
		selected_item_label.text = "%s × %d  ·  Ez maga a fizetőeszköz (%d arany)" % [
			item_data.display_name,
			selected_inventory_item.amount,
			selected_inventory_item.amount
		]
		sell_button.text = "FIZETŐESZKÖZ"
		sell_button.disabled = true
		return
	var sell_value := item_data.sell_price * selected_inventory_item.amount
	selected_item_label.text = "%s × %d  ·  Eladási érték: %d arany" % [
		item_data.display_name,
		selected_inventory_item.amount,
		sell_value
	]
	sell_button.text = "ELADÁS — %d ARANY" % sell_value
	sell_button.disabled = sell_value <= 0


# -----------------------------------------------------------------------------
# Selling, feedback and presentation
# -----------------------------------------------------------------------------

func _on_sell_button_pressed() -> void:
	var active_inventory := GameState.get_active_inventory()
	if (
		selected_inventory_item == null
		or selected_inventory_item != inventory_grid.selected_item
		or active_inventory == null
		or not active_inventory.items.has(selected_inventory_item)
	):
		_set_feedback("Előbb jelölj ki egy tárgyat a hátizsákban.", false)
		return

	var item_name := selected_inventory_item.item_data.display_name
	if GameState.sell_item(selected_inventory_item):
		selected_inventory_item = null
		inventory_grid.clear_selection()
		refresh_selection_details()
		AudioManager.sfx(&"gold_coins", 0.96, 1.06)
		_set_feedback("Eladva: %s." % item_name, true)
	else:
		AudioManager.sfx(&"ui_error", 0.96, 1.04)
		_set_feedback("A tárgy eladása nem sikerült.", false)


func _on_action_feedback(message: String, is_success: bool) -> void:
	_set_feedback(message, is_success)


func _set_feedback(message: String, is_success: bool) -> void:
	feedback_label.text = message
	feedback_label.add_theme_color_override(
		"font_color",
		UI_THEME.EMERALD if is_success else UI_THEME.CRIMSON
	)


func _style_ui() -> void:
	UI_THEME.style_window_shell(self, UI_THEME.GOLD)

	# Prepend framed shop emblem to the header without altering any @onready paths
	if ResourceLoader.exists(SHOP_ICON_PATH) and header_row.get_node_or_null("ShopEmblem") == null:
		var icon_frame := PanelContainer.new()
		icon_frame.name = "ShopEmblem"
		icon_frame.custom_minimum_size = Vector2(42, 42)
		icon_frame.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		icon_frame.add_theme_stylebox_override(
			"panel",
			UI_THEME.make_card_box(Color(0.05, 0.07, 0.11, 0.96), UI_THEME.GOLD, 1, 9, 5.0, 5.0)
		)
		var icon_rect := TextureRect.new()
		icon_rect.texture = load(SHOP_ICON_PATH) as Texture2D
		icon_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon_rect.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		icon_rect.size_flags_vertical = Control.SIZE_EXPAND_FILL
		icon_frame.add_child(icon_rect)
		header_row.add_child(icon_frame)
		header_row.move_child(icon_frame, 0)

	inventory_panel.add_theme_stylebox_override(
		"panel",
		UI_THEME.make_card_box(UI_THEME.SURFACE_DARK, Color(0.45, 0.66, 0.72, 0.55), 1, 12, 0.0, 0.0)
	)
	shop_panel.add_theme_stylebox_override(
		"panel",
		UI_THEME.make_card_box(UI_THEME.SURFACE_DARK, Color(UI_THEME.GOLD.r, UI_THEME.GOLD.g, UI_THEME.GOLD.b, 0.55), 1, 12, 0.0, 0.0)
	)
	gold_panel.add_theme_stylebox_override(
		"panel",
		UI_THEME.make_card_box(Color(0.11, 0.085, 0.036, 0.96), UI_THEME.GOLD, 1, 9, 14.0, 4.0)
	)
	gold_panel.custom_minimum_size = Vector2(146, 38)

	UI_THEME.style_compact_button(sell_button, UI_THEME.FORGE_EMBER, true, 42.0, 14)
	UI_THEME.style_compact_button(close_button, UI_THEME.GOLD, false, 38.0, 13)
	close_button.text = "BEZÁRÁS"
	close_button.custom_minimum_size = Vector2(120, 38)
	close_button.size_flags_vertical = Control.SIZE_SHRINK_CENTER

	title_label.add_theme_color_override("font_color", UI_THEME.GOLD)
	title_label.add_theme_font_size_override("font_size", 22)
	subtitle_label.add_theme_color_override("font_color", UI_THEME.MUTED)
	subtitle_label.add_theme_font_size_override("font_size", 12)
	inventory_title.add_theme_color_override("font_color", UI_THEME.GOLD)
	inventory_title.add_theme_font_size_override("font_size", 15)
	shop_title_label.add_theme_color_override("font_color", UI_THEME.GOLD)
	shop_title_label.add_theme_font_size_override("font_size", 15)
	shop_hint_label.add_theme_color_override("font_color", UI_THEME.MUTED)
	shop_hint_label.add_theme_font_size_override("font_size", 12)
	character_label.add_theme_color_override("font_color", UI_THEME.IVORY)
	character_label.add_theme_font_size_override("font_size", 13)
	gold_label.add_theme_color_override("font_color", UI_THEME.GOLD)
	gold_label.add_theme_font_size_override("font_size", 16)
	feedback_label.add_theme_color_override("font_color", UI_THEME.MUTED)
	feedback_label.add_theme_font_size_override("font_size", 13)
	selected_item_label.add_theme_color_override("font_color", UI_THEME.IVORY)
	selected_item_label.add_theme_font_size_override("font_size", 13)


func _on_close_button_pressed() -> void:
	AudioManager.sfx(&"ui_window_close", 0.96, 1.04)
	hide()
