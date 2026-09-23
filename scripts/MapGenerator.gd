extends Node2D

@export_group("Generálási Beállítások")
@export var max_rooms: int = 15
@export var starter_scene: PackedScene
@export var room_scenes: Array[PackedScene]
@export var tile_size: Vector2 = Vector2(16, 16)
@export var door_step_tiles: int = 0

@export_group("Központi Rendszerek (Húzd be a Main-ből)")
@export var master_floor: TileMapLayer
@export var master_wall: TileMapLayer
@export var master_decoratives: TileMapLayer
@export var master_torch: TileMapLayer
@export var fog_of_war: FogOfWar
@export var player: HeroController

var open_doors: Array[Dictionary] = []
var placed_rooms: Array[Dictionary] = []
var player_spawn_pos: Vector2 = Vector2.ZERO

var opposites: Dictionary = {
	"felso": "also",
	"fent":  "also",
	"also":  "felso",
	"lent":  "felso",
	"jobb":  "bal",
	"bal":   "jobb"
}

var step_directions: Dictionary = {
	"felso": Vector2(0, -1),
	"fent":  Vector2(0, -1),
	"also":  Vector2(0, 1),
	"lent":  Vector2(0, 1),
	"jobb":  Vector2(1, 0),
	"bal":   Vector2(-1, 0)
}

func _ready() -> void:
	randomize()
	generate_dungeon()

func generate_dungeon() -> void:
	if starter_scene == null or room_scenes.is_empty():
		push_error("[MapGenerator] Hiányzik a starter_scene vagy a room_scenes lista!")
		return

	# Rétegek tisztítása
	if master_floor: master_floor.clear()
	if master_wall: master_wall.clear()
	if master_decoratives: master_decoratives.clear()
	if master_torch: master_torch.clear()

	# 1. Kezdőszoba lerakása
	var start_room = starter_scene.instantiate() as Node2D
	add_child(start_room)
	start_room.global_position = Vector2.ZERO
	start_room.force_update_transform()

	# Spawn pont keresése a kezdőszobában
	var spawn_marker = start_room.find_child("PlayerSpawn", true, false) as Marker2D
	if spawn_marker:
		player_spawn_pos = spawn_marker.global_position
	else:
		player_spawn_pos = start_room.global_position

	var start_rect = _get_room_bounding_rect(start_room)
	placed_rooms.append({
		"node": start_room,
		"rect": start_rect,
		"name": starter_scene.resource_path.get_file()
	})
	register_doors(start_room)

	print("[MapGenerator] Kezdőszoba felépítve. Ajtók: ", open_doors.size())

	var rooms_spawned: int = 1
	var attempts: int = 0
	var max_attempts: int = 300

	# 2. Generáló ciklus
	while open_doors.size() > 0 and rooms_spawned < max_rooms and attempts < max_attempts:
		attempts += 1
		var door_index = randi() % open_doors.size()
		var target_door = open_doors[door_index]

		var raw_dir = target_door["dir"].to_lower()
		if not opposites.has(raw_dir):
			open_doors.remove_at(door_index)
			continue

		var required_dir = opposites[raw_dir]
		var dir_vector: Vector2 = step_directions.get(raw_dir, Vector2.ZERO)
		var step_offset: Vector2 = dir_vector * tile_size * float(door_step_tiles)

		var candidate_scenes = room_scenes.duplicate()
		candidate_scenes.shuffle()

		var placed: bool = false

		for scene in candidate_scenes:
			var scene_file = scene.resource_path.get_file()
			var test_room = scene.instantiate() as Node2D
			var matching_door = _find_door(test_room, required_dir)

			if matching_door != null:
				add_child(test_room)

				var door_offset = matching_door.global_position - test_room.global_position
				var calculated_pos = (target_door["pos"] + step_offset) - door_offset
				test_room.global_position = calculated_pos.snapped(tile_size)
				test_room.force_update_transform()

				var new_rect = _get_room_bounding_rect(test_room)

				# Ütközésvizsgálat idegen szobákkal
				var overlaps: bool = false
				for placed_data in placed_rooms:
					var existing_room = placed_data["node"]
					var existing_rect: Rect2 = placed_data["rect"]

					if existing_room == target_door["room"]:
						var seam_tolerance = minf(tile_size.x * 1.5, 24.0)
						if new_rect.grow(-seam_tolerance).intersects(existing_rect.grow(-seam_tolerance)):
							overlaps = true
							break
					else:
						if new_rect.grow(-4.0).intersects(existing_rect.grow(-4.0)):
							overlaps = true
							break

				if not overlaps:
					placed_rooms.append({
						"node": test_room,
						"rect": new_rect,
						"name": scene_file
					})
					open_doors.remove_at(door_index)
					register_doors(test_room, matching_door.name.replace("_ajto", ""))

					rooms_spawned += 1
					placed = true
					print("[MapGenerator] Siker: #", rooms_spawned, " (", scene_file, ") csatlakozott a(z) ", raw_dir, " ajtóra.")
					break
				else:
					test_room.queue_free()
			else:
				test_room.queue_free()

		if not placed:
			open_doors.remove_at(door_index)

	print("[MapGenerator] Generálás befejezve! Lehelyezett szobák száma: ", rooms_spawned)

	# 3. Csempék összefűzése a Mester rétegekre
	_bake_to_master()

	# 4. Rendszerek aktiválása a teljes világra
	_setup_world_systems()

func _bake_to_master() -> void:
	for placed in placed_rooms:
		var room = placed["node"] as Node2D
		for child in room.get_children():
			if child is TileMapLayer:
				var target_master: TileMapLayer = null
				var l_name = child.name.to_lower()

				if "floor" in l_name or "padlo" in l_name:
					target_master = master_floor
				elif "wall" in l_name or "fal" in l_name:
					target_master = master_wall
				elif "torch" in l_name or "faklya" in l_name:
					target_master = master_torch
				elif "decor" in l_name or "dekor" in l_name:
					target_master = master_decoratives

				if target_master != null:
					if target_master.tile_set == null and child.tile_set != null:
						target_master.tile_set = child.tile_set

					for cell in child.get_used_cells():
						var world_pos = child.to_global(child.map_to_local(cell))
						var master_cell = target_master.local_to_map(target_master.to_local(world_pos))
						target_master.set_cell(
							master_cell,
							child.get_cell_source_id(cell),
							child.get_cell_atlas_coords(cell),
							child.get_cell_alternative_tile(cell)
						)

					child.visible = false

func _setup_world_systems() -> void:
	# A Player beállítása
	if player and master_floor:
		player.floor_layer = master_floor
		player.wall_layer = master_wall
		player.decoratives_layer = master_decoratives
		player.fog_of_war = fog_of_war

		# Hős a kezdőszoba PlayerSpawn pontjára igazítása
		player.global_position = player_spawn_pos
		player.grid_pos = master_floor.local_to_map(master_floor.to_local(player.global_position))
		player.position = master_floor.map_to_local(player.grid_pos)
		player.setup_grid_astar()

	# A FogOfWar beállítása a teljes labirintusra
	if fog_of_war and master_floor:
		fog_of_war.floor_layer = master_floor
		fog_of_war.wall_layer = master_wall
		fog_of_war.decoratives_layer = master_decoratives
		fog_of_war.torch_layer = master_torch
		fog_of_war.init_fog()

	# Látótér frissítése a hős körül
	if player:
		player.update_fog_of_war()

	print("[MapGenerator] MINDEN RENDSZER KÉSZ! A játékos és a köd feloldva a teljes pályán.")

func _get_room_bounding_rect(room: Node2D) -> Rect2:
	var combined: Rect2 = Rect2()
	var has_layer: bool = false
	for child in room.get_children():
		if child is TileMapLayer and child.tile_set != null:
			var used = child.get_used_rect()
			if used.size != Vector2i.ZERO:
				var t_size = Vector2(child.tile_set.tile_size)
				var w_pos = child.to_global(child.map_to_local(used.position)) - (t_size / 2.0)
				var rect = Rect2(w_pos, Vector2(used.size) * t_size)
				if not has_layer:
					combined = rect
					has_layer = true
				else:
					combined = combined.merge(rect)
	return combined if has_layer else Rect2(room.global_position, Vector2(160, 160))

func _find_door(room: Node2D, target_dir: String) -> Node2D:
	var doors = room.get_node_or_null("Ajtok")
	if not doors: return null
	for child in doors.get_children():
		var dir = child.name.replace("_ajto", "").to_lower()
		if dir == target_dir: return child
		if (target_dir == "felso" and dir == "fent") or (target_dir == "also" and dir == "lent"): return child
	return null

func register_doors(room: Node2D, ignore_door: String = "") -> void:
	var doors = room.get_node_or_null("Ajtok")
	if not doors: return
	for door in doors.get_children():
		var dir = door.name.replace("_ajto", "").to_lower()
		if dir != ignore_door:
			open_doors.append({
				"pos": door.global_position.snapped(tile_size),
				"dir": dir,
				"room": room
			})
