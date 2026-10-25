extends Panel

const UI_THEME = preload("res://Scripts/UI/ui_theme.gd")
const RESOURCE_CATALOG := preload("res://Scripts/Utils/ResourceCatalog.gd")
const SHOP_ITEM_ROW_SCENE = preload("res://Scenes/Shop/ShopItemRow.tscn")
const ITEM_DATA_DIRECTORY := "res://Data/Items"

@onready var title_label: Label = $MarginContainer/VBoxContainer/Header/TitleBlock/Title
@onready var subtitle_label: Label = $MarginContainer/VBoxContainer/Header/TitleBlock/Subtitle
@onready var gold_label: Label = $MarginContainer/VBoxContainer/Header/GoldPanel/GoldLabel
@onready var close_button: Button = $MarginContainer/VBoxContainer/Header/CloseButton
@onready var inventory_panel: PanelContainer = $MarginContainer/VBoxContainer/Content/InventoryPanel
@onready var inventory_title: Label = $MarginContainer/VBoxContainer/Content/InventoryPanel/InventoryMargin/InventoryVBox/InventoryHeader/InventoryTitle
@onready var character_label: Label = $MarginContainer/VBoxContainer/Content/InventoryPanel/InventoryMargin/InventoryVBox/InventoryHeader/CharacterLabel
@onready var inventory_grid: InventoryGrid = $MarginContainer/VBoxContainer/Content/InventoryPanel/InventoryMargin/InventoryVBox/GridCenter/BackpackGrid
@onready var selected_item_label: Label = $MarginContainer/VBoxContainer/Content/InventoryPanel/InventoryMargin/InventoryVBox/SelectedItemLabel
@onready var sell_button: Button = $MarginContainer/VBoxContainer/Content/InventoryPanel/InventoryMargin/InventoryVBox/SellButton
@onready var shop_panel: PanelContainer = $MarginContainer/VBoxContainer/Content/ShopPanel
@onready var shop_list: VBoxContainer = $MarginContainer/VBoxContainer/Content/ShopPanel/ShopMargin/ShopVBox/ShopScroll/ShopList
@onready var feedback_label: Label = $MarginContainer/VBoxContainer/FeedbackLabel

var shop_items: Array[ItemData] = []
var selected_inventory_item: InventoryItem = null


# -----------------------------------------------------------------------------
# Initialization and data binding
# -----------------------------------------------------------------------------

func _ready() -> void:
	_style_ui()
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
		inventory_title.text = "KARAKTER INVENTORY"
		return
	character_label.text = character.character_name
	inventory_title.text = "HÁTIZSÁK"


func _on_active_character_changed(_character_id: String) -> void:
	selected_inventory_item = null
	inventory_grid.clear_selection()
	inventory_grid.set_inventory(GameState.get_active_inventory())
	refresh_character_label()
	refresh_selection_details()
	_set_feedback("Aktív karakter hátizsákja betöltve.", true)


# -----------------------------------------------------------------------------
# Catalog-driven shop stock
# -----------------------------------------------------------------------------

func _load_shop_items() -> void:
	shop_items.clear()
	var paths: Array[String] = RESOURCE_CATALOG.collect_resource_paths(ITEM_DATA_DIRECTORY)

	var seen_ids: Dictionary = {}
	for resource_path in paths:
		var resource := load(resource_path)
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

	if shop_items.is_empty():
		var empty_label := Label.new()
		empty_label.text = "Jelenleg nincs elérhető áru."
		empty_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		empty_label.add_theme_color_override("font_color", UI_THEME.MUTED)
		shop_list.add_child(empty_label)
		return

	for item_data in shop_items:
		var row = SHOP_ITEM_ROW_SCENE.instantiate()
		row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		shop_list.add_child(row)
		row.setup_buy(item_data)


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
	var sell_value := item_data.sell_price * selected_inventory_item.amount
	selected_item_label.text = "%s × %d  |  Eladási érték: %d arany" % [
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
		_set_feedback("Eladva: %s." % item_name, true)
	else:
		_set_feedback("A tárgy eladása nem sikerült.", false)


func _on_action_feedback(message: String, is_success: bool) -> void:
	_set_feedback(message, is_success)


func _set_feedback(message: String, is_success: bool) -> void:
	feedback_label.text = message
	feedback_label.add_theme_color_override(
		"font_color",
		Color(0.55, 0.95, 0.62, 1.0) if is_success else Color(1.0, 0.48, 0.42, 1.0)
	)


func _style_ui() -> void:
	UI_THEME.style_panel(inventory_panel, Color(0.43, 0.62, 0.62, 1.0), Color(0.035, 0.06, 0.09, 0.98))
	UI_THEME.style_panel(shop_panel, UI_THEME.GOLD, Color(0.035, 0.06, 0.09, 0.98))
	UI_THEME.style_panel($MarginContainer/VBoxContainer/Header/GoldPanel, UI_THEME.GOLD, Color(0.16, 0.11, 0.045, 0.98))
	UI_THEME.style_button(sell_button, Color(0.82, 0.55, 0.33, 1.0), true)
	UI_THEME.style_button(close_button, Color(0.62, 0.69, 0.76, 1.0))

	for label in [title_label, gold_label, inventory_title, character_label, feedback_label, selected_item_label]:
		label.add_theme_color_override("font_color", UI_THEME.IVORY)
	title_label.add_theme_font_size_override("font_size", 26)
	subtitle_label.add_theme_color_override("font_color", UI_THEME.MUTED)
	inventory_title.add_theme_font_size_override("font_size", 18)
	character_label.add_theme_color_override("font_color", UI_THEME.GOLD)
	gold_label.add_theme_color_override("font_color", UI_THEME.GOLD)
	gold_label.add_theme_font_size_override("font_size", 20)
	feedback_label.add_theme_font_size_override("font_size", 14)
	selected_item_label.add_theme_font_size_override("font_size", 13)
	close_button.text = "BEZÁRÁS"
	close_button.custom_minimum_size = Vector2(130, 46)


func _on_close_button_pressed() -> void:
	hide()
