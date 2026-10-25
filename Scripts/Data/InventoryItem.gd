class_name InventoryItem
extends Resource

@export var item_data: ItemData
@export var position: Vector2i = Vector2i.ZERO
@export var amount: int = 1
## Upgrade state belongs to the individual item instance and persists in saves.
@export_range(0, 5, 1) var upgrade_level: int = 0
## Stable EnchantmentData IDs; definitions are loaded separately.
@export var enchantment_ids: PackedStringArray = PackedStringArray()
