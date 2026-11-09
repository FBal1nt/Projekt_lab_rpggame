class_name SmithingRecipeData
extends Resource

## Data-driven smithing recipe. Add or edit .tres resources under Data/SmithingRecipes.
## recipe_type: "craft" creates an ItemData resource; "upgrade" targets a +1..+5 step.

@export var id: StringName = &""
@export var display_name: String = ""
@export_multiline var description: String = ""
@export var recipe_type: StringName = &"craft"
@export var enabled: bool = true

## Craft-only output item ID. Upgrade recipes leave this empty.
@export var result_item_id: StringName = &""

## Upgrade-only desired target level, from 1 through 5.
@export_range(1, 5, 1) var target_upgrade_level: int = 1

## Parallel arrays: each item ID consumes the matching amount.
@export var ingredient_item_ids: PackedStringArray = PackedStringArray()
@export var ingredient_amounts: PackedInt32Array = PackedInt32Array()
@export_range(0, 999999, 1) var gold_cost: int = 0
