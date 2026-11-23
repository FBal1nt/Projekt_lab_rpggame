extends Node2D
class_name HeroController

@export_group("Hős Alapadatok")
@export var hero_name: String = "Gandalf"

@export_group("Debug")
@export var debug_mode_on_start: bool = false
@export var debug_default_class: CharacterClass

@export_group("Komponensek")
@onready var visuals: HeroVisuals = $Visuals
@onready var mover: HeroMover = $Mover
@onready var combat: HeroCombat = $Combat
@onready var progression: HeroProgression = $Progression

var _grid_pos: Vector2i = Vector2i.ZERO

var grid_pos: Vector2i:
	get: return mover.grid_pos if mover else _grid_pos
	set(val):
		_grid_pos = val
		if mover: mover.grid_pos = val

var current_step_target: Vector2i:
	get: return mover.current_step_target if mover else grid_pos
	set(val):
		if mover: mover.current_step_target = val

var is_moving: bool:
	get: return mover.is_moving if mover else false
	set(val):
		if mover: mover.is_moving = val

var path_queue: Array[Vector2i]:
	get: return mover.path_queue if mover else []
	set(val):
		if mover: mover.path_queue = val

var is_attacking: bool:
	get: return combat.is_attacking if combat else false
	set(val):
		if combat: combat.is_attacking = val
		
var is_stunned: bool:
	get: return combat.is_stunned if combat else false
	set(val):
		if combat: combat.is_stunned = val

var in_battle: bool:
	get: return combat.in_battle if combat else false
	set(val):
		if combat: combat.in_battle = val

var current_hp: int:
	get: return progression.current_hp if progression else 0
	set(val):
		if progression: progression.current_hp = val

var max_hp: int:
	get: return progression.max_hp if progression else 100

var active_class: CharacterClass:
	get: return progression.active_class if progression else null

var sprite: AnimatedSprite2D:
	get: return visuals.sprite if visuals else null

var level: int:
	get: return progression.level if progression else 1

var xp: int:
	get: return progression.xp if progression else 0

var attack_power: int:
	get: return progression.attack_power if progression else 10

var vision_limit: int:
	get: return visuals.vision_limit if visuals else 2

var _floor_layer: TileMapLayer = null
var _wall_layer: TileMapLayer = null
var _decoratives_layer: TileMapLayer = null
var _fog_of_war: FogOfWar = null

var floor_layer: TileMapLayer:
	get:
		if mover and mover.grid_manager and mover.grid_manager.floor_layer:
			return mover.grid_manager.floor_layer
		return _floor_layer
	set(val):
		_floor_layer = val
		if mover and mover.grid_manager:
			mover.grid_manager.floor_layer = val

var wall_layer: TileMapLayer:
	get:
		if mover and mover.grid_manager and mover.grid_manager.wall_layer:
			return mover.grid_manager.wall_layer
		return _wall_layer
	set(val):
		_wall_layer = val
		if mover and mover.grid_manager:
			mover.grid_manager.wall_layer = val

var decoratives_layer: TileMapLayer:
	get:
		if mover and mover.grid_manager and mover.grid_manager.decoratives_layer:
			return mover.grid_manager.decoratives_layer
		return _decoratives_layer
	set(val):
		_decoratives_layer = val
		if mover and mover.grid_manager:
			mover.grid_manager.decoratives_layer = val

var fog_of_war: FogOfWar:
	get:
		if visuals and visuals.fog_of_war:
			return visuals.fog_of_war
		return _fog_of_war
	set(val):
		_fog_of_war = val
		if visuals:
			visuals.fog_of_war = val

var is_death_played: bool = false
var debug_invincible: bool = false

func _exit_tree() -> void:
	var sm := get_node_or_null("/root/SettingsManager")
	if sm != null and sm.has_signal("settings_changed") and sm.settings_changed.is_connected(_apply_camera_settings):
		sm.settings_changed.disconnect(_apply_camera_settings)

func _ready() -> void:
	add_to_group("player")
	z_index = 10

	# Komponensek összekötése:
	if mover: mover.setup(self)
	if visuals: visuals.setup(self)
	if combat: combat.setup(self)
	if progression: progression.setup(self)

	_apply_camera_settings()
	var sm := get_node_or_null("/root/SettingsManager")
	if sm != null and sm.has_signal("settings_changed") and not sm.settings_changed.is_connected(_apply_camera_settings):
		sm.settings_changed.connect(_apply_camera_settings)

	if debug_mode_on_start:
		enable_debug_mode()

func _apply_camera_settings() -> void:
	var cam := get_node_or_null("Camera2D") as Camera2D
	if cam == null:
		return
	cam.position_smoothing_enabled = false
	var sm := get_node_or_null("/root/SettingsManager")
	if sm == null:
		return
	var zoom_val := clampf(float(sm.get("camera_zoom")), 2.5, 6.0)
	cam.zoom = Vector2(zoom_val, zoom_val)

func setup_grid_astar() -> void:
	var gm = get_tree().get_first_node_in_group("grid_manager") as GridManager
	if gm:
		gm.setup_astar()
	if mover:
		mover.setup(self)

func update_fog_of_war() -> void:
	if visuals and visuals.has_method("update_fog_of_war"):
		visuals.update_fog_of_war()

func _process(_delta: float) -> void:
	var dm := get_node_or_null("/root/DungeonManager")
	if dm != null and dm.has_method("is_loading_dungeon") and dm.is_loading_dungeon():
		return
	if visuals:
		visuals.process_hover()

func _mark_input_handled() -> void:
	if not is_inside_tree():
		return
	var vp := get_viewport()
	if vp != null and vp.is_inside_tree():
		vp.set_input_as_handled()

func _unhandled_input(event: InputEvent) -> void:
	if not is_inside_tree():
		return
	var dm := get_node_or_null("/root/DungeonManager")
	if dm != null and dm.has_method("is_loading_dungeon") and dm.is_loading_dungeon():
		return
	if not is_alive() or in_battle or is_attacking or is_stunned:
		return

	var sm_move := get_node_or_null("/root/SettingsManager")
	var allow_wasd: bool = (
		bool(sm_move.is_wasd_movement_enabled())
		if (sm_move != null and sm_move.has_method("is_wasd_movement_enabled"))
		else true
	)
	var allow_click_move: bool = (
		bool(sm_move.is_click_movement_enabled())
		if (sm_move != null and sm_move.has_method("is_click_movement_enabled"))
		else true
	)

	# 1. WASD és Nyílbillentyűk (lépés mezőnként)
	if allow_wasd:
		var move_dir := Vector2i.ZERO
		if event.is_action_pressed("ui_up") or _is_key_pressed(event, [KEY_W, KEY_UP]):
			move_dir = Vector2i(0, -1)
		elif event.is_action_pressed("ui_down") or _is_key_pressed(event, [KEY_S, KEY_DOWN]):
			move_dir = Vector2i(0, 1)
		elif event.is_action_pressed("ui_left") or _is_key_pressed(event, [KEY_A, KEY_LEFT]):
			move_dir = Vector2i(-1, 0)
		elif event.is_action_pressed("ui_right") or _is_key_pressed(event, [KEY_D, KEY_RIGHT]):
			move_dir = Vector2i(1, 0)

		if move_dir != Vector2i.ZERO:
			if mover and mover.move_in_direction(move_dir):
				_mark_input_handled()
				return

	# 2. Számbillentyűk és képességek
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_Z or (event.keycode == KEY_NONE and event.physical_keycode == KEY_Z):
			if _teleport_to_boss_debug():
				_mark_input_handled()
				return

		var sm := get_node_or_null("/root/SettingsManager")
		var is_wizard_swap: bool = (
			sm.matches_keybind(event, "wizard_element")
			if (sm != null and sm.has_method("matches_keybind"))
			else _is_key_pressed(event, [KEY_F])
		)
		var is_priest_heal: bool = (
			sm.matches_keybind(event, "priest_heal")
			if (sm != null and sm.has_method("matches_keybind"))
			else _is_key_pressed(event, [KEY_H])
		)
		if is_wizard_swap:
			if combat and active_class and active_class.class_name_id == "Wizard":
				combat.wizard_element = "fire" if combat.wizard_element == "ice" else "ice"
				AudioManager.sfx(&"element_swap", 0.96, 1.06, -2.0)
				print("[VARÁZSLÓ] Elem váltva: ", combat.wizard_element)
				if progression:
					progression.update_hud()
				_mark_input_handled()
				return
		elif is_priest_heal:
			if combat and active_class and active_class.class_name_id == "Priest":
				combat.cast_priest_self_heal()
				_mark_input_handled()
				return

	# 3. Egér kattintások:
	# Bal klikk: ha ellenségre kattintunk -> támadás, ha üres mezőre -> odasétálás (ha az egérmozgás aktív)!
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		var handled_attack = combat.handle_attack_click() if combat else false
		if not handled_attack and allow_click_move and mover:
			mover.handle_move_click()
		if handled_attack or allow_click_move:
			_mark_input_handled()
		return

	# Jobb klikk: közvetlen mozgás parancs (csak ha a kattintásos mozgás engedélyezve van)
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
		if allow_click_move and mover:
			mover.handle_move_click()
			_mark_input_handled()
		return

func _is_key_pressed(event: InputEvent, keys: Array) -> bool:
	if not (event is InputEventKey and event.pressed):
		return false
	var kc: int = (event as InputEventKey).keycode
	var pkc: int = (event as InputEventKey).physical_keycode
	for target in keys:
		if kc == target or pkc == target:
			return true
	return false

func trigger_monsters_turn() -> void:
	for enemy in get_tree().get_nodes_in_group("enemies"):
		if is_instance_valid(enemy) and enemy.has_method("take_turn"):
			enemy.take_turn(self)

func get_initiative() -> float: return progression.get_initiative() if progression else 10.0
func get_defense() -> int: return progression.get_defense() if progression else 0
func get_current_hp() -> int: return current_hp
func get_max_hp() -> int: return max_hp
func is_alive() -> bool: return current_hp > 0

func award_title(new_title: String) -> void:
	if progression and progression.has_method("award_title"):
		progression.award_title(new_title)

func on_boss_defeated() -> void:
	var map_gen := get_tree().get_first_node_in_group("map_generator")
	if map_gen != null and map_gen.has_method("on_boss_defeated"):
		map_gen.on_boss_defeated()
	for gate in get_tree().get_nodes_in_group("exit_gates"):
		if is_instance_valid(gate) and gate.has_method("on_boss_defeated"):
			gate.on_boss_defeated()
	var hud := get_tree().get_first_node_in_group("hud")
	if hud != null and hud.has_method("show_boss_defeated_toast"):
		hud.show_boss_defeated_toast()

func take_damage(incoming_raw_damage: int) -> int:
	return combat.take_damage(incoming_raw_damage) if combat else 0

func try_trigger_block() -> bool:
	return combat.try_trigger_block() if combat else false

func play_hurt_reaction() -> void:
	if visuals: await visuals.play_hurt_reaction()
	
func apply_stun(duration: float = 0.8) -> void:
	is_stunned = true
	if visuals and visuals.has_method("play_stun_sequence"):
		await visuals.play_stun_sequence(duration)

func perform_combat_turn(target_enemy: Node2D) -> int:
	if combat: return await combat.perform_combat_turn(target_enemy)
	return 0

func cancel_movement_immediately() -> void:
	if mover: mover.cancel_movement_immediately()

func can_attack_cell(target_cell: Vector2i) -> bool:
	return combat.can_attack_cell(target_cell) if combat else false

func is_tile_in_vision(cell: Vector2i) -> bool:
	return visuals.is_tile_in_vision(cell) if visuals else true

## A hős elterülése és földön maradása halál esetén
func play_overworld_death() -> void:
	if is_death_played: return
	is_death_played = true
	AudioManager.sfx(&"death_hero", 0.96, 1.04, 0.0)

	if mover:
		mover.cancel_movement_immediately()
		mover.is_moving = false
		mover.path_queue.clear()

	in_battle = false
	is_attacking = false

	var spr = sprite
	if spr and spr.sprite_frames and spr.sprite_frames.has_animation("death"):
		var last_frame: int = maxi(0, spr.sprite_frames.get_frame_count("death") - 1)
		if not (spr.animation == "death" and spr.frame >= last_frame and not spr.is_playing()):
			spr.play("death")
			await spr.animation_finished
			spr.stop()
			spr.animation = "death"
			spr.frame = last_frame

	var battle_ui := get_tree().get_first_node_in_group("battle_ui")
	if battle_ui == null or not bool(battle_ui.get("combat_active")):
		show_death_screen()


## Megnyitja a halálképernyőt (és elrejti a HUD-ot)
func show_death_screen() -> void:
	var hud := get_tree().get_first_node_in_group("hud")
	if hud != null:
		if hud.has_method("set_battle_mode"):
			hud.set_battle_mode(true)
		elif "visible" in hud:
			hud.visible = false

	var death_ui := get_tree().get_first_node_in_group("death_screen")
	if death_ui == null and ResourceLoader.exists("res://Scenes/UI/death_screen.tscn"):
		var packed := load("res://Scenes/UI/death_screen.tscn") as PackedScene
		if packed != null:
			death_ui = packed.instantiate()
			get_tree().current_scene.add_child(death_ui)

	if death_ui != null and death_ui.has_method("show_death_screen"):
		death_ui.show_death_screen(self)


func _teleport_to_boss_debug() -> bool:
	var scene := get_tree().current_scene
	if scene == null:
		return false

	var debug_marker: Node2D = null
	var map_gen := scene.find_child("MapGenerator", true, false)
	if map_gen != null:
		var boss_room = map_gen.get("boss_room_node") as Node
		if is_instance_valid(boss_room):
			debug_marker = boss_room.find_child("DEBUG", true, false) as Node2D
	if debug_marker == null:
		debug_marker = scene.find_child("DEBUG", true, false) as Node2D
	if debug_marker == null:
		return false

	if mover:
		mover.cancel_movement_immediately()

	var fl: TileMapLayer = floor_layer
	if fl != null:
		var target_cell := fl.local_to_map(fl.to_local(debug_marker.global_position))
		grid_pos = target_cell
		current_step_target = target_cell
		global_position = fl.to_global(fl.map_to_local(target_cell))
	else:
		global_position = debug_marker.global_position

	enable_debug_mode()
	return true


## Enables debug testing mode (invincibility and extended 50-tile room vision).
func enable_debug_mode() -> void:
	debug_invincible = true
	if visuals:
		visuals.vision_limit = maxi(visuals.vision_limit, 50)
	update_fog_of_war()
	if progression:
		progression.update_hud()
	if visuals:
		visuals.queue_redraw()
