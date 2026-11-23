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
signal map_generation_progress(progress: float, stage_text: String)
signal map_generation_completed

enum Difficulty { EASY, MEDIUM, HARD }

const ENEMY_SPAWNER_SCRIPT := preload("res://Scripts/World/EnemySpawner.gd")

# === BELSŐ VÁLTOZÓK ===
var open_doors: Array = []
var rooms_spawned: int = 0
var start_room_node: Node2D = null
var boss_room_node: Node2D = null
var placed_rooms: Array[Dictionary] = []
var _occupied_room_grid: Dictionary = {}
var player_spawn_pos: Vector2 = Vector2.ZERO
var is_generating: bool = false
var current_difficulty: Difficulty = Difficulty.MEDIUM
var enemies_container: Node2D = null

# === BOSS SZOBA DINAMIKUS FALAK (BEJÁRAT ÉS KIJÁRATI FOLYOSÓ) ===
var boss_entry_door: Dictionary = {}
var boss_exit_door: Dictionary = {}
var _boss_room_floor_cells: Dictionary = {}
var _boss_entry_barrier_tiles: Array[Dictionary] = []
var _boss_entry_saved_tiles: Array[Dictionary] = []
var _boss_exit_barrier_tiles: Array[Dictionary] = []
var _boss_exit_saved_tiles: Array[Dictionary] = []
var _boss_entry_sealed: bool = false
var _boss_exit_sealed: bool = false
var _boss_fight_started: bool = false
var _boss_defeated: bool = false
var _pending_entry_seal: bool = false

const ROOM_GRID_STEP: float = 320.0

const OPPOSITES = {
	"felso": "also",
	"also": "felso",
	"jobb": "bal",
	"bal": "jobb"
}


func _room_grid_key(world_pos: Vector2) -> Vector2i:
	return Vector2i(roundi(world_pos.x / ROOM_GRID_STEP), roundi(world_pos.y / ROOM_GRID_STEP))


func _is_room_slot_occupied(world_pos: Vector2) -> bool:
	return _occupied_room_grid.has(_room_grid_key(world_pos))


func _snap_room_position(raw_pos: Vector2) -> Vector2:
	return Vector2(snappedf(raw_pos.x, ROOM_GRID_STEP), snappedf(raw_pos.y, ROOM_GRID_STEP))

func apply_difficulty(diff: Difficulty) -> void:
	current_difficulty = diff
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


func _difficulty_to_id(diff: Difficulty) -> String:
	match diff:
		Difficulty.EASY: return "easy"
		Difficulty.HARD: return "hard"
		_: return "normal"

func _ready() -> void:
	add_to_group("map_generator")
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


func _process(_delta: float) -> void:
	if _pending_entry_seal and not _boss_entry_sealed and not _boss_defeated and not is_generating:
		_try_seal_boss_entrance_if_hero_inside()

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
	map_generation_progress.emit(0.05, "Kezdőszoba előkészítése...")

	# 1. Kezdőszoba lerakása
	if not _spawn_starter_room():
		is_generating = false
		return

	print("--- 1. LÉPÉS: Kezdőszoba lerakva ---")
	map_generation_progress.emit(0.10, "Labirintus szobák építése...")

	# 2. Normál szobák fűzése
	await _generate_branches()
	print("--- 2. LÉPÉS: Normál szobák lerakva (", rooms_spawned, " db) ---")

	# 3. Boss szoba + Reward szoba + Falak lehelyezése
	map_generation_progress.emit(0.70, "Főellenség termének kialakítása...")
	await _place_boss_room()

	# 4. Maradék nyitott folyosóvégek lefalazása
	map_generation_progress.emit(0.78, "Pálya rétegeinek összeállítása...")
	_close_remaining_doors()
	print("--- GENERÁLÁS KÉSZ! Összesen lerakott szoba: ", rooms_spawned, " ---")

	# 5. Csempék összemásolása a mester rétegekre
	_bake_to_master()

	# 5b. Boss szoba dinamikus falainak előkészítése (a kijárati folyosó alapértelmezetten lefalazva)
	_prepare_boss_room_barriers()

	# 6. Rendszerek inicializálása (GridManager, FogOfWar, Player spawn)
	_setup_world_systems()

	is_generating = false
	map_generation_progress.emit(1.0, "Pálya elkészült!")
	map_generation_completed.emit()


func _reset_generator() -> void:
	open_doors.clear()
	placed_rooms.clear()
	_occupied_room_grid.clear()
	rooms_spawned = 0
	start_room_node = null
	boss_room_node = null
	boss_entry_door.clear()
	boss_exit_door.clear()
	_boss_room_floor_cells.clear()
	_boss_entry_barrier_tiles.clear()
	_boss_entry_saved_tiles.clear()
	_boss_exit_barrier_tiles.clear()
	_boss_exit_saved_tiles.clear()
	_boss_entry_sealed = false
	_boss_exit_sealed = false
	_boss_fight_started = false
	_boss_defeated = false
	_pending_entry_seal = false
	for child in get_children():
		child.queue_free()
	var container := _get_enemies_container(false)
	if container != null:
		for enemy_child in container.get_children():
			if enemy_child.is_in_group("enemies"):
				enemy_child.remove_from_group("enemies")
			enemy_child.queue_free()
	var loot_host := get_parent() if get_parent() != null else self
	var loot_container := loot_host.get_node_or_null("LootBags")
	if loot_container != null:
		for loot_child in loot_container.get_children():
			if loot_child.is_in_group("loot_bags"):
				loot_child.remove_from_group("loot_bags")
			loot_child.queue_free()


func _spawn_starter_room() -> bool:
	if starter_scene == null:
		push_error("MapGenerator: Nincs beállítva a 'starter_scene'!")
		return false

	var start_room = starter_scene.instantiate() as Node2D
	add_child(start_room)
	start_room.global_position = Vector2.ZERO
	_occupied_room_grid[_room_grid_key(start_room.global_position)] = true
	rooms_spawned += 1
	start_room_node = start_room
	placed_rooms.append({"node": start_room, "depth": 0, "kind": "start"})

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

			var raw_pos: Vector2 = target_door["pos"] - matching_door.position
			var snapped_pos: Vector2 = _snap_room_position(raw_pos)
			if _is_room_slot_occupied(snapped_pos):
				room.queue_free()
				continue
			room.global_position = snapped_pos

			await get_tree().physics_frame
			await get_tree().physics_frame

			if _check_hitbox_collision(room):
				room.queue_free()
				continue

			room.visible = true
			_occupied_room_grid[_room_grid_key(room.global_position)] = true
			rooms_spawned += 1
			placed_rooms.append({"node": room, "depth": int(target_door["depth"]) + 1, "kind": "normal"})
			var branch_ratio := clampf(float(rooms_spawned) / float(maxi(1, max_rooms)), 0.0, 1.0)
			map_generation_progress.emit(0.10 + branch_ratio * 0.56, "Labirintus szobák építése (%d/%d)..." % [rooms_spawned, max_rooms])
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

	# Először olyan ajtót keresünk, ahol a Boss szoba ÉS a kijárati (Kapu) szoba is elfér;
	# csak végső tartalékként fogadunk el kijárat nélküli elhelyezést.
	var passes: Array[bool] = [true, false]
	for require_exit in passes:
		for i in range(open_doors.size()):
			var target_door = open_doors[i]
			var required_dir: String = String(OPPOSITES.get(target_door["dir"], ""))

			var boss_room := boss_scene.instantiate() as Node2D
			add_child(boss_room)
			boss_room.visible = false

			var matching_door := boss_room.get_node_or_null("Ajtok/" + required_dir + "_ajto") as Node2D
			if matching_door == null:
				boss_room.queue_free()
				continue

			var raw_pos: Vector2 = target_door["pos"] - matching_door.position
			var snapped_boss_pos: Vector2 = _snap_room_position(raw_pos)
			if _is_room_slot_occupied(snapped_boss_pos):
				boss_room.queue_free()
				continue
			boss_room.global_position = snapped_boss_pos

			await get_tree().physics_frame
			await get_tree().physics_frame

			if _check_hitbox_collision(boss_room):
				boss_room.queue_free()
				continue

			var boss_grid_key: Vector2i = _room_grid_key(boss_room.global_position)
			_occupied_room_grid[boss_grid_key] = true

			# Megpróbáljuk ráilleszteni a Kapu/Exit szobát, még mielőtt véglegesítenénk a Boss szobát
			var exit_result: Dictionary = await _handle_boss_room_exits(boss_room, required_dir, require_exit)
			var exit_placed: bool = bool(exit_result.get("placed", false))
			if require_exit and not exit_placed:
				_occupied_room_grid.erase(boss_grid_key)
				boss_room.queue_free()
				await get_tree().physics_frame
				continue

			boss_room.visible = true
			rooms_spawned += 1
			boss_room_node = boss_room
			placed_rooms.append({"node": boss_room, "depth": int(target_door["depth"]) + 1, "kind": "boss"})
			boss_entry_door = {
				"pos": boss_room.global_position + matching_door.position,
				"dir": required_dir
			}
			boss_exit_door = exit_result.get("exit_door", {}) as Dictionary

			open_doors.remove_at(i)
			_prune_open_doors_near_boss_passages()

			print("--- BOSS SZOBA elhelyezve! Pozíció: ", boss_room.global_position, " | Bejárat: ", required_dir, " | Kijárat: ", String(boss_exit_door.get("dir", "nincs")), " ---")
			return

	print("Hiba: Egyetlen nyitott ajtóra sem sikerült ráilleszteni a Boss szobát!")


func _prune_open_doors_near_boss_passages() -> void:
	var protected_positions: Array[Vector2] = []
	if boss_entry_door.has("pos"):
		protected_positions.append(boss_entry_door["pos"] as Vector2)
	if boss_exit_door.has("pos"):
		protected_positions.append(boss_exit_door["pos"] as Vector2)
	if protected_positions.is_empty():
		return

	var kept: Array = []
	for door in open_doors:
		var d_pos: Vector2 = door["pos"]
		var overlaps_protected := false
		for p_pos in protected_positions:
			if d_pos.distance_to(p_pos) < 24.0:
				overlaps_protected = true
				break
		if not overlaps_protected:
			kept.append(door)
	open_doors = kept


func _handle_boss_room_exits(boss_room: Node2D, entry_dir: String, abort_if_no_exit: bool = false) -> Dictionary:
	var result: Dictionary = {"placed": false, "exit_door": {}}
	var boss_doors_node = boss_room.get_node_or_null("Ajtok")
	if boss_doors_node == null:
		return result

	var remaining_boss_doors: Array = []
	for door in boss_doors_node.get_children():
		var dir_name: String = door.name.replace("_ajto", "")
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
			var required_dir: String = String(OPPOSITES.get(b_door["dir"], ""))

			var candidate_exits = exit_scenes.duplicate()
			candidate_exits.shuffle()
			for scene in candidate_exits:
				var reward_room := scene.instantiate() as Node2D
				add_child(reward_room)
				reward_room.visible = false

				var matching_door := reward_room.get_node_or_null("Ajtok/" + required_dir + "_ajto") as Node2D
				if matching_door != null:
					var raw_pos: Vector2 = b_door["pos"] - matching_door.position
					var snapped_exit_pos: Vector2 = _snap_room_position(raw_pos)
					if _is_room_slot_occupied(snapped_exit_pos):
						reward_room.queue_free()
						continue
					reward_room.global_position = snapped_exit_pos

					await get_tree().physics_frame
					await get_tree().physics_frame

					if _check_hitbox_collision(reward_room):
						reward_room.queue_free()
						continue
					else:
						reward_room.visible = true
						_occupied_room_grid[_room_grid_key(reward_room.global_position)] = true
						rooms_spawned += 1
						placed_rooms.append({"node": reward_room, "depth": max_depth + 1, "kind": "exit"})
						reward_placed = true
						reward_door_index = idx
						result["placed"] = true
						result["exit_door"] = {
							"pos": b_door["pos"],
							"dir": b_door["dir"]
						}
						print(" -> Reward Room csatlakoztatva a Boss szoba '", b_door["dir"], "' ajtajára!")
						break
				else:
					reward_room.queue_free()

			if reward_placed:
				break

	if abort_if_no_exit and not reward_placed:
		return result

	# 2. A megmaradt 2 (nem kijárati) ajtót véglegesen lefalazzuk
	var walls := _get_wall_scenes_map()
	for idx in range(remaining_boss_doors.size()):
		if idx == reward_door_index:
			continue

		var b_door = remaining_boss_doors[idx]
		var wall_scene: PackedScene = walls.get(b_door["dir"], null) as PackedScene
		if wall_scene != null:
			var wall := wall_scene.instantiate() as Node2D
			add_child(wall)
			wall.global_position = Vector2(snapped(b_door["pos"].x, 32), snapped(b_door["pos"].y, 32))
			print(" -> Boss szoba '", b_door["dir"], "' ajtaja lefalazva.")

	return result


func _get_wall_scenes_map() -> Dictionary:
	return {
		"felso": wall_felso,
		"also": wall_also,
		"jobb": wall_jobb,
		"bal": wall_bal
	}


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
					var world_pos: Vector2 = layer.to_global(layer.map_to_local(cell))
					if is_wall_piece:
						# A Wall_*.tscn csemperétegek fél-csempével eltolva a mezőhatárra esnek;
						# a kifelé mutató (+Y) 1 px-es eltolás megakadályozza a lebegőpontos kettészakadást
						# és garantálja, hogy a zárófal a szoba melletti külső mezősorba/oszlopba kerüljön.
						world_pos += layer.global_transform.y.normalized()
					var master_cell: Vector2i = target_master.local_to_map(target_master.to_local(world_pos))
					var alt_tile: int = _compose_tile_alternative_with_layer_transform(
						layer.get_cell_alternative_tile(cell),
						layer,
						target_master
					)
					target_master.set_cell(
						master_cell,
						layer.get_cell_source_id(cell),
						layer.get_cell_atlas_coords(cell),
						alt_tile
					)

				# A forrás csemperéteget elrejtjük, mert a mester réteg a forgatással együtt rendereli
				layer.visible = false

		# Hitbox monitoring leállítása a generálás után felesleges fizikai terhelés elkerülésére
		var hitbox = room_child.get_node_or_null("Hitbox") as Area2D
		if hitbox:
			hitbox.monitoring = false
			hitbox.monitorable = false


func _compose_tile_alternative_with_layer_transform(base_alt: int, source_layer: TileMapLayer, target_layer: TileMapLayer) -> int:
	var rel_xform: Transform2D = target_layer.global_transform.affine_inverse() * source_layer.global_transform
	var gx: Vector2 = rel_xform.x.normalized()
	var gy: Vector2 = rel_xform.y.normalized()
	var ix := Vector2i(roundi(gx.x), roundi(gx.y))
	var iy := Vector2i(roundi(gy.x), roundi(gy.y))

	# Ha nincs forgatás vagy tükrözés a rétegen, az eredeti alternative_tile változatlan marad
	if ix == Vector2i(1, 0) and iy == Vector2i(0, 1):
		return base_alt
	# Nem-ortogonális transzformáció biztonsági védelme
	if (absi(ix.x) + absi(ix.y)) != 1 or (absi(iy.x) + absi(iy.y)) != 1 or (ix.x * iy.x + ix.y * iy.y) != 0:
		return base_alt

	var alt_id: int = base_alt & 0x0FFF
	var in_flip_h: bool = (base_alt & TileSetAtlasSource.TRANSFORM_FLIP_H) != 0
	var in_flip_v: bool = (base_alt & TileSetAtlasSource.TRANSFORM_FLIP_V) != 0
	var in_transpose: bool = (base_alt & TileSetAtlasSource.TRANSFORM_TRANSPOSE) != 0

	var bx: Vector2i = Vector2i(0, 1) if in_transpose else Vector2i(1, 0)
	var by: Vector2i = Vector2i(1, 0) if in_transpose else Vector2i(0, 1)
	if in_flip_h:
		bx.x = -bx.x
		by.x = -by.x
	if in_flip_v:
		bx.y = -bx.y
		by.y = -by.y

	var nbx: Vector2i = bx.x * ix + bx.y * iy
	var nby: Vector2i = by.x * ix + by.y * iy

	var out_transpose: bool = nbx.x == 0
	var out_flip_h: bool = (nby.x < 0) if out_transpose else (nbx.x < 0)
	var out_flip_v: bool = (nbx.y < 0) if out_transpose else (nby.y < 0)

	var result: int = alt_id
	if out_flip_h:
		result |= TileSetAtlasSource.TRANSFORM_FLIP_H
	if out_flip_v:
		result |= TileSetAtlasSource.TRANSFORM_FLIP_V
	if out_transpose:
		result |= TileSetAtlasSource.TRANSFORM_TRANSPOSE
	return result


func _setup_world_systems() -> void:
	if grid_manager == null:
		grid_manager = get_tree().get_first_node_in_group("grid_manager") as GridManager

	if grid_manager and master_floor:
		map_generation_progress.emit(0.84, "Útvonalhálózat felépítése...")
		grid_manager.floor_layer = master_floor
		grid_manager.wall_layer = master_wall
		grid_manager.decoratives_layer = master_decoratives
		grid_manager.setup_astar()

	if player == null:
		player = get_tree().get_first_node_in_group("player") as HeroController

	var hero_cell := Vector2i.ZERO
	if player and master_floor:
		player.floor_layer = master_floor
		player.wall_layer = master_wall
		player.decoratives_layer = master_decoratives
		player.fog_of_war = fog_of_war

		# Játékos a kezdőszoba Player_Spawn pontjára igazítása
		player.global_position = player_spawn_pos
		var spawn_grid = master_floor.local_to_map(master_floor.to_local(player_spawn_pos))
		hero_cell = spawn_grid
		player.grid_pos = spawn_grid
		player.position = master_floor.map_to_local(spawn_grid)
		if player.mover:
			player.mover.setup(player)

	if fog_of_war and master_floor:
		map_generation_progress.emit(0.90, "Köd és fáklyák inicializálása...")
		fog_of_war.floor_layer = master_floor
		fog_of_war.wall_layer = master_wall
		fog_of_war.decoratives_layer = master_decoratives
		fog_of_war.torch_layer = master_torch
		fog_of_war.init_fog()

	map_generation_progress.emit(0.95, "Szörnyek idézése...")
	_spawn_enemies(hero_cell)

	if player and player.visuals and player.visuals.has_method("update_fog_of_war"):
		player.visuals.fog_of_war = fog_of_war
		player.visuals.update_fog_of_war()

	print("[MapGenerator] MINDEN RENDSZER KÉSZ! Pálya sikeresen generálva és felépítve.")


func _get_enemies_container(create_if_missing: bool = true) -> Node2D:
	if enemies_container != null and is_instance_valid(enemies_container):
		return enemies_container

	var host := get_parent() if get_parent() != null else self
	var existing := host.get_node_or_null("Enemies") as Node2D
	if existing != null:
		enemies_container = existing
		return enemies_container

	if not create_if_missing:
		return null

	var container := Node2D.new()
	container.name = "Enemies"
	host.add_child(container)
	enemies_container = container
	return enemies_container


func _spawn_enemies(hero_cell: Vector2i) -> void:
	var container := _get_enemies_container(true)
	var spawner := ENEMY_SPAWNER_SCRIPT.new()
	spawner.populate_dungeon(
		placed_rooms,
		container,
		grid_manager,
		fog_of_war,
		hero_cell,
		max_depth,
		_difficulty_to_id(current_difficulty)
	)


# === BOSS SZOBA DINAMIKUS FALAK KEZELÉSE ===

func is_boss_defeated() -> bool:
	return _boss_defeated


func _prepare_boss_room_barriers() -> void:
	_boss_room_floor_cells.clear()
	_boss_entry_barrier_tiles.clear()
	_boss_entry_saved_tiles.clear()
	_boss_exit_barrier_tiles.clear()
	_boss_exit_saved_tiles.clear()
	_boss_entry_sealed = false
	_boss_exit_sealed = false
	_boss_fight_started = false
	_boss_defeated = false
	_pending_entry_seal = false

	if boss_room_node == null or not is_instance_valid(boss_room_node) or master_wall == null or master_floor == null:
		return

	# Összegyűjtjük a Boss szoba padlócelláit a mester rács koordinátáiban
	for layer in boss_room_node.find_children("*", "TileMapLayer", true, false):
		if not (layer is TileMapLayer):
			continue
		var tile_layer := layer as TileMapLayer
		var l_name: String = tile_layer.name.to_lower()
		if "floor" in l_name or "padlo" in l_name:
			for cell in tile_layer.get_used_cells():
				var world_pos: Vector2 = tile_layer.to_global(tile_layer.map_to_local(cell))
				var master_cell: Vector2i = master_floor.local_to_map(master_floor.to_local(world_pos))
				_boss_room_floor_cells[master_cell] = true

	if not boss_entry_door.is_empty():
		_boss_entry_barrier_tiles = _extract_wall_barrier_tiles(boss_entry_door)
	if not boss_exit_door.is_empty():
		_boss_exit_barrier_tiles = _extract_wall_barrier_tiles(boss_exit_door)

	# A kijárati folyosó alapértelmezetten le van falazva, amíg a főellenség le nincs győzve
	_seal_boss_exit(false)


func _extract_wall_barrier_tiles(door_info: Dictionary) -> Array[Dictionary]:
	var tiles: Array[Dictionary] = []
	if master_wall == null or door_info.is_empty():
		return tiles
	var dir_str: String = String(door_info.get("dir", ""))
	var door_pos: Vector2 = door_info.get("pos", Vector2.ZERO) as Vector2
	var walls := _get_wall_scenes_map()
	var wall_scene: PackedScene = walls.get(dir_str, null) as PackedScene
	if wall_scene == null:
		return tiles

	var temp_wall := wall_scene.instantiate() as Node2D
	add_child(temp_wall)
	temp_wall.global_position = Vector2(snapped(door_pos.x, 32), snapped(door_pos.y, 32))

	for layer in temp_wall.find_children("*", "TileMapLayer", true, false):
		if not (layer is TileMapLayer):
			continue
		var wall_layer := layer as TileMapLayer
		var l_name: String = wall_layer.name.to_lower()
		if not ("wall" in l_name or "fal" in l_name):
			continue
		if master_wall.tile_set == null and wall_layer.tile_set != null:
			master_wall.tile_set = wall_layer.tile_set
		for cell in wall_layer.get_used_cells():
			var world_pos: Vector2 = wall_layer.to_global(wall_layer.map_to_local(cell))
			world_pos += wall_layer.global_transform.y.normalized()
			var master_cell: Vector2i = master_wall.local_to_map(master_wall.to_local(world_pos))
			var alt_tile: int = _compose_tile_alternative_with_layer_transform(
				wall_layer.get_cell_alternative_tile(cell),
				wall_layer,
				master_wall
			)
			tiles.append({
				"cell": master_cell,
				"source_id": wall_layer.get_cell_source_id(cell),
				"atlas": wall_layer.get_cell_atlas_coords(cell),
				"alt": alt_tile
			})

	remove_child(temp_wall)
	temp_wall.queue_free()
	return tiles


func _apply_barrier(barrier_tiles: Array[Dictionary]) -> Dictionary:
	var saved: Array[Dictionary] = []
	var changed_cells: Array[Vector2i] = []
	if master_wall == null:
		return {"saved": saved, "cells": changed_cells}

	for entry in barrier_tiles:
		var cell: Vector2i = entry["cell"] as Vector2i
		saved.append({
			"cell": cell,
			"source_id": master_wall.get_cell_source_id(cell),
			"atlas": master_wall.get_cell_atlas_coords(cell),
			"alt": master_wall.get_cell_alternative_tile(cell)
		})
		master_wall.set_cell(
			cell,
			int(entry["source_id"]),
			entry["atlas"] as Vector2i,
			int(entry["alt"])
		)
		changed_cells.append(cell)

	return {"saved": saved, "cells": changed_cells}


func _restore_barrier(saved_tiles: Array[Dictionary]) -> Array[Vector2i]:
	var changed_cells: Array[Vector2i] = []
	if master_wall == null:
		return changed_cells

	for entry in saved_tiles:
		var cell: Vector2i = entry["cell"] as Vector2i
		var src_id: int = int(entry["source_id"])
		if src_id == -1:
			master_wall.erase_cell(cell)
		else:
			master_wall.set_cell(
				cell,
				src_id,
				entry["atlas"] as Vector2i,
				int(entry["alt"])
			)
		changed_cells.append(cell)

	return changed_cells


func _seal_boss_exit(notify_world: bool = true) -> void:
	if _boss_exit_sealed or _boss_exit_barrier_tiles.is_empty():
		return
	var res: Dictionary = _apply_barrier(_boss_exit_barrier_tiles)
	_boss_exit_saved_tiles.assign(res["saved"])
	_boss_exit_sealed = true
	if notify_world:
		var cells: Array[Vector2i] = []
		cells.assign(res["cells"])
		_notify_world_cells_changed(cells)


func _unseal_boss_exit() -> void:
	if not _boss_exit_sealed:
		return
	var changed_cells: Array[Vector2i] = _restore_barrier(_boss_exit_saved_tiles)
	_boss_exit_saved_tiles.clear()
	_boss_exit_sealed = false
	_notify_world_cells_changed(changed_cells)


func _seal_boss_entrance() -> void:
	if _boss_entry_sealed or _boss_defeated or _boss_entry_barrier_tiles.is_empty():
		return
	var res: Dictionary = _apply_barrier(_boss_entry_barrier_tiles)
	_boss_entry_saved_tiles.assign(res["saved"])
	_boss_entry_sealed = true
	_pending_entry_seal = false
	var cells: Array[Vector2i] = []
	cells.assign(res["cells"])
	_notify_world_cells_changed(cells)
	AudioManager.sfx(&"crit_slam", 0.70, 0.78, -3.5)


func _unseal_boss_entrance() -> void:
	_pending_entry_seal = false
	if not _boss_entry_sealed:
		return
	var changed_cells := _restore_barrier(_boss_entry_saved_tiles)
	_boss_entry_saved_tiles.clear()
	_boss_entry_sealed = false
	_notify_world_cells_changed(changed_cells)


func _is_hero_safely_inside_boss_room() -> bool:
	if player == null or not is_instance_valid(player):
		player = get_tree().get_first_node_in_group("player") as HeroController
	if player == null or not is_instance_valid(player) or not player.is_alive():
		return false
	if _boss_room_floor_cells.is_empty():
		return false

	var hero_cell: Vector2i = player.grid_pos
	if not _boss_room_floor_cells.has(hero_cell):
		return false
	if player.is_moving and not _boss_room_floor_cells.has(player.current_step_target):
		return false

	for entry in _boss_entry_barrier_tiles:
		var b_cell: Vector2i = entry["cell"] as Vector2i
		if hero_cell == b_cell or (player.is_moving and player.current_step_target == b_cell):
			return false
	return true


func _try_seal_boss_entrance_if_hero_inside() -> void:
	if _boss_entry_sealed or _boss_defeated or _boss_entry_barrier_tiles.is_empty():
		return
	if _is_hero_safely_inside_boss_room():
		_seal_boss_entrance()


func on_boss_fight_started() -> void:
	if _boss_defeated:
		return
	_boss_fight_started = true
	if _boss_entry_sealed or _boss_entry_barrier_tiles.is_empty():
		return
	if _is_hero_safely_inside_boss_room():
		_seal_boss_entrance()
	else:
		# Ha a hős kívülről (távolsági támadással) indította a harcot, amint belép a terembe, lezárul mögötte a fal
		_pending_entry_seal = true


func on_boss_defeated() -> void:
	_boss_defeated = true
	_pending_entry_seal = false
	_unseal_boss_exit()
	_unseal_boss_entrance()


func _notify_world_cells_changed(changed_cells: Array[Vector2i]) -> void:
	if grid_manager == null or not is_instance_valid(grid_manager):
		grid_manager = get_tree().get_first_node_in_group("grid_manager") as GridManager
	if grid_manager != null and grid_manager.has_method("refresh_cells"):
		grid_manager.refresh_cells(changed_cells)

	if player != null and is_instance_valid(player):
		if player.has_method("update_fog_of_war"):
			player.update_fog_of_war()
		if player.visuals != null and is_instance_valid(player.visuals):
			player.visuals.queue_redraw()

	var hud := get_tree().get_first_node_in_group("hud")
	if hud != null:
		var mm := hud.get("minimap_canvas") as Control
		if mm != null and is_instance_valid(mm):
			mm.queue_redraw()
		var bm := hud.get("big_map_canvas") as Control
		if bm != null and is_instance_valid(bm):
			bm.queue_redraw()
