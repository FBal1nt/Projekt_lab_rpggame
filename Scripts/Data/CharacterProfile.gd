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
## Mana is optional. Classes without a mana pool have max_mana == 0.
@export var current_mana: int = -1
## Darkest-Dungeon-style stress is character-specific and persistent.
@export_range(0, 100, 1) var stress: int = 0
## Optional per-character traits; IDs can be registered by future gameplay systems.
@export var quirk_ids: PackedStringArray = PackedStringArray()
## Persistent named attribute values (e.g. strength, agility, intellect). Empty values fall back to class data.
@export var attributes: Dictionary = {}
## Persistent additive modifiers granted by equipment, quests, traits, or mechanics.
@export var stat_modifiers: Dictionary = {}
## Equipment slot -> InventoryItem instance. Items remain the same instances when equipped.
var equipment: Dictionary = {}
## Dungeon effects should be JSON-compatible dictionaries, e.g. {"id":"poison", "turns_left":2}.
var status_effects: Array[Dictionary] = []
## Skill/ability ID -> remaining cooldown turns.
@export var ability_cooldowns: Dictionary = {}
## Extensible per-character payload for future mechanics and quest systems.
@export var persistent_data: Dictionary = {}

var inventory: Inventory

## Preferred name for new code; archetype remains as a compatibility alias.
var class_id: StringName:
	get:
		return archetype
	set(value):
		archetype = value
