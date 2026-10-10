extends Node
class_name GridManager

@export_group("Map Rétegek")
@export var floor_layer: TileMapLayer
@export var wall_layer: TileMapLayer
@export var decoratives_layer: TileMapLayer

var astar: AStarGrid2D
var cell_size: Vector2 = Vector2(16, 16)
var is_initialized: bool = false

func _ready() -> void:
	add_to_group("grid_manager")
	if floor_layer == null: floor_layer = get_tree().root.find_child("Floor", true, false) as TileMapLayer
	if wall_layer == null: wall_layer = get_tree().root.find_child("Wall", true, false) as TileMapLayer
	if decoratives_layer == null: decoratives_layer = get_tree().root.find_child("Decoratives", true, false) as TileMapLayer

	setup_astar()

func setup_astar() -> void:
	if not floor_layer: return
	cell_size = Vector2(floor_layer.tile_set.tile_size)
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
			if is_cell_solid(cell):
				astar.set_point_solid(cell, true)

	is_initialized = true

func is_cell_solid(cell: Vector2i) -> bool:
	if floor_layer == null: return true
	var floor_data = _get_safe_tile_data(floor_layer, cell)
	if floor_data == null: return true
	if is_tile_blocking(floor_data, floor_layer.tile_set, false): return true

	if wall_layer != null:
		var wall_data = _get_safe_tile_data(wall_layer, cell)
		if wall_data != null and is_tile_blocking(wall_data, wall_layer.tile_set, true): return true

	if decoratives_layer != null:
		var decor_data = _get_safe_tile_data(decoratives_layer, cell)
		if decor_data != null and is_tile_blocking(decor_data, decoratives_layer.tile_set, false): return true

	return false

func _get_safe_tile_data(layer: TileMapLayer, cell: Vector2i) -> TileData:
	if layer == null or layer.tile_set == null: return null
	var source_id = layer.get_cell_source_id(cell)
	if source_id == -1 or not layer.tile_set.has_source(source_id): return null
	return layer.get_cell_tile_data(cell)

func is_tile_blocking(tile_data: TileData, tile_set: TileSet, default_blocking: bool) -> bool:
	if tile_data == null: return false
	if tile_set != null:
		var idx_camel = tile_set.get_custom_data_layer_by_name("isWall")
		if idx_camel != -1 and tile_data.get_custom_data_by_layer_id(idx_camel) == true: return true
		var idx_snake = tile_set.get_custom_data_layer_by_name("is_wall")
		if idx_snake != -1 and tile_data.get_custom_data_by_layer_id(idx_snake) == true: return true
	if tile_data.get_collision_polygons_count(0) > 0: return true
	return default_blocking

func get_grid_distance(a: Vector2i, b: Vector2i) -> int:
	return maxi(absi(a.x - b.x), absi(a.y - b.y))

func get_manhattan_distance(a: Vector2i, b: Vector2i) -> int:
	return absi(a.x - b.x) + absi(a.y - b.y)
