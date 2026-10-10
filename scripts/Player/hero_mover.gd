extends Node
class_name HeroMover

var controller: HeroController
var grid_manager: GridManager

@export_group("Mozgás Beállítások")
@export var move_duration: float = 0.15

var move_tween: Tween
var grid_pos: Vector2i = Vector2i.ZERO
var current_step_target: Vector2i = Vector2i.ZERO
var is_moving: bool = false
var path_queue: Array[Vector2i] = []

func setup(p_controller: HeroController) -> void:
	controller = p_controller
	grid_manager = get_tree().get_first_node_in_group("grid_manager") as GridManager

	if grid_manager and grid_manager.floor_layer:
		var fl = grid_manager.floor_layer
		grid_pos = fl.local_to_map(fl.to_local(controller.global_position))
		controller.position = fl.map_to_local(grid_pos)
		current_step_target = grid_pos

func handle_move_click() -> void:
	if not grid_manager or not grid_manager.floor_layer or is_moving or controller.in_battle or not controller.is_alive():
		return

	var fl = grid_manager.floor_layer
	var target_cell = fl.local_to_map(fl.to_local(controller.get_global_mouse_position()))

	if target_cell == grid_pos:
		return

	if not controller.is_tile_in_vision(target_cell):
		return

	if grid_manager.is_cell_solid(target_cell):
		return

	if is_cell_blocked_for_player(target_cell):
		return

	if grid_manager.astar:
		var path = grid_manager.astar.get_id_path(grid_pos, target_cell)
		if path.size() > 1:
			path.remove_at(0)
			start_move_along_path(path)

func start_move_along_path(path: Array[Vector2i]) -> void:
	if controller.in_battle or controller.is_attacking or not controller.is_alive() or is_moving:
		return

	path_queue = path
	_step_next_in_queue()

func _step_next_in_queue() -> void:
	if path_queue.is_empty() or not controller.is_alive() or controller.in_battle:
		is_moving = false
		current_step_target = grid_pos
		if controller.visuals: controller.visuals.play_idle_anim()
		return

	var next_cell = path_queue.pop_front()

	if is_cell_blocked_for_player(next_cell):
		path_queue.clear()
		is_moving = false
		current_step_target = grid_pos
		if controller.visuals: controller.visuals.play_idle_anim()
		return

	current_step_target = next_cell
	is_moving = true

	if controller.visuals:
		controller.visuals.update_facing(next_cell.x)
		controller.visuals.play_walk_anim()

	grid_pos = next_cell

	var fl = grid_manager.floor_layer
	var target_world = fl.map_to_local(grid_pos)

	if move_tween and move_tween.is_valid():
		move_tween.kill()

	move_tween = controller.create_tween()
	move_tween.tween_property(controller, "position", target_world, move_duration)
	move_tween.finished.connect(_on_step_finished)

func is_cell_blocked_for_player(cell: Vector2i) -> bool:
	if grid_manager and grid_manager.is_cell_solid(cell):
		return true

	for enemy in get_tree().get_nodes_in_group("enemies"):
		if is_instance_valid(enemy) and enemy.has_method("is_monster_alive") and enemy.is_monster_alive():
			if enemy.grid_pos == cell: return true
			if enemy.is_moving and enemy.get("current_step_target") == cell: return true

	return false

func cancel_movement_immediately() -> void:
	path_queue.clear()
	is_moving = false
	current_step_target = grid_pos
	if move_tween and move_tween.is_valid():
		move_tween.kill()
	if grid_manager and grid_manager.floor_layer:
		controller.position = grid_manager.floor_layer.map_to_local(grid_pos)
	if controller.visuals:
		controller.visuals.play_idle_anim()

func _on_step_finished() -> void:
	if controller.visuals:
		controller.visuals.update_fog_of_war()

	controller.trigger_monsters_turn()
	_step_next_in_queue()
