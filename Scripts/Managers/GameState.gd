extends Node

# -----------------------------------------------------------------------------
# Shared game state and compatibility properties
# -----------------------------------------------------------------------------

const RESOURCE_CATALOG := preload("res://Scripts/Utils/ResourceCatalog.gd")
const SAVE_SERIALIZER := preload("res://Scripts/Managers/GameSaveSerializer.gd")
const SAVE_VERSION := 4

signal state_changed
signal characters_changed
signal active_character_changed(character_id: String)

const LEGACY_SAVE_PATH := "user://savegame.json"
const MANUAL_SAVE_PATH_TEMPLATE := "user://save_slot_%d.json"
const AUTOSAVE_PATH := "user://autosave.json"
const MANUAL_SAVE_SLOT_COUNT := 3
const AUTOSAVE_INTERVAL_SECONDS := 60.0

var current_save_slot: int = 1
var _autosave_timer: Timer
const ITEM_DATA_DIRECTORY := "res://Data/Items"
const CHARACTER_CLASS_DIRECTORY := "res://Data/CharacterClasses"
const SMITHING_RECIPE_DIRECTORY := "res://Data/SmithingRecipes"
const ENCHANTMENT_DIRECTORY := "res://Data/Enchantments"
const BACKPACK_WIDTH := 8
const BACKPACK_HEIGHT := 4
const STASH_WIDTH := 10
const STASH_HEIGHT := 5

var gold: int = 500
var characters: Array[CharacterProfile] = []
var character_classes: Dictionary = {}
var smithing_recipes: Array[SmithingRecipeData] = []
var enchantments: Dictionary = {}
var active_character_id: String = ""
var stash: Inventory
## Shared, persistent dungeon/run data. Use JSON-compatible values only.
## Example: {"dungeon_id":"crypt_01", "floor":2, "seed":12345, "turn":8}.
var run_state: Dictionary = {}

var _loading_save: bool = false

## Backwards-compatible access for older scripts. This now always resolves to
## the active character's backpack, so teammates can keep using GameState.backpack.
var backpack: Inventory:
	get:
		return get_active_inventory()
	set(value):
		var character := get_active_character()
		if character == null or value == null:
			return
		character.inventory = value
		_connect_inventory(value)
		_save_and_emit_state()

## Level and XP belong to the active character, not to the account as a whole.
var level: int:
	get:
		var character := get_active_character()
		return character.level if character != null else 1
	set(value):
		var character := get_active_character()
		if character == null:
			return
		character.level = max(value, 1)
		_save_and_emit_state()

var xp: int:
	get:
		var character := get_active_character()
		return character.xp if character != null else 0
	set(value):
		var character := get_active_character()
		if character == null:
			return
		character.xp = max(value, 0)
		_save_and_emit_state()


# -----------------------------------------------------------------------------
# Lifecycle and initialization
# -----------------------------------------------------------------------------

func _ready() -> void:
	_load_character_classes()
	_load_smithing_data()
	# Do not silently load an old campaign on startup. The main menu explicitly
	# decides whether to start fresh or load one of the three manual slots.
	_migrate_legacy_save_if_needed()
	_create_new_game()
	_connect_all_inventories()
	_start_autosave_timer()

	state_changed.emit()
	characters_changed.emit()
	active_character_changed.emit(active_character_id)


func _migrate_legacy_save_if_needed() -> void:
	# Preserve existing users' old single-save file as manual slot 1 without
	# automatically loading it; the player can choose it from the main menu.
	if FileAccess.file_exists(_manual_save_path(1)) or not FileAccess.file_exists(LEGACY_SAVE_PATH):
		return
	var source := FileAccess.open(LEGACY_SAVE_PATH, FileAccess.READ)
	if source == null:
		return
	var contents := source.get_as_text()
	source.close()
	var destination := FileAccess.open(_manual_save_path(1), FileAccess.WRITE)
	if destination == null:
		push_warning("A régi mentést nem sikerült átmásolni az 1. mentési helyre.")
		return
	destination.store_string(contents)
	destination.close()


func _exit_tree() -> void:
	# Manual slots are only changed by explicit save/new-game actions.
	# Autosave is maintained separately by the timer.
	pass


# -----------------------------------------------------------------------------
# Character lookup and persistent gameplay state
# -----------------------------------------------------------------------------

func get_active_character() -> CharacterProfile:
	for character in characters:
		if character.id == active_character_id:
			return character
	return null


func get_active_inventory() -> Inventory:
	var character := get_active_character()
	if character != null:
		return character.inventory
	return null


func get_character_classes() -> Array[CharacterClassData]:
	var result: Array[CharacterClassData] = []
	for class_data in character_classes.values():
		if class_data is CharacterClassData:
			result.append(class_data as CharacterClassData)
	result.sort_custom(_sort_classes_by_name)
	return result


func _sort_classes_by_name(a: CharacterClassData, b: CharacterClassData) -> bool:
	return a.display_name.naturalnocasecmp_to(b.display_name) < 0


func get_character_class(class_id: StringName) -> CharacterClassData:
	return character_classes.get(class_id, null) as CharacterClassData


func get_character_by_id(character_id: String) -> CharacterProfile:
	for character in characters:
		if character.id == character_id:
			return character
	return null


func set_character_health(character_id: String, current_health: int) -> bool:
	var character := get_character_by_id(character_id)
	if character == null:
		return false
	var stats := get_character_stats(character)
	var max_health := int(stats.get("max_health", maxi(character.current_health, 1)))
	character.current_health = clampi(current_health, 0, max_health)
	_save_and_emit_state()
	return true


func set_active_character_health(current_health: int) -> bool:
	var character := get_active_character()
	if character == null:
		return false
	return set_character_health(character.id, current_health)


func set_character_mana(character_id: String, current_mana: int) -> bool:
	var character := get_character_by_id(character_id)
	if character == null:
		return false
	var stats := get_character_stats(character)
	var max_mana := maxi(int(stats.get("max_mana", 0)), 0)
	character.current_mana = clampi(current_mana, 0, max_mana)
	_save_and_emit_state()
	return true


func set_active_character_mana(current_mana: int) -> bool:
	var character := get_active_character()
	if character == null:
		return false
	return set_character_mana(character.id, current_mana)


func damage_character(character_id: String, damage: int) -> bool:
	var character := get_character_by_id(character_id)
	if character == null or damage < 0:
		return false
	return set_character_health(character_id, character.current_health - damage)


func heal_character(character_id: String, amount: int) -> bool:
	var character := get_character_by_id(character_id)
	if character == null or amount < 0:
		return false
	return set_character_health(character_id, character.current_health + amount)


func spend_character_mana(character_id: String, amount: int) -> bool:
	var character := get_character_by_id(character_id)
	if character == null or amount < 0 or character.current_mana < amount:
		return false
	return set_character_mana(character_id, character.current_mana - amount)


func restore_character_mana(character_id: String, amount: int) -> bool:
	var character := get_character_by_id(character_id)
	if character == null or amount < 0:
		return false
	return set_character_mana(character_id, character.current_mana + amount)


func set_character_stat_modifier(character_id: String, stat_id: StringName, value: float) -> bool:
	var character := get_character_by_id(character_id)
	if character == null or String(stat_id).strip_edges().is_empty():
		return false
	character.stat_modifiers[String(stat_id)] = value
	_clamp_character_resources(character)
	_save_and_emit_state()
	return true


func set_character_attribute(character_id: String, attribute_id: StringName, value: float) -> bool:
	## Set a persistent named attribute, such as strength, agility or intellect.
	var character := get_character_by_id(character_id)
	if character == null or String(attribute_id).strip_edges().is_empty():
		return false
	character.attributes[String(attribute_id)] = value
	_clamp_character_resources(character)
	_save_and_emit_state()
	return true


func add_character_stat_modifier(character_id: String, stat_id: StringName, amount: float) -> bool:
	var character := get_character_by_id(character_id)
	if character == null or String(stat_id).strip_edges().is_empty():
		return false
	character.stat_modifiers[String(stat_id)] = float(character.stat_modifiers.get(String(stat_id), 0.0)) + amount
	_clamp_character_resources(character)
	_save_and_emit_state()
	return true


func set_character_status_effects(character_id: String, effects: Array[Dictionary]) -> bool:
	var character := get_character_by_id(character_id)
	if character == null:
		return false
	character.status_effects = effects.duplicate(true)
	_save_and_emit_state()
	return true


func set_character_ability_cooldowns(character_id: String, cooldowns: Dictionary) -> bool:
	var character := get_character_by_id(character_id)
	if character == null:
		return false
	character.ability_cooldowns = cooldowns.duplicate(true)
	_save_and_emit_state()
	return true


func set_character_persistent_data(character_id: String, data: Dictionary) -> bool:
	var character := get_character_by_id(character_id)
	if character == null:
		return false
	character.persistent_data = data.duplicate(true)
	_save_and_emit_state()
	return true


func commit_character_state(character_id: String) -> bool:
	## Call after a dungeon turn when gameplay has directly changed several profile fields.
	var character := get_character_by_id(character_id)
	if character == null:
		return false
	_clamp_character_resources(character)
	_save_and_emit_state()
	return true


func set_run_state(data: Dictionary) -> void:
	run_state = data.duplicate(true)
	_save_and_emit_state()


func update_run_state(key: StringName, value: Variant) -> void:
	## Store only JSON-compatible values (numbers, strings, bools, arrays, and dictionaries).
	run_state[String(key)] = value
	_save_and_emit_state()


func clear_run_state() -> void:
	run_state.clear()
	_save_and_emit_state()


func set_character_stress(character_id: String, stress_value: int) -> bool:
	var character := get_character_by_id(character_id)
	if character == null:
		return false
	character.stress = clampi(stress_value, 0, 100)
	_save_and_emit_state()
	return true


func set_character_quirks(character_id: String, quirk_ids: PackedStringArray) -> bool:
	var character := get_character_by_id(character_id)
	if character == null:
		return false
	character.quirk_ids = quirk_ids.duplicate()
	_save_and_emit_state()
	return true


# -----------------------------------------------------------------------------
# Effective stats and equipment slots
# -----------------------------------------------------------------------------

func get_character_stats(character: CharacterProfile = null) -> Dictionary:
	## Authoritative effective-stat calculation for UI, equipment and dungeon combat.
	## Returns class growth + persistent modifiers + equipped item/enchantment bonuses.
	var target := character if character != null else get_active_character()
	if target == null:
		return {}
	var class_data := get_character_class(target.class_id)
	if class_data == null:
		return {}
	var result: Dictionary = class_data.get_stats_at_level(target.level).duplicate(true)
	for attribute_id in target.attributes:
		result[String(attribute_id)] = target.attributes[attribute_id]
	for stat_id in target.stat_modifiers:
		var stat_key := String(stat_id)
		result[stat_key] = float(result.get(stat_key, 0.0)) + float(target.stat_modifiers[stat_id])
	for equipped_value in target.equipment.values():
		if not equipped_value is InventoryItem:
			continue
		var equipped_item := equipped_value as InventoryItem
		var item_stats := get_item_stats(equipped_item)
		for stat_id in item_stats:
			var stat_key := String(stat_id)
			result[stat_key] = float(result.get(stat_key, 0.0)) + float(item_stats[stat_id])
	return result


func _clamp_character_resources(character: CharacterProfile) -> void:
	if character == null:
		return
	var stats := get_character_stats(character)
	character.current_health = clampi(character.current_health, 0, maxi(int(stats.get("max_health", 1)), 1))
	character.current_mana = clampi(character.current_mana, 0, maxi(int(stats.get("max_mana", 0)), 0))


func get_equipped_item(character_id: String, slot: StringName) -> InventoryItem:
	var character := get_character_by_id(character_id)
	if character == null:
		return null
	return character.equipment.get(slot, null) as InventoryItem


func equip_item(character_id: String, inventory_item: InventoryItem) -> bool:
	## Move an item from the specified character's backpack into its equipment slot.
	## If the slot was occupied, the previous item is returned to the backpack if it fits.
	var character := get_character_by_id(character_id)
	if character == null or character.inventory == null or inventory_item == null or inventory_item.item_data == null:
		return false
	var inventory := character.inventory
	var item_index := inventory.items.find(inventory_item)
	if item_index < 0 or inventory_item.amount != 1:
		return false
	var slot := inventory_item.item_data.equipment_slot
	if String(slot).is_empty() or slot == &"none":
		return false

	var previous_item := character.equipment.get(slot, null) as InventoryItem
	var replacement_position := Vector2i(-1, -1)
	if previous_item != null:
		var simulation := _copy_inventory(inventory)
		simulation.items.remove_at(item_index)
		replacement_position = simulation.find_free_position(previous_item.item_data)
		if replacement_position == Vector2i(-1, -1):
			return false

	inventory.items.erase(inventory_item)
	if previous_item != null:
		previous_item.position = replacement_position
		inventory.items.append(previous_item)
	inventory_item.position = Vector2i(-1, -1)
	character.equipment[slot] = inventory_item
	_clamp_character_resources(character)
	inventory.inventory_changed.emit()
	return true


func unequip_item(character_id: String, slot: StringName) -> bool:
	var character := get_character_by_id(character_id)
	if character == null or character.inventory == null:
		return false
	var inventory_item := character.equipment.get(slot, null) as InventoryItem
	if inventory_item == null or inventory_item.item_data == null:
		return false
	var free_position := character.inventory.find_free_position(inventory_item.item_data)
	if free_position == Vector2i(-1, -1):
		return false
	character.equipment.erase(slot)
	inventory_item.position = free_position
	character.inventory.items.append(inventory_item)
	_clamp_character_resources(character)
	character.inventory.inventory_changed.emit()
	return true


# -----------------------------------------------------------------------------
# Character-class registry
# -----------------------------------------------------------------------------

func _load_character_classes() -> void:
	character_classes.clear()
	var paths: Array[String] = RESOURCE_CATALOG.collect_resource_paths(CHARACTER_CLASS_DIRECTORY)

	for resource_path in paths:
		var loaded_resource := load(resource_path)
		if not loaded_resource is CharacterClassData:
			continue
		var class_data := loaded_resource as CharacterClassData
		if String(class_data.id).strip_edges().is_empty():
			push_warning("A karakterosztály definíciójának nincs azonosítója: " + resource_path)
			continue
		if character_classes.has(class_data.id):
			push_warning("Duplikált karakterosztály-azonosító: " + String(class_data.id))
			continue
		character_classes[class_data.id] = class_data

	if character_classes.is_empty():
		push_error("Nem található karakterosztály a következő mappában: " + CHARACTER_CLASS_DIRECTORY)


# -----------------------------------------------------------------------------
# Character creation and selection
# -----------------------------------------------------------------------------

func create_character(character_name: String, archetype: StringName = &"warrior") -> bool:
	var clean_name := character_name.strip_edges()
	if clean_name.is_empty():
		return false
	if get_character_class(archetype) == null:
		push_warning("Ismeretlen karakterosztály: " + String(archetype))
		return false

	for existing in characters:
		if existing.character_name.strip_edges().to_lower() == clean_name.to_lower():
			return false

	var character := CharacterProfile.new()
	character.id = _generate_character_id()
	character.character_name = clean_name
	character.class_id = archetype
	character.level = 1
	character.xp = 0
	var initial_stats := get_character_class(archetype).get_stats_at_level(1)
	character.current_health = int(initial_stats.get("max_health", 30))
	character.current_mana = int(initial_stats.get("max_mana", 0))
	character.stress = 0
	character.equipment = {}
	character.inventory = _new_inventory(BACKPACK_WIDTH, BACKPACK_HEIGHT)

	characters.append(character)
	_connect_inventory(character.inventory)
	active_character_id = character.id

	save_autosave()
	characters_changed.emit()
	active_character_changed.emit(active_character_id)
	state_changed.emit()
	return true


func select_character(character_id: String) -> bool:
	for character in characters:
		if character.id != character_id:
			continue
		if active_character_id == character_id:
			return true

		active_character_id = character_id
		save_autosave()
		active_character_changed.emit(active_character_id)
		state_changed.emit()
		return true
	return false


# -----------------------------------------------------------------------------
# Recipe and enchantment registry
# -----------------------------------------------------------------------------

func _load_smithing_data() -> void:
	smithing_recipes.clear()
	var recipe_paths: Array[String] = RESOURCE_CATALOG.collect_resource_paths(SMITHING_RECIPE_DIRECTORY)
	for resource_path in recipe_paths:
		var loaded_resource := load(resource_path)
		if not loaded_resource is SmithingRecipeData:
			continue
		var recipe := loaded_resource as SmithingRecipeData
		if String(recipe.id).strip_edges().is_empty():
			push_warning("A kovácsreceptnek nincs azonosítója: " + resource_path)
			continue
		smithing_recipes.append(recipe)

	enchantments.clear()
	var enchantment_paths: Array[String] = RESOURCE_CATALOG.collect_resource_paths(ENCHANTMENT_DIRECTORY)
	for resource_path in enchantment_paths:
		var loaded_resource := load(resource_path)
		if not loaded_resource is EnchantmentData:
			continue
		var enchantment := loaded_resource as EnchantmentData
		if String(enchantment.id).strip_edges().is_empty():
			push_warning("Az enchantnek nincs azonosítója: " + resource_path)
			continue
		if enchantments.has(enchantment.id):
			push_warning("Duplikált enchant ID: " + String(enchantment.id))
			continue
		enchantments[enchantment.id] = enchantment


func get_smithing_recipes(recipe_type: StringName = &"") -> Array[SmithingRecipeData]:
	var result: Array[SmithingRecipeData] = []
	for recipe in smithing_recipes:
		if not recipe.enabled:
			continue
		if not String(recipe_type).is_empty() and recipe.recipe_type != recipe_type:
			continue
		result.append(recipe)
	return result


func get_enchantments() -> Array[EnchantmentData]:
	var result: Array[EnchantmentData] = []
	for enchantment in enchantments.values():
		if enchantment is EnchantmentData and enchantment.enabled:
			result.append(enchantment as EnchantmentData)
	result.sort_custom(_sort_enchantments_by_name)
	return result


func get_enchantments_for_workshop(workshop_type: StringName, option_category: StringName = &"") -> Array[EnchantmentData]:
	## Shared, data-driven lookup used by both the Blacksmith and Wizard UIs.
	var result: Array[EnchantmentData] = []
	for enchantment in get_enchantments():
		if enchantment.workshop_type != workshop_type:
			continue
		if not String(option_category).is_empty() and enchantment.option_category != option_category:
			continue
		result.append(enchantment)
	result.sort_custom(_sort_enchantments_by_name)
	return result


func _sort_enchantments_by_name(a: EnchantmentData, b: EnchantmentData) -> bool:
	return a.display_name.naturalnocasecmp_to(b.display_name) < 0


func get_enchantment(enchantment_id: StringName) -> EnchantmentData:
	return enchantments.get(enchantment_id, null) as EnchantmentData


func get_item_data(item_id: StringName) -> ItemData:
	return _find_item_data_by_id(ITEM_DATA_DIRECTORY, item_id)


func get_item_stats(item: InventoryItem) -> Dictionary:
	## Unified stat helper for future combat/equipment scripts.
	if item == null or item.item_data == null:
		return {}
	var result: Dictionary = item.item_data.base_stats.duplicate(true)
	for stat_name in item.item_data.upgrade_stat_bonuses:
		var bonus := float(item.item_data.upgrade_stat_bonuses[stat_name])
		result[stat_name] = float(result.get(stat_name, 0.0)) + bonus * item.upgrade_level
	for enchantment_id in item.enchantment_ids:
		var enchantment := get_enchantment(StringName(enchantment_id))
		if enchantment == null:
			continue
		for stat_name in enchantment.stat_modifiers:
			result[stat_name] = float(result.get(stat_name, 0.0)) + float(enchantment.stat_modifiers[stat_name])
	return result


func _find_upgrade_recipe(target_level: int) -> SmithingRecipeData:
	for recipe in smithing_recipes:
		if recipe.enabled and recipe.recipe_type == &"upgrade" and recipe.target_upgrade_level == target_level:
			return recipe
	return null


# -----------------------------------------------------------------------------
# Crafting, upgrades and enchantment transactions
# -----------------------------------------------------------------------------

func get_item_count(item_id: StringName, include_stash: bool = true) -> int:
	var total := 0
	var inventory := get_active_inventory()
	if inventory != null:
		for item in inventory.items:
			if item.item_data != null and item.item_data.id == item_id:
				total += item.amount
	if include_stash and stash != null:
		for item in stash.items:
			if item.item_data != null and item.item_data.id == item_id:
				total += item.amount
	return total


func _has_ingredients(item_ids: PackedStringArray, amounts: PackedInt32Array) -> bool:
	if item_ids.size() != amounts.size():
		return false
	var totals: Dictionary = {}
	for i in range(item_ids.size()):
		if amounts[i] < 0:
			return false
		var item_id := StringName(item_ids[i])
		totals[item_id] = int(totals.get(item_id, 0)) + amounts[i]
	for item_id in totals:
		if get_item_count(StringName(item_id)) < int(totals[item_id]):
			return false
	return true


func _copy_inventory(inventory: Inventory) -> Inventory:
	var simulation := Inventory.new()
	if inventory == null:
		return simulation
	simulation.width = inventory.width
	simulation.height = inventory.height
	for item in inventory.items:
		var copy := InventoryItem.new()
		copy.item_data = item.item_data
		copy.position = item.position
		copy.amount = item.amount
		copy.upgrade_level = item.upgrade_level
		copy.enchantment_ids = item.enchantment_ids.duplicate()
		simulation.items.append(copy)
	return simulation


func _consume_item_quantity(inventory: Inventory, item_id: StringName, amount: int) -> int:
	if inventory == null or amount <= 0:
		return amount
	var remaining := amount
	for item in inventory.items.duplicate():
		if remaining <= 0:
			break
		if item.item_data == null or item.item_data.id != item_id:
			continue
		var take := mini(remaining, item.amount)
		item.amount -= take
		remaining -= take
		if item.amount <= 0:
			inventory.items.erase(item)
	return remaining


func _consume_ingredients(item_ids: PackedStringArray, amounts: PackedInt32Array) -> bool:
	if not _has_ingredients(item_ids, amounts):
		return false
	var inventory := get_active_inventory()
	for i in range(item_ids.size()):
		var remaining := _consume_item_quantity(inventory, StringName(item_ids[i]), amounts[i])
		if remaining > 0:
			remaining = _consume_item_quantity(stash, StringName(item_ids[i]), remaining)
		if remaining > 0:
			# Availability was validated in advance; this is a guard against bad data/state.
			push_error("Anyagfogyasztási hiba: " + item_ids[i])
			return false
	return true


func can_craft_recipe(recipe: SmithingRecipeData) -> bool:
	if recipe == null or not recipe.enabled or recipe.recipe_type != &"craft":
		return false
	if gold < recipe.gold_cost or not _has_ingredients(recipe.ingredient_item_ids, recipe.ingredient_amounts):
		return false
	var result_item := get_item_data(recipe.result_item_id)
	var inventory := get_active_inventory()
	if result_item == null or inventory == null:
		return false
	# Simulate material use from the backpack first. If ingredients free space,
	# a craft can succeed even when the backpack was full before the transaction.
	var simulation := _copy_inventory(inventory)
	for i in range(recipe.ingredient_item_ids.size()):
		_consume_item_quantity(simulation, StringName(recipe.ingredient_item_ids[i]), recipe.ingredient_amounts[i])
	return simulation.can_add_item(result_item, 1)


func craft_recipe(recipe: SmithingRecipeData) -> bool:
	if not can_craft_recipe(recipe):
		return false
	var result_item := get_item_data(recipe.result_item_id)
	var inventory := get_active_inventory()
	if result_item == null or inventory == null:
		return false
	if not _consume_ingredients(recipe.ingredient_item_ids, recipe.ingredient_amounts):
		return false
	var remaining := inventory.try_add_item(result_item, 1, false)
	if remaining > 0:
		push_error("A kovácsolt tárgy az előzetes helyellenőrzés ellenére nem fért el.")
		return false
	gold -= recipe.gold_cost
	inventory.inventory_changed.emit()
	if stash != null:
		stash.inventory_changed.emit()
	_save_and_emit_state()
	return true


func can_upgrade_item(item: InventoryItem) -> bool:
	var inventory := get_active_inventory()
	if item == null or item.item_data == null or inventory == null or not inventory.items.has(item):
		return false
	if not item.item_data.can_upgrade or item.amount != 1:
		return false
	var next_level := item.upgrade_level + 1
	if next_level > mini(item.item_data.max_upgrade_level, 5):
		return false
	var recipe := _find_upgrade_recipe(next_level)
	return recipe != null and gold >= recipe.gold_cost and _has_ingredients(recipe.ingredient_item_ids, recipe.ingredient_amounts)


func upgrade_item(item: InventoryItem) -> bool:
	if not can_upgrade_item(item):
		return false
	var next_level := item.upgrade_level + 1
	var recipe := _find_upgrade_recipe(next_level)
	if recipe == null or not _consume_ingredients(recipe.ingredient_item_ids, recipe.ingredient_amounts):
		return false
	gold -= recipe.gold_cost
	item.upgrade_level = next_level
	var inventory := get_active_inventory()
	if inventory != null:
		inventory.inventory_changed.emit()
	if stash != null:
		stash.inventory_changed.emit()
	_save_and_emit_state()
	return true


func can_apply_enchantment(item: InventoryItem, enchantment_id: StringName) -> bool:
	var inventory := get_active_inventory()
	var enchantment := get_enchantment(enchantment_id)
	if item == null or item.item_data == null or inventory == null or not inventory.items.has(item):
		return false
	if enchantment == null or not enchantment.enabled or item.amount != 1:
		return false
	if item.enchantment_ids.has(String(enchantment_id)):
		return false
	if not enchantment.applicable_item_types.is_empty() and not enchantment.applicable_item_types.has(String(item.item_data.item_type)):
		return false
	return gold >= enchantment.gold_cost and _has_ingredients(enchantment.ingredient_item_ids, enchantment.ingredient_amounts)


func apply_enchantment(item: InventoryItem, enchantment_id: StringName) -> bool:
	if not can_apply_enchantment(item, enchantment_id):
		return false
	var enchantment := get_enchantment(enchantment_id)
	if enchantment == null or not _consume_ingredients(enchantment.ingredient_item_ids, enchantment.ingredient_amounts):
		return false
	gold -= enchantment.gold_cost
	item.enchantment_ids.append(String(enchantment_id))
	var inventory := get_active_inventory()
	if inventory != null:
		inventory.inventory_changed.emit()
	if stash != null:
		stash.inventory_changed.emit()
	_save_and_emit_state()
	return true


# -----------------------------------------------------------------------------
# New-game setup and inventory factories
# -----------------------------------------------------------------------------

func _create_new_game() -> void:
	characters.clear()
	gold = 500
	run_state.clear()
	stash = _new_inventory(STASH_WIDTH, STASH_HEIGHT)

	var starter := CharacterProfile.new()
	starter.id = _generate_character_id()
	starter.character_name = "Vándor"
	starter.class_id = &"warrior"
	starter.level = 1
	starter.xp = 0
	var starter_class := get_character_class(starter.class_id)
	var starter_stats := starter_class.get_stats_at_level(1) if starter_class != null else {"max_health": 30, "max_mana": 0}
	starter.current_health = int(starter_stats.get("max_health", 30))
	starter.current_mana = int(starter_stats.get("max_mana", 0))
	starter.stress = 0
	starter.equipment = {}
	starter.inventory = _new_inventory(BACKPACK_WIDTH, BACKPACK_HEIGHT)
	characters.append(starter)
	active_character_id = starter.id

	_setup_starting_inventory(starter.inventory)
	_seed_starting_smithing_materials()


func _seed_starting_smithing_materials() -> void:
	# A small shared stock lets the player try crafting, upgrades and enchantments
	# immediately in a fresh save. Existing saves are not overwritten.
	var initial_stock := {
		&"iron_ingot": 16,
		&"silver_ingot": 6,
		&"arcane_dust": 8,
		&"leather_strip": 12
	}
	for item_id in initial_stock:
		var item_data := get_item_data(StringName(item_id))
		if item_data != null and stash != null:
			stash.try_add_item(item_data, int(initial_stock[item_id]))


func _new_inventory(width: int, height: int) -> Inventory:
	var result := Inventory.new()
	result.width = width
	result.height = height
	return result


func _generate_character_id() -> String:
	return "character_%s_%s" % [str(Time.get_unix_time_from_system()), str(randi())]


func _setup_starting_inventory(target_inventory: Inventory) -> void:
	var sword := load("res://Data/Items/iron_sword.tres") as ItemData
	var potion := load("res://Data/Items/health_potion.tres") as ItemData

	if sword != null:
		target_inventory.add_item(sword, Vector2i(0, 0), 1, false)
	if potion != null:
		target_inventory.add_item(potion, Vector2i(2, 0), 3, false)
		target_inventory.add_item(potion, Vector2i(5, 0), 4, false)


# -----------------------------------------------------------------------------
# Economy: purchases and sales
# -----------------------------------------------------------------------------

func buy_item(item_data: ItemData, amount: int = 1) -> bool:
	var inventory := get_active_inventory()
	if item_data == null or amount <= 0 or item_data.buy_price < 0 or inventory == null:
		return false

	var total_price := item_data.buy_price * amount
	if gold < total_price:
		return false
	if not inventory.can_add_item(item_data, amount):
		return false

	var remaining := inventory.try_add_item(item_data, amount)
	if remaining > 0:
		return false

	gold -= total_price
	_save_and_emit_state()
	return true


func get_buy_item_at_failure_reason(
	item_data: ItemData,
	target_position: Vector2i,
	amount: int = 1
) -> String:
	var inventory := get_active_inventory()
	if item_data == null or amount <= 0:
		return "Érvénytelen tárgy."
	if item_data.buy_price < 0:
		return "Ez a tárgy nem vásárolható meg."
	if inventory == null:
		return "Nincs aktív karakter."
	if gold < item_data.buy_price * amount:
		return "Nincs elég aranyad."

	var target_item := inventory.get_item_at_cell(target_position)
	if target_item != null:
		if target_item.item_data == null or target_item.item_data.id != item_data.id:
			return "A célhely foglalt."
		if target_item.amount + amount > target_item.item_data.max_stack:
			return "A cél-stackben nincs elég hely."
		return ""

	if not inventory.can_place_item(item_data, target_position):
		return "A tárgy nem fér el ezen a helyen."
	return ""


func can_buy_item_at(
	item_data: ItemData,
	target_position: Vector2i,
	amount: int = 1
) -> bool:
	return get_buy_item_at_failure_reason(item_data, target_position, amount).is_empty()


func buy_item_at(
	item_data: ItemData,
	target_position: Vector2i,
	amount: int = 1
) -> bool:
	# Validate both conditions before changing either inventory or gold.
	if not can_buy_item_at(item_data, target_position, amount):
		return false

	var inventory := get_active_inventory()
	var target_item := inventory.get_item_at_cell(target_position)
	if target_item != null:
		target_item.amount += amount
	else:
		var added_item := inventory.add_item(item_data, target_position, amount, false)
		if added_item == null:
			return false

	gold -= item_data.buy_price * amount
	# Inventory UI and the save manager both refresh from this single signal.
	inventory.inventory_changed.emit()
	return true


func sell_item(inventory_item: InventoryItem) -> bool:
	var inventory := get_active_inventory()
	if inventory_item == null or inventory == null:
		return false
	if not inventory.items.has(inventory_item):
		return false

	var sell_price := inventory_item.item_data.sell_price * inventory_item.amount
	if not inventory.remove_item(inventory_item):
		return false

	gold += sell_price
	_save_and_emit_state()
	return true


# -----------------------------------------------------------------------------
# Change notifications and persistence entry points
# -----------------------------------------------------------------------------

func _connect_all_inventories() -> void:
	for character in characters:
		if character.inventory == null:
			character.inventory = _new_inventory(BACKPACK_WIDTH, BACKPACK_HEIGHT)
		_connect_inventory(character.inventory)
	if stash == null:
		stash = _new_inventory(STASH_WIDTH, STASH_HEIGHT)
	_connect_inventory(stash)


func _connect_inventory(inventory: Inventory) -> void:
	if inventory == null:
		return
	if not inventory.inventory_changed.is_connected(_on_inventory_changed):
		inventory.inventory_changed.connect(_on_inventory_changed)


func _on_inventory_changed() -> void:
	if _loading_save:
		return
	save_autosave()
	state_changed.emit()


func _save_and_emit_state() -> void:
	if not _loading_save:
		save_autosave()
	state_changed.emit()


# -----------------------------------------------------------------------------
# Save serialization
# -----------------------------------------------------------------------------

func save_game() -> bool:
	return save_to_slot(current_save_slot)


func save_to_slot(slot: int) -> bool:
	if _loading_save or slot < 1 or slot > MANUAL_SAVE_SLOT_COUNT:
		return false
	current_save_slot = slot
	return _write_save_file(_manual_save_path(slot))


func save_autosave() -> bool:
	if _loading_save or characters.is_empty():
		return false
	return _write_save_file(AUTOSAVE_PATH)


func _write_save_file(path: String) -> bool:
	var save_payload := SAVE_SERIALIZER.build_payload(
		characters,
		gold,
		active_character_id,
		stash,
		run_state,
		SAVE_VERSION,
		Vector2i(BACKPACK_WIDTH, BACKPACK_HEIGHT),
		Vector2i(STASH_WIDTH, STASH_HEIGHT)
	)
	return SAVE_SERIALIZER.save_payload(path, save_payload)


func load_from_slot(slot: int) -> bool:
	if slot < 1 or slot > MANUAL_SAVE_SLOT_COUNT:
		return false
	if not _load_game(_manual_save_path(slot)):
		return false
	current_save_slot = slot
	save_to_slot(slot) # Persist any migration back to the slot that was loaded.
	state_changed.emit()
	characters_changed.emit()
	active_character_changed.emit(active_character_id)
	return true


func has_save_slot(slot: int) -> bool:
	return slot >= 1 and slot <= MANUAL_SAVE_SLOT_COUNT and FileAccess.file_exists(_manual_save_path(slot))


func has_autosave() -> bool:
	return FileAccess.file_exists(AUTOSAVE_PATH)


func load_autosave() -> bool:
	if not has_autosave() or not _load_game(AUTOSAVE_PATH):
		return false
	state_changed.emit()
	characters_changed.emit()
	active_character_changed.emit(active_character_id)
	return true


func get_save_slot_summary(slot: int) -> Dictionary:
	var path := _manual_save_path(slot)
	if slot < 1 or slot > MANUAL_SAVE_SLOT_COUNT or not FileAccess.file_exists(path):
		return {"exists": false, "label": "Üres mentési hely"}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {"exists": false, "label": "Nem olvasható mentés"}
	var parser := JSON.new()
	var error := parser.parse(file.get_as_text())
	file.close()
	if error != OK or typeof(parser.data) != TYPE_DICTIONARY:
		return {"exists": false, "label": "Hibás mentés"}
	var data: Dictionary = parser.data
	var characters_data: Array = data.get("characters", [])
	var first_name := "Kaland"
	if not characters_data.is_empty() and typeof(characters_data[0]) == TYPE_DICTIONARY:
		first_name = str(characters_data[0].get("name", "Kaland"))
	return {"exists": true, "label": "Hely %d — %s · %d karakter · %d arany" % [slot, first_name, characters_data.size(), int(data.get("gold", 0))]}


func start_new_game(slot: int) -> bool:
	if slot < 1 or slot > MANUAL_SAVE_SLOT_COUNT:
		return false
	_loading_save = true
	_create_new_game()
	_loading_save = false
	current_save_slot = slot
	_connect_all_inventories()
	var saved := save_to_slot(slot)
	state_changed.emit()
	characters_changed.emit()
	active_character_changed.emit(active_character_id)
	return saved


func _manual_save_path(slot: int) -> String:
	return MANUAL_SAVE_PATH_TEMPLATE % slot


func _start_autosave_timer() -> void:
	_autosave_timer = Timer.new()
	_autosave_timer.name = "AutosaveTimer"
	_autosave_timer.wait_time = AUTOSAVE_INTERVAL_SECONDS
	_autosave_timer.one_shot = false
	_autosave_timer.autostart = true
	_autosave_timer.timeout.connect(_on_autosave_timeout)
	add_child(_autosave_timer)


func _on_autosave_timeout() -> void:
	if not characters.is_empty():
		save_autosave()


# -----------------------------------------------------------------------------
# Save loading, validation and version migration
# -----------------------------------------------------------------------------

func _load_game(path: String) -> bool:
	if not FileAccess.file_exists(path):
		return false

	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_warning("A mentés nem olvasható, új játék indul.")
		return false

	var parser := JSON.new()
	var parse_result := parser.parse(file.get_as_text())
	file.close()
	if parse_result != OK or typeof(parser.data) != TYPE_DICTIONARY:
		push_warning("A mentés hibás, új játék indul.")
		return false

	var save_data: Dictionary = parser.data
	var save_version := int(save_data.get("version", 1))
	_loading_save = true
	gold = int(save_data.get("gold", 500))
	characters.clear()

	var stored_characters: Array = save_data.get("characters", [])
	for character_entry in stored_characters:
		if typeof(character_entry) != TYPE_DICTIONARY:
			continue
		var character := CharacterProfile.new()
		character.id = str(character_entry.get("id", ""))
		if character.id.is_empty():
			character.id = _generate_character_id()
		character.character_name = str(character_entry.get("name", "Vándor"))
		var stored_class_id := StringName(str(character_entry.get("class_id", character_entry.get("archetype", "warrior"))))
		if get_character_class(stored_class_id) == null:
			push_warning("A mentett karakter osztálya nem található (" + String(stored_class_id) + "); alapértelmezett osztályra állítva.")
			if get_character_class(&"warrior") != null:
				stored_class_id = &"warrior"
		character.class_id = stored_class_id
		character.level = max(int(character_entry.get("level", 1)), 1)
		character.xp = max(int(character_entry.get("xp", 0)), 0)
		character.stress = clampi(int(character_entry.get("stress", 0)), 0, 100)
		var stored_quirks: Array = character_entry.get("quirk_ids", [])
		character.quirk_ids = PackedStringArray()
		for quirk_id in stored_quirks:
			character.quirk_ids.append(str(quirk_id))
		var stored_attributes: Variant = character_entry.get("attributes", {})
		character.attributes = stored_attributes.duplicate(true) if typeof(stored_attributes) == TYPE_DICTIONARY else {}
		var stored_modifiers: Variant = character_entry.get("stat_modifiers", {})
		character.stat_modifiers = stored_modifiers.duplicate(true) if typeof(stored_modifiers) == TYPE_DICTIONARY else {}
		var stored_effects: Variant = character_entry.get("status_effects", [])
		character.status_effects = []
		if typeof(stored_effects) == TYPE_ARRAY:
			for effect in stored_effects:
				if typeof(effect) == TYPE_DICTIONARY:
					var effect_dictionary: Dictionary = effect
					character.status_effects.append(effect_dictionary.duplicate(true))
		var stored_cooldowns: Variant = character_entry.get("ability_cooldowns", {})
		character.ability_cooldowns = stored_cooldowns.duplicate(true) if typeof(stored_cooldowns) == TYPE_DICTIONARY else {}
		var stored_custom_data: Variant = character_entry.get("persistent_data", {})
		character.persistent_data = stored_custom_data.duplicate(true) if typeof(stored_custom_data) == TYPE_DICTIONARY else {}
		character.equipment = _deserialize_equipment(character_entry.get("equipment", {}))
		character.inventory = _deserialize_inventory(
			character_entry.get("inventory", {}),
			BACKPACK_WIDTH,
			BACKPACK_HEIGHT
		)
		characters.append(character)
		var stats_after_load := get_character_stats(character)
		var max_health := maxi(int(stats_after_load.get("max_health", 30)), 1)
		var max_mana := maxi(int(stats_after_load.get("max_mana", 0)), 0)
		var saved_health := int(character_entry.get("current_health", -1))
		var saved_mana := int(character_entry.get("current_mana", -1))
		character.current_health = clampi(saved_health if saved_health >= 0 else max_health, 0, max_health)
		character.current_mana = clampi(saved_mana if saved_mana >= 0 else max_mana, 0, max_mana)

	stash = _deserialize_inventory(save_data.get("stash", {}), STASH_WIDTH, STASH_HEIGHT)
	var stored_run_state: Variant = save_data.get("run_state", {})
	run_state = stored_run_state.duplicate(true) if typeof(stored_run_state) == TYPE_DICTIONARY else {}
	active_character_id = str(save_data.get("active_character_id", ""))
	if get_active_character() == null and not characters.is_empty():
		active_character_id = characters[0].id

	_loading_save = false
	if characters.is_empty():
		return false
	# Migrate pre-smithing saves once so the new feature is immediately testable.
	if save_version < 3:
		_seed_starting_smithing_materials()
	_connect_all_inventories()
	# Version 4 adds mana, equipped items, status effects and dungeon run_state.
	# The caller persists migrated data to the correct selected slot.
	return true


# -----------------------------------------------------------------------------
# Resource restoration from saved item IDs and paths
# -----------------------------------------------------------------------------

func _deserialize_inventory(data: Variant, default_width: int, default_height: int) -> Inventory:
	var width := default_width
	var height := default_height
	var stored_items: Array = []
	if typeof(data) == TYPE_DICTIONARY:
		var inventory_data: Dictionary = data
		width = max(int(inventory_data.get("width", default_width)), 1)
		height = max(int(inventory_data.get("height", default_height)), 1)
		stored_items = inventory_data.get("items", [])

	var result := _new_inventory(width, height)
	for item_entry in stored_items:
		if typeof(item_entry) != TYPE_DICTIONARY:
			continue
		var item_info: Dictionary = item_entry
		var item_data := _resolve_item_data(
			str(item_info.get("resource_path", "")),
			StringName(str(item_info.get("id", "")))
		)
		if item_data == null:
			push_warning("A mentésben szereplő tárgy nem található: " + str(item_info.get("id", "ismeretlen")))
			continue

		var position := Vector2i(int(item_info.get("x", 0)), int(item_info.get("y", 0)))
		var amount = max(int(item_info.get("amount", 1)), 1)
		var restored_item := result.add_item(item_data, position, amount, false)
		if restored_item == null:
			push_warning("Egy tárgyat nem lehetett visszatölteni az inventoryba: " + String(item_data.id))
			continue
		restored_item.upgrade_level = clampi(int(item_info.get("upgrade_level", 0)), 0, mini(item_data.max_upgrade_level, 5))
		var stored_enchantments: Array = item_info.get("enchantment_ids", [])
		restored_item.enchantment_ids = PackedStringArray()
		for enchantment_id in stored_enchantments:
			if get_enchantment(StringName(str(enchantment_id))) != null:
				restored_item.enchantment_ids.append(str(enchantment_id))
	return result


func _deserialize_equipment(data: Variant) -> Dictionary:
	var result: Dictionary = {}
	if typeof(data) != TYPE_DICTIONARY:
		return result
	for slot_key in data:
		var slot := StringName(str(slot_key))
		var item_info: Variant = data[slot_key]
		if typeof(item_info) != TYPE_DICTIONARY:
			continue
		var item_dictionary: Dictionary = item_info
		var item := _deserialize_item(item_dictionary, Vector2i(-1, -1))
		if item == null or item.item_data == null:
			continue
		if item.item_data.equipment_slot != slot:
			push_warning("A mentett felszerelési hely nem egyezik a tárggyal: " + String(slot))
			continue
		result[slot] = item
	return result


func _deserialize_item(item_info: Dictionary, position_override: Vector2i = Vector2i(-999, -999)) -> InventoryItem:
	var item_data := _resolve_item_data(
		str(item_info.get("resource_path", "")),
		StringName(str(item_info.get("id", "")))
	)
	if item_data == null:
		push_warning("A mentésben szereplő tárgy nem található: " + str(item_info.get("id", "ismeretlen")))
		return null
	var restored := InventoryItem.new()
	restored.item_data = item_data
	if position_override == Vector2i(-999, -999):
		restored.position = Vector2i(int(item_info.get("x", 0)), int(item_info.get("y", 0)))
	else:
		restored.position = position_override
	restored.amount = max(int(item_info.get("amount", 1)), 1)
	restored.upgrade_level = clampi(int(item_info.get("upgrade_level", 0)), 0, mini(item_data.max_upgrade_level, 5))
	var stored_enchantments: Array = item_info.get("enchantment_ids", [])
	restored.enchantment_ids = PackedStringArray()
	for enchantment_id in stored_enchantments:
		if get_enchantment(StringName(str(enchantment_id))) != null:
			restored.enchantment_ids.append(str(enchantment_id))
	return restored


func _resolve_item_data(resource_path: String, item_id: StringName) -> ItemData:
	if not resource_path.is_empty() and ResourceLoader.exists(resource_path):
		var by_path := load(resource_path) as ItemData
		if by_path != null:
			return by_path
	if not String(item_id).is_empty():
		return _find_item_data_by_id(ITEM_DATA_DIRECTORY, item_id)
	return null


func _find_item_data_by_id(directory_path: String, target_id: StringName) -> ItemData:
	for resource_path in RESOURCE_CATALOG.collect_resource_paths(directory_path):
		var candidate := load(resource_path) as ItemData
		if candidate != null and candidate.id == target_id:
			return candidate
	return null
