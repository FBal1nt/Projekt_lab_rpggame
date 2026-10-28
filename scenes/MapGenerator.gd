extends Node2D

# === INSPECTOR BEÁLLÍTÁSOK ===
@export_group("Szobák")
@export var starter_scene: PackedScene
@export var room_scenes: Array[PackedScene]     # 2-4 ajtós normál szobák
@export var boss_scene: PackedScene             # 4-ajtós Boss szoba
@export var exit_scenes: Array[PackedScene]     # 1-ajtós zsákutcák / Reward szobák

@export_group("Falazó Elemek (Vakajtók lezárásához)")
@export var wall_felso: PackedScene
@export var wall_also: PackedScene
@export var wall_jobb: PackedScene
@export var wall_bal: PackedScene

@export_group("Generálási Korlátok")
@export var max_rooms: int = 30
@export var max_depth: int = 5

enum Difficulty { EASY, MEDIUM, HARD }

func apply_difficulty(diff: Difficulty):
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

# === BELSŐ VÁLTOZÓK ===
var open_doors: Array = []
var rooms_spawned: int = 0

const OPPOSITES = {
	"felso": "also",
	"also": "felso",
	"jobb": "bal",
	"bal": "jobb"
}

func _ready():
	generate_map()

# === FŐ GENERÁLÁSI FOLYAMAT ===
func generate_map(p_max_rooms: int = -1, p_max_depth: int = -1):
	_reset_generator()
	
	# Ha a Hívó (Lobby / Main) felülbírálja a nehézség alapján:
	if p_max_rooms > 0:
		max_rooms = p_max_rooms
	if p_max_depth > 0:
		max_depth = p_max_depth
		
	print("Pálya generálása indítva -> Max szobák: ", max_rooms, " | Max mélység: ", max_depth)
	
	# 1. Kezdőszoba lerakása
	if not _spawn_starter_room():
		return
		
	print("--- 1. LÉPÉS: Kezdőszoba lerakva ---")
	
	# 2. Normál szobák fűzése
	await _generate_branches()
	print("--- 2. LÉPÉS: Normál szobák lerakva (", rooms_spawned, " db) ---")

	# 3. Boss szoba + Reward szoba + 2 Fal lehelyezése
	await _place_boss_room()

	# 4. Maradék nyitott folyosóvégek (normál szobák) lefalazása
	_close_remaining_doors()
	print("--- GENERÁLÁS KÉSZ! Összesen lerakott szoba: ", rooms_spawned, " ---")


func _reset_generator():
	open_doors.clear()
	rooms_spawned = 0
	for child in get_children():
		child.queue_free()


func _spawn_starter_room() -> bool:
	if starter_scene == null:
		push_error("MapGenerator: Nincs beállítva a 'starter_scene'!")
		return false
		
	var start_room = starter_scene.instantiate()
	add_child(start_room)
	start_room.global_position = Vector2.ZERO
	rooms_spawned += 1
	_register_doors(start_room, 1, "")
	return true


func _generate_branches():
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

		room_scenes.shuffle()
		var room_placed = false

		for scene in room_scenes:
			var room = scene.instantiate()
			add_child(room)
			room.visible = false

			var matching_door = room.get_node_or_null("Ajtok/" + required_dir + "_ajto")
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


func _place_boss_room():
	if boss_scene == null or open_doors.is_empty():
		print("Figyelem: Nincs 'boss_scene' beállítva vagy nincs nyitott ajtó!")
		return

	# Mélység szerint csökkenő sorrendbe rendezzük az ajtókat (a legmélyebb van elöl)
	open_doors.sort_custom(func(a, b): return a["depth"] > b["depth"])

	for i in range(open_doors.size()):
		var target_door = open_doors[i]
		var required_dir = OPPOSITES.get(target_door["dir"], "")

		var boss_room = boss_scene.instantiate()
		add_child(boss_room)
		boss_room.visible = false

		var matching_door = boss_room.get_node_or_null("Ajtok/" + required_dir + "_ajto")
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
				
				# CÉLZOTTEN KEZELJÜK A BOSS SZOBA MARADÉK 3 AJTAJÁT (1 Reward + 2 Fal)
				await _handle_boss_room_exits(boss_room, required_dir)
				return
		else:
			boss_room.queue_free()

	print("Hiba: Egyetlen nyitott ajtóra sem sikerült ráilleszteni a Boss szobát!")


func _handle_boss_room_exits(boss_room: Node2D, entry_dir: String):
	var boss_doors_node = boss_room.get_node_or_null("Ajtok")
	if boss_doors_node == null:
		return

	# A Boss szoba 3 megmaradt kivezető ajtójának kigyűjtése
	var remaining_boss_doors: Array = []
	for door in boss_doors_node.get_children():
		var dir_name = door.name.replace("_ajto", "")
		if dir_name != entry_dir:
			remaining_boss_doors.append({
				"pos": boss_room.global_position + door.position,
				"dir": dir_name
			})

	remaining_boss_doors.shuffle()

	var reward_placed = false
	var reward_door_index = -1

	# 1. Megpróbálunk 1 db Reward / Exit szobát ráilleszteni az egyik szabad ajtóra
	if not exit_scenes.is_empty():
		for idx in range(remaining_boss_doors.size()):
			var b_door = remaining_boss_doors[idx]
			var required_dir = OPPOSITES.get(b_door["dir"], "")

			exit_scenes.shuffle()
			for scene in exit_scenes:
				var reward_room = scene.instantiate()
				add_child(reward_room)
				reward_room.visible = false

				var matching_door = reward_room.get_node_or_null("Ajtok/" + required_dir + "_ajto")
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

	# 2. A megmaradt ajtókat (2 db, vagy mind a 3-at, ha a Reward nem fért el) lefalazzuk
	var walls = {
		"felso": wall_felso,
		"also": wall_also,
		"jobb": wall_jobb,
		"bal": wall_bal
	}

	for idx in range(remaining_boss_doors.size()):
		if idx == reward_door_index:
			continue # Ezen az ajtón van a Reward szoba, ezt nem falazzuk le!

		var b_door = remaining_boss_doors[idx]
		var wall_scene = walls.get(b_door["dir"])
		if wall_scene != null:
			var wall = wall_scene.instantiate()
			add_child(wall)
			wall.global_position = Vector2(snapped(b_door["pos"].x, 32), snapped(b_door["pos"].y, 32))
			print(" -> Boss szoba '", b_door["dir"], "' ajtaja lefalazva.")


func _close_remaining_doors():
	var walls = {
		"felso": wall_felso,
		"also": wall_also,
		"jobb": wall_jobb,
		"bal": wall_bal
	}

	for door in open_doors:
		var scene = walls.get(door["dir"])
		if scene != null:
			var wall = scene.instantiate()
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
