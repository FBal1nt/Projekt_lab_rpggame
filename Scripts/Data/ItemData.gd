class_name ItemData
extends Resource


@export_category("Basic Information")
@export var id: StringName
@export var display_name: String = ""
@export_multiline var description: String = ""


@export_category("Visual")
@export var icon: Texture2D


@export_category("Inventory")
@export var size: Vector2i = Vector2i(1, 1)
@export var max_stack: int = 1


@export_category("Economy")
@export var buy_price: int = 0
@export var sell_price: int = 0


@export_category("Equipment and Smithing")
## Stable type IDs used by smithing/enchantments: weapon, armor, ring, earring, material, consumable, other.
@export var item_type: StringName = &"other"
@export var equipment_slot: StringName = &"none"
@export var can_upgrade: bool = false
@export_range(0, 5, 1) var max_upgrade_level: int = 5
## Numeric base stats consumed by the combat/equipment systems.
@export var base_stats: Dictionary = {}
## Additive bonus gained per upgrade level, e.g. {"damage": 2.0}.
@export var upgrade_stat_bonuses: Dictionary = {}
