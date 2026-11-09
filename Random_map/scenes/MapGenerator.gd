extends Node2D

# === INSPECTOR BEÁLLÍTÁSOK ===
@export_group("Szobák")
@export var starter_scene: PackedScene
@export var room_scenes: Array[PackedScene]     # 2-4 ajtós normál szobák
@export var boss_scene: PackedScene             # 4-ajtós Boss szoba
@export var exit_scenes: Array[PackedScene]     # 1-ajtós zsákutcák / Reward / Kapu szobák

@export_group("Falazó Elemek (Vakajtók lezárásához)")
@export var wall_felso: PackedScene
@export var wall_also: PackedScene
@export var wall_jobb: PackedScene
@export var wall_bal: PackedScene

@export_group("Generálási Korlátok")
@export var max_rooms: int = 30
@export var max_depth: int = 5

@export_group("Központi Rendszerek (Húzd be a Main-ből)")
@export var master_floor: TileMapLayer
@export var master_wall: TileMapLayer
@export var master_decoratives: TileMapLayer
@export var master_torch: TileMapLayer
@export var fog_of_war: FogOfWar
@export var player: HeroController
@export var grid_manager: GridManager

signal map_generation_started
signal map_generation_completed

enum Difficulty { EASY, MEDIUM, HARD }

# === BELSŐ VÁLTOZÓK ===
var open_doors: Array = []
var rooms_spawned: int = 0
var start_room_node: Node2D = null
var player_spawn_pos: Vector2 = Vector2.ZERO
var is_generating: bool = false

const OPPOSITES = {
	"felso": "also",
	"also": "felso",
	"jobb": "bal",
	"bal": "jobb"
}

func apply_difficulty(diff: Difficulty) -> void:
	match diff:
		Difficulty.EASY:
			max_rooms = 15
			max_depth = 4
		Difficulty.MEDIUM:
			max_rooms = 25
			max_depth = 6
		Difficulty.HARD:
			max_rooms = 35
			max_depth = 8

func _ready() -> void:
	# Nehézség és Seed beállítása a GameState.run_state alapján, ha van
	var game_state = get_node_or_null("/root/GameState")
	if game_state and "run_state" in game_state and game_state.run_state is Dictionary:
		if game_state.run_state.has("seed"):
			seed(int(game_state.run_state["seed"]))
		if game_state.run_state.has("difficulty_id"):
			var diff_str := String(game_state.run_state["difficulty_id"]).to_lower()
			if "easy" in diff_str:
				apply_difficulty(Difficulty.EASY)
			elif "hard" in diff_str:
				apply_difficulty(Difficulty.HARD)
			else:
				apply_difficulty(Difficulty.MEDIUM)

	generate_map()

# Kompatibilitási alias
func generate_dungeon() -> void:
	generate_map()

# === FŐ GENERÁLÁSI FOLYAMAT ===
func generate_map(p_max_rooms: int = -1, p_max_depth: int = -1) -> void:
	is_generating = true
	map_generation_started.emit()
	_reset_generator()

	if p_max_rooms > 0:
		max_rooms = p_max_rooms
	if p_max_depth > 0:
		max_depth = p_max_depth

	print("[MapGenerator] Pálya generálása indítva -> Max szobák: ", max_rooms, " | Max mélység: ", max_depth)

	# 1. Kezdőszoba lerakása
	if not _spawn_starter_room():
		is_generating = false
		return

	print("--- 1. LÉPÉS: Kezdőszoba lerakva ---")

	# 2. Normál szobák fűzése
	await _generate_branches()
	print("--- 2. LÉPÉS: Normál szobák lerakva (", rooms_spawned, " db) ---")

	# 3. Boss szoba + Reward szoba + Falak lehelyezése
	await _place_boss_room()

	# 4. Maradék nyitott folyosóvégek lefalazása
	_close_remaining_doors()
	print("--- GENERÁLÁS KÉSZ! Összesen lerakott szoba: ", rooms_spawned, " ---")

	# 5. Csempék összemásolása a mester rétegekre
	_bake_to_master()

	# 6. Rendszerek inicializálása (GridManager, FogOfWar, Player spawn)
	_setup_world_systems()

	is_generating = false
	map_generation_completed.emit()


func _reset_generator() -> void:
	open_doors.clear()
	rooms_spawned = 0
	start_room_node = null
	for child in get_children():
		child.queue_free()


func _spawn_starter_room() -> bool:
	if starter_scene == null:
		push_error("MapGenerator: Nincs beállítva a 'starter_scene'!")
		return false

	var start_room = starter_scene.instantiate() as Node2D
	add_child(start_room)
	start_room.global_position = Vector2.ZERO
	rooms_spawned += 1
	start_room_node = start_room

	var spawn_marker = start_room.find_child("Player_Spawn", true, false) as Marker2D
	if not spawn_marker:
		spawn_marker = start_room.find_child("PlayerSpawn", true, false) as Marker2D
	if spawn_marker:
		player_spawn_pos = spawn_marker.global_position
	else:
		player_spawn_pos = start_room.global_position

	_register_doors(start_room, 1, "")
	return true


func _generate_branches() -> void:
	var unplaced_doors: Array = []

	while open_doors.size() > 0 and rooms_spawned < max_rooms:
		var door_index = randi() % open_doors.size()
		var target_door = open_doors[door_index]
		open_doors.remove_at(door_index)

		if target_door["depth"] > max_depth:
			unplaced_doors.append(target_door)
			continue

		var required_dir = OPPOSITES.get(target_door["dir"], "")
		if required_dir == "":
			unplaced_doors.append(target_door)
			continue

		var candidate_scenes = room_scenes.duplicate()
		candidate_scenes.shuffle()
		var room_placed: bool = false

		for scene in candidate_scenes:
			var room = scene.instantiate() as Node2D
			add_child(room)
			room.visible = false

			var matching_door = room.get_node_or_null("Ajtok/" + required_dir + "_ajto") as Node2D
			if matching_door == null:
				room.queue_free()
				continue

			var raw_pos = target_door["pos"] - matching_door.position
			room.global_position = Vector2(snapped(raw_pos.x, 32), snapped(raw_pos.y, 32))

			await get_tree().physics_frame
			await get_tree().physics_frame

			if _check_hitbox_collision(room):
				room.queue_free()
				continue

			room.visible = true
			rooms_spawned += 1
			_register_doors(room, target_door["depth"] + 1, required_dir)
			room_placed = true
			break

		if not room_placed:
			unplaced_doors.append(target_door)

	open_doors.append_array(unplaced_doors)


func _place_boss_room() -> void:
	if boss_scene == null or open_doors.is_empty():
		print("Figyelem: Nincs 'boss_scene' beállítva vagy nincs nyitott ajtó!")
		return

	# Mélység szerint csökkenő sorrendbe rendezzük az ajtókat (a legmélyebb van elöl)
	open_doors.sort_custom(func(a, b): return a["depth"] > b["depth"])

	for i in range(open_doors.size()):
		var target_door = open_doors[i]
		var required_dir = OPPOSITES.get(target_door["dir"], "")

		var boss_room = boss_scene.instantiate() as Node2D
		add_child(boss_room)
		boss_room.visible = false

		var matching_door = boss_room.get_node_or_null("Ajtok/" + required_dir + "_ajto") as Node2D
		if matching_door != null:
			var raw_pos = target_door["pos"] - matching_door.position
			boss_room.global_position = Vector2(snapped(raw_pos.x, 32), snapped(raw_pos.y, 32))

			await get_tree().physics_frame
			await get_tree().physics_frame

			if _check_hitbox_collision(boss_room):
				boss_room.queue_free()
				continue
			else:
				boss_room.visible = true
				rooms_spawned += 1
				open_doors.remove_at(i) # Kiemeljük a bejárati ajtót

				print("--- BOSS SZOBA elhelyezve! Pozíció: ", boss_room.global_position, " ---")

				# Célzottan kezeljük a Boss szoba maradék 3 ajtaját (1 Reward/Kapu + 2 Fal)
				await _handle_boss_room_exits(boss_room, required_dir)
				return
		else:
			boss_room.queue_free()

	print("Hiba: Egyetlen nyitott ajtóra sem sikerült ráilleszteni a Boss szobát!")


func _handle_boss_room_exits(boss_room: Node2D, entry_dir: String) -> void:
	var boss_doors_node = boss_room.get_node_or_null("Ajtok")
	if boss_doors_node == null:
		return

	var remaining_boss_doors: Array = []
	for door in boss_doors_node.get_children():
		var dir_name = door.name.replace("_ajto", "")
		if dir_name != entry_dir:
			remaining_boss_doors.append({
				"pos": boss_room.global_position + door.position,
				"dir": dir_name
			})

	remaining_boss_doors.shuffle()

	var reward_placed: bool = false
	var reward_door_index: int = -1

	# 1. Megpróbálunk 1 db Reward / Exit szobát ráilleszteni az egyik szabad ajtóra
	if not exit_scenes.is_empty():
		for idx in range(remaining_boss_doors.size()):
			var b_door = remaining_boss_doors[idx]
			var required_dir = OPPOSITES.get(b_door["dir"], "")

			var candidate_exits = exit_scenes.duplicate()
			candidate_exits.shuffle()
			for scene in candidate_exits:
				var reward_room = scene.instantiate() as Node2D
				add_child(reward_room)
				reward_room.visible = false

				var matching_door = reward_room.get_node_or_null("Ajtok/" + required_dir + "_ajto") as Node2D
				if matching_door != null:
					var raw_pos = b_door["pos"] - matching_door.position
					reward_room.global_position = Vector2(snapped(raw_pos.x, 32), snapped(raw_pos.y, 32))

					await get_tree().physics_frame
					await get_tree().physics_frame

					if _check_hitbox_collision(reward_room):
						reward_room.queue_free()
						continue
					else:
						reward_room.visible = true
						rooms_spawned += 1
						reward_placed = true
						reward_door_index = idx
						print(" -> Reward Room csatlakoztatva a Boss szoba '", b_door["dir"], "' ajtajára!")
						break
				else:
					reward_room.queue_free()

			if reward_placed:
				break

	# 2. A megmaradt ajtókat lefalazzuk
	var walls = {
		"felso": wall_felso,
		"also": wall_also,
		"jobb": wall_jobb,
		"bal": wall_bal
	}

	for idx in range(remaining_boss_doors.size()):
		if idx == reward_door_index:
			continue

		var b_door = remaining_boss_doors[idx]
		var wall_scene = walls.get(b_door["dir"])
		if wall_scene != null:
			var wall = wall_scene.instantiate() as Node2D
			add_child(wall)
			wall.global_position = Vector2(snapped(b_door["pos"].x, 32), snapped(b_door["pos"].y, 32))
			print(" -> Boss szoba '", b_door["dir"], "' ajtaja lefalazva.")


func _close_remaining_doors() -> void:
	var walls = {
		"felso": wall_felso,
		"also": wall_also,
		"jobb": wall_jobb,
		"bal": wall_bal
	}

	for door in open_doors:
		var scene = walls.get(door["dir"])
		if scene != null:
			var wall = scene.instantiate() as Node2D
			add_child(wall)
			wall.global_position = Vector2(snapped(door["pos"].x, 32), snapped(door["pos"].y, 32))

	open_doors.clear()


func _check_hitbox_collision(room: Node2D) -> bool:
	var hitbox = room.get_node_or_null("Hitbox")
	if hitbox != null and hitbox is Area2D:
		return hitbox.get_overlapping_areas().size() > 0
	return false


func _register_doors(room: Node2D, depth: int, entry_dir: String) -> Array:
	var added_doors: Array = []
	var doors_node = room.get_node_or_null("Ajtok")
	if doors_node == null: 
		return added_doors

	for door in doors_node.get_children():
		var dir_name = door.name.replace("_ajto", "")
		if dir_name == entry_dir:
			continue

		var calculated_global_pos = room.global_position + door.position

		var door_info = {
			"pos": calculated_global_pos,
			"dir": dir_name,
			"depth": depth
		}

		open_doors.append(door_info)
		added_doors.append(door_info)

	return added_doors


func _bake_to_master() -> void:
	if master_floor: master_floor.clear()
	if master_wall: master_wall.clear()
	if master_decoratives: master_decoratives.clear()
	if master_torch: master_torch.clear()

	for room_child in get_children():
		if not (room_child is Node2D):
			continue

		var is_wall_piece: bool = room_child is StaticBody2D or "Wall" in room_child.name

		for layer in room_child.find_children("*", "TileMapLayer", true, false):
			if not (layer is TileMapLayer):
				continue

			var target_master: TileMapLayer = null
			var l_name: String = layer.name.to_lower()

			if "floor" in l_name or "padlo" in l_name:
				target_master = master_floor
			elif "wall" in l_name or "fal" in l_name:
				target_master = master_wall
			elif "torch" in l_name or "faklya" in l_name:
				target_master = master_torch
			elif "decor" in l_name or "dekor" in l_name:
				target_master = master_decoratives

			if target_master != null:
				if target_master.tile_set == null and layer.tile_set != null:
					target_master.tile_set = layer.tile_set

				for cell in layer.get_used_cells():
					var world_pos = layer.to_global(layer.map_to_local(cell))
					var master_cell = target_master.local_to_map(target_master.to_local(world_pos))
					target_master.set_cell(
						master_cell,
						layer.get_cell_source_id(cell),
						layer.get_cell_atlas_coords(cell),
						layer.get_cell_alternative_tile(cell)
					)

				# A normál szobák belső csemperétegeit elrejtjük, mert a mester réteg rendereli őket
				# A falazó elemek láthatóak maradnak, hogy a forgatás és fizika megmaradjon
				if not is_wall_piece:
					layer.visible = false

		# Hitbox monitoring leállítása a generálás után felesleges fizikai terhelés elkerülésére
		var hitbox = room_child.get_node_or_null("Hitbox") as Area2D
		if hitbox:
			hitbox.monitoring = false
			hitbox.monitorable = false


func _setup_world_systems() -> void:
	if grid_manager == null:
		grid_manager = get_tree().get_first_node_in_group("grid_manager") as GridManager

	if grid_manager and master_floor:
		grid_manager.floor_layer = master_floor
		grid_manager.wall_layer = master_wall
		grid_manager.decoratives_layer = master_decoratives
		grid_manager.setup_astar()

	if player == null:
		player = get_tree().get_first_node_in_group("player") as HeroController

	if player and master_floor:
		player.floor_layer = master_floor
		player.wall_layer = master_wall
		player.decoratives_layer = master_decoratives
		player.fog_of_war = fog_of_war

		# Játékos a kezdőszoba Player_Spawn pontjára igazítása
		player.global_position = player_spawn_pos
		var spawn_grid = master_floor.local_to_map(master_floor.to_local(player_spawn_pos))
		player.grid_pos = spawn_grid
		player.position = master_floor.map_to_local(spawn_grid)
		if player.mover:
			player.mover.setup(player)

	if fog_of_war and master_floor:
		fog_of_war.floor_layer = master_floor
		fog_of_war.wall_layer = master_wall
		fog_of_war.decoratives_layer = master_decoratives
		fog_of_war.torch_layer = master_torch
		fog_of_war.init_fog()

	if player and player.visuals and player.visuals.has_method("update_fog_of_war"):
		player.visuals.fog_of_war = fog_of_war
		player.visuals.update_fog_of_war()

	print("[MapGenerator] MINDEN RENDSZER KÉSZ! Random_map sikeresen generálva és felépítve.")
