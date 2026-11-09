extends Node
class_name GridMover

var controller: EnemyController
var grid_manager: GridManager

var grid_pos: Vector2i = Vector2i.ZERO
var current_step_target: Vector2i = Vector2i.ZERO
var is_moving: bool = false
var path_queue: Array[Vector2i] = []

var floor_layer: TileMapLayer:
	get: return grid_manager.floor_layer if grid_manager else null

var astar: AStarGrid2D:
	get: return grid_manager.astar if grid_manager else null

func setup(p_controller: EnemyController) -> void:
	controller = p_controller
	grid_manager = get_tree().get_first_node_in_group("grid_manager") as GridManager

	if grid_manager and grid_manager.floor_layer:
		var fl = grid_manager.floor_layer
		grid_pos = fl.local_to_map(fl.to_local(controller.global_position))
		controller.position = fl.map_to_local(grid_pos)
		current_step_target = grid_pos

func is_cell_walkable(cell: Vector2i) -> bool:
	if not grid_manager: return false
	if grid_manager.is_cell_solid(cell):
		return false
	return not is_cell_blocked_by_entity(cell)

func is_cell_blocked_by_entity(cell: Vector2i) -> bool:
	var hero = _find_hero()
	if hero != null and is_instance_valid(hero) and hero.is_alive():
		if hero.grid_pos == cell:
			return true
		if hero.is_moving and hero.get("current_step_target") == cell:
			return true

	for enemy in get_tree().get_nodes_in_group("enemies"):
		if enemy != controller and is_instance_valid(enemy) and enemy.is_monster_alive():
			if enemy.grid_pos == cell:
				return true
			if enemy.is_moving and enemy.get("current_step_target") == cell:
				return true

	return false

func _start_moving_path(new_path: Array[Vector2i]) -> void:
	path_queue = new_path
	if not is_moving:
		_step_next_in_queue()

func _step_next_in_queue() -> void:
	var hero = _find_hero()
	if hero != null and hero.in_battle:
		is_moving = false
		current_step_target = grid_pos
		return

	if path_queue.is_empty() or controller.is_dead or controller.is_attacking:
		is_moving = false
		current_step_target = grid_pos
		if controller.visuals and not controller.is_dead and not controller.is_attacking:
			controller.visuals.play_idle_anim()
		return

	var next_cell = path_queue.pop_front()
	if is_cell_blocked_by_entity(next_cell) or (grid_manager and grid_manager.is_cell_solid(next_cell)):
		path_queue.clear()
		is_moving = false
		current_step_target = grid_pos
		return

	current_step_target = next_cell
	is_moving = true

	if controller.visuals:
		controller.visuals.update_facing(next_cell.x)

	grid_pos = next_cell

	if controller.visuals:
		controller.visuals.play_move_anim()

	var fl = grid_manager.floor_layer if grid_manager else null
	if not fl:
		is_moving = false
		return

	var target_world = fl.map_to_local(grid_pos)
	var dur = controller.enemy_data.move_duration if controller.enemy_data else 0.5

	var tween = controller.create_tween()
	tween.tween_property(controller, "position", target_world, dur)
	tween.finished.connect(_on_step_finished)

func _on_step_finished() -> void:
	if controller.visuals:
		controller.visuals.update_fog_visibility()

	var hero = _find_hero()
	if hero and controller.combat and controller.combat.can_attack_hero(hero.grid_pos) and not hero.in_battle:
		path_queue.clear()
		is_moving = false
		if controller.visuals:
			controller.visuals.update_facing(hero.grid_pos.x)

		if controller.attack_range > 1:
			controller.combat._perform_overworld_ranged_initiation(hero)
		else:
			controller.combat.attack_hero(hero)
		return

	_step_next_in_queue()

func _find_hero() -> HeroController:
	var heroes = get_tree().get_nodes_in_group("player")
	return heroes[0] if not heroes.is_empty() else null
