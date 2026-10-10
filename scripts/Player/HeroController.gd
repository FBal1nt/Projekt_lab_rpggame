extends Node2D
class_name HeroController

@export_group("Hős Alapadatok")
@export var hero_name: String = "Gandalf"

@export_group("Komponensek")
@onready var visuals: HeroVisuals = $Visuals
@onready var mover: HeroMover = $Mover
@onready var combat: HeroCombat = $Combat
@onready var progression: HeroProgression = $Progression

var grid_pos: Vector2i:
	get: return mover.grid_pos if mover else Vector2i.ZERO
	set(val):
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
	get: return visuals.vision_limit if visuals else 25

var floor_layer: TileMapLayer:
	get: return mover.grid_manager.floor_layer if (mover and mover.grid_manager) else null

var decoratives_layer: TileMapLayer:
	get: return mover.grid_manager.decoratives_layer if (mover and mover.grid_manager) else null

var is_death_played: bool = false

func _ready() -> void:
	add_to_group("player")
	z_index = 10

	# Komponensek összekötése:
	if mover: mover.setup(self)
	if visuals: visuals.setup(self)
	if combat: combat.setup(self)
	if progression: progression.setup(self)

func _process(_delta: float) -> void:
	if visuals:
		visuals.process_hover()

func _unhandled_input(event: InputEvent) -> void:
	if not is_alive() or in_battle or is_attacking or is_stunned:
		return

	if event is InputEventKey and event.pressed and not event.echo:
		var code = event.physical_keycode if event.physical_keycode != 0 else event.keycode
		match code:
			KEY_1: progression.select_class_by_index(0)
			KEY_2: progression.select_class_by_index(1)
			KEY_3: progression.select_class_by_index(2)
			KEY_4: progression.select_class_by_index(3)
			KEY_5: progression.select_class_by_index(4)
			KEY_6: progression.select_class_by_index(5)
			KEY_7: progression.select_class_by_index(6)
			KEY_8: progression.select_class_by_index(7)
			KEY_F:
				combat.wizard_element = "fire" if combat.wizard_element == "ice" else "ice"
				print("🔥/❄️ Varázsló elem váltva: ", combat.wizard_element)
			KEY_H: combat.cast_priest_self_heal()

	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		combat.handle_attack_click()
		return

	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
		mover.handle_move_click()

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

	if mover:
		mover.cancel_movement_immediately()
		mover.is_moving = false
		mover.path_queue.clear()

	in_battle = false
	is_attacking = false

	var spr = sprite
	if spr and spr.sprite_frames and spr.sprite_frames.has_animation("death"):
		spr.play("death")
		await spr.animation_finished
		var last_frame = spr.sprite_frames.get_frame_count("death") - 1
		spr.frame = last_frame
		spr.pause()
