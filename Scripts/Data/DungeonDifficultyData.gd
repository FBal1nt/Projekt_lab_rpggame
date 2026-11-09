class_name DungeonDifficultyData
extends Resource

## One difficulty configuration for one specific dungeon. Duplicate a .tres file
## and change these values to tune the spawn rate, enemy pool, and enemy levels.
@export var dungeon_id: StringName = &""
@export var id: StringName = &"normal"
@export var display_name: String = "Közepes"
@export_multiline var description: String = ""
@export_range(0.1, 5.0, 0.05) var spawn_rate_multiplier: float = 1.0
@export_range(1, 100, 1) var enemy_level_min: int = 1
@export_range(1, 100, 1) var enemy_level_max: int = 3
@export var enemy_type_ids: PackedStringArray = PackedStringArray()
## Optional display names parallel to enemy_type_ids; these are only for the UI.
@export var enemy_type_names: PackedStringArray = PackedStringArray()
@export_range(0.0, 1.0, 0.01) var elite_spawn_chance: float = 0.0
@export_range(0.1, 5.0, 0.05) var encounter_count_multiplier: float = 1.0
@export_range(0, 100, 1) var sort_order: int = 1
