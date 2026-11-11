class_name CharacterProfile
extends Resource

## Persistent player-owned data. Class configuration lives separately in
## CharacterClassData resources so class definitions can be extended safely.

@export var id: String = ""
@export var character_name: String = "Vándor"
## Kept for save-file and teammate-script compatibility; this stores the class ID.
@export var archetype: StringName = &"warrior"
@export var level: int = 1
@export var xp: int = 0
## -1 means "initialize from the class's maximum health" when loading.
@export var current_health: int = -1
## Darkest-Dungeon-style stress is character-specific and persistent.
@export_range(0, 100, 1) var stress: int = 0
## Optional per-character traits; IDs can be registered by future gameplay systems.
@export var quirk_ids: PackedStringArray = PackedStringArray()

var inventory: Inventory
## Character-specific equipment. Keys are ItemData.equipment_slot IDs and values are InventoryItem instances.
@export var equipment: Dictionary = {}
## Cached class/level stats before equipment modifiers.
@export var base_stats: Dictionary = {}
## Cached final stats after all currently equipped items, upgrades and enchantments.
@export var derived_stats: Dictionary = {}

## Preferred name for new code; archetype remains as a compatibility alias.
var class_id: StringName:
	get:
		return archetype
	set(value):
		archetype = value
