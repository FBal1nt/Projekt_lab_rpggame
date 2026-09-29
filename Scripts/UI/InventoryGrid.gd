class_name InventoryGrid
extends Control


signal item_selected(item: InventoryItem)


@export var cell_size: int = 64

var inventory: Inventory
var selected_item: InventoryItem = null

var placement_preview: Panel
var preview_cell: Vector2i = Vector2i(-1, -1)

var drag_candidate: InventoryItem = null
var dragging_item: InventoryItem = null
var drag_offset: Vector2i = Vector2i.ZERO
var drag_start_position: Vector2 = Vector2.ZERO

var item_visuals: Dictionary = {}

const DRAG_THRESHOLD := 8.0

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP

	placement_preview = Panel.new()
	placement_preview.mouse_filter = Control.MOUSE_FILTER_IGNORE
	placement_preview.z_index = 100
	placement_preview.visible = false

	add_child(placement_preview)

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
	for child in get_children():
		if child != placement_preview:
			child.queue_free()

	item_visuals.clear()

	if placement_preview != null:
		placement_preview.hide()

	if inventory == null:
		return

	for inventory_item in inventory.items:
		create_item_visual(inventory_item)

	if placement_preview != null:
		move_child(placement_preview, -1)


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

	item_visuals[inventory_item] = item_panel

	var label := Label.new()

	label.text = inventory_item.item_data.display_name

	if inventory_item.amount > 1:
		label.text += "\nx" + str(inventory_item.amount)

	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	item_panel.add_child(label)

func select_item(item: InventoryItem) -> void:
	selected_item = item
	preview_cell = Vector2i(-1, -1)

	print("Selected item: ", item.item_data.display_name)

	item_selected.emit(item)

	queue_redraw()

func is_item_selected(item: InventoryItem) -> bool:
	return selected_item == item

func create_selected_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()

	style.bg_color = Color(0.25, 0.25, 0.35, 1.0)
	style.border_color = Color(1.0, 0.85, 0.2, 1.0)

	style.set_border_width_all(3)

	return style

func get_cell_from_mouse_position(mouse_position: Vector2) -> Vector2i:
	return Vector2i(
		floor(mouse_position.x / cell_size),
		floor(mouse_position.y / cell_size)
	)

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		handle_mouse_button(event)
	elif event is InputEventMouseMotion:
		handle_mouse_motion(event)

func try_move_selected_item(target_cell: Vector2i) -> void:
	if inventory == null:
		return

	if selected_item == null:
		return

	var moved := inventory.move_item(
		selected_item,
		target_cell
	)

	if moved:
		print(
			"Moved ",
			selected_item.item_data.display_name,
			" to ",
			target_cell
		)

		selected_item = null
		preview_cell = Vector2i(-1, -1)
		placement_preview.hide()
	else:
		print(
			"Cannot move ",
			selected_item.item_data.display_name,
			" to ",
			target_cell
		)

func _process(_delta: float) -> void:
	if selected_item == null:
		if placement_preview.visible:
			placement_preview.hide()

		return

	if inventory == null:
		return

	var mouse_position := get_local_mouse_position()

	if dragging_item != null:
		update_drag_visual(mouse_position)

	var grid_rect := Rect2(
		Vector2.ZERO,
		Vector2(
			inventory.width * cell_size,
			inventory.height * cell_size
		)
	)

	if not grid_rect.has_point(mouse_position):
		placement_preview.hide()
		return

	var mouse_cell := get_cell_from_mouse_position(mouse_position)

	var target_cell := mouse_cell

	if dragging_item != null:
		target_cell = mouse_cell - drag_offset

	if target_cell != preview_cell:
		preview_cell = target_cell
		update_placement_preview(target_cell)

func update_placement_preview(target_cell: Vector2i) -> void:
	if selected_item == null:
		placement_preview.hide()
		return

	var item_size := selected_item.item_data.size

	var can_place := inventory.can_place_item(
		selected_item.item_data,
		target_cell,
		selected_item
	)

	placement_preview.position = Vector2(
		target_cell.x * cell_size + 2,
		target_cell.y * cell_size + 2
	)

	placement_preview.size = Vector2(
		item_size.x * cell_size - 4,
		item_size.y * cell_size - 4
	)

	placement_preview.add_theme_stylebox_override(
		"panel",
		create_preview_style(can_place)
	)

	placement_preview.show()

func create_preview_style(can_place: bool) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()

	if can_place:
		style.bg_color = Color(0.2, 0.8, 0.2, 0.25)
		style.border_color = Color(0.3, 1.0, 0.3, 0.9)
	else:
		style.bg_color = Color(0.8, 0.2, 0.2, 0.25)
		style.border_color = Color(1.0, 0.3, 0.3, 0.9)

	style.set_border_width_all(3)

	return style

func handle_item_click(clicked_item: InventoryItem) -> void:
	if selected_item == null:
		select_item(clicked_item)
		return

	if selected_item == clicked_item:
		return

	try_move_selected_item(clicked_item.position)

func handle_mouse_button(event: InputEventMouseButton) -> void:
	if event.button_index != MOUSE_BUTTON_LEFT:
		return

	var cell := get_cell_from_mouse_position(event.position)

	if event.pressed:
		handle_left_mouse_press(cell, event.position)
	else:
		handle_left_mouse_release(cell)

func handle_left_mouse_press(cell: Vector2i, mouse_position: Vector2) -> void:
	if inventory == null:
		return

	var clicked_item := inventory.get_item_at_cell(cell)

	# Ha nincs kijelölt item, az itemre kattintás kijelöli.
	if selected_item == null:
		if clicked_item != null:
			select_item(clicked_item)

			drag_candidate = clicked_item
			drag_start_position = mouse_position
			drag_offset = cell - clicked_item.position

		return

	# Ha másik itemre kattintunk, megpróbáljuk oda áttenni
	# a jelenleg kijelölt itemet.
	if clicked_item != null and clicked_item != selected_item:
		try_move_selected_item(clicked_item.position)
		return

	# Ha ugyanarra az itemre kattintunk, kezdődhet a drag.
	if clicked_item == selected_item:
		drag_candidate = selected_item
		drag_start_position = mouse_position
		drag_offset = cell - selected_item.position
		return

	# Üres cella → a kétkattintásos mozgatás továbbra is működik.
	try_move_selected_item(cell)


func handle_mouse_motion(event: InputEventMouseMotion) -> void:
	if drag_candidate == null:
		return

	if not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		return

	if not dragging_item:
		var distance := event.position.distance_to(drag_start_position)

		if distance < DRAG_THRESHOLD:
			return

		dragging_item = drag_candidate
		selected_item = dragging_item

		var visual: Control = item_visuals.get(dragging_item)

		if visual != null:
			visual.z_index = 200

	update_drag_preview(event.position)
	update_drag_visual(event.position)

func update_drag_preview(mouse_position: Vector2) -> void:
	if dragging_item == null:
		placement_preview.hide()
		return

	var mouse_cell := get_cell_from_mouse_position(mouse_position)

	var target_cell := mouse_cell - drag_offset

	if target_cell != preview_cell:
		preview_cell = target_cell
		update_placement_preview(target_cell)

func handle_left_mouse_release(cell: Vector2i) -> void:
	if dragging_item == null:
		drag_candidate = null
		return

	var target_cell := cell - drag_offset

	var moved := inventory.move_item(
		dragging_item,
		target_cell
	)

	var visual: Control = item_visuals.get(dragging_item)

	if visual != null:
		visual.z_index = 0

	if moved:
		print(
			"Dragged ",
			dragging_item.item_data.display_name,
			" to ",
			target_cell
		)
	else:
		print(
			"Cannot place ",
			dragging_item.item_data.display_name,
			" at ",
			target_cell
		)
	if not moved:
		refresh()

	selected_item = null
	drag_candidate = null
	dragging_item = null

	preview_cell = Vector2i(-1, -1)
	placement_preview.hide()

func update_drag_visual(mouse_position: Vector2) -> void:
	if dragging_item == null:
		return

	var visual: Control = item_visuals.get(dragging_item)

	if visual == null:
		return

	visual.position = (
		mouse_position
		- Vector2(drag_offset * cell_size)
		+ Vector2(2, 2)
	)
