@tool
extends Resource
class_name EnemyData

@export_group("Alapadatok")
@export var monster_id: String = "skeleton"
@export var monster_name: String = "Csontváz"
@export var title: String = ""
@export var xp_reward: int = 25

@export_group("Megjelenés")
@export var sprite_frames: SpriteFrames
@export var sprite_scale: Vector2 = Vector2(1.0, 1.0)
@export var sprite_offset: Vector2 = Vector2.ZERO

@export_group("Harci Statisztikák")
@export var max_hp: int = 45
@export var base_damage: int = 12
@export var defense: int = 1
@export var initiative: float = 9.0

## 1: Közelharc (csak balról/jobbról!), >1: Távolsági
@export var attack_range: int = 1:
	set(value):
		attack_range = value
		notify_property_list_changed()

## Csak akkor jelenik meg az Inspectorban, ha attack_range > 1 (mint a hősöknél)
@export var projectile_scene: PackedScene

@export_group("Rács és AI Mozgás")
@export var move_distance: int = 1
@export var move_duration: float = 0.5
@export var action_interval: float = 1.5
@export var aggro_range: int = 3

@export_group("Egyedi Képességek")
## Csontváz: 0 HP-kor újraéled
@export var can_resurrect: bool = false:
	set(value):
		can_resurrect = value
		notify_property_list_changed()

@export var resurrect_hp_percent: float = 0.5

## Blokk mechanika (Csontváz védekezés): esély és tompítás mértéke
@export var can_block: bool = true:
	set(value):
		can_block = value
		notify_property_list_changed()

@export_range(0.0, 1.0) var block_chance: float = 0.35      # 35% esély a blokkolásra
@export_range(0.0, 1.0) var block_reduction: float = 0.5   # 50%-ra tompítja a sebzést

## Denevér: kitérési esély és vámpírizmus
@export_range(0.0, 1.0) var dodge_chance: float = 0.0
@export_range(0.0, 1.0) var life_steal_ratio: float = 0.0

## Nyálka (Slime): Kizárólag halál esetén esély a duplázódásra!
@export var can_split: bool = false:
	set(value):
		can_split = value
		notify_property_list_changed()

@export_range(0.0, 1.0) var split_chance_on_death: float = 0.75 # pl. 75% esély halálkor

# --- INSPECTOR DINAMIKUS ELREJTÉS / MEGJELENÍTÉS ---

func _validate_property(property: Dictionary) -> void:
	# 1. Ha közelharci (attack_range <= 1), elrejtjük a projectile_scene-t:
	if property.name == "projectile_scene" and attack_range <= 1:
		property.usage &= ~PROPERTY_USAGE_EDITOR

	# 2. Ha can_resurrect == false, elrejtjük a feltámadási HP százalékot:
	elif property.name == "resurrect_hp_percent" and not can_resurrect:
		property.usage &= ~PROPERTY_USAGE_EDITOR

	# 3. Ha can_block == false, elrejtjük a blokkolási esélyt és tompítást:
	elif (property.name == "block_chance" or property.name == "block_reduction") and not can_block:
		property.usage &= ~PROPERTY_USAGE_EDITOR

	# 4. Ha can_split == false, elrejtjük a duplázódási esélyt:
	elif property.name == "split_chance_on_death" and not can_split:
		property.usage &= ~PROPERTY_USAGE_EDITOR

# --- BELSŐ ÁLLAPOT ÉS HARCI LOGIKA ---

var _current_hp: int = 45
var _is_alive: bool = true
var _has_resurrected: bool = false
var _just_resurrected: bool = false

func initialize() -> void:
	_current_hp = max_hp
	_is_alive = true
	_has_resurrected = false
	_just_resurrected = false

func get_current_hp() -> int: return _current_hp
func get_max_hp() -> int: return max_hp
func get_base_damage() -> int: return base_damage
func get_defense() -> int: return defense
func get_initiative() -> float: return initiative
func get_attack_range() -> int: return attack_range
func is_alive() -> bool: return _is_alive and _current_hp > 0

func roll_attack_damage() -> int:
	return ceili(float(base_damage) * randf_range(0.8, 1.0))

func check_dodge() -> bool:
	return randf() < dodge_chance if dodge_chance > 0.0 else false

func take_damage(incoming_raw_damage: int) -> int:
	if not _is_alive: return 0

	var final_damage = maxi(0, incoming_raw_damage - defense)
	_current_hp = maxi(0, _current_hp - final_damage)

	if _current_hp == 0:
		_is_alive = false

	return final_damage

func revive(hp_percent: float = 0.5) -> void:
	_has_resurrected = true
	_current_hp = ceili(float(max_hp) * hp_percent)
	_is_alive = true

func has_resurrected() -> bool:
	return _has_resurrected

func apply_life_steal(damage_dealt: int) -> int:
	if life_steal_ratio <= 0.0 or not _is_alive: return 0
	var heal_val = ceili(float(damage_dealt) * life_steal_ratio)
	_current_hp = mini(_current_hp + heal_val, max_hp)
	return heal_val
