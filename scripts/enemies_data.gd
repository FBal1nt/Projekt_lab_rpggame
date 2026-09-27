@tool
extends Resource
class_name MonsterData

@export var monster_name: String = ""
@export var title: String = ""              # Ha van titulusa (pl. "the Giant Skeleton"), a hős megkapja
@export var max_hp: int = 45
@export var base_damage: int = 12
@export var defense: int = 1
@export var initiative: float = 9.0        # Lebegőpontos kezdeményezés
@export var xp_reward: int = 25

# Privát belső állapot
var _current_hp: int = 45
var _is_alive: bool = true

func initialize() -> void:
	_current_hp = max_hp
	_is_alive = true

func get_current_hp() -> int:
	return _current_hp

func get_max_hp() -> int:
	return max_hp

func get_base_damage() -> int:
	return base_damage

func get_defense() -> int:
	return defense

func get_initiative() -> float:
	return initiative

func is_alive() -> bool:
	return _is_alive and _current_hp > 0

# Sebzés levonása a védelem figyelembevételével
func take_damage(incoming_raw_damage: int) -> int:
	if not _is_alive:
		return 0
	
	# Védelem levonása a beérkező sebzésből
	var final_damage = maxi(0, incoming_raw_damage - defense)
	_current_hp = maxi(0, _current_hp - final_damage)
	
	if _current_hp == 0:
		_is_alive = false
		
	return final_damage

# 80-100% sebzés kalkuláció felfelé kerekítve
func roll_attack_damage() -> int:
	var roll = randf_range(0.8, 1.0)
	return ceili(float(base_damage) * roll)
