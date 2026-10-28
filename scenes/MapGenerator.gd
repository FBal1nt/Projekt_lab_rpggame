
extends Node2D

@export var starter_scene: PackedScene
@export var room_scenes: Array[PackedScene]
@export var exit_scenes: Array[PackedScene]

# Falak
@export var wall_felso: PackedScene
@export var wall_also: PackedScene
@export var wall_jobb: PackedScene
@export var wall_bal: PackedScene

# Generálási korlátok
@export var max_rooms: int = 15
@export var max_depth: int = 10
@export var max_exits: int = 1

var open_doors: Array[Dictionary] = []

var rooms_spawned: int = 0
var exits_spawned: int = 0

var opposites: Dictionary = {
	"felso": "also",
	"also": "felso",
	"jobb": "bal",
	"bal": "jobb"
}


func _ready() -> void:
	generate_map()


# ==================================================
# PÁLYAGENERÁLÁS
# ==================================================

func generate_map() -> void:
	if starter_scene == null:
		push_error("HIBA: Nincs beállítva a starter_scene!")
		return

	open_doors.clear()
	rooms_spawned = 0
	exits_spawned = 0

	print("--- PÁLYAGENERÁLÁS INDÍTÁSA ---")

	# Kezdőszoba
	var start_room = starter_scene.instantiate() as Node2D

	if start_room == null:
		push_error("A kezdőszoba gyökérnode-ja Node2D legyen!")
		return

	add_child(start_room)
	start_room.global_position = Vector2.ZERO

	rooms_spawned += 1

	await get_tree().physics_frame

	# A kezdőszoba összes ajtajának regisztrálása
	register_doors(start_room, 1, "")

	# Fő generáló ciklus
	while not open_doors.is_empty() and rooms_spawned < max_rooms:

		# FONTOS JAVÍTÁS:
		# A feldolgozandó ajtót AZONNAL kivesszük a listából.
		# Ez még azelőtt történik, hogy az új szoba ajtóit
		# hozzáadnánk az open_doors listához.
		var target_door: Dictionary = open_doors.pop_back()

		var parent_room = target_door["room"] as Node2D

		if not is_instance_valid(parent_room):
			continue

		var depth: int = int(target_door["depth"])

		print(
			"Ajtó feldolgozása: ",
			target_door["dir"],
			" | Mélység: ",
			depth,
			" | Várakozó ajtók: ",
			open_doors.size()
		)

		# Maximális mélység elérése
		if depth > max_depth:
			var exit_placed := false

			if exits_spawned < max_exits:
				exit_placed = await try_place_exit_room(target_door)

			if not exit_placed:
				place_wall(target_door)

			continue

		# A csatlakozó ajtó iránya
		var required_dir: String = str(
			opposites.get(target_door["dir"], "")
		)

		if required_dir == "":
			push_warning("Ismeretlen ajtóirány!")
			place_wall(target_door)
			continue

		# Szobák véletlenszerű sorrendben
		var shuffled_scenes: Array[PackedScene] = room_scenes.duplicate()
		shuffled_scenes.shuffle()

		var room_placed := false

		for scene in shuffled_scenes:
			if scene == null:
				continue

			var new_room = scene.instantiate() as Node2D

			if new_room == null:
				continue

			add_child(new_room)
			new_room.visible = false

			# Megkeressük a csatlakozó ajtót.
			var matching_door = new_room.get_node_or_null("Ajtok/" + required_dir + "_ajto")

			# Ha a szobának nincs ilyen ajtaja,
			# akkor ez a szobatípus nem használható.
			if matching_door == null:
				new_room.queue_free()
				continue

			# Ajtók pontos illesztése
			new_room.global_position = target_door["pos"] - new_room.to_local(matching_door.global_position)

			# Megvárjuk a fizikai ütközések frissítését.
			await get_tree().physics_frame
			await get_tree().physics_frame

			var hitbox = new_room.get_node_or_null("Hitbox")
			var overlaps := false

			if hitbox != null and hitbox is Area2D:
				for area in hitbox.get_overlapping_areas():
					var area_owner = get_room_owner(area)
					# A szülőszobával való ajtókapcsolat megengedett.
					if area_owner == null:
						continue
					if area_owner == new_room:
						continue
					if area_owner == parent_room:
						continue
					# Másik már lerakott szobával ütközik.
					overlaps = true
					break
			if overlaps:
				print(
					"Szoba elutasítva ütközés miatt: ",
					new_room.name
				)
				new_room.queue_free()
				continue

			# SIKERES SZOBALERAKÁS
			new_room.visible = true
			rooms_spawned += 1
			room_placed = true

			print(
				"Szoba lerakva: ",
				new_room.name,
				" | ",
				rooms_spawned,
				"/",
				max_rooms,
				" | Mélység: ",
				depth
			)

			# A legfontosabb lépés:
			# Az új szoba összes további ajtaját hozzáadjuk
			# a feldolgozásra váró ajtók listájához.
			register_doors(
				new_room,
				depth + 1,
				required_dir
			)

			# Egy ajtóhoz elegendő egy szobát lerakni.
			break

		# Ha egyik szobatípus sem illeszthető,
		# csak az aktuális ajtót zárjuk le.
		if not room_placed:
			print(
				"Nem található megfelelő szoba ehhez az ajtóhoz."
			)
			place_wall(target_door)

	# Ha elértük a maximális szobaszámot,
	# a fennmaradó ajtókat falakkal lezárjuk.
	close_remaining_doors()

	print(
		"--- PÁLYAGENERÁLÁS KÉSZ: ",
		rooms_spawned,
		" szoba, ",
		exits_spawned,
		" kijárat/zsákutca. ---"
	)


# ==================================================
# AJTÓK REGISZTRÁLÁSA
# ==================================================

func register_doors(
	room: Node2D,
	depth: int,
	entry_dir: String
) -> void:

	var doors_node = room.get_node_or_null("Ajtok")

	if doors_node == null:
		push_warning(
			"Hiányzik az Ajtok node: " + room.name
		)
		return

	var new_doors: Array[Dictionary] = []

	# Csak a ténylegesen létező ajtókat dolgozzuk fel.
	for door in doors_node.get_children():

		var door_name: String = str(door.name).replace(
			"_ajto", ""
		)

		# A belépési ajtót nem nyitjuk meg újra.
		if door_name == entry_dir:
			continue

		if not opposites.has(door_name):
			push_warning(
				"Ismeretlen ajtónév: " + str(door.name)
			)
			continue

		new_doors.append({
			"pos": door.global_position,
			"dir": door_name,
			"depth": depth,
			"room": room
		})

	new_doors.shuffle()

	# A korábban feldolgozott ajtókhoz nem nyúlunk.
	# Az új ajtókat a lista végére tesszük.
	open_doors.append_array(new_doors)

	print(
		"Ajtók regisztrálva: ",
		room.name,
		" | Új ajtók: ",
		new_doors.size(),
		" | Összes várakozó: ",
		open_doors.size()
	)


# ==================================================
# SZOBATULAJDONOS MEGKERESÉSE
# ==================================================

func get_room_owner(node: Node) -> Node2D:
	var current: Node = node

	while current != null and current != self:
		if current.get_parent() == self and current is Node2D:
			return current as Node2D

		current = current.get_parent()

	return null


# ==================================================
# KIJÁRAT / ZSÁKUTCA
# ==================================================

func try_place_exit_room(door: Dictionary) -> bool:
	if exit_scenes.is_empty():
		return false

	var required_dir: String = str(
		opposites.get(door["dir"], "")
	)

	if required_dir == "":
		return false

	var parent_room = door["room"] as Node2D

	if not is_instance_valid(parent_room):
		return false

	var shuffled_exits: Array[PackedScene] = exit_scenes.duplicate()
	shuffled_exits.shuffle()

	for scene in shuffled_exits:
		if scene == null:
			continue

		var temp_room = scene.instantiate() as Node2D

		if temp_room == null:
			continue

		add_child(temp_room)
		temp_room.visible = false

		var matching_door = temp_room.get_node_or_null(
			"Ajtok/" + required_dir + "_ajto"
		)

		if matching_door == null:
			temp_room.queue_free()
			continue

		temp_room.global_position = (
			door["pos"] - matching_door.position
		)

		await get_tree().physics_frame
		await get_tree().physics_frame

		var hitbox = temp_room.get_node_or_null("Hitbox")
		var overlaps := false

		if hitbox != null and hitbox is Area2D:
			for area in hitbox.get_overlapping_areas():
				var area_owner = get_room_owner(area)

				if area_owner == null:
					continue

				if area_owner == temp_room:
					continue

				if area_owner == parent_room:
					continue

				overlaps = true
				break

		if overlaps:
			temp_room.queue_free()
			continue

		# Kijárat sikeresen lerakva.
		temp_room.visible = true

		rooms_spawned += 1
		exits_spawned += 1

		print(
			"Kijárat/zsákutca lerakva. Mélység: ",
			door["depth"]
		)

		return true

	return false


# ==================================================
# FALAK
# ==================================================

func place_wall(door: Dictionary) -> void:
	var wall_dict: Dictionary = {
		"felso": wall_felso,
		"also": wall_also,
		"jobb": wall_jobb,
		"bal": wall_bal
	}

	var direction: String = str(door["dir"])
	var scene_to_spawn = wall_dict.get(direction)

	if scene_to_spawn == null:
		push_warning(
			"Nincs beállítva fal ehhez az irányhoz: "
			+ direction
		)
		return

	var wall = scene_to_spawn.instantiate() as Node2D

	if wall == null:
		return

	add_child(wall)
	wall.global_position = door["pos"]


# ==================================================
# MARADÉK AJTÓK LEZÁRÁSA
# ==================================================

func close_remaining_doors() -> void:
	while not open_doors.is_empty():
		var door: Dictionary = open_doors.pop_back()
		place_wall(door)
