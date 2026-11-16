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
@export var unexplored_color: Color = Color(0.07, 0.08, 0.11, 0.80)
@export var fog_color: Color = Color(0.11, 0.13, 0.18, 0.48)
@export_range(0.05, 1.0) var edge_softness: float = 0.45
@export_range(0.0, 0.4) var mist_intensity: float = 0.14
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

const EXPLORED_SUBRES: int = 4
const MAX_SHADER_TORCHES: int = 128
const FOG_SHADER_CODE: String = """
shader_type canvas_item;

uniform vec4 unexplored_color : source_color = vec4(0.07, 0.08, 0.11, 0.80);
uniform vec4 fog_color : source_color = vec4(0.11, 0.13, 0.18, 0.48);
uniform vec2 map_size_tiles = vec2(1.0, 1.0);
uniform vec2 hero_center = vec2(-9999.0, -9999.0);
uniform float hero_radius = 2.5;
uniform int torch_count = 0;
uniform float torch_radius = 2.5;
uniform vec2 torch_positions[128];
uniform float edge_softness = 0.45;
uniform float mist_intensity = 0.14;

float hash21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float value_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	float a = hash21(i);
	float b = hash21(i + vec2(1.0, 0.0));
	float c = hash21(i + vec2(0.0, 1.0));
	float d = hash21(i + vec2(1.0, 1.0));
	return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

float fbm_mist(vec2 p) {
	float v = 0.0;
	float amp = 0.5;
	for (int i = 0; i < 3; i++) {
		v += amp * value_noise(p);
		p *= 2.03;
		amp *= 0.5;
	}
	return v;
}

float circle_visibility(vec2 pos, vec2 center, float radius, float inner_ratio, float outer_ratio, float mist_offset) {
	if (radius <= 0.0) {
		return 0.0;
	}
	float dist = length(pos - center) + mist_offset;
	float inner_r = radius * inner_ratio;
	float outer_r = radius * outer_ratio;
	return 1.0 - smoothstep(inner_r, outer_r, dist);
}

void fragment() {
	vec2 tile_pos = UV * map_size_tiles;

	float mist_a = fbm_mist(tile_pos * 0.45 + vec2(TIME * 0.07, -TIME * 0.04));
	float mist_b = fbm_mist(tile_pos * 0.90 + vec2(-TIME * 0.05, TIME * 0.06) + 13.7);
	float mist_centered = (mist_a * 0.65 + mist_b * 0.35) - 0.5;

	float inner_ratio = clamp(1.0 - edge_softness * 0.75, 0.25, 0.95);
	float outer_ratio = 1.0 + edge_softness * 0.35;
	float edge_wisp = mist_centered * edge_softness * 0.6;

	float visibility = circle_visibility(tile_pos, hero_center, hero_radius, inner_ratio, outer_ratio, edge_wisp);

	if (visibility < 1.0 && torch_radius > 0.0) {
		float max_torch_r = torch_radius * (outer_ratio + 0.3);
		float max_torch_r2 = max_torch_r * max_torch_r;
		for (int i = 0; i < 128; i++) {
			if (i >= torch_count) {
				break;
			}
			vec2 t_diff = tile_pos - torch_positions[i];
			if (dot(t_diff, t_diff) <= max_torch_r2) {
				float t_vis = circle_visibility(tile_pos, torch_positions[i], torch_radius, inner_ratio, outer_ratio, edge_wisp);
				visibility = max(visibility, t_vis);
				if (visibility >= 0.999) {
					break;
				}
			}
		}
	}

	float explored = texture(TEXTURE, UV).r;
	float explored_mix = smoothstep(0.2, 0.8, explored);
	vec4 base_fog = mix(unexplored_color, fog_color, explored_mix);
	base_fog.rgb += vec3(mist_centered * mist_intensity * 0.35);
	base_fog.a = clamp(base_fog.a + mist_centered * mist_intensity, 0.0, 0.96);

	COLOR = vec4(base_fog.rgb, base_fog.a * (1.0 - visibility));
}
"""

var cell_states: Dictionary = {}
var real_map_cells: Dictionary = {}
var current_visible_cells: Array[Vector2i] = []
var torch_cells: Array[Vector2i] = []
var torch_world_positions: Array[Vector2] = []
var discovered_torches: Dictionary = {}
var map_explored_cells: Dictionary = {}
var cell_size: Vector2 = Vector2(16, 16)
var map_rect: Rect2i = Rect2i()
var is_initialized: bool = false

var fog_sprite: Sprite2D = null
var fog_material: ShaderMaterial = null
var explored_image: Image = null
var explored_texture: ImageTexture = null

func _ready() -> void:
	z_index = 5
	RenderingServer.set_default_clear_color(Color(unexplored_color.r, unexplored_color.g, unexplored_color.b, 1.0))
	_ensure_fog_overlay()

	if not is_initialized and primary_layer and primary_layer.tile_set:
		init_fog()

func _ensure_fog_overlay() -> void:
	if fog_sprite != null and is_instance_valid(fog_sprite):
		return

	var shader := Shader.new()
	shader.code = FOG_SHADER_CODE

	fog_material = ShaderMaterial.new()
	fog_material.shader = shader

	fog_sprite = Sprite2D.new()
	fog_sprite.name = "FogOverlay"
	fog_sprite.centered = false
	fog_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	fog_sprite.material = fog_material
	add_child(fog_sprite)

func init_fog() -> void:
	if not primary_layer or primary_layer.tile_set == null:
		return

	if primary_layer.tile_set:
		cell_size = Vector2(primary_layer.tile_set.tile_size)

	cell_states.clear()
	real_map_cells.clear()
	torch_cells.clear()
	torch_world_positions.clear()
	discovered_torches.clear()
	map_explored_cells.clear()
	current_visible_cells.clear()
	_ensure_fog_overlay()

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
	map_rect = expanded_rect
	for x in range(expanded_rect.position.x, expanded_rect.end.x):
		for y in range(expanded_rect.position.y, expanded_rect.end.y):
			cell_states[Vector2i(x, y)] = CellState.UNEXPLORED

	_setup_explored_overlay()
	_collect_torches()
	_stamp_torches_to_explored()
	_sync_torch_shader_params()
	apply_torch_lights()

	is_initialized = true
	print("[FogOfWar] Inicializálva! Valós cellák: ", real_map_cells.size(), " | Fáklyák száma: ", torch_cells.size())

func _setup_explored_overlay() -> void:
	if map_rect.size.x <= 0 or map_rect.size.y <= 0:
		return

	var img_w: int = map_rect.size.x * EXPLORED_SUBRES
	var img_h: int = map_rect.size.y * EXPLORED_SUBRES
	explored_image = Image.create(img_w, img_h, false, Image.FORMAT_RGBA8)
	explored_texture = ImageTexture.create_from_image(explored_image)

	var origin_local: Vector2 = primary_layer.map_to_local(map_rect.position) - (cell_size * 0.5)
	fog_sprite.texture = explored_texture
	fog_sprite.position = to_local(primary_layer.to_global(origin_local))
	fog_sprite.scale = cell_size / float(EXPLORED_SUBRES)

	fog_material.set_shader_parameter("unexplored_color", unexplored_color)
	fog_material.set_shader_parameter("fog_color", fog_color)
	fog_material.set_shader_parameter("edge_softness", edge_softness)
	fog_material.set_shader_parameter("mist_intensity", mist_intensity)
	fog_material.set_shader_parameter("map_size_tiles", Vector2(map_rect.size))
	fog_material.set_shader_parameter("hero_center", Vector2(-9999.0, -9999.0))
	fog_material.set_shader_parameter("hero_radius", 0.0)

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
					torch_world_positions.append(primary_layer.to_global(primary_layer.map_to_local(cell)))
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
						torch_world_positions.append(primary_layer.to_global(primary_layer.map_to_local(cell)))

	_collect_torch_nodes()

func _collect_torch_nodes() -> void:
	if primary_layer == null or not is_inside_tree():
		return

	var torch_nodes: Array[Node2D] = []

	for node in get_tree().get_nodes_in_group("torches"):
		if _is_torch_node_active(node):
			var torch_node: Node2D = node as Node2D
			if not torch_nodes.has(torch_node):
				torch_nodes.append(torch_node)

	var search_root: Node = get_parent() if get_parent() != null else get_tree().current_scene
	if search_root != null:
		for node in search_root.find_children("*", "Node2D", true, false):
			if (node.is_in_group("torches") or node.scene_file_path.ends_with("/torch.tscn")) and _is_torch_node_active(node):
				var torch_node: Node2D = node as Node2D
				if not torch_nodes.has(torch_node):
					torch_nodes.append(torch_node)

	for torch_node in torch_nodes:
		var cell: Vector2i = primary_layer.local_to_map(primary_layer.to_local(torch_node.global_position))
		if not torch_cells.has(cell):
			torch_cells.append(cell)
		torch_world_positions.append(torch_node.global_position)

func _is_torch_node_active(node: Node) -> bool:
	if not is_instance_valid(node) or not (node is Node2D):
		return false
	if not node.is_inside_tree():
		return false
	if node is CanvasItem and not (node as CanvasItem).is_visible_in_tree():
		return false

	var curr: Node = node
	while curr != null:
		if curr.is_queued_for_deletion():
			return false
		curr = curr.get_parent()

	return true

func _world_to_rel_tile(world_pos: Vector2) -> Vector2:
	var local_pos: Vector2 = primary_layer.to_local(world_pos)
	return (local_pos / cell_size) - Vector2(map_rect.position)

func _get_circle_radius_tiles(grid_radius: int, disable_at_zero: bool = true) -> float:
	if grid_radius < 0 or (disable_at_zero and grid_radius == 0):
		return 0.0
	return float(grid_radius) + 0.5

func _stamp_circle_to_explored(center_rel_tile: Vector2, radius_tiles: float) -> void:
	if explored_image == null or radius_tiles <= 0.0:
		return

	var img_w: int = explored_image.get_width()
	var img_h: int = explored_image.get_height()
	var cx: float = center_rel_tile.x * float(EXPLORED_SUBRES)
	var cy: float = center_rel_tile.y * float(EXPLORED_SUBRES)
	var r_px: float = radius_tiles * float(EXPLORED_SUBRES)
	var r_px_sq: float = r_px * r_px

	var min_x: int = clampi(int(floor(cx - r_px)), 0, img_w - 1)
	var max_x: int = clampi(int(ceil(cx + r_px)), 0, img_w - 1)
	var min_y: int = clampi(int(floor(cy - r_px)), 0, img_h - 1)
	var max_y: int = clampi(int(ceil(cy + r_px)), 0, img_h - 1)

	for py in range(min_y, max_y + 1):
		var dy: float = (float(py) + 0.5) - cy
		for px in range(min_x, max_x + 1):
			var dx: float = (float(px) + 0.5) - cx
			if dx * dx + dy * dy <= r_px_sq:
				explored_image.set_pixel(px, py, Color.WHITE)

func _stamp_torches_to_explored() -> void:
	if explored_image == null or explored_texture == null:
		return
	var r_tiles: float = _get_circle_radius_tiles(torch_radius)
	if r_tiles <= 0.0:
		return
	for world_pos in torch_world_positions:
		var center_rel: Vector2 = _world_to_rel_tile(world_pos) + Vector2(torch_offset)
		_stamp_circle_to_explored(center_rel, r_tiles)
	explored_texture.update(explored_image)

func is_torch_discovered(cell: Vector2i) -> bool:
	return discovered_torches.has(cell)

func is_cell_map_discovered(cell: Vector2i) -> bool:
	return map_explored_cells.has(cell)

func _sync_torch_shader_params() -> void:
	if fog_material == null:
		return

	var r_tiles: float = _get_circle_radius_tiles(torch_radius)
	var count: int = mini(torch_world_positions.size(), MAX_SHADER_TORCHES)
	var packed := PackedVector2Array()
	packed.resize(MAX_SHADER_TORCHES)
	for i in range(count):
		packed[i] = _world_to_rel_tile(torch_world_positions[i]) + Vector2(torch_offset)

	fog_material.set_shader_parameter("torch_count", count)
	fog_material.set_shader_parameter("torch_radius", r_tiles)
	fog_material.set_shader_parameter("torch_positions", packed)

func _mark_torch_cells_on_map(origin: Vector2i) -> void:
	var r_tiles: float = _get_circle_radius_tiles(torch_radius)
	if r_tiles <= 0.0:
		if real_map_cells.has(origin):
			map_explored_cells[origin] = true
		return
	var r_sq: float = r_tiles * r_tiles
	var center_cell: Vector2i = origin + torch_offset
	for dx in range(-torch_radius, torch_radius + 1):
		for dy in range(-torch_radius, torch_radius + 1):
			if float(dx * dx + dy * dy) <= r_sq:
				var target_cell: Vector2i = center_cell + Vector2i(dx, dy)
				if real_map_cells.has(target_cell):
					map_explored_cells[target_cell] = true

func _discover_visible_torches(hero_pos: Vector2i, r_sq: float) -> void:
	for origin in torch_cells:
		if discovered_torches.has(origin):
			continue
		var center_cell: Vector2i = origin + torch_offset
		var origin_diff := Vector2(origin - hero_pos)
		var center_diff := Vector2(center_cell - hero_pos)
		if (
			map_explored_cells.has(origin)
			or map_explored_cells.has(center_cell)
			or origin_diff.length_squared() <= r_sq
			or center_diff.length_squared() <= r_sq
		):
			discovered_torches[origin] = true
			_mark_torch_cells_on_map(origin)

func update_vision(hero_pos: Vector2i, vision_limit: int) -> void:
	if not is_initialized:
		init_fog()

	for cell in current_visible_cells:
		cell_states[cell] = CellState.IN_FOG
	current_visible_cells.clear()

	# Kör alakú látótávolság (euklideszi sugár = vision_limit + 0.5 csempe)
	var r_tiles: float = _get_circle_radius_tiles(vision_limit, false)
	var r_sq: float = r_tiles * r_tiles
	for dx in range(-vision_limit, vision_limit + 1):
		for dy in range(-vision_limit, vision_limit + 1):
			if float(dx * dx + dy * dy) <= r_sq:
				var target_cell = hero_pos + Vector2i(dx, dy)
				if real_map_cells.has(target_cell):
					cell_states[target_cell] = CellState.VISIBLE
					map_explored_cells[target_cell] = true
					current_visible_cells.append(target_cell)

	_discover_visible_torches(hero_pos, r_sq)

	var hero_center_rel: Vector2 = Vector2(hero_pos - map_rect.position) + Vector2(0.5, 0.5)
	if explored_image != null and explored_texture != null:
		_stamp_circle_to_explored(hero_center_rel, r_tiles)
		explored_texture.update(explored_image)

	if fog_material != null:
		fog_material.set_shader_parameter("hero_center", hero_center_rel)
		fog_material.set_shader_parameter("hero_radius", r_tiles)

	apply_torch_lights()

func apply_torch_lights() -> void:
	var r_tiles: float = _get_circle_radius_tiles(torch_radius)
	if r_tiles <= 0.0:
		return
	var r_sq: float = r_tiles * r_tiles

	for origin in torch_cells:
		var center_cell: Vector2i = origin + torch_offset

		for dx in range(-torch_radius, torch_radius + 1):
			for dy in range(-torch_radius, torch_radius + 1):
				if float(dx * dx + dy * dy) <= r_sq:
					var target_cell = center_cell + Vector2i(dx, dy)
					if real_map_cells.has(target_cell):
						cell_states[target_cell] = CellState.VISIBLE
						if not current_visible_cells.has(target_cell):
							current_visible_cells.append(target_cell)
