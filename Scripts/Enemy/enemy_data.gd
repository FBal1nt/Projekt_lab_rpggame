@tool
extends Resource
class_name EnemyData

enum EnemyTier {
	BASIC = 1,
	ARMORED = 2,
	ELITE = 3,
	BOSS = 4
}

enum SpecialProfile {
	STANDARD,
	ARMORED_SKELETON,
	ARMORED_ORC,
	ARMORED_AXEMAN,
	NECROMANCER,
	ELITE_ORC,
	GREATSWORD_SKELETON,
	WEREBEAR,
	WEREWOLF,
	BEARMAN = 7
}

@export_group("Alapadatok")
@export var monster_id: String = "enemy"
@export var monster_name: String = "Name"
@export var title: String = ""
@export var tier: EnemyTier = EnemyTier.BASIC
@export var enemy_level: int = 1
@export var xp_reward: int = 1

@export_group("Megjelenés")
@export var sprite_frames: SpriteFrames
@export var sprite_scale: Vector2 = Vector2(1.0, 1.0)
@export var sprite_offset: Vector2 = Vector2.ZERO

@export_group("Harci Statisztikák")
@export var max_hp: int = 1
@export var base_damage: int = 1
@export var defense: int = 1
@export var initiative: float = 1

@export_group("Páncél és Speciális Profil")
## Fix elnyelt sebzés minden egyes bekapott találatból (pl. 6)
@export var flat_armor: int = 0
## A szörny egyedi támadási és harci viselkedése
@export var special_profile: SpecialProfile = SpecialProfile.STANDARD

@export_group("Hátralökési Képkockák (Impact Frames)")
## Az attack_1 hányadik képkockájánál (0-tól indexelve) lökjön hátra (pl. Csontváz és Fejszés bökés/suhintás):
@export var knockback_frame_attack_1: int = 2

## Az attack_2 hányadik képkockájánál (0-tól indexelve) lökjön hátra (pl. Ork erős bökés):
@export var knockback_frame_attack_2: int = 2

## Az attack_3 hányadik képkockájánál (0-tól indexelve) történjen a lecsapás és a nagy lökés (pl. Ork és Fejszés zúzás):
@export var knockback_frame_attack_3: int = 3

## Segédfüggvény a képkocka lekéréséhez az animáció neve alapján
func get_knockback_frame(anim_name: String) -> int:
	match anim_name:
		"attack_1": return knockback_frame_attack_1
		"attack_2": return knockback_frame_attack_2
		"attack_3": return knockback_frame_attack_3
	return 2

@export_group("Kombó és Támadási Szorzók")
@export var light_attack_multiplier: float = 0.9     # Normál/gyorsabb fejszecsapás
@export var heavy_attack_multiplier: float = 1.5     # Felkészült, erősebb zúzás
@export_range(0.0, 1.0) var heavy_attack_chance: float = 0.25 # 25% eséllyel adja be az erős ütést

## 1: Közelharc (csak balról/jobbról!), >1: Távolsági
@export_group("Támadási Hatótávolság")
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
## 0 HP-kor újraéled a földről
@export var can_self_revive: bool = false:
	set(value):
		can_self_revive = value
		notify_property_list_changed()

## Életerő arány feltámadáskor (pl. 0.5 = 50% HP)
@export_range(0.1, 1.0) var resurrect_hp_percent: float = 0.5

## Hány másodpercig heverjen a földön a feltámadás előtt:
@export var resurrect_delay: float = 3.0

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

	# 2. Ha nincs feltámadás, elrejtjük a százalékot és a késleltetést is:
	elif (property.name == "resurrect_hp_percent" or property.name == "resurrect_delay") and not can_self_revive:
		property.usage &= ~PROPERTY_USAGE_EDITOR

	# 3. Ha can_block == false, elrejtjük a blokkolási esélyt és tompítást:
	elif (property.name == "block_chance" or property.name == "block_reduction") and not can_block:
		property.usage &= ~PROPERTY_USAGE_EDITOR

	# 4. Ha can_split == false, elrejtjük a duplázódási esélyt:
	elif property.name == "split_chance_on_death" and not can_split:
		property.usage &= ~PROPERTY_USAGE_EDITOR
		
	# 5. Ha nem STANDARD szörnyről van szó, elrejtjük a véletlenszerű kombócsúszkákat:
	elif property.name in ["light_attack_multiplier", "heavy_attack_multiplier", "heavy_attack_chance"]:
		if special_profile != SpecialProfile.STANDARD:
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

## Szint- és nehézségfüggő skálázás a megidézett szörny példányán
func apply_level_scaling(target_level: int, difficulty_id: String = "normal") -> void:
	enemy_level = maxi(1, target_level)
	var diff_clean := difficulty_id.to_lower()
	var is_easy := "easy" in diff_clean
	var is_hard := "hard" in diff_clean

	if tier == EnemyTier.BOSS:
		var hp_mult := 1.0
		var dmg_mult := 1.0
		var init_mult := 1.0
		if is_easy:
			hp_mult = 0.75
			dmg_mult = 0.78
			init_mult = 0.92
			flat_armor = maxi(0, flat_armor - 1)
		elif is_hard:
			hp_mult = 1.35
			dmg_mult = 1.32
			init_mult = 1.08
			defense += 1

		var boss_extra := maxi(0, enemy_level - 6)
		var boss_def_div: float = 4.0 if is_easy else 3.0
		var boss_hp_scale := 1.0 + float(boss_extra) * 0.08
		var boss_dmg_scale := 1.0 + float(boss_extra) * 0.095
		var boss_init_scale := pow(1.06, boss_extra)
		max_hp = maxi(1, roundi(float(max_hp) * hp_mult * boss_hp_scale))
		base_damage = maxi(1, roundi(float(base_damage) * dmg_mult * boss_dmg_scale))
		initiative = snappedf(maxf(1.0, initiative * init_mult * boss_init_scale), 0.1)
		defense += floori(float(boss_extra) / boss_def_div)
		_current_hp = max_hp
		return

	var tier_base_level := 1
	match tier:
		EnemyTier.ARMORED: tier_base_level = 3
		EnemyTier.ELITE: tier_base_level = 5

	var diff_hp_mult := 1.0
	var diff_dmg_mult := 1.0
	var diff_init_mult := 1.0
	if is_easy:
		diff_hp_mult = 0.82
		diff_dmg_mult = 0.80
		diff_init_mult = 0.92
		flat_armor = maxi(0, flat_armor - 1)
	elif is_hard:
		diff_hp_mult = 1.22
		diff_dmg_mult = 1.32
		diff_init_mult = 1.08
		defense += 1

	var level_delta := maxi(-2, enemy_level - tier_base_level)
	var lvl_hp_mult_step: float = 0.05 if level_delta < 0 else 0.08
	var lvl_dmg_mult_step: float = 0.04 if level_delta < 0 else 0.095
	var lvl_hp_scale := 1.0 + float(level_delta) * lvl_hp_mult_step
	var lvl_dmg_scale := 1.0 + float(level_delta) * lvl_dmg_mult_step
	var lvl_init_scale := pow(1.06, maxi(0, level_delta))

	max_hp = maxi(1, roundi(float(max_hp) * diff_hp_mult * lvl_hp_scale))
	base_damage = maxi(1, roundi(float(base_damage) * diff_dmg_mult * lvl_dmg_scale))
	initiative = snappedf(maxf(1.0, initiative * diff_init_mult * lvl_init_scale), 0.1)
	if level_delta >= 2:
		var def_step_div: float = 4.0 if is_easy else 3.0
		defense += floori(float(level_delta) / def_step_div)
	_current_hp = max_hp

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
