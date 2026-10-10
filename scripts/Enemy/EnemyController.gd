extends Node2D
class_name EnemyController

@export_group("Adatmodell")
@export var enemy_data: EnemyData

@export_group("Map Rétegek")
@export var fog_of_war: FogOfWar

@export_group("Komponensek")
@onready var visuals: EnemyVisuals = $Visuals
@onready var mover: GridMover = $Mover
@onready var combat: EnemyCombat = $Combat
@onready var brain: EnemyBrain = $Brain

# --- DINAMIKUS ÁLLAPOTOK PROXY DELEGÁLÁSA ---

var monster_name: String:
	get: return enemy_data.monster_name if enemy_data else "Ellenség"

var title: String:
	get: return enemy_data.title if enemy_data else ""

var current_hp: int:
	get: return enemy_data.get_current_hp() if enemy_data else 0

var max_hp: int:
	get: return enemy_data.get_max_hp() if enemy_data else 10

var defense: int:
	get: return enemy_data.get_defense() if enemy_data else 0

var initiative: float:
	get: return enemy_data.get_initiative() if enemy_data else 8.0

var attack_range: int:
	get: return enemy_data.get_attack_range() if enemy_data else 1

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

var is_dead: bool:
	get: return combat.is_dead if combat else false
	set(val):
		if combat: combat.is_dead = val

var is_attacking: bool:
	get: return combat.is_attacking if combat else false
	set(val):
		if combat: combat.is_attacking = val

var sprite: AnimatedSprite2D:
	get: return visuals.sprite if visuals else null

# --- ÉLETCIKLUS ---

func _ready() -> void:
	add_to_group("enemies")
	z_index = 8
	# LÁTHATÓSÁG: Nem rejtjük el azonnal, így látható marad a tesztelés alatt!
	visible = true

	# Adatmodell másolása
	if enemy_data != null:
		enemy_data = enemy_data.duplicate()
		enemy_data.initialize()
	else:
		enemy_data = EnemyData.new()
		enemy_data.initialize()

	# Ha a gyökéren megadtad a rétegeket, átadjuk a komponenseknek:
	if mover:
		mover.setup(self)

	if visuals:
		if fog_of_war: visuals.fog_of_war = fog_of_war
		visuals.setup(self)

	if combat: combat.setup(self)
	if brain: brain.setup(self)

# --- PROXY METÓDUSOK ---

func get_monster_name() -> String: return monster_name
func get_title() -> String: return title
func get_initiative() -> float: return initiative
func get_defense() -> int: return defense
func get_current_hp() -> int: return current_hp
func get_max_hp() -> int: return max_hp
func get_attack_range() -> int: return attack_range
func is_monster_alive() -> bool: return not is_dead and (enemy_data != null and enemy_data.is_alive())

func take_damage(incoming_raw_damage: int) -> int:
	return combat.take_damage(incoming_raw_damage) if combat else 0

func try_trigger_block() -> bool:
	return combat.try_trigger_block() if combat else false

func roll_attack_damage() -> int:
	return combat.roll_attack_damage() if combat else 0

func can_attack_hero(hero_cell: Vector2i) -> bool:
	return combat.can_attack_hero(hero_cell) if combat else false

func attack_hero(target_hero: HeroController) -> void:
	if combat: combat.attack_hero(target_hero)

func opportunity_attack(target_hero: HeroController) -> void:
	if combat: combat.opportunity_attack(target_hero)

func perform_combat_turn(target_hero: HeroController) -> int:
	if combat: return await combat.perform_combat_turn(target_hero)
	return 0

func play_overworld_death() -> void:
	if combat: await combat.play_overworld_death()

func play_hurt_reaction() -> void:
	if visuals: await visuals.play_hurt_reaction()

func update_facing(target_grid_x: int) -> void:
	if visuals: visuals.update_facing(target_grid_x)

func update_fog_visibility() -> void:
	if visuals: visuals.update_fog_visibility()

func take_turn(hero: HeroController) -> void:
	if brain: brain.take_turn(hero)
