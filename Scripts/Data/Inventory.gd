class_name Inventory
extends Resource


signal inventory_changed


@export var width: int = 8
@export var height: int = 4

var items: Array[InventoryItem] = []

func is_position_inside(position: Vector2i, size: Vector2i) -> bool:
	if position.x < 0:
		return false

	if position.y < 0:
		return false

	if position.x + size.x > width:
		return false

	if position.y + size.y > height:
		return false

	return true

func get_item_at_cell(cell: Vector2i, ignore_item: InventoryItem = null) -> InventoryItem:
	for inventory_item in items:
		if inventory_item == ignore_item:
			continue

		var item_size := inventory_item.item_data.size
		var item_position := inventory_item.position

		if (
			cell.x >= item_position.x
			and cell.x < item_position.x + item_size.x
			and cell.y >= item_position.y
			and cell.y < item_position.y + item_size.y
		):
			return inventory_item

	return null

func can_place_item(
	item_data: ItemData,
	position: Vector2i,
	ignore_item: InventoryItem = null
) -> bool:
	if not is_position_inside(position, item_data.size):
		return false

	for y in range(position.y, position.y + item_data.size.y):
		for x in range(position.x, position.x + item_data.size.x):
			var cell := Vector2i(x, y)

			if get_item_at_cell(cell, ignore_item) != null:
				return false

	return true

func add_item(
	item_data: ItemData,
	position: Vector2i,
	amount: int = 1
) -> InventoryItem:
	if not can_place_item(item_data, position):
		return null

	var inventory_item := InventoryItem.new()

	inventory_item.item_data = item_data
	inventory_item.position = position
	inventory_item.amount = amount

	items.append(inventory_item)

	inventory_changed.emit()

	return inventory_item

func move_item(
	inventory_item: InventoryItem,
	new_position: Vector2i
) -> bool:
	if not items.has(inventory_item):
		return false

	if not can_place_item(
		inventory_item.item_data,
		new_position,
		inventory_item
	):
		return false

	inventory_item.position = new_position

	inventory_changed.emit()

	return true

func remove_item(inventory_item: InventoryItem) -> bool:
	if not items.has(inventory_item):
		return false

	items.erase(inventory_item)

	inventory_changed.emit()

	return true
