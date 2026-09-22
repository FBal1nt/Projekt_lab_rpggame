extends Node2D

@export var max_rooms: int = 15
@export var starter_scene: PackedScene
@export var room_scenes: Array[PackedScene] 

var open_doors = [] # Itt tároljuk a befejezetlen, szabad csatlakozási pontokat

# Szótár a magyar ellentétes irányok párosításához
var opposites = {
	"felso": "also",
	"also": "felso",
	"jobb": "bal",
	"bal": "jobb"
}

func _ready():
	randomize() # Véletlenszám-generátor inicializálása
	generate_map()

func generate_map():
	# 1. Kezdőszoba lerakása
	var start_room = starter_scene.instantiate()
	add_child(start_room)
	start_room.global_position = Vector2.ZERO
	register_doors(start_room)
	
	print("Kezdőszoba lerakva. Talált ajtók száma: ", open_doors.size())
	if open_doors.size() == 0:
		print("HIBA: A script nem találta meg az 'Ajtok' csomópontot a Start_room-ban!")
	
	var rooms_spawned = 1
	
	# 2. Generáló ciklus
	while open_doors.size() > 0 and rooms_spawned < max_rooms:
		var door_index = randi() % open_doors.size()
		var target_door = open_doors[door_index]
		open_doors.remove_at(door_index)
		
		# Kikeressük, milyen irányú ajtó kell (pl. "jobb" célponthoz "bal" ajtó kell)
		var required_dir = opposites[target_door["dir"]]
		
		#Debug sor
		print("Keresem a következőt: A régi szobában volt '", target_door["dir"], "', ezért az új szobában kell egy: '", required_dir, "_ajto'")
		
		# Megkeverjük a szobák listáját a véletlenszerűséghez
		room_scenes.shuffle()
		
		for scene in room_scenes:
			var new_room = scene.instantiate()
			# A kódban így fogja keresni: pl. "Ajtok/bal_ajto"
			var matching_door = new_room.get_node_or_null("Ajtok/" + required_dir + "_ajto")
			
			if matching_door != null:
				add_child(new_room)
				
				# TÉRBELI ILLESZTÉS
				new_room.global_position = target_door["pos"] - matching_door.position
				
				register_doors(new_room, required_dir)
				rooms_spawned += 1
				break # Kilépünk, a szoba sikeresen le lett rakva
			else:
				new_room.queue_free()

# Összegyűjti egy lerakott szoba szabad ajtóit
func register_doors(room: Node2D, ignore_dir: String = ""):
	var doors_node = room.get_node_or_null("Ajtok")
	if doors_node:
		for door in doors_node.get_children():
			# A "jobb_ajto"-ból levágja az "_ajto"-t, így marad a "jobb"
			var dir = door.name.replace("_ajto", "")
			if dir != ignore_dir:
				open_doors.append({
					"pos": door.global_position,
					"dir": dir
				})
