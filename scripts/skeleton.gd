extends Node2D
class_name EnemySkeleton

@export_group("Map és Köd Referenciák")
@export var floor_layer: TileMapLayer       # TileMapLayer_Floor
@export var wall_layer: TileMapLayer        # TileMapLayer_Wall
@export var decoratives_layer: TileMapLayer # TileMapLayer_Decoratives
@export var fog_of_war: FogOfWar

@export_group("Statisztikák és Mozgékonyság")
@export var start_facing_left: bool = false # Alapértelmezett nézési irány
@export var max_hp: int = 60
@export var attack_power: int = 12
@export var xp_reward: int = 45

@export_subgroup("Mozgásbeállítások")
@export var move_distance: int = 2          # Hány csempét fusson egy akció során (pl. 2, 3 vagy 4)!
@export var move_duration: float = 0.14     # Egy csempe megtételének ideje (kisebb = gyorsabb sprint)
@export var action_interval: float = 1.3    # Hány másodpercenként indítson új akciót
@export var aggro_range: int = 7            # Látótávolság mezőkben

@onready var sprite: AnimatedSprite2D = $AnimatedSprite2D

var current_hp: int
var grid_pos: Vector2i = Vector2i.ZERO
var is_moving: bool = false
var is_attacking: bool = false
var is_dead: bool = false
var cell_size: Vector2 = Vector2(16, 16)

var astar: AStarGrid2D
var path_queue: Array[Vector2i] = []
var ai_timer: Timer

func _ready() -> void:
	current_hp = max_hp
	z_index = 8

	if floor_layer:
		cell_size = Vector2(floor_layer.tile_set.tile_size)
		grid_pos = floor_layer.local_to_map(floor_layer.to_local(global_position))
		position = floor_layer.map_to_local(grid_pos)

	if sprite:
		sprite.flip_h = start_facing_left
		sprite.play("idle")

	setup_astar()
	update_fog_visibility()
	_setup_autonomous_ai()

# Beállítja az útvonalkeresőt a falak és a padló alapján
func setup_astar() -> void:
	if not floor_layer:
		return

	astar = AStarGrid2D.new()
	var full_region: Rect2i = floor_layer.get_used_rect()
	if wall_layer:
		full_region = full_region.merge(wall_layer.get_used_rect())
	if decoratives_layer:
		full_region = full_region.merge(decoratives_layer.get_used_rect())

	astar.region = full_region
	astar.cell_size = cell_size
	astar.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_NEVER
	astar.update()

	for x in range(astar.region.position.x, astar.region.end.x):
		for y in range(astar.region.position.y, astar.region.end.y):
			var cell = Vector2i(x, y)
			if not is_cell_static_walkable(cell):
				astar.set_point_solid(cell, true)

func _setup_autonomous_ai() -> void:
	ai_timer = Timer.new()
	ai_timer.wait_time = action_interval
	ai_timer.autostart = true
	ai_timer.one_shot = false
	ai_timer.timeout.connect(_on_ai_tick)
	add_child(ai_timer)

func _on_ai_tick() -> void:
	if is_dead or is_moving or is_attacking:
		return

	var hero = _find_hero()
	if hero != null and is_instance_valid(hero):
		var dist = _manhattan_distance(grid_pos, hero.grid_pos)

		# 1. Ha már eleve mellette áll: azonnali támadás
		if dist == 1:
			update_facing(hero.grid_pos.x)
			attack_hero(hero)
			return

		# 2. Ha látótávon belül van: többcsempés sprint a hős felé
		if dist <= aggro_range and astar != null:
			var full_path = astar.get_id_path(grid_pos, hero.grid_pos)
			if full_path.size() > 1:
				full_path.remove_at(0) # Kezdőpont törlése

				# A hős mezőjére nem lép rá, előtte kell megállnia
				if full_path.back() == hero.grid_pos:
					full_path.pop_back()

				# Csak legfeljebb 'move_distance' darab csempét tesz meg ebben a körben
				var sliced_path: Array[Vector2i] = []
				var steps = mini(move_distance, full_path.size())
				for i in range(steps):
					sliced_path.append(full_path[i])

				if not sliced_path.is_empty():
					_start_moving_path(sliced_path)
					return

	# 3. KÓBORLÁS: többcsempés járőrözés a szobában
	_wander_multiple_tiles()

func _wander_multiple_tiles() -> void:
	if randf() < 0.35: # Időnként csak egy helyben pihen
		if sprite and not is_moving and not is_attacking:
			sprite.play("idle")
		return

	var directions = [Vector2i.RIGHT, Vector2i.LEFT, Vector2i.DOWN, Vector2i.UP]
	directions.shuffle()

	# Keresünk egy irányt, amerre több szabad csempe is van egymás után
	for dir in directions:
		var test_path: Array[Vector2i] = []
		var current = grid_pos
		for step in range(randi_range(1, move_distance)):
			var next = current + dir
			if is_cell_walkable(next):
				test_path.append(next)
				current = next
			else:
				break

		if not test_path.is_empty():
			_start_moving_path(test_path)
			return

# Útvonallánc indítása
func _start_moving_path(new_path: Array[Vector2i]) -> void:
	path_queue = new_path
	if not is_moving:
		_step_next_in_queue()

func _step_next_in_queue() -> void:
	if path_queue.is_empty() or is_dead or is_attacking:
		is_moving = false
		if sprite and not is_dead and not is_attacking:
			sprite.play("idle")
		return

	var next_cell = path_queue.pop_front()

	# Ha a mezőt egy másik szörny vagy a hős blokkolja:
	if is_cell_blocked_by_entity(next_cell):
		path_queue.clear()
		is_moving = false
		if sprite and not is_dead:
			sprite.play("idle")
		return

	is_moving = true
	grid_pos = next_cell
	update_facing(grid_pos.x)

	if sprite and sprite.sprite_frames.has_animation("walk"):
		if sprite.animation != "walk":
			sprite.play("walk")

	var target_world = floor_layer.map_to_local(grid_pos)
	var tween = create_tween()
	tween.tween_property(self, "position", target_world, move_duration)
	tween.finished.connect(_on_step_finished)

func _on_step_finished() -> void:
	update_fog_visibility()

	# Ha lépés közben a hős mellé érünk, azonnal megállunk és ütünk!
	var hero = _find_hero()
	if hero and _manhattan_distance(grid_pos, hero.grid_pos) == 1:
		path_queue.clear()
		is_moving = false
		update_facing(hero.grid_pos.x)
		attack_hero(hero)
		return

	_step_next_in_queue()

func _manhattan_distance(a: Vector2i, b: Vector2i) -> int:
	return absi(a.x - b.x) + absi(a.y - b.y)

# Pálya statikus járhatósága (AStar-hoz)
func is_cell_static_walkable(cell: Vector2i) -> bool:
	if floor_layer == null:
		return false
	if floor_layer.get_cell_tile_data(cell) == null:
		return false
	if wall_layer and wall_layer.get_cell_tile_data(cell) != null:
		return false
	if decoratives_layer:
		var decor_data = decoratives_layer.get_cell_tile_data(cell)
		if decor_data != null:
			var is_wall = decor_data.get_custom_data("isWall")
			if is_wall == null:
				is_wall = decor_data.get_custom_data("is_wall")
			if is_wall == true or decor_data.get_collision_polygons_count(0) > 0:
				return false
	return true

# Dinamikus ellenőrzés (élőlények vizsgálata)
func is_cell_walkable(cell: Vector2i) -> bool:
	if not is_cell_static_walkable(cell):
		return false
	return not is_cell_blocked_by_entity(cell)

func is_cell_blocked_by_entity(cell: Vector2i) -> bool:
	var hero = _find_hero()
	if hero and hero.grid_pos == cell:
		return true

	var enemies = get_tree().get_nodes_in_group("enemies")
	for enemy in enemies:
		if enemy != self and is_instance_valid(enemy) and enemy.get("grid_pos") == cell:
			return true
	return false

func _find_hero() -> HeroController:
	var heroes = get_tree().get_nodes_in_group("player")
	if not heroes.is_empty():
		return heroes[0] as HeroController
	return null

func update_facing(target_grid_x: int) -> void:
	if not sprite:
		return
	if target_grid_x < grid_pos.x:
		sprite.flip_h = true
	elif target_grid_x > grid_pos.x:
		sprite.flip_h = false

func attack_hero(target_hero: HeroController) -> void:
	if is_dead or is_attacking or not sprite:
		return

	is_attacking = true
	var anim = "attack_1" if randf() < 0.5 else "attack_2"
	sprite.play(anim)

	var dmg = int(attack_power * randf_range(0.8, 1.0))
	print("[SKELETON TÁMADÁS] Sebzés: ", dmg)

	await sprite.animation_finished
	is_attacking = false

	if not is_dead:
		sprite.play("idle")

	if target_hero and is_instance_valid(target_hero):
		target_hero.take_damage(dmg)

func update_fog_visibility() -> void:
	if fog_of_war and fog_of_war.is_initialized:
		visible = (grid_pos in fog_of_war.current_visible_cells)

func take_damage(amount: int) -> void:
	if is_dead:
		return
	current_hp -= amount
	print("[SKELETON SEBZŐDÖTT] HP: ", current_hp)
	if current_hp <= 0:
		die()
	else:
		if sprite and sprite.sprite_frames.has_animation("hurt"):
			sprite.play("hurt")
			await sprite.animation_finished
			if not is_moving and not is_dead and not is_attacking:
				sprite.play("idle")

func die() -> void:
	is_dead = true
	if ai_timer and is_instance_valid(ai_timer):
		ai_timer.stop()
	path_queue.clear()
	remove_from_group("enemies")
	if sprite and sprite.sprite_frames.has_animation("death"):
		sprite.play("death")
		await sprite.animation_finished
	queue_free()

func take_turn(_hero: HeroController) -> void:
	pass
