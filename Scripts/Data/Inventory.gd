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
	amount: int = 1,
	emit_change: bool = true
) -> InventoryItem:
	if item_data == null or amount <= 0:
		return null

	if not can_place_item(item_data, position):
		return null

	var inventory_item := InventoryItem.new()

	inventory_item.item_data = item_data
	inventory_item.position = position
	inventory_item.amount = amount

	items.append(inventory_item)

	if emit_change:
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


func transfer_item_to(
	inventory_item: InventoryItem,
	target_inventory: Inventory,
	target_position: Vector2i
) -> bool:
	# The source and target are only changed after destination validation,
	# so a failed transfer cannot delete or duplicate an item.
	if inventory_item == null or target_inventory == null:
		return false

	if target_inventory == self or not items.has(inventory_item):
		return false

	var target_item := target_inventory.get_item_at_cell(target_position)

	# A stack target takes as many items as it has room for.
	if target_item != null:
		if not target_inventory.can_stack(inventory_item, target_item):
			return false

		var free_space: int = target_item.item_data.max_stack - target_item.amount
		var transfer_amount: int = min(inventory_item.amount, free_space)

		if transfer_amount <= 0:
			return false

		target_item.amount += transfer_amount
		inventory_item.amount -= transfer_amount

		if inventory_item.amount <= 0:
			items.erase(inventory_item)
	else:
		# Empty destination cell: validate the item's complete footprint first.
		if not target_inventory.can_place_item(
			inventory_item.item_data,
			target_position
		):
			return false

		items.erase(inventory_item)
		inventory_item.position = target_position
		target_inventory.items.append(inventory_item)

	inventory_changed.emit()
	target_inventory.inventory_changed.emit()
	return true

func can_stack(
	source: InventoryItem,
	target: InventoryItem
) -> bool:
	if source == null or target == null:
		return false

	if source.item_data == null or target.item_data == null:
		return false
	if source.item_data.id != target.item_data.id:
		return false
	if source.upgrade_level != target.upgrade_level:
		return false
	var source_enchantments: PackedStringArray = source.enchantment_ids.duplicate()
	var target_enchantments: PackedStringArray = target.enchantment_ids.duplicate()
	source_enchantments.sort()
	target_enchantments.sort()
	if source_enchantments != target_enchantments:
		return false

	if target.amount >= target.item_data.max_stack:
		return false

	return true
	
func merge_items(
	source: InventoryItem,
	target: InventoryItem
) -> bool:
	if not items.has(source):
		return false

	if not items.has(target):
		return false

	if not can_stack(source, target):
		return false

	var free_space := (
		target.item_data.max_stack - target.amount
	)

	var transfer_amount = min(
		source.amount,
		free_space
	)

	target.amount += transfer_amount
	source.amount -= transfer_amount

	if source.amount <= 0:
		items.erase(source)

	inventory_changed.emit()

	return true

func find_free_position(item_data: ItemData) -> Vector2i:
	for y in range(height):
		for x in range(width):
			var position := Vector2i(x, y)

			if can_place_item(item_data, position):
				return position

	return Vector2i(-1, -1)

func try_add_item(
	item_data: ItemData,
	amount: int = 1,
	emit_change: bool = true
) -> int:
	if item_data == null or amount <= 0:
		return max(amount, 0)

	var remaining := amount

	# 1. Először töltsük fel a már meglévő stackeket.
	for inventory_item in items.duplicate():
		if remaining <= 0:
			break

		if inventory_item.item_data.id != item_data.id:
			continue
		# try_add_item adds an unupgraded, unenchanted item definition.
		# Never merge it into an upgraded/enchantened stack.
		if inventory_item.upgrade_level != 0 or not inventory_item.enchantment_ids.is_empty():
			continue

		if inventory_item.amount >= item_data.max_stack:
			continue

		var free_space = (
			item_data.max_stack - inventory_item.amount
		)

		var transfer_amount = min(
			remaining,
			free_space
		)

		inventory_item.amount += transfer_amount
		remaining -= transfer_amount

	# 2. A maradékhoz keressünk új helyet.
	while remaining > 0:
		var position := find_free_position(item_data)

		if position == Vector2i(-1, -1):
			break

		var stack_amount = min(
			remaining,
			item_data.max_stack
		)

		var new_item = add_item(
			item_data,
			position,
			stack_amount,
			false
		)

		if new_item == null:
			break

		remaining -= stack_amount

	if emit_change:
		inventory_changed.emit()

	return remaining

func can_add_item(
	item_data: ItemData,
	amount: int = 1
) -> bool:
	var simulation = Inventory.new()

	simulation.width = width
	simulation.height = height

	for existing_item in items:
		var copy = InventoryItem.new()

		copy.item_data = existing_item.item_data
		copy.position = existing_item.position
		copy.amount = existing_item.amount
		copy.upgrade_level = existing_item.upgrade_level
		copy.enchantment_ids = existing_item.enchantment_ids.duplicate()

		simulation.items.append(copy)

	var remaining = simulation.try_add_item(
		item_data,
		amount
	)

	return remaining == 0
