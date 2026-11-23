extends CanvasLayer
class_name DungeonBackpackOverlay

signal backpack_closed

const INVENTORY_WINDOW_SCENE := preload("res://Scenes/Inventory/InventoryWindow.tscn")

var backdrop: ColorRect = null
var inventory_window: Panel = null
var _was_paused_before_open: bool = false


func _ready() -> void:
	add_to_group("dungeon_backpack")
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 50
	visible = false

	_build_overlay()


func _build_overlay() -> void:
	backdrop = ColorRect.new()
	backdrop.name = "BackpackBackdrop"
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	backdrop.color = Color(0.02, 0.025, 0.04, 0.78)
	backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(backdrop)

	var center := CenterContainer.new()
	center.name = "BackpackCenter"
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_PASS
	backdrop.add_child(center)

	inventory_window = INVENTORY_WINDOW_SCENE.instantiate() as Panel
	if inventory_window != null:
		inventory_window.name = "DungeonInventoryWindow"
		inventory_window.custom_minimum_size = Vector2(800, 620)
		inventory_window.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		inventory_window.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		center.add_child(inventory_window)
		if inventory_window.has_method("set_dungeon_mode"):
			inventory_window.set_dungeon_mode(true)
		if inventory_window.has_signal("close_requested"):
			inventory_window.close_requested.connect(close_backpack)
		inventory_window.hide()


func is_open() -> bool:
	return visible


func open_backpack() -> void:
	if visible or not is_inside_tree():
		return

	_was_paused_before_open = get_tree().paused
	get_tree().paused = true
	visible = true
	AudioManager.sfx(&"ui_window_open", 0.96, 1.04)

	if inventory_window != null:
		inventory_window.show()
		if inventory_window.has_method("refresh_window"):
			inventory_window.refresh_window()


func close_backpack() -> void:
	if not visible:
		return

	if inventory_window != null:
		var grid = inventory_window.get("backpack_grid")
		if grid != null and grid.has_method("cancel_external_drag"):
			grid.cancel_external_drag()
		inventory_window.hide()

	var vp := get_viewport()
	if vp != null:
		var focus_owner := vp.gui_get_focus_owner()
		if focus_owner != null and is_ancestor_of(focus_owner):
			focus_owner.release_focus()

	visible = false
	AudioManager.sfx(&"ui_window_close", 0.96, 1.04)
	if is_inside_tree():
		get_tree().paused = _was_paused_before_open
	backpack_closed.emit()


func _mark_input_handled() -> void:
	if not is_inside_tree():
		return
	var vp := get_viewport()
	if vp != null and vp.is_inside_tree():
		vp.set_input_as_handled()


func _is_blocked_by_higher_overlay() -> bool:
	var sm := get_node_or_null("/root/SettingsManager")
	if sm != null and sm.has_method("is_open") and sm.is_open():
		return true

	var pause_ui := get_tree().get_first_node_in_group("pause_menu")
	if pause_ui != null and pause_ui.visible:
		return true

	var death_ui := get_tree().get_first_node_in_group("death_screen")
	if death_ui != null and death_ui.visible:
		return true

	return false


func _input(event: InputEvent) -> void:
	if not visible or not is_inside_tree():
		return
	if _is_blocked_by_higher_overlay():
		return
	if not (event is InputEventKey):
		return
	var key_event := event as InputEventKey
	if not key_event.pressed or key_event.echo:
		return

	var kc := key_event.keycode
	var pkc := key_event.physical_keycode
	var sm := get_node_or_null("/root/SettingsManager")
	var is_toggle: bool = (
		bool(sm.matches_keybind(key_event, "toggle_backpack"))
		if (sm != null and sm.has_method("matches_keybind"))
		else (kc == KEY_TAB or pkc == KEY_TAB)
	)
	var is_esc := kc == KEY_ESCAPE or pkc == KEY_ESCAPE
	if is_toggle or is_esc:
		close_backpack()
		_mark_input_handled()
