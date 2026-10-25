extends Panel


@onready var backpack_grid: InventoryGrid = $MarginContainer/VBoxContainer/InventoryContainer/BackpackPanel/VBoxContainer/BackpackGrid
@onready var stash_grid: InventoryGrid = $MarginContainer/VBoxContainer/InventoryContainer/StashPanel/VBoxContainer/StashGrid
@onready var feedback_label: Label = $MarginContainer/VBoxContainer/FeedbackLabel
@onready var backpack_label: Label = $MarginContainer/VBoxContainer/InventoryContainer/BackpackPanel/VBoxContainer/Label
@onready var stash_label: Label = $MarginContainer/VBoxContainer/InventoryContainer/StashPanel/VBoxContainer/Label
@onready var title_label: Label = $MarginContainer/VBoxContainer/Title
@onready var close_button: Button = $MarginContainer/VBoxContainer/CloseButton


func _ready() -> void:
	backpack_grid.set_inventory(GameState.backpack)
	stash_grid.set_inventory(GameState.stash)
	_refresh_character_labels()
	if not GameState.active_character_changed.is_connected(_on_active_character_changed):
		GameState.active_character_changed.connect(_on_active_character_changed)

	backpack_grid.set_peer_grid(stash_grid)
	stash_grid.set_peer_grid(backpack_grid)

	backpack_grid.action_feedback.connect(_on_action_feedback)
	stash_grid.action_feedback.connect(_on_action_feedback)

	feedback_label.text = "Kattints egy tárgyra, majd a célrács egy üres helyére."


func _input(event: InputEvent) -> void:
	if not visible:
		return

	# Track drag thresholds globally so moving quickly between grids still works.
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

	# A source grid handles normal same-grid drops itself.
	if source_grid.get_global_rect().has_point(event.global_position):
		return

	var target_grid: InventoryGrid = source_grid.peer_grid
	if target_grid.get_global_rect().has_point(event.global_position):
		var target_mouse_position := target_grid.get_local_mouse_position()
		var hovered_cell := target_grid.get_cell_from_mouse_position(target_mouse_position)
		var target_cell := hovered_cell - source_grid.drag_offset
		target_grid.accept_external_drag(
			source_grid,
			target_cell,
			hovered_cell
		)
	else:
		# Don't leave a drag stuck if the mouse is released outside either grid.
		source_grid.cancel_external_drag()


func _on_action_feedback(message: String, is_success: bool) -> void:
	feedback_label.text = message
	if is_success:
		feedback_label.add_theme_color_override("font_color", Color(0.55, 0.95, 0.55))
	else:
		feedback_label.add_theme_color_override("font_color", Color(1.0, 0.45, 0.4))


func _on_close_button_pressed() -> void:
	hide()


func _on_active_character_changed(_character_id: String) -> void:
	# Clear both selection states before rebinding so no item reference from the
	# previous character can remain selected after a character switch.
	backpack_grid.clear_selection()
	stash_grid.clear_selection()
	backpack_grid.set_inventory(GameState.backpack)
	stash_grid.set_inventory(GameState.stash)
	_refresh_character_labels()
	feedback_label.text = "Aktív karakter hátizsákja betöltve; a Stash közös."
	feedback_label.remove_theme_color_override("font_color")


func _refresh_character_labels() -> void:
	var character := GameState.get_active_character()
	if character == null:
		title_label.text = "INVENTORY"
		backpack_label.text = "HÁTIZSÁK"
		return
	title_label.text = "INVENTORY — " + character.character_name.to_upper()
	backpack_label.text = "HÁTIZSÁK — " + character.character_name.to_upper()
	stash_label.text = "STASH (KÖZÖS)"
