class_name InventoryGrid
extends Control


signal item_selected(item: InventoryItem)
signal action_feedback(message: String, is_success: bool)


@export var cell_size: int = 64

var inventory: Inventory
var peer_grid: InventoryGrid = null
var selected_item: InventoryItem = null

var placement_preview: Panel
var preview_cell: Vector2i = Vector2i(-1, -1)

var drag_candidate: InventoryItem = null
var dragging_item: InventoryItem = null
var drag_offset: Vector2i = Vector2i.ZERO
var drag_start_position: Vector2 = Vector2.ZERO
# If the already-selected item is clicked again without dragging, treat it as a cancel.
var cancel_selection_if_click_released: bool = false

var item_visuals: Dictionary = {}
var external_purchase_data: Dictionary = {}

const DRAG_THRESHOLD := 8.0

# -----------------------------------------------------------------------------
# Setup and inventory binding
# -----------------------------------------------------------------------------

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


func set_peer_grid(new_peer_grid: InventoryGrid) -> void:
	peer_grid = new_peer_grid


func clear_selection() -> void:
	var had_selection := selected_item != null
	selected_item = null
	drag_candidate = null
	dragging_item = null
	cancel_selection_if_click_released = false
	preview_cell = Vector2i(-1, -1)
	if placement_preview != null:
		placement_preview.hide()
	if had_selection:
		item_selected.emit(null)
	queue_redraw()


func maybe_begin_drag_from_global_motion() -> void:
	# The parent window calls this even after the pointer leaves this Control,
	# so a fast drag can still cross into the other inventory grid.
	if drag_candidate == null or dragging_item != null:
		return
	if not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		return

	var mouse_position := get_local_mouse_position()
	if mouse_position.distance_to(drag_start_position) >= DRAG_THRESHOLD:
		begin_dragging()


func begin_dragging() -> void:
	if drag_candidate == null or dragging_item != null:
		return

	cancel_selection_if_click_released = false
	dragging_item = drag_candidate
	selected_item = dragging_item

	var visual: Control = item_visuals.get(dragging_item)
	if visual != null:
		visual.z_index = 200


func _on_inventory_changed() -> void:
	refresh()
	queue_redraw()


# -----------------------------------------------------------------------------
# Grid rendering and item visuals
# -----------------------------------------------------------------------------

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

	var item_label := inventory_item.item_data.display_name
	if inventory_item.upgrade_level > 0:
		item_label += " +%d" % inventory_item.upgrade_level
	if not inventory_item.enchantment_ids.is_empty():
		item_label += " (Enchant: %d)" % inventory_item.enchantment_ids.size()
	item_panel.tooltip_text = item_label + "\n\n" + inventory_item.item_data.description
	var stat_values := GameState.get_item_stats(inventory_item)
	if not stat_values.is_empty():
		var stat_parts: Array[String] = []
		for stat_key in stat_values.keys():
			stat_parts.append("%s: %s" % [String(stat_key), str(stat_values[stat_key])])
		item_panel.tooltip_text += "\n\n" + ", ".join(PackedStringArray(stat_parts))

	add_child(item_panel)

	item_visuals[inventory_item] = item_panel

	if inventory_item.item_data.icon != null:
		var icon := TextureRect.new()
		icon.texture = inventory_item.item_data.icon
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		item_panel.add_child(icon)
	else:
		# Readable fallback for new data-driven items that do not have art yet.
		var fallback := Label.new()
		var words := inventory_item.item_data.display_name.split(" ", false)
		var initials := ""
		for word in words:
			if not word.is_empty():
				initials += word.substr(0, 1).to_upper()
				if initials.length() >= 3:
					break
		fallback.text = initials if not initials.is_empty() else "?"
		fallback.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		fallback.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		fallback.mouse_filter = Control.MOUSE_FILTER_IGNORE
		fallback.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		fallback.add_theme_color_override("font_color", Color(0.92, 0.72, 0.38, 1.0))
		fallback.add_theme_font_size_override("font_size", 22)
		item_panel.add_child(fallback)

	if inventory_item.upgrade_level > 0:
		var upgrade_label := Label.new()
		upgrade_label.text = "+%d" % inventory_item.upgrade_level
		upgrade_label.position = Vector2(3, 1)
		upgrade_label.size = Vector2(46, 20)
		upgrade_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		upgrade_label.add_theme_color_override("font_color", Color(1.0, 0.82, 0.36, 1.0))
		upgrade_label.add_theme_font_size_override("font_size", 14)
		upgrade_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 1))
		upgrade_label.add_theme_constant_override("shadow_offset_x", 1)
		upgrade_label.add_theme_constant_override("shadow_offset_y", 1)
		item_panel.add_child(upgrade_label)

	if inventory_item.amount > 1:
		var amount_label := Label.new()

		amount_label.text = str(inventory_item.amount)

		amount_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		amount_label.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM

		amount_label.set_anchors_and_offsets_preset(
			Control.PRESET_FULL_RECT
		)

		item_panel.add_child(amount_label)

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

# -----------------------------------------------------------------------------
# Godot drag-and-drop bridge (including shop purchase previews)
# -----------------------------------------------------------------------------

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		handle_mouse_button(event)
	elif event is InputEventMouseMotion:
		handle_mouse_motion(event)


func _can_drop_data(at_position: Vector2, data: Variant) -> bool:
	if inventory == null or typeof(data) != TYPE_DICTIONARY:
		return false
	if str(data.get("kind", "")) != "shop_purchase":
		return false
	if not (data.get("item_data") is ItemData):
		return false

	external_purchase_data = data
	_update_external_purchase_preview(at_position, external_purchase_data)
	# Return true for recognized shop data even if the current target is invalid,
	# so _drop_data can report the reason and the preview can turn red.
	return true


func _drop_data(at_position: Vector2, data: Variant) -> void:
	if typeof(data) != TYPE_DICTIONARY or str(data.get("kind", "")) != "shop_purchase":
		return
	var item_data := data.get("item_data") as ItemData
	if item_data == null:
		return

	var amount := maxi(int(data.get("amount", 1)), 1)
	var target_cell := get_cell_from_mouse_position(at_position)
	if GameState.buy_item_at(item_data, target_cell, amount):
		action_feedback.emit(
			"Megvásárolva: %s (-%d arany)." % [item_data.display_name, item_data.buy_price * amount],
			true
		)
	else:
		var reason := GameState.get_buy_item_at_failure_reason(item_data, target_cell, amount)
		if reason.is_empty():
			reason = "A vásárlás nem sikerült."
		action_feedback.emit(reason, false)

	# A shop drag is not an inventory-item drag; clear any old local selection
	# so its placement preview cannot reappear when the shop drag ends.
	clear_selection()
	external_purchase_data.clear()
	preview_cell = Vector2i(-1, -1)
	if placement_preview != null:
		placement_preview.hide()


func _update_external_purchase_preview(at_position: Vector2, data: Dictionary) -> void:
	if inventory == null or placement_preview == null:
		return
	var item_data := data.get("item_data") as ItemData
	if item_data == null:
		placement_preview.hide()
		return

	var grid_size := Vector2(inventory.width * cell_size, inventory.height * cell_size)
	if not Rect2(Vector2.ZERO, grid_size).has_point(at_position):
		placement_preview.hide()
		return

	var target_cell := get_cell_from_mouse_position(at_position)
	var preview_position := target_cell
	var preview_size := item_data.size
	var target_item := inventory.get_item_at_cell(target_cell)
	if target_item != null and target_item.item_data != null and target_item.item_data.id == item_data.id:
		preview_position = target_item.position
		preview_size = target_item.item_data.size

	var amount := maxi(int(data.get("amount", 1)), 1)
	var can_buy_here := GameState.can_buy_item_at(item_data, target_cell, amount)
	placement_preview.position = Vector2(
		preview_position.x * cell_size + 2,
		preview_position.y * cell_size + 2
	)
	placement_preview.size = Vector2(
		maxi(preview_size.x * cell_size - 4, 4),
		maxi(preview_size.y * cell_size - 4, 4)
	)
	placement_preview.add_theme_stylebox_override("panel", create_preview_style(can_buy_here))
	placement_preview.show()
	preview_cell = target_cell


func _notification(what: int) -> void:
	if what == NOTIFICATION_DRAG_END:
		var was_shop_drag := not external_purchase_data.is_empty()
		external_purchase_data.clear()
		if placement_preview != null:
			placement_preview.hide()
		preview_cell = Vector2i(-1, -1)
		if was_shop_drag:
			clear_selection()

# -----------------------------------------------------------------------------
# Placement previews and validated item movement
# -----------------------------------------------------------------------------

func try_place_selected_item(target_cell: Vector2i) -> void:
	if inventory == null:
		return

	if selected_item == null:
		return

	# Dropping an item back onto its exact original anchor is a valid no-op.
	# Do not ask the inventory to move an item onto the cell it already occupies;
	# simply finish the interaction and leave the item and save data untouched.
	if target_cell == selected_item.position:
		clear_selection()
		preview_cell = Vector2i(-1, -1)
		if placement_preview != null:
			placement_preview.hide()
		return

	var target_item := inventory.get_item_at_cell(
		target_cell,
		selected_item
	)

	# Azonos item → stackelési kísérlet.
	if target_item != null:
		if inventory.can_stack(selected_item, target_item):
			var item_being_merged := selected_item
			var merged := inventory.merge_items(
				item_being_merged,
				target_item
			)

			if merged and not inventory.items.has(item_being_merged):
				selected_item = null

			preview_cell = Vector2i(-1, -1)
			placement_preview.hide()
			return

		# Másik item vagy megtelt stack → nincs mozgatás.
		print(
			"Cannot place ",
			selected_item.item_data.display_name,
			" here."
		)

		return

	# Üres cella → normális mozgatás.
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
			"Cannot place ",
			selected_item.item_data.display_name,
			" at ",
			target_cell
		)

func _process(_delta: float) -> void:
	if inventory == null:
		return

	var mouse_position := get_local_mouse_position()

	# A shop purchase uses Godot's native drag-and-drop API. Keep its placement
	# preview active while the pointer is over this grid; it is green only when
	# both the target cell and the character's gold balance are valid.
	if not external_purchase_data.is_empty():
		# If the drag was released outside this grid, no _drop_data callback is
		# fired here. Clear the preview as soon as the left mouse button is up.
		if not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
			external_purchase_data.clear()
			clear_selection()
			placement_preview.hide()
			preview_cell = Vector2i(-1, -1)
			return
		_update_external_purchase_preview(mouse_position, external_purchase_data)
		return

	# The source grid continues to move the dragged item visual even when the
	# pointer is over the other grid.
	if dragging_item != null:
		update_drag_visual(mouse_position)

	# Pick the item this grid should preview. When the pointer crosses from the
	# backpack to the stash (or vice versa), the destination grid previews the
	# item selected/dragged by its peer instead of hiding the placement marker.
	var preview_item: InventoryItem = selected_item
	var external_drag_source: InventoryGrid = null
	if peer_grid != null and peer_grid.dragging_item != null:
		# Give an item actively dragged from the other panel priority over any
		# stale local selection, so the preview always matches the moving item.
		preview_item = peer_grid.dragging_item
		external_drag_source = peer_grid
	elif preview_item == null and peer_grid != null and peer_grid.selected_item != null:
		# Also preview cross-panel placement for the two-click interaction.
		preview_item = peer_grid.selected_item

	if preview_item == null:
		if placement_preview.visible:
			placement_preview.hide()
		return

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

	if dragging_item != null and preview_item == dragging_item:
		# Dragging within this grid.
		target_cell = mouse_cell - drag_offset
	elif external_drag_source != null:
		# Dragging from the peer grid: preserve the grabbed cell offset.
		target_cell = mouse_cell - external_drag_source.drag_offset

	# Also refresh when the preview was hidden on leaving a grid and the cursor
	# returns to the same cell.
	if target_cell != preview_cell or not placement_preview.visible:
		preview_cell = target_cell
		update_placement_preview(target_cell, preview_item)

func update_placement_preview(
	target_cell: Vector2i,
	item_to_preview: InventoryItem = null
) -> void:
	var preview_item: InventoryItem = item_to_preview if item_to_preview != null else selected_item
	if preview_item == null:
		placement_preview.hide()
		return

	var item_size := preview_item.item_data.size

	var target_item := inventory.get_item_at_cell(
		target_cell,
		preview_item
	)

	var can_place := inventory.can_place_item(
		preview_item.item_data,
		target_cell,
		preview_item
	)

	var can_stack := false

	if target_item != null:
		can_stack = inventory.can_stack(
			preview_item,
			target_item
		)

	var preview_position := target_cell
	var preview_size := item_size

	# Ha stackelhető célpontra mutatunk,
	# akkor ez is érvényes elhelyezési lehetőség.
	if can_stack:
		preview_position = target_item.position
		preview_size = target_item.item_data.size

	var placement_is_valid := can_place or can_stack

	placement_preview.position = Vector2(
		preview_position.x * cell_size + 2,
		preview_position.y * cell_size + 2
	)

	placement_preview.size = Vector2(
		preview_size.x * cell_size - 4,
		preview_size.y * cell_size - 4
	)

	placement_preview.add_theme_stylebox_override(
		"panel",
		create_preview_style(placement_is_valid)
	)

	placement_preview.show()

func create_preview_style(can_place: bool) -> StyleBoxFlat:
	var style = StyleBoxFlat.new()

	if can_place:
		style.bg_color = Color(0.2, 0.8, 0.2, 0.25)
		style.border_color = Color(0.3, 1.0, 0.3, 0.9)
	else:
		style.bg_color = Color(0.8, 0.2, 0.2, 0.25)
		style.border_color = Color(1.0, 0.3, 0.3, 0.9)

	style.set_border_width_all(3)

	return style

# -----------------------------------------------------------------------------
# Selection, double-click transfer and native drag handling
# -----------------------------------------------------------------------------

func handle_item_click(clicked_item: InventoryItem) -> void:
	if selected_item == null:
		select_item(clicked_item)
		return

	if selected_item == clicked_item:
		return

	try_place_selected_item(clicked_item.position)

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

	cancel_selection_if_click_released = false
	var clicked_item := inventory.get_item_at_cell(cell)

	# Ha a másik rácsban van kijelölt tárgy, a kattintás ide helyezi át.
	if selected_item == null:
		if peer_grid != null and peer_grid.selected_item != null:
			try_transfer_from_peer(cell)
			return

		# Ha nincs kijelölés egyik rácson sem, az itemre kattintás kijelöli.
		if clicked_item != null:
			select_item(clicked_item)

			drag_candidate = clicked_item
			drag_start_position = mouse_position
			drag_offset = cell - clicked_item.position

		return

	# Ha másik itemre kattintunk, megpróbáljuk oda áttenni
	# a jelenleg kijelölt itemet.
	if clicked_item != null and clicked_item != selected_item:
		try_place_selected_item(clicked_item.position)
		return

	# Ha ugyanarra az itemre kattintunk, kezdődhet a drag.
	if clicked_item == selected_item:
		# A second click on the selected item cancels the pickup if the pointer
		# is released without moving. If the pointer moves past the drag threshold,
		# the normal drag-and-drop path still takes over.
		cancel_selection_if_click_released = true
		drag_candidate = selected_item
		drag_start_position = mouse_position
		drag_offset = cell - selected_item.position
		return

	# Üres cella → a kétkattintásos mozgatás továbbra is működik.
	try_place_selected_item(cell)


func try_transfer_from_peer(target_cell: Vector2i) -> bool:
	if inventory == null or peer_grid == null:
		return false
	if peer_grid.inventory == null or peer_grid.selected_item == null:
		return false

	var source_grid: InventoryGrid = peer_grid
	var source_item: InventoryItem = source_grid.selected_item
	var target_item := inventory.get_item_at_cell(target_cell)
	var destination_position: Vector2i = target_cell
	if target_item != null:
		destination_position = target_item.position

	var transferred := source_grid.inventory.transfer_item_to(
		source_item,
		inventory,
		destination_position
	)

	if transferred:
		if not source_grid.inventory.items.has(source_item):
			source_grid.clear_selection()
		action_feedback.emit(
			"Áthelyezve: " + source_item.item_data.display_name,
			true
		)
	else:
		action_feedback.emit(
			"Nem lehet ide áthelyezni a tárgyat.",
			false
		)

	return transferred


func accept_external_drag(
	source_grid: InventoryGrid,
	target_cell: Vector2i,
	hovered_cell: Vector2i
) -> bool:
	if inventory == null or source_grid == null or source_grid.inventory == null:
		return false

	var source_item: InventoryItem = source_grid.dragging_item
	if source_item == null:
		return false

	# Ha a kurzor egy másik item fölött van, annak stackelési pozícióját használd.
	var hovered_item := inventory.get_item_at_cell(hovered_cell)
	var destination_position: Vector2i = target_cell
	if hovered_item != null:
		destination_position = hovered_item.position

	var transferred := source_grid.inventory.transfer_item_to(
		source_item,
		inventory,
		destination_position
	)

	source_grid.finish_external_drag(source_item)

	if transferred:
		action_feedback.emit(
			"Áthelyezve: " + source_item.item_data.display_name,
			true
		)
	else:
		action_feedback.emit(
			"Nem lehet ide áthelyezni a tárgyat.",
			false
		)

	return transferred


func finish_external_drag(source_item: InventoryItem) -> void:
	if inventory == null or not inventory.items.has(source_item):
		clear_selection()

	drag_candidate = null
	dragging_item = null
	preview_cell = Vector2i(-1, -1)
	if placement_preview != null:
		placement_preview.hide()
	# Refresh also snaps the dragged visual back when the transfer failed,
	# and redraws a partially transferred stack at its original cell.
	refresh()
	queue_redraw()


func cancel_external_drag() -> void:
	var dragged_item := dragging_item
	if dragged_item != null:
		finish_external_drag(dragged_item)
	else:
		drag_candidate = null
		dragging_item = null
		cancel_selection_if_click_released = false


func handle_mouse_motion(event: InputEventMouseMotion) -> void:
	if drag_candidate == null:
		return

	if not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		return

	if not dragging_item:
		var distance := event.position.distance_to(drag_start_position)

		if distance < DRAG_THRESHOLD:
			return

		begin_dragging()

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
		var should_cancel_selection := cancel_selection_if_click_released
		drag_candidate = null
		cancel_selection_if_click_released = false
		if should_cancel_selection:
			clear_selection()
		return

	var target_cell := cell - drag_offset
	cancel_selection_if_click_released = false

	var item_before := dragging_item

	try_place_selected_item(target_cell)

	var visual: Control = item_visuals.get(item_before)

	if visual != null:
		visual.z_index = 0

	# Ha nem sikerült elhelyezni, állítsuk vissza a vizuális helyzetet.
	if items_visual_still_exists(item_before):
		var current_visual: Control = item_visuals.get(item_before)

		if current_visual != null:
			current_visual.position = Vector2(
				item_before.position.x * cell_size + 2,
				item_before.position.y * cell_size + 2
			)

	drag_candidate = null
	dragging_item = null
	cancel_selection_if_click_released = false

	preview_cell = Vector2i(-1, -1)
	placement_preview.hide()

func items_visual_still_exists(item: InventoryItem) -> bool:
	if inventory == null:
		return false

	return inventory.items.has(item)

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
