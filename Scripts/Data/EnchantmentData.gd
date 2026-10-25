class_name EnchantmentData
extends Resource

## Data-driven physical upgrade or magical enchantment.
## Add/edit .tres resources under Data/Enchantments; no UI code changes are needed.

@export var id: StringName = &""
@export var display_name: String = ""
@export_multiline var description: String = ""
@export var enabled: bool = true

## Which workshop presents this enhancement: "blacksmith" or "wizard".
@export var workshop_type: StringName = &"wizard"
## Which of that workshop's three options contains this effect.
@export var option_category: StringName = &"weapon_element"
## Optional gameplay tag such as fire, ice, poison, or physical.
@export var element: StringName = &"none"

## Values are ItemData.item_type IDs (weapon, armor, ring, earring, tool, etc.).
@export var applicable_item_types: PackedStringArray = PackedStringArray()
@export var ingredient_item_ids: PackedStringArray = PackedStringArray()
@export var ingredient_amounts: PackedInt32Array = PackedInt32Array()
@export_range(0, 999999, 1) var gold_cost: int = 0

## Additive stat modifiers exposed through GameState.get_item_stats().
## Suggested combat keys include damage, crit_chance, defense, bleed_chance,
## bleed_damage, max_bleed_stacks, fire_damage, ice_damage, poison_damage,
## fire_attack_bonus, ice_attack_bonus, poison_attack_bonus, fire_resistance,
## ice_resistance, poison_resistance, max_health, and out_of_combat_hp_regen.
@export var stat_modifiers: Dictionary = {}
