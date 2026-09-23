extends Node2D
class_name HeroController

@export_group("Kaszt és Megjelenés")
@export var character_class: CharacterClass # Ide húzd be a knight_class.tres-t!

@export_group("Map Rétegek")
@export var floor_layer: TileMapLayer       # TileMapLayer_Floor
@export var wall_layer: TileMapLayer        # TileMapLayer_Wall
@export var decoratives_layer: TileMapLayer # TileMapLayer_Decoratives

@export_group("Játékmenet")
@export var move_duration: float = 0.15
@export var fog_of_war: FogOfWar

# Csomópont hivatkozás az animációhoz
@onready var sprite: AnimatedSprite2D = $AnimatedSprite2D

# Futásidejű statisztikák
var current_hp: int = 100
var max_hp: int = 100
var attack_power: int = 15
var initiative: int = 10
var level: int = 1
var xp: int = 0

var primary_layer: TileMapLayer:
	get:
		return floor_layer

var grid_pos: Vector2i = Vector2i.ZERO
var is_moving: bool = false
var cell_size: Vector2 = Vector2(16, 16)

var astar: AStarGrid2D
var path_queue: Array[Vector2i] = []
var current_step_target: Vector2i = Vector2i.ZERO
var hovered_cell: Vector2i = Vector2i(-99999, -99999)

var vision_limit: int = 8 # 5x5 mező

func _ready() -> void:
	add_to_group("player")
	
	if not floor_layer:
		push_error("HIBA: A 'floor_layer' nincs hozzárendelve a Player Inspectorában!")
		return

	if floor_layer.tile_set:
		cell_size = Vector2(floor_layer.tile_set.tile_size)

	# Kaszt statisztikáinak és kinézetének betöltése
	apply_character_class()

	grid_pos = floor_layer.local_to_map(floor_layer.to_local(global_position))
	position = floor_layer.map_to_local(grid_pos)

	setup_grid_astar()
	update_fog_of_war()

func apply_character_class() -> void:
	if character_class:
		max_hp = character_class.max_hp
		current_hp = max_hp
		attack_power = character_class.base_damage
		initiative = character_class.initiative
		move_duration = character_class.move_duration

		if sprite and character_class.sprite_frames:
			sprite.sprite_frames = character_class.sprite_frames
			sprite.scale = character_class.sprite_scale
			sprite.offset = character_class.sprite_offset
			sprite.play("idle")
	else:
		if sprite:
			sprite.play("idle")

func setup_grid_astar() -> void:
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
			if is_cell_solid(cell):
				astar.set_point_solid(cell, true)

func is_cell_solid(cell: Vector2i) -> bool:
	if floor_layer == null:
		return true

	var floor_data: TileData = floor_layer.get_cell_tile_data(cell)
	if floor_data == null:
		return true

	if is_tile_blocking(floor_data, floor_layer.tile_set, false):
		return true

	if wall_layer != null:
		var wall_data: TileData = wall_layer.get_cell_tile_data(cell)
		if wall_data != null:
			if is_tile_blocking(wall_data, wall_layer.tile_set, true):
				return true

	if decoratives_layer != null:
		var decor_data: TileData = decoratives_layer.get_cell_tile_data(cell)
		if decor_data != null:
			if is_tile_blocking(decor_data, decoratives_layer.tile_set, false):
				return true

	return false

func is_tile_blocking(tile_data: TileData, tile_set: TileSet, default_blocking: bool) -> bool:
	if tile_data == null:
		return false

	if tile_set != null:
		if tile_set.has_custom_data_layer_by_name("isWall"):
			var val = tile_data.get_custom_data("isWall")
			if val != null and typeof(val) == TYPE_BOOL:
				return val
		elif tile_set.has_custom_data_layer_by_name("is_wall"):
			var val = tile_data.get_custom_data("is_wall")
			if val != null and typeof(val) == TYPE_BOOL:
				return val

	if tile_data.get_collision_polygons_count(0) > 0:
		return true

	return default_blocking

func is_tile_in_vision(cell: Vector2i) -> bool:
	if fog_of_war and fog_of_war.is_initialized:
		return cell in fog_of_war.current_visible_cells

	var diff = cell - grid_pos
	return (diff.x * diff.x + diff.y * diff.y) <= vision_limit

func _process(_delta: float) -> void:
	if not floor_layer:
		return

	var current_cell = floor_layer.local_to_map(floor_layer.to_local(get_global_mouse_position()))
	if current_cell != hovered_cell:
		hovered_cell = current_cell
		queue_redraw()

func _draw() -> void:
	if not floor_layer:
		return

	var target_global = floor_layer.to_global(floor_layer.map_to_local(hovered_cell))
	var draw_pos = to_local(target_global)
	var rect = Rect2(draw_pos - cell_size / 2.0, cell_size)

	var blocked = is_cell_solid(hovered_cell) or not is_tile_in_vision(hovered_cell)
	var fill_color = Color(0.9, 0.2, 0.2, 0.25) if blocked else Color(1.0, 1.0, 1.0, 0.15)
	var border_color = Color(0.9, 0.2, 0.2, 0.9) if blocked else Color(1.0, 0.9, 0.3, 0.9)

	draw_rect(rect, fill_color, true)
	draw_rect(rect, border_color, false, 1.5)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		handle_mouse_click()

func handle_mouse_click() -> void:
	if not floor_layer or not astar:
		return

	var target_cell = floor_layer.local_to_map(floor_layer.to_local(get_global_mouse_position()))

	if not is_tile_in_vision(target_cell):
		return

	if is_cell_solid(target_cell):
		return

	var start_cell = current_step_target if is_moving else grid_pos

	var new_path = astar.get_id_path(start_cell, target_cell)
	if new_path.is_empty():
		return

	if new_path[0] == start_cell:
		new_path.remove_at(0)

	path_queue = new_path

	if not is_moving:
		_step_next_in_queue()

func _step_next_in_queue() -> void:
	if path_queue.is_empty():
		is_moving = false
		if sprite:
			sprite.play("idle")
		return

	is_moving = true
	current_step_target = path_queue.pop_front()

	# Karakter megfordítása amerre halad (Flip horizontal)
	var step_dir = current_step_target - grid_pos
	if sprite:
		if step_dir.x > 0:
			sprite.flip_h = false # Jobbra néz
		elif step_dir.x < 0:
			sprite.flip_h = true  # Balra néz

		if sprite.animation != "walk":
			sprite.play("walk")

	check_opportunity_attacks()

	var target_world_pos = floor_layer.map_to_local(current_step_target)
	var tween = create_tween()
	tween.tween_property(self, "position", target_world_pos, move_duration)
	tween.finished.connect(_on_step_finished)

func _on_step_finished() -> void:
	grid_pos = current_step_target
	update_fog_of_war()
	trigger_monsters_turn()
	_step_next_in_queue()

func check_opportunity_attacks() -> void:
	pass

func update_fog_of_war() -> void:
	if fog_of_war:
		fog_of_war.update_vision(grid_pos, vision_limit)
		# Értesítjük az összes pályán lévő szörnyet a látótér változásáról:
		get_tree().call_group("enemies", "update_fog_visibility")

func level_up() -> void:
	level += 1
	vision_limit *= 3
	max_hp = int(max_hp * 1.2)
	current_hp = max_hp # Teljes gyógyulás szintlépéskor
	attack_power = int(attack_power * 1.25)
	update_fog_of_war()
	print("[Szintlépés!] Új szint: ", level, " | Max HP: ", max_hp, " | Sebzés: ", attack_power)

func trigger_monsters_turn() -> void:
	var enemies = get_tree().get_nodes_in_group("enemies")
	for enemy in enemies:
		if is_instance_valid(enemy) and enemy.has_method("take_turn"):
			enemy.take_turn(self)
