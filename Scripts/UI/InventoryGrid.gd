class_name InventoryGrid
extends Control


@export var cell_size: int = 64

var inventory: Inventory


func set_inventory(new_inventory: Inventory) -> void:
	if inventory != null:
		if inventory.inventory_changed.is_connected(_on_inventory_changed):
			inventory.inventory_changed.disconnect(_on_inventory_changed)

	inventory = new_inventory

	if inventory != null:
		inventory.inventory_changed.connect(_on_inventory_changed)

		custom_minimum_size = Vector2(
			inventory.width * cell_size,
			inventory.height * cell_size
		)

		size = custom_minimum_size

	refresh()
	queue_redraw()


func _on_inventory_changed() -> void:
	refresh()
	queue_redraw()


func _draw() -> void:
	if inventory == null:
		return

	var grid_size := Vector2(
		inventory.width * cell_size,
		inventory.height * cell_size
	)

	# Háttér
	draw_rect(
		Rect2(Vector2.ZERO, grid_size),
		Color(0.12, 0.12, 0.12, 1.0)
	)

	# Függőleges vonalak
	for x in range(inventory.width + 1):
		var start := Vector2(x * cell_size, 0)
		var end := Vector2(x * cell_size, grid_size.y)

		draw_line(
			start,
			end,
			Color(0.35, 0.35, 0.35, 1.0),
			1.0
		)

	# Vízszintes vonalak
	for y in range(inventory.height + 1):
		var start := Vector2(0, y * cell_size)
		var end := Vector2(grid_size.x, y * cell_size)

		draw_line(
			start,
			end,
			Color(0.35, 0.35, 0.35, 1.0),
			1.0
		)


func refresh() -> void:
	# Korábbi item-megjelenítések törlése
	for child in get_children():
		child.queue_free()

	if inventory == null:
		return

	# Itemek kirajzolása
	for inventory_item in inventory.items:
		create_item_visual(inventory_item)


func create_item_visual(inventory_item: InventoryItem) -> void:
	var item_panel := Panel.new()

	item_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var item_position := inventory_item.position
	var item_size := inventory_item.item_data.size

	item_panel.position = Vector2(
		item_position.x * cell_size + 2,
		item_position.y * cell_size + 2
	)

	item_panel.size = Vector2(
		item_size.x * cell_size - 4,
		item_size.y * cell_size - 4
	)

	item_panel.tooltip_text = inventory_item.item_data.description

	add_child(item_panel)

	var label := Label.new()

	label.text = inventory_item.item_data.display_name

	if inventory_item.amount > 1:
		label.text += "\nx" + str(inventory_item.amount)

	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	item_panel.add_child(label)
