extends PanelContainer


@onready var icon: TextureRect = $MarginContainer/HBoxContainer/Icon
@onready var item_name: Label = $MarginContainer/HBoxContainer/Info/Name
@onready var price: Label = $MarginContainer/HBoxContainer/Info/Price
@onready var action_button: Button = $MarginContainer/HBoxContainer/ActionButton


var item_data: ItemData
var inventory_item: InventoryItem = null
var action_callback: Callable


func _ready() -> void:
	custom_minimum_size = Vector2(0, 90)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL

func setup_buy(
	new_item_data: ItemData,
	callback: Callable
) -> void:
	custom_minimum_size = Vector2(0, 90)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL

	item_data = new_item_data
	inventory_item = null
	action_callback = callback

	icon.texture = item_data.icon
	item_name.text = item_data.display_name
	price.text = str(item_data.buy_price) + " G"

	action_button.text = "VÁSÁROL"

	action_button.pressed.connect(_on_action_pressed)


func setup_sell(
	new_inventory_item: InventoryItem,
	callback: Callable
) -> void:
	custom_minimum_size = Vector2(0, 90)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL

	inventory_item = new_inventory_item
	item_data = new_inventory_item.item_data
	action_callback = callback

	icon.texture = item_data.icon

	item_name.text = (
		item_data.display_name
		+ " ×"
		+ str(inventory_item.amount)
	)

	price.text = str(
		item_data.sell_price * inventory_item.amount
	) + " G"

	action_button.text = "ELAD"

	action_button.pressed.connect(_on_action_pressed)


func _on_action_pressed() -> void:
	if action_callback.is_valid():
		action_callback.call(self)
