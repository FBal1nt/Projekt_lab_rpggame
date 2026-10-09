extends Node


signal state_changed


var gold: int = 500
var level: int = 1
var xp: int = 0


var backpack: Inventory
var stash: Inventory


func _ready() -> void:
	backpack = Inventory.new()
	backpack.width = 8
	backpack.height = 4

	stash = Inventory.new()
	stash.width = 10
	stash.height = 5
	
	setup_starting_inventory()


func setup_starting_inventory() -> void:
	var sword: ItemData = load("res://Data/Items/iron_sword.tres")
	var potion: ItemData = load("res://Data/Items/health_potion.tres")

	backpack.add_item(
		sword,
		Vector2i(0, 0)
	)

	backpack.add_item(
		potion,
		Vector2i(2, 0),
		3
	)

	backpack.add_item(
		potion,
		Vector2i(5, 0),
		4
	)

func buy_item(
	item_data: ItemData,
	amount: int = 1
) -> bool:
	if item_data == null or amount <= 0 or item_data.buy_price < 0:
		return false

	var total_price := item_data.buy_price * amount

	if gold < total_price:
		return false

	if not backpack.can_add_item(item_data, amount):
		return false

	var remaining := backpack.try_add_item(
		item_data,
		amount
	)

	if remaining > 0:
		return false

	gold -= total_price
	state_changed.emit()

	return true

func sell_item(
	inventory_item: InventoryItem
) -> bool:
	if inventory_item == null:
		return false

	if not backpack.items.has(inventory_item):
		return false

	var sell_price := (
		inventory_item.item_data.sell_price
		* inventory_item.amount
	)

	if not backpack.remove_item(inventory_item):
		return false

	gold += sell_price
	state_changed.emit()

	return true
