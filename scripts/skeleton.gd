extends Node2D
class_name EnemySkeleton

@export_group("Adatmodell és Statisztikák")
@export var monster_data: MonsterData
@export var attack_range: int = 1 # Melee csontváznál 1, íjásznál pl. 4-5 tile

@export_group("Map és Köd Referenciák")
@export var floor_layer: TileMapLayer
@export var wall_layer: TileMapLayer
@export var decoratives_layer: TileMapLayer
@export var fog_of_war: FogOfWar

@export_group("Mozgásbeállítások")
@export var start_facing_left: bool = false
@export var move_distance: int = 1
@export var move_duration: float = 0.5
@export var action_interval: float = 1.5
@export var aggro_range: int = 3

@onready var sprite: AnimatedSprite2D = $AnimatedSprite2D

var is_dead: bool = false
var has_resurrected: bool = false

var grid_pos: Vector2i = Vector2i.ZERO
var is_moving: bool = false
var is_attacking: bool = false
var cell_size: Vector2 = Vector2(16, 16)

var astar: AStarGrid2D
var path_queue: Array[Vector2i] = []
var ai_timer: Timer

var monster_name: String:
	get:
		if monster_data and monster_data.monster_name != "": return monster_data.monster_name
		return "Csontváz"

var title: String:
	get: return monster_data.title if monster_data else ""

var current_hp: int:
	get: return get_current_hp()

var max_hp: int:
	get: return get_max_hp()

var defense: int:
	get: return get_defense()

var initiative: float:
	get: return get_initiative()

func _ready() -> void:
	add_to_group("enemies")
	z_index = 8
	visible = false

	if floor_layer == null: floor_layer = get_tree().root.find_child("Floor", true, false) as TileMapLayer
	if wall_layer == null: wall_layer = get_tree().root.find_child("Wall", true, false) as TileMapLayer
	if decoratives_layer == null: decoratives_layer = get_tree().root.find_child("Decoratives", true, false) as TileMapLayer
	if fog_of_war == null: fog_of_war = get_tree().root.find_child("FogOfWar", true, false) as FogOfWar

	if monster_data == null:
		monster_data = MonsterData.new()
		monster_data.monster_name = "Csontváz"
		monster_data.max_hp = 45
		monster_data.base_damage = 12
		monster_data.defense = 1
		monster_data.initiative = 9.0
		monster_data.xp_reward = 25

	monster_data.initialize()

	if floor_layer:
		cell_size = Vector2(floor_layer.tile_set.tile_size)
		grid_pos = floor_layer.local_to_map(floor_layer.to_local(global_position))
		position = floor_layer.map_to_local(grid_pos)

	if sprite:
		sprite.flip_h = start_facing_left
		sprite.play("idle")

	setup_astar()
	_setup_autonomous_ai()
	update_fog_visibility()

func get_monster_name() -> String: return monster_name
func get_initiative() -> float: return monster_data.get_initiative() if monster_data else 9.0
func get_defense() -> int: return monster_data.get_defense() if monster_data else 1
func get_current_hp() -> int: return monster_data.get_current_hp() if monster_data else 0
func get_max_hp() -> int: return monster_data.get_max_hp() if monster_data else 45
func get_title() -> String: return monster_data.title if monster_data else ""
func is_monster_alive() -> bool: return not is_dead and (monster_data != null and monster_data.is_alive())
func get_attack_range() -> int: return attack_range

func roll_attack_damage() -> int:
	if monster_data: return monster_data.roll_attack_damage()
	return ceili(12.0 * randf_range(0.8, 1.0))

func take_damage(incoming_raw_damage: int) -> int:
	if is_dead or monster_data == null: return 0
	var actual_damage = monster_data.take_damage(incoming_raw_damage)

	if not monster_data.is_alive():
		if not has_resurrected:
			has_resurrected = true
			var revive_hp = int(float(monster_data.get_max_hp()) * 0.5)
			monster_data.initialize()
			monster_data.take_damage(monster_data.get_max_hp() - revive_hp)
			print("★ [CSONTVÁZ ÚJRAÉLEDÉS] A csontok összeforrtak a mezőn! Újra él %d/%d HP-val!" % [
				monster_data.get_current_hp(), monster_data.get_max_hp()
			])
		else:
			is_dead = true
			if ai_timer and is_instance_valid(ai_timer): ai_timer.stop()
			path_queue.clear()
			remove_from_group("enemies")

	return actual_damage

## A szörny harci köre közvetlenül a mezőjén:
func perform_combat_turn(target_hero: HeroController) -> int:
	if is_dead or not is_instance_valid(target_hero): return 0
	update_facing(target_hero.grid_pos.x)

	# 1. Támadás animáció a mezőn
	var anim = "attack_1" if randf() < 0.5 else "attack_2"
	if sprite and sprite.sprite_frames.has_animation(anim):
		sprite.play(anim)
		await sprite.animation_finished
		if not is_dead and sprite: sprite.play("idle")

	# 2. Sebzés átadása és a hős sérülési reakciója
	var raw_dmg = roll_attack_damage()
	var dealt = target_hero.take_damage(raw_dmg)
	target_hero.play_hurt_reaction()

	return dealt

func play_hurt_reaction() -> void:
	if sprite and sprite.sprite_frames.has_animation("hurt") and not is_dead:
		sprite.play("hurt")
		await sprite.animation_finished
		if sprite and not is_dead: sprite.play("idle")

## SZIGORÚAN A HARC UTÁN: Halál animáció lejátszása a mezőn
func play_overworld_death() -> void:
	if sprite and sprite.sprite_frames.has_animation("death"):
		sprite.play("death")
		await sprite.animation_finished
	queue_free()

func attack_hero(target_hero: HeroController) -> void:
	if is_dead or is_attacking or not is_monster_alive(): return
	var battle_ui = get_tree().get_first_node_in_group("battle_ui") as BattleDialog
	if battle_ui != null and not battle_ui.combat_active:
		battle_ui.open_battle(target_hero, self)

# --- AI, LEFAGYASZTÁS ÉS RÁCSMOZGÁS ---

func _setup_autonomous_ai() -> void:
	ai_timer = Timer.new()
	ai_timer.wait_time = action_interval
	ai_timer.autostart = true
	ai_timer.one_shot = false
	ai_timer.timeout.connect(_on_ai_tick)
	add_child(ai_timer)

func _on_ai_tick() -> void:
	if is_dead or is_moving or is_attacking or not is_monster_alive(): return

	var hero = _find_hero()
	# VILÁG LEFAGYASZTÁSA: Ha a hős épp harcol bárkivel, az összes többi szörny azonnal megáll!
	if hero != null and hero.in_battle:
		return

	if hero != null and is_instance_valid(hero) and hero.is_alive():
		var dist = _manhattan_distance(grid_pos, hero.grid_pos)
		if dist == 1:
			update_facing(hero.grid_pos.x)
			attack_hero(hero)
			return

		if dist <= aggro_range and astar != null:
			var full_path = astar.get_id_path(grid_pos, hero.grid_pos)
			if full_path.size() > 1:
				full_path.remove_at(0)
				if full_path.back() == hero.grid_pos: full_path.pop_back()
				var sliced_path: Array[Vector2i] = []
				var steps = mini(move_distance, full_path.size())
				for i in range(steps): sliced_path.append(full_path[i])
				if not sliced_path.is_empty():
					_start_moving_path(sliced_path)
					return

	_wander_multiple_tiles()

func _wander_multiple_tiles() -> void:
	if randf() < 0.35: return
	var directions = [Vector2i.RIGHT, Vector2i.LEFT, Vector2i.DOWN, Vector2i.UP]
	directions.shuffle()
	for dir in directions:
		var test_path: Array[Vector2i] = []
		var current = grid_pos
		for step in range(randi_range(1, move_distance)):
			var next = current + dir
			if is_cell_walkable(next):
				test_path.append(next)
				current = next
			else: break
		if not test_path.is_empty():
			_start_moving_path(test_path)
			return

func _start_moving_path(new_path: Array[Vector2i]) -> void:
	path_queue = new_path
	if not is_moving: _step_next_in_queue()

func _step_next_in_queue() -> void:
	var hero = _find_hero()
	if hero != null and hero.in_battle:
		is_moving = false
		return

	if path_queue.is_empty() or is_dead or is_attacking:
		is_moving = false
		if sprite and not is_dead and not is_attacking: sprite.play("idle")
		return

	var next_cell = path_queue.pop_front()
	if is_cell_blocked_by_entity(next_cell):
		path_queue.clear()
		is_moving = false
		return

	is_moving = true
	grid_pos = next_cell
	update_facing(grid_pos.x)
	if sprite and sprite.sprite_frames.has_animation("walk"): sprite.play("walk")

	var target_world = floor_layer.map_to_local(grid_pos)
	var tween = create_tween()
	tween.tween_property(self, "position", target_world, move_duration)
	tween.finished.connect(_on_step_finished)

func _on_step_finished() -> void:
	update_fog_visibility()
	var hero = _find_hero()
	if hero and _manhattan_distance(grid_pos, hero.grid_pos) == 1 and not hero.in_battle:
		path_queue.clear()
		is_moving = false
		update_facing(hero.grid_pos.x)
		attack_hero(hero)
		return
	_step_next_in_queue()

func _manhattan_distance(a: Vector2i, b: Vector2i) -> int: return absi(a.x - b.x) + absi(a.y - b.y)

func _get_safe_tile_data(layer: TileMapLayer, cell: Vector2i) -> TileData:
	if layer == null or layer.tile_set == null: return null
	var source_id = layer.get_cell_source_id(cell)
	if source_id == -1 or not layer.tile_set.has_source(source_id): return null
	return layer.get_cell_tile_data(cell)

func setup_astar() -> void:
	if not floor_layer: return
	astar = AStarGrid2D.new()
	var full_region: Rect2i = floor_layer.get_used_rect()
	if wall_layer: full_region = full_region.merge(wall_layer.get_used_rect())
	if decoratives_layer: full_region = full_region.merge(decoratives_layer.get_used_rect())
	astar.region = full_region
	astar.cell_size = cell_size
	astar.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_NEVER
	astar.update()

	for x in range(astar.region.position.x, astar.region.end.x):
		for y in range(astar.region.position.y, astar.region.end.y):
			var cell = Vector2i(x, y)
			if not is_cell_static_walkable(cell): astar.set_point_solid(cell, true)

func is_cell_static_walkable(cell: Vector2i) -> bool:
	if floor_layer == null: return false
	var floor_data = _get_safe_tile_data(floor_layer, cell)
	if floor_data == null: return false
	if wall_layer and _get_safe_tile_data(wall_layer, cell) != null: return false
	if decoratives_layer:
		var decor_data = _get_safe_tile_data(decoratives_layer, cell)
		if decor_data != null and decor_data.get_collision_polygons_count(0) > 0: return false
	return true

func is_cell_walkable(cell: Vector2i) -> bool:
	if not is_cell_static_walkable(cell): return false
	return not is_cell_blocked_by_entity(cell)

func is_cell_blocked_by_entity(cell: Vector2i) -> bool:
	var hero = _find_hero()
	if hero and hero.grid_pos == cell: return true
	var enemies = get_tree().get_nodes_in_group("enemies")
	for enemy in enemies:
		if enemy != self and is_instance_valid(enemy) and enemy.get("grid_pos") == cell: return true
	return false

func _find_hero() -> HeroController:
	var heroes = get_tree().get_nodes_in_group("player")
	if not heroes.is_empty(): return heroes[0] as HeroController
	return null

func update_facing(target_grid_x: int) -> void:
	if not sprite: return
	if target_grid_x < grid_pos.x: sprite.flip_h = true
	elif target_grid_x > grid_pos.x: sprite.flip_h = false

func update_fog_visibility() -> void:
	if fog_of_war == null: fog_of_war = get_tree().root.find_child("FogOfWar", true, false) as FogOfWar
	if fog_of_war and fog_of_war.is_initialized:
		visible = (grid_pos in fog_of_war.current_visible_cells)
	else:
		var hero = _find_hero()
		visible = hero.is_tile_in_vision(grid_pos) if hero else false

func take_turn(hero: HeroController) -> void:
	if is_dead or is_moving or is_attacking or not is_monster_alive():
		return
	# Reakció a kör átadásakor (ha látótávon belül van, elindul a hős felé):
	_on_ai_tick()
