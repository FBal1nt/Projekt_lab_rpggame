class_name CharacterClassData
extends Resource

## Data-driven definition for a playable character class.
## Add another .tres resource under Data/CharacterClasses to register a class.

@export var id: StringName = &"warrior"
@export var display_name: String = "Harcos"
@export var role: String = "Közelharci"
@export_multiline var description: String = ""

## Portrait is used by the lobby/class-selection UI. Battle sprite is intended
## for the dungeon/combat scene. They can point to the same texture if desired.
@export var portrait: Texture2D
@export var battle_sprite: Texture2D
@export var placeholder_color: Color = Color(0.35, 0.42, 0.50, 1.0)

## Base stats at level 1. Percent-based values use 0-100.
@export_range(1, 999, 1) var base_health: int = 30
@export_range(0, 999, 1) var base_mana: int = 0
@export_range(0, 999, 1) var base_damage_min: int = 4
@export_range(0, 999, 1) var base_damage_max: int = 8
@export_range(0, 999, 1) var base_defense: int = 2
@export_range(0, 99, 1) var base_speed: int = 4
@export_range(0, 100, 1) var base_accuracy: int = 90
@export_range(0.0, 100.0, 0.1) var base_crit_chance: float = 5.0
@export_range(0, 100, 1) var base_dodge: int = 8
@export_range(0, 100, 1) var base_healing_power: int = 0
@export_range(0, 100, 1) var base_stress_resistance: int = 35
## Optional primary attributes (e.g. strength, agility, intellect, vitality).
@export var base_attributes: Dictionary = {}

## Simple default growth. Gameplay can replace this formula later if needed.
@export_range(0, 99, 1) var health_per_level: int = 3
@export_range(0, 99, 1) var mana_per_level: int = 0
@export_range(0, 99, 1) var damage_min_per_level: int = 0
@export_range(0, 99, 1) var damage_max_per_level: int = 1
@export_range(0, 99, 1) var defense_per_level: int = 0

## Stable IDs for the future combat/ability system, plus readable lobby labels.
@export var skill_ids: PackedStringArray = PackedStringArray()
@export var skill_names: PackedStringArray = PackedStringArray()
## Optional ItemData IDs for future starting-equipment integration.
@export var starting_equipment_ids: PackedStringArray = PackedStringArray()


func get_stats_at_level(character_level: int = 1) -> Dictionary:
	var level_steps := maxi(character_level - 1, 0)
	var result: Dictionary = {
		"max_health": base_health + health_per_level * level_steps,
		"max_mana": base_mana + mana_per_level * level_steps,
		"damage_min": base_damage_min + damage_min_per_level * level_steps,
		"damage_max": base_damage_max + damage_max_per_level * level_steps,
		"defense": base_defense + defense_per_level * level_steps,
		"speed": base_speed,
		"accuracy": base_accuracy,
		"crit_chance": base_crit_chance,
		"dodge": base_dodge,
		"healing_power": base_healing_power,
		"stress_resistance": base_stress_resistance
	}
	for attribute_id in base_attributes:
		result[String(attribute_id)] = base_attributes[attribute_id]
	return result
