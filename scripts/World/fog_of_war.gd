extends Node2D
class_name FogOfWar

enum CellState { UNEXPLORED, IN_FOG, VISIBLE }

@export_group("Map Rétegek")
@export var floor_layer: TileMapLayer       # TileMapLayer_Floor
@export var wall_layer: TileMapLayer        # TileMapLayer_Wall
@export var decoratives_layer: TileMapLayer # TileMapLayer_Decoratives
@export var torch_layer: TileMapLayer       # TileMapLayer_Torch (IDE HÚZD BE A FÁKLYA RÉTEGET!)

@export_group("Fáklyák és Világítás")
@export var torch_offset: Vector2i = Vector2i(0, 0)
@export var torch_radius: int = 2 # 1 = 3x3 mező | 2 = 5x5 mező | 3 = 7x7 mező

@export_group("Köd Színek és Beállítások")
@export var unexplored_color: Color = Color(0.03, 0.03, 0.05, 1.0)
@export var fog_color: Color = Color(0.12, 0.12, 0.18, 0.65)
@export var void_margin: int = 20

var primary_layer: TileMapLayer:
	get:
		if floor_layer:
			return floor_layer
		if wall_layer:
			return wall_layer
		if decoratives_layer:
			return decoratives_layer
		return torch_layer

var cell_states: Dictionary = {}
var real_map_cells: Dictionary = {}
var current_visible_cells: Array[Vector2i] = []
var torch_cells: Array[Vector2i] = []
var cell_size: Vector2 = Vector2(16, 16)
var is_initialized: bool = false

func _ready() -> void:
	z_index = 5
	RenderingServer.set_default_clear_color(unexplored_color)

	if not is_initialized and primary_layer:
		init_fog()

func init_fog() -> void:
	if not primary_layer:
		push_error("[FogOfWar HIBA] Nincs réteg behúzva!")
		return

	if primary_layer.tile_set:
		cell_size = Vector2(primary_layer.tile_set.tile_size)

	cell_states.clear()
	real_map_cells.clear()
	torch_cells.clear()

	# Mind a négy réteget bevonjuk a pálya kiterjedésébe
	var layers: Array[TileMapLayer] = [floor_layer, wall_layer, decoratives_layer, torch_layer]
	var full_rect: Rect2i = Rect2i()
	var has_bounds: bool = false

	for layer in layers:
		if layer != null:
			var used_rect = layer.get_used_rect()
			if used_rect.size != Vector2i.ZERO:
				if not has_bounds:
					full_rect = used_rect
					has_bounds = true
				else:
					full_rect = full_rect.merge(used_rect)

			for cell in layer.get_used_cells():
				real_map_cells[cell] = true

	var expanded_rect: Rect2i = full_rect.grow(void_margin)
	for x in range(expanded_rect.position.x, expanded_rect.end.x):
		for y in range(expanded_rect.position.y, expanded_rect.end.y):
			cell_states[Vector2i(x, y)] = CellState.UNEXPLORED

	_collect_torches()

	is_initialized = true
	print("[FogOfWar] Inicializálva! Valós cellák: ", real_map_cells.size(), " | Fáklyák száma: ", torch_cells.size())
	queue_redraw()

func _collect_torches() -> void:
	# Elsősorban a dedikált fáklya réteget nézzük meg!
	var check_layers: Dictionary = {
		"TorchLayer": torch_layer,
		"Decoratives": decoratives_layer,
		"Wall": wall_layer
	}

	for layer_name in check_layers.keys():
		var layer: TileMapLayer = check_layers[layer_name]
		if layer == null or layer.tile_set == null:
			continue

		# Ha a réteg neve közvetlenül "torch_layer", és azon bármilyen csempe le van rakva:
		if layer == torch_layer:
			for cell in layer.get_used_cells():
				if not torch_cells.has(cell):
					torch_cells.append(cell)
			continue

		# Egyébként a szokásos is_torch / isTorch vizsgálat
		var torch_prop: String = ""
		for prop in ["is_torch", "isTorch", "torch", "Torch"]:
			if layer.tile_set.has_custom_data_layer_by_name(prop):
				torch_prop = prop
				break

		if torch_prop != "":
			for cell in layer.get_used_cells():
				var data = layer.get_cell_tile_data(cell)
				if data and data.get_custom_data(torch_prop) == true:
					if not torch_cells.has(cell):
						torch_cells.append(cell)

func update_vision(hero_pos: Vector2i, vision_limit: int) -> void:
	if not is_initialized:
		init_fog()

	for cell in current_visible_cells:
		cell_states[cell] = CellState.IN_FOG
	current_visible_cells.clear()

	var max_range: int = ceili(sqrt(vision_limit))
	for dx in range(-max_range, max_range + 1):
		for dy in range(-max_range, max_range + 1):
			if (dx * dx) + (dy * dy) <= vision_limit:
				var target_cell = hero_pos + Vector2i(dx, dy)
				if real_map_cells.has(target_cell):
					cell_states[target_cell] = CellState.VISIBLE
					current_visible_cells.append(target_cell)

	apply_torch_lights()
	queue_redraw()

func apply_torch_lights() -> void:
	for origin in torch_cells:
		var center_cell: Vector2i = origin + torch_offset

		# torch_radius = 2 esetén pontosan a [-2, 2] sávot járja be (5x5 mező)
		for dx in range(-torch_radius, torch_radius + 1):
			for dy in range(-torch_radius, torch_radius + 1):
				var target_cell = center_cell + Vector2i(dx, dy)
				if real_map_cells.has(target_cell):
					cell_states[target_cell] = CellState.VISIBLE
					if not current_visible_cells.has(target_cell):
						current_visible_cells.append(target_cell)

func _draw() -> void:
	if not primary_layer:
		return

	for cell in cell_states.keys():
		var state: CellState = cell_states[cell]
		if state == CellState.VISIBLE:
			continue

		var cell_world = primary_layer.to_global(primary_layer.map_to_local(cell))
		var draw_pos = to_local(cell_world) - (cell_size / 2.0)
		var rect = Rect2(draw_pos, cell_size)

		if state == CellState.UNEXPLORED:
			draw_rect(rect, unexplored_color, true)
		elif state == CellState.IN_FOG:
			draw_rect(rect, fog_color, true)
