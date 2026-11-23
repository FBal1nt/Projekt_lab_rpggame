class_name EnemySpawner
extends RefCounted

const ENEMY_SCENE_PATH := "res://Scenes/Enemy/enemy.tscn"
const HERO_SAFE_SPAWN_RADIUS := 4

const MONSTER_RESOURCE_PATHS: Array[String] = [
	"res://Data/Monsters/slime_data.tres",
	"res://Data/Monsters/bat_data.tres",
	"res://Data/Monsters/skeleton_data.tres",
	"res://Data/Monsters/skeleton_archer_data.tres",
	"res://Data/Monsters/orc_data.tres",
	"res://Data/Monsters/armored_skeleton_data.tres",
	"res://Data/Monsters/armored_orc_data.tres",
	"res://Data/Monsters/armored_axeman_data.tres",
	"res://Data/Monsters/elite_orc_data.tres",
	"res://Data/Monsters/greatsword_skeleton_data.tres",
	"res://Data/Monsters/werewolf_data.tres",
	"res://Data/Monsters/werebear_data.tres",
	"res://Data/Monsters/necromancer_data.tres"
]

var _enemy_scene: PackedScene
var _catalog_by_id: Dictionary = {}
var _ids_by_tier: Dictionary = {
	EnemyData.EnemyTier.BASIC: [],
	EnemyData.EnemyTier.ARMORED: [],
	EnemyData.EnemyTier.ELITE: [],
	EnemyData.EnemyTier.BOSS: []
}


func _init() -> void:
	if ResourceLoader.exists(ENEMY_SCENE_PATH):
		_enemy_scene = load(ENEMY_SCENE_PATH) as PackedScene
	_load_monster_catalog()


## Lerakja az összes ellenfelet a generált szobák EnemySpawn_* markereire és a Boss szobába
func populate_dungeon(
	placed_rooms: Array,
	enemies_container: Node2D,
	grid_manager: GridManager,
	fog_of_war: FogOfWar,
	hero_cell: Vector2i,
	max_depth: int,
	difficulty_fallback: String = "normal"
) -> Dictionary:
	var summary := {"normal_enemies": 0, "boss_spawned": false, "boss_minions": 0}
	if _enemy_scene == null or enemies_container == null or grid_manager == null or grid_manager.floor_layer == null:
		push_warning("[EnemySpawner] Hiányzó komponens a szörnyek generálásához.")
		return summary

	var ctx := _build_spawn_context(difficulty_fallback)
	var occupied_cells: Dictionary = {hero_cell: true}

	for room_entry in placed_rooms:
		var room_node = room_entry.get("node") as Node2D
		if room_node == null or not is_instance_valid(room_node):
			continue

		var kind: String = String(room_entry.get("kind", "normal"))
		var depth: int = int(room_entry.get("depth", 1))

		if kind == "start" or kind == "exit":
			continue

		if kind == "boss":
			var boss_result := _spawn_boss_room_encounter(room_node, enemies_container, grid_manager, fog_of_war, occupied_cells, ctx)
			summary["boss_spawned"] = boss_result["boss_spawned"]
			summary["boss_minions"] = int(summary["boss_minions"]) + int(boss_result["minions_spawned"])
			continue

		summary["normal_enemies"] = int(summary["normal_enemies"]) + _spawn_room_enemies(
			room_node,
			depth,
			maxi(1, max_depth),
			enemies_container,
			grid_manager,
			fog_of_war,
			hero_cell,
			occupied_cells,
			ctx
		)

	print("[EnemySpawner] Generálás kész (%s) -> Szobai szörnyek: %d | Boss: %s | Boss csatlósok: %d" % [
		ctx["difficulty_id"],
		summary["normal_enemies"],
		"igen" if summary["boss_spawned"] else "nem",
		summary["boss_minions"]
	])
	return summary


func _load_monster_catalog() -> void:
	_catalog_by_id.clear()
	for tier_key in _ids_by_tier.keys():
		(_ids_by_tier[tier_key] as Array).clear()

	for path in MONSTER_RESOURCE_PATHS:
		if not ResourceLoader.exists(path):
			continue
		var res := load(path) as EnemyData
		if res == null:
			continue
		var m_id := res.monster_id.strip_edges().to_lower()
		if m_id.is_empty() or m_id == "enemy":
			m_id = path.get_file().get_basename().replace("_data", "").to_lower()
		_catalog_by_id[m_id] = res
		if _ids_by_tier.has(res.tier):
			(_ids_by_tier[res.tier] as Array).append(m_id)


func _build_spawn_context(difficulty_fallback: String) -> Dictionary:
	var ctx := {
		"difficulty_id": difficulty_fallback.to_lower(),
		"spawn_rate_multiplier": 1.0,
		"encounter_count_multiplier": 1.0,
		"enemy_level_min": 2,
		"enemy_level_max": 4,
		"elite_spawn_chance": 0.15,
		"allowed_ids": {}
	}

	if "easy" in ctx["difficulty_id"]:
		ctx["spawn_rate_multiplier"] = 0.7
		ctx["encounter_count_multiplier"] = 0.75
		ctx["enemy_level_min"] = 1
		ctx["enemy_level_max"] = 2
		ctx["elite_spawn_chance"] = 0.0
	elif "hard" in ctx["difficulty_id"]:
		ctx["spawn_rate_multiplier"] = 1.45
		ctx["encounter_count_multiplier"] = 1.35
		ctx["enemy_level_min"] = 5
		ctx["enemy_level_max"] = 7
		ctx["elite_spawn_chance"] = 0.45

	var tree := Engine.get_main_loop() as SceneTree
	var gs: Node = tree.root.get_node_or_null("GameState") if tree else null
	var hero_level := 1
	if gs != null:
		if gs.has_method("get_active_character"):
			var active_char = gs.get_active_character()
			if active_char != null and active_char.get("level") != null:
				hero_level = maxi(1, int(active_char.level))
		elif "level" in gs:
			hero_level = maxi(1, int(gs.level))

	var already_scaled := false
	if gs != null and "run_state" in gs and gs.run_state is Dictionary and not gs.run_state.is_empty():
		var rs: Dictionary = gs.run_state
		if rs.has("difficulty_id"):
			ctx["difficulty_id"] = String(rs["difficulty_id"]).to_lower()
		if rs.has("spawn_rate_multiplier"):
			ctx["spawn_rate_multiplier"] = maxf(float(rs["spawn_rate_multiplier"]), 0.1)
		if rs.has("encounter_count_multiplier"):
			ctx["encounter_count_multiplier"] = maxf(float(rs["encounter_count_multiplier"]), 0.1)
		if rs.has("enemy_level_min"):
			ctx["enemy_level_min"] = maxi(int(rs["enemy_level_min"]), 1)
		if rs.has("enemy_level_max"):
			ctx["enemy_level_max"] = maxi(int(ctx["enemy_level_min"]), int(rs["enemy_level_max"]))
		if rs.has("hero_level_at_start") and int(rs["hero_level_at_start"]) > 0:
			already_scaled = true
		if rs.has("elite_spawn_chance"):
			ctx["elite_spawn_chance"] = clampf(float(rs["elite_spawn_chance"]), 0.0, 1.0)
		if rs.has("enemy_type_ids") and rs["enemy_type_ids"] is Array:
			var allowed: Dictionary = {}
			for raw_id in rs["enemy_type_ids"]:
				var clean_id := String(raw_id).strip_edges().to_lower()
				if not clean_id.is_empty() and clean_id != "necromancer":
					allowed[clean_id] = true
			ctx["allowed_ids"] = allowed

	if not already_scaled and hero_level > 1:
		var base_min := int(ctx["enemy_level_min"])
		var base_max := maxi(base_min, int(ctx["enemy_level_max"]))
		var spread := base_max - base_min
		if "easy" in String(ctx["difficulty_id"]):
			var easy_min := maxi(1, hero_level - 1)
			ctx["enemy_level_min"] = easy_min
			ctx["enemy_level_max"] = easy_min + spread
		else:
			ctx["enemy_level_min"] = base_min + (hero_level - 1)
			ctx["enemy_level_max"] = base_max + (hero_level - 1)

	return ctx


func _spawn_room_enemies(
	room_node: Node2D,
	depth: int,
	max_depth: int,
	enemies_container: Node2D,
	grid_manager: GridManager,
	fog_of_war: FogOfWar,
	hero_cell: Vector2i,
	occupied_cells: Dictionary,
	ctx: Dictionary
) -> int:
	var markers := _collect_room_enemy_markers(room_node)
	if markers.is_empty():
		return 0

	var target_count := _compute_room_spawn_count(markers.size(), ctx)
	if target_count <= 0:
		return 0

	markers.shuffle()
	var spawned := 0

	for marker in markers:
		if spawned >= target_count:
			break

		var cell_lookup := _find_walkable_spawn_cell(
			marker.global_position,
			grid_manager,
			occupied_cells,
			hero_cell,
			HERO_SAFE_SPAWN_RADIUS,
			3
		)
		if not cell_lookup["found"]:
			continue

		var rolled_level := randi_range(int(ctx["enemy_level_min"]), int(ctx["enemy_level_max"]))
		var chosen_tier := _pick_tier_for_spawn(depth, max_depth, rolled_level, ctx)
		var monster_id := _pick_monster_id_for_tier(chosen_tier, ctx)
		if monster_id.is_empty():
			continue

		var enemy := _spawn_enemy_instance(
			monster_id,
			cell_lookup["cell"],
			rolled_level,
			String(ctx["difficulty_id"]),
			enemies_container,
			grid_manager,
			fog_of_war,
			occupied_cells
		)
		if enemy != null:
			spawned += 1

	return spawned


func _collect_room_enemy_markers(room_node: Node2D) -> Array[Marker2D]:
	var markers: Array[Marker2D] = []
	var spawners_node := room_node.get_node_or_null("Spawners")
	if spawners_node == null:
		return markers

	for child in spawners_node.get_children():
		if child is Marker2D and child.name.begins_with("EnemySpawn"):
			markers.append(child as Marker2D)

	markers.sort_custom(func(a: Marker2D, b: Marker2D) -> bool: return a.name < b.name)
	return markers


func _compute_room_spawn_count(marker_count: int, ctx: Dictionary) -> int:
	if marker_count <= 0:
		return 0

	var diff_id: String = String(ctx["difficulty_id"])
	var spawn_mult: float = float(ctx["spawn_rate_multiplier"])
	var encounter_mult: float = float(ctx["encounter_count_multiplier"])

	var room_active_chance := 0.88
	var max_room_cap := marker_count
	if "easy" in diff_id:
		room_active_chance = 0.72
		max_room_cap = mini(2, marker_count)
	elif "hard" in diff_id:
		room_active_chance = 0.96
		# Szűk folyosókban / zsákutcákban (3 marker) max 2 ellenség, nagyobb 4 markeres szobákban max 3-4
		max_room_cap = 2 if marker_count <= 3 else marker_count
	else:
		room_active_chance = 0.86
		max_room_cap = mini(3, marker_count)

	if randf() > room_active_chance:
		return 0

	var intensity := clampf(spawn_mult * encounter_mult, 0.35, 2.2)
	var avg_fraction := lerpf(0.32, 0.68, clampf((intensity - 0.5) / 1.5, 0.0, 1.0))
	var exact_target := float(marker_count) * avg_fraction
	var count := floori(exact_target)
	if randf() < (exact_target - float(count)):
		count += 1

	return clampi(maxi(1, count), 1, max_room_cap)


func _pick_tier_for_spawn(depth: int, max_depth: int, rolled_level: int, ctx: Dictionary) -> EnemyData.EnemyTier:
	var diff_id: String = String(ctx["difficulty_id"])
	var elite_chance: float = float(ctx["elite_spawn_chance"])
	var depth_ratio := clampf(float(depth) / float(maxi(1, max_depth)), 0.0, 1.0)
	var is_max_difficulty := ("hard" in diff_id) or elite_chance >= 0.40

	var w_basic := 0.0
	var w_armored := 0.0
	var w_elite := 0.0

	if is_max_difficulty:
		# Maximális nehézségen / szinten egyáltalán nincs alap (Tier 1) szörny
		w_basic = 0.0
		w_armored = lerpf(0.70, 0.25, depth_ratio)
		w_elite = maxf(elite_chance, lerpf(0.30, 0.75, depth_ratio))
	elif "easy" in diff_id:
		if depth_ratio < 0.5:
			w_basic = 1.0
			w_armored = 0.0
		else:
			w_basic = 0.85
			w_armored = 0.15
		w_elite = 0.0
	else:
		# Közepes nehézség: mélységgel együtt erősödő Tier eloszlás
		if depth_ratio < 0.35:
			w_basic = 0.70
			w_armored = 0.26
			w_elite = clampf(elite_chance * 0.4, 0.0, 0.08)
		elif depth_ratio < 0.70:
			w_basic = 0.38
			w_armored = 0.48
			w_elite = maxf(0.14, elite_chance)
		else:
			w_basic = 0.14
			w_armored = 0.58
			w_elite = maxf(0.28, elite_chance * 1.5)

	var total := w_basic + w_armored + w_elite
	if total <= 0.0:
		return EnemyData.EnemyTier.ARMORED if is_max_difficulty else EnemyData.EnemyTier.BASIC

	var roll := randf() * total
	if roll < w_basic:
		return EnemyData.EnemyTier.BASIC
	if roll < w_basic + w_armored:
		return EnemyData.EnemyTier.ARMORED
	return EnemyData.EnemyTier.ELITE


func _pick_monster_id_for_tier(tier: EnemyData.EnemyTier, ctx: Dictionary) -> String:
	var tier_ids: Array = (_ids_by_tier.get(tier, []) as Array).duplicate()
	if tier_ids.is_empty():
		return ""

	var allowed: Dictionary = ctx.get("allowed_ids", {})
	if not allowed.is_empty():
		var filtered: Array[String] = []
		for m_id in tier_ids:
			if allowed.has(m_id):
				filtered.append(String(m_id))
		if not filtered.is_empty():
			return filtered.pick_random()

	return String(tier_ids.pick_random())


func _spawn_boss_room_encounter(
	boss_room: Node2D,
	enemies_container: Node2D,
	grid_manager: GridManager,
	fog_of_war: FogOfWar,
	occupied_cells: Dictionary,
	ctx: Dictionary
) -> Dictionary:
	var result := {"boss_spawned": false, "minions_spawned": 0}
	var boss_marker := boss_room.get_node_or_null("Spawners/BossSpawn") as Node2D
	if boss_marker == null:
		boss_marker = boss_room.find_child("BossSpawn", true, false) as Node2D

	var boss_world_pos := boss_marker.global_position if boss_marker != null else boss_room.global_position
	var roam_cells := _collect_boss_roam_cells(boss_room, grid_manager)
	var boss_cell_lookup := _find_walkable_spawn_cell(boss_world_pos, grid_manager, occupied_cells, Vector2i.ZERO, 0, 4)
	if not boss_cell_lookup["found"]:
		push_warning("[EnemySpawner] Nem található járható mező a Nekromanta számára a Boss szobában!")
		return result

	var boss_cell: Vector2i = boss_cell_lookup["cell"]
	if not roam_cells.is_empty() and not roam_cells.has(boss_cell):
		var best_cell := boss_cell
		var best_dist := INF
		for cell_variant in roam_cells.keys():
			var candidate := cell_variant as Vector2i
			if grid_manager.is_cell_solid(candidate) or occupied_cells.has(candidate):
				continue
			var d := Vector2(candidate - boss_cell).length_squared()
			if d < best_dist:
				best_dist = d
				best_cell = candidate
		boss_cell = best_cell

	var boss_level := maxi(int(ctx["enemy_level_max"]), 2)
	var diff_id: String = String(ctx["difficulty_id"])
	var boss := _spawn_enemy_instance(
		"necromancer",
		boss_cell,
		boss_level,
		diff_id,
		enemies_container,
		grid_manager,
		fog_of_war,
		occupied_cells
	)
	if boss == null:
		return result

	if not roam_cells.is_empty():
		boss.set_meta("roam_room_cells", roam_cells)

	result["boss_spawned"] = true
	return result


func _find_walkable_spawn_cell(
	world_pos: Vector2,
	grid_manager: GridManager,
	occupied_cells: Dictionary,
	hero_cell: Vector2i,
	min_hero_dist: int,
	max_radius: int
) -> Dictionary:
	var fl := grid_manager.floor_layer
	var origin_cell := fl.local_to_map(fl.to_local(world_pos))

	for radius in range(0, max_radius + 1):
		var ring_cells: Array[Vector2i] = []
		for dx in range(-radius, radius + 1):
			for dy in range(-radius, radius + 1):
				if radius > 0 and maxi(absi(dx), absi(dy)) != radius:
					continue
				ring_cells.append(origin_cell + Vector2i(dx, dy))
		if radius > 0:
			ring_cells.shuffle()

		for cell in ring_cells:
			if grid_manager.is_cell_solid(cell):
				continue
			if occupied_cells.has(cell):
				continue
			if min_hero_dist > 0 and grid_manager.get_grid_distance(cell, hero_cell) < min_hero_dist:
				continue
			return {"found": true, "cell": cell}

	return {"found": false, "cell": Vector2i.ZERO}


func _collect_boss_roam_cells(boss_room: Node2D, grid_manager: GridManager) -> Dictionary:
	var floor_cells := _collect_room_floor_cells(boss_room, grid_manager)
	if boss_room == null or grid_manager == null or grid_manager.floor_layer == null:
		return floor_cells

	var roam_zone := boss_room.get_node_or_null("RoamZone") as Area2D
	if roam_zone == null:
		return floor_cells

	var shapes: Array[CollisionShape2D] = []
	var polygons: Array[CollisionPolygon2D] = []
	for child in roam_zone.find_children("*", "", true, false):
		if child is CollisionShape2D:
			var cs := child as CollisionShape2D
			if not cs.disabled and cs.shape != null:
				shapes.append(cs)
		elif child is CollisionPolygon2D:
			var cp := child as CollisionPolygon2D
			if not cp.disabled and cp.polygon.size() >= 3:
				polygons.append(cp)

	if shapes.is_empty() and polygons.is_empty():
		return floor_cells

	var master_floor := grid_manager.floor_layer
	var zoned_cells: Dictionary = {}
	for cell_variant in floor_cells.keys():
		var cell := cell_variant as Vector2i
		if grid_manager.is_cell_solid(cell):
			continue
		var world_pos := master_floor.to_global(master_floor.map_to_local(cell))
		if _is_world_point_in_roam_zone(world_pos, shapes, polygons):
			zoned_cells[cell] = true

	return zoned_cells if not zoned_cells.is_empty() else floor_cells


func _is_world_point_in_roam_zone(
	world_pos: Vector2,
	shapes: Array[CollisionShape2D],
	polygons: Array[CollisionPolygon2D]
) -> bool:
	for cs in shapes:
		var local_pt: Vector2 = cs.global_transform.affine_inverse() * world_pos
		if cs.shape is RectangleShape2D:
			var half := (cs.shape as RectangleShape2D).size * 0.5
			if absf(local_pt.x) <= half.x and absf(local_pt.y) <= half.y:
				return true
		elif cs.shape is CircleShape2D:
			var radius := (cs.shape as CircleShape2D).radius
			if local_pt.length_squared() <= radius * radius:
				return true

	for cp in polygons:
		var local_pt: Vector2 = cp.global_transform.affine_inverse() * world_pos
		if Geometry2D.is_point_in_polygon(local_pt, cp.polygon):
			return true

	return false


func _collect_room_floor_cells(room_node: Node2D, grid_manager: GridManager) -> Dictionary:
	var cells: Dictionary = {}
	if room_node == null or grid_manager == null or grid_manager.floor_layer == null:
		return cells

	var master_floor := grid_manager.floor_layer
	for layer in room_node.find_children("*", "TileMapLayer", true, false):
		var tile_layer := layer as TileMapLayer
		if tile_layer == null:
			continue
		var l_name := String(tile_layer.name).to_lower()
		if not ("floor" in l_name or "padlo" in l_name):
			continue
		for local_cell in tile_layer.get_used_cells():
			var world_pos: Vector2 = tile_layer.to_global(tile_layer.map_to_local(local_cell))
			var master_cell: Vector2i = master_floor.local_to_map(master_floor.to_local(world_pos))
			cells[master_cell] = true
	return cells


func _spawn_enemy_instance(
	monster_id: String,
	cell: Vector2i,
	enemy_level: int,
	difficulty_id: String,
	enemies_container: Node2D,
	grid_manager: GridManager,
	fog_of_war: FogOfWar,
	occupied_cells: Dictionary
) -> EnemyController:
	var base_data := _catalog_by_id.get(monster_id, null) as EnemyData
	if base_data == null:
		push_warning("[EnemySpawner] Ismeretlen szörny azonosító: %s" % monster_id)
		return null

	var scaled_data := base_data.duplicate() as EnemyData
	scaled_data.initialize()
	scaled_data.apply_level_scaling(enemy_level, difficulty_id)

	var enemy := _enemy_scene.instantiate() as EnemyController
	if enemy == null:
		return null

	enemy.enemy_data = scaled_data
	enemy.fog_of_war = fog_of_war
	var spawn_world_pos := grid_manager.floor_layer.to_global(grid_manager.floor_layer.map_to_local(cell))
	enemy.position = enemies_container.to_local(spawn_world_pos)
	enemies_container.add_child(enemy)

	enemy.grid_pos = cell
	if enemy.mover:
		enemy.mover.grid_pos = cell
		enemy.mover.current_step_target = cell
	enemy.update_fog_visibility()

	occupied_cells[cell] = true
	return enemy
