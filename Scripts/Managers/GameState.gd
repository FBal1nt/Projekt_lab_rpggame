extends Node

signal state_changed
signal characters_changed
signal active_character_changed(character_id: String)

const LEGACY_SAVE_PATH := "user://savegame.json"
const MANUAL_SAVE_PATH_TEMPLATE := "user://save_slot_%d.json"
const AUTOSAVE_PATH := "user://autosave.json"
const MANUAL_SAVE_SLOT_COUNT := 3
const AUTOSAVE_INTERVAL_SECONDS := 60.0
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

var _loading_save: bool = false
var current_save_slot: int = 1
var game_started: bool = false
var _autosave_timer: Timer

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


func _ready() -> void:
	_load_character_classes()
	_load_smithing_data()
	_migrate_legacy_save_if_needed()
	_create_new_game()
	_connect_all_inventories()
	_recalculate_all_character_stats()
	_start_autosave_timer()

	state_changed.emit()
	characters_changed.emit()
	active_character_changed.emit(active_character_id)


func _exit_tree() -> void:
	# Manual save slots are only changed by explicit save/new-game actions.
	# The timer maintains the independent autosave while a campaign is active.
	pass


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


func get_character_stats(character: CharacterProfile = null) -> Dictionary:
	var target := character if character != null else get_active_character()
	if target == null:
		return {}
	return recalculate_character_stats(target)


func recalculate_character_stats(character: CharacterProfile) -> Dictionary:
	if character == null:
		return {}
	var class_data := get_character_class(character.class_id)
	if class_data == null:
		return {}

	var base := class_data.get_stats_at_level(character.level)
	var final_stats := base.duplicate(true)
	for slot in character.equipment:
		var equipped_item := character.equipment[slot] as InventoryItem
		if equipped_item == null or equipped_item.item_data == null:
			continue
		var modifiers := get_item_stats(equipped_item)
		for stat_key in modifiers:
			var bonus := float(modifiers[stat_key])
			if String(stat_key) == "damage":
				final_stats["damage_min"] = float(final_stats.get("damage_min", 0.0)) + bonus
				final_stats["damage_max"] = float(final_stats.get("damage_max", 0.0)) + bonus
			else:
				final_stats[stat_key] = float(final_stats.get(stat_key, 0.0)) + bonus

	character.base_stats = base.duplicate(true)
	character.derived_stats = final_stats.duplicate(true)
	var max_health := maxi(int(round(float(final_stats.get("max_health", 1)))), 1)
	if character.current_health < 0:
		character.current_health = max_health
	else:
		character.current_health = mini(character.current_health, max_health)
	return character.derived_stats.duplicate(true)


func _recalculate_all_character_stats() -> void:
	for character in characters:
		recalculate_character_stats(character)


func get_character_equipment(character: CharacterProfile = null) -> Dictionary:
	var target := character if character != null else get_active_character()
	if target == null:
		return {}
	return target.equipment


func get_equipped_item(slot: StringName, character: CharacterProfile = null) -> InventoryItem:
	var target := character if character != null else get_active_character()
	if target == null:
		return null
	return target.equipment.get(slot, null) as InventoryItem


func can_equip_item(item: InventoryItem, character: CharacterProfile = null) -> bool:
	var target := character if character != null else get_active_character()
	if target == null or target.inventory == null or item == null or item.item_data == null:
		return false
	if item.amount != 1 or not target.inventory.items.has(item):
		return false
	var slot := item.item_data.equipment_slot
	if String(slot).is_empty() or slot == &"none":
		return false
	if not target.equipment.has(slot):
		return true
	var currently_equipped := target.equipment[slot] as InventoryItem
	if currently_equipped == null:
		return true

	# Test the swap in a temporary inventory before mutating the real state.
	var simulation := _copy_inventory(target.inventory)
	var simulated_source := simulation.get_item_at_cell(item.position)
	if simulated_source == null:
		return false
	simulation.items.erase(simulated_source)
	return simulation.find_free_position(currently_equipped.item_data) != Vector2i(-1, -1)


func equip_item(item: InventoryItem, character: CharacterProfile = null) -> bool:
	var target := character if character != null else get_active_character()
	if not can_equip_item(item, target):
		return false
	var slot := item.item_data.equipment_slot
	var previous := target.equipment.get(slot, null) as InventoryItem
	if previous != null:
		var simulation := _copy_inventory(target.inventory)
		var simulated_source := simulation.get_item_at_cell(item.position)
		if simulated_source == null:
			return false
		simulation.items.erase(simulated_source)
		var return_position := simulation.find_free_position(previous.item_data)
		if return_position == Vector2i(-1, -1):
			return false
		target.inventory.items.erase(item)
		previous.position = return_position
		target.inventory.items.append(previous)
	else:
		target.inventory.items.erase(item)
	target.equipment[slot] = item
	recalculate_character_stats(target)
	target.inventory.inventory_changed.emit()
	return true


func can_unequip_item(slot: StringName, character: CharacterProfile = null) -> bool:
	var target := character if character != null else get_active_character()
	if target == null or target.inventory == null:
		return false
	var equipped := target.equipment.get(slot, null) as InventoryItem
	return equipped != null and target.inventory.find_free_position(equipped.item_data) != Vector2i(-1, -1)


func unequip_item(slot: StringName, character: CharacterProfile = null) -> bool:
	var target := character if character != null else get_active_character()
	if not can_unequip_item(slot, target):
		return false
	var equipped := target.equipment[slot] as InventoryItem
	var position := target.inventory.find_free_position(equipped.item_data)
	if position == Vector2i(-1, -1):
		return false
	target.equipment.erase(slot)
	equipped.position = position
	target.inventory.items.append(equipped)
	recalculate_character_stats(target)
	target.inventory.inventory_changed.emit()
	return true


func _load_character_classes() -> void:
	character_classes.clear()
	var paths: Array[String] = []
	_collect_resource_paths(CHARACTER_CLASS_DIRECTORY, paths)
	paths.sort()

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


func _collect_resource_paths(directory_path: String, output: Array[String]) -> void:
	var directory := DirAccess.open(directory_path)
	if directory == null:
		return

	directory.list_dir_begin()
	var entry := directory.get_next()
	while not entry.is_empty():
		if directory.current_is_dir():
			if not entry.begins_with("."):
				_collect_resource_paths(directory_path.path_join(entry), output)
		elif entry.ends_with(".tres") or entry.ends_with(".res"):
			output.append(directory_path.path_join(entry))
		entry = directory.get_next()
	directory.list_dir_end()


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
	character.current_health = int(get_character_class(archetype).get_stats_at_level(1).get("max_health", 30))
	character.stress = 0
	character.inventory = _new_inventory(BACKPACK_WIDTH, BACKPACK_HEIGHT)

	characters.append(character)
	_connect_inventory(character.inventory)
	active_character_id = character.id
	recalculate_character_stats(character)

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
		recalculate_character_stats(character)
		save_autosave()
		active_character_changed.emit(active_character_id)
		state_changed.emit()
		return true
	return false


func _load_smithing_data() -> void:
	smithing_recipes.clear()
	var recipe_paths: Array[String] = []
	_collect_resource_paths(SMITHING_RECIPE_DIRECTORY, recipe_paths)
	recipe_paths.sort()
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
	var enchantment_paths: Array[String] = []
	_collect_resource_paths(ENCHANTMENT_DIRECTORY, enchantment_paths)
	enchantment_paths.sort()
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




func _character_has_equipped_item(character: CharacterProfile, item: InventoryItem) -> bool:
	if character == null or item == null:
		return false
	for slot in character.equipment:
		if character.equipment[slot] == item:
			return true
	return false


func can_upgrade_item(item: InventoryItem) -> bool:
	var inventory := get_active_inventory()
	var active := get_active_character()
	if item == null or item.item_data == null or inventory == null:
		return false
	var is_owned := inventory.items.has(item) or _character_has_equipped_item(active, item)
	if not is_owned:
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
	var active := get_active_character()
	var enchantment := get_enchantment(enchantment_id)
	if item == null or item.item_data == null or inventory == null:
		return false
	var is_owned := inventory.items.has(item) or _character_has_equipped_item(active, item)
	if not is_owned:
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


func _create_new_game() -> void:
	characters.clear()
	gold = 500
	stash = _new_inventory(STASH_WIDTH, STASH_HEIGHT)

	var starter := CharacterProfile.new()
	starter.id = _generate_character_id()
	starter.character_name = "Vándor"
	starter.class_id = &"warrior"
	starter.level = 1
	starter.xp = 0
	var starter_class := get_character_class(starter.class_id)
	starter.current_health = int(starter_class.get_stats_at_level(1).get("max_health", 30)) if starter_class != null else 30
	starter.stress = 0
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
	_recalculate_all_character_stats()
	save_autosave()
	state_changed.emit()


func _save_and_emit_state() -> void:
	if not _loading_save:
		_recalculate_all_character_stats()
		save_autosave()
	state_changed.emit()


func save_game() -> bool:
	return save_to_slot(current_save_slot)


func save_to_slot(slot: int) -> bool:
	if _loading_save or slot < 1 or slot > MANUAL_SAVE_SLOT_COUNT:
		return false
	current_save_slot = slot
	return _write_save_file(_manual_save_path(slot))


func save_autosave() -> bool:
	if _loading_save or not game_started:
		return false
	return _write_save_file(AUTOSAVE_PATH)


func _write_save_file(path: String) -> bool:
	if _loading_save:
		return false
	_recalculate_all_character_stats()
	var character_entries: Array[Dictionary] = []
	for character in characters:
		character_entries.append({
			"id": character.id,
			"name": character.character_name,
			"class_id": String(character.class_id),
			"archetype": String(character.archetype),
			"level": character.level,
			"xp": character.xp,
			"current_health": character.current_health,
			"stress": character.stress,
			"quirk_ids": Array(character.quirk_ids),
			"base_stats": character.base_stats.duplicate(true),
			"derived_stats": character.derived_stats.duplicate(true),
			"inventory": _serialize_inventory(character.inventory),
			"equipment": _serialize_equipment(character.equipment)
		})

	var save_data := {
		"version": 5,
		"current_save_slot": current_save_slot,
		"gold": gold,
		"active_character_id": active_character_id,
		"characters": character_entries,
		"stash": _serialize_inventory(stash)
	}
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_error("Nem sikerült megnyitni a mentési fájlt: " + path)
		return false
	file.store_string(JSON.stringify(save_data, "\t"))
	file.close()
	return true


func _serialize_equipment(equipment: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	for slot in equipment:
		var item := equipment[slot] as InventoryItem
		if item != null and item.item_data != null:
			result[String(slot)] = _serialize_inventory_item(item)
	return result


func _serialize_inventory_item(item: InventoryItem) -> Dictionary:
	return {
		"resource_path": item.item_data.resource_path,
		"id": String(item.item_data.id),
		"x": item.position.x,
		"y": item.position.y,
		"amount": item.amount,
		"upgrade_level": item.upgrade_level,
		"enchantment_ids": Array(item.enchantment_ids)
	}


func has_save_slot(slot: int) -> bool:
	return slot >= 1 and slot <= MANUAL_SAVE_SLOT_COUNT and FileAccess.file_exists(_manual_save_path(slot))


func has_autosave() -> bool:
	return FileAccess.file_exists(AUTOSAVE_PATH)


func get_save_slot_summary(slot: int) -> Dictionary:
	var path := _manual_save_path(slot)
	if not has_save_slot(slot):
		return {"exists": false, "label": "Üres mentési hely"}
	var details := _read_save_summary(path)
	if bool(details.get("exists", false)):
		details["label"] = "Kézi mentés %d" % slot
	return details


func get_autosave_summary() -> Dictionary:
	if not has_autosave():
		return {"exists": false, "label": "Nincs automatikus mentés"}
	var details := _read_save_summary(AUTOSAVE_PATH)
	if bool(details.get("exists", false)):
		details["label"] = "Automatikus mentés"
	return details


func _read_save_summary(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {"exists": false, "label": "Nem olvasható mentés"}
	var parser := JSON.new()
	var parse_result := parser.parse(file.get_as_text())
	file.close()
	if parse_result != OK or typeof(parser.data) != TYPE_DICTIONARY:
		return {"exists": false, "label": "Hibás mentés"}
	var save_data: Dictionary = parser.data
	var stored_characters: Array = save_data.get("characters", [])
	var names: Array[String] = []
	for entry in stored_characters:
		if typeof(entry) == TYPE_DICTIONARY:
			names.append(str(entry.get("name", "Névtelen")))
	return {
		"exists": true,
		"characters": names,
		"gold": int(save_data.get("gold", 0)),
		"modified": FileAccess.get_modified_time(path)
	}


func load_from_slot(slot: int) -> bool:
	if not has_save_slot(slot):
		return false
	if not _load_game(_manual_save_path(slot)):
		return false
	current_save_slot = slot
	game_started = true
	_connect_all_inventories()
	_recalculate_all_character_stats()
	# Persist any schema migration back to the selected slot.
	var saved := save_to_slot(slot)
	state_changed.emit()
	characters_changed.emit()
	active_character_changed.emit(active_character_id)
	return saved


func load_autosave() -> bool:
	if not has_autosave() or not _load_game(AUTOSAVE_PATH):
		return false
	game_started = true
	_connect_all_inventories()
	_recalculate_all_character_stats()
	state_changed.emit()
	characters_changed.emit()
	active_character_changed.emit(active_character_id)
	return true


func start_new_game(slot: int) -> bool:
	if slot < 1 or slot > MANUAL_SAVE_SLOT_COUNT:
		return false
	_loading_save = true
	_create_new_game()
	_loading_save = false
	current_save_slot = slot
	game_started = true
	_connect_all_inventories()
	_recalculate_all_character_stats()
	if not save_to_slot(slot):
		return false
	save_autosave()
	state_changed.emit()
	characters_changed.emit()
	active_character_changed.emit(active_character_id)
	return true


func _manual_save_path(slot: int) -> String:
	return MANUAL_SAVE_PATH_TEMPLATE % slot


func _migrate_legacy_save_if_needed() -> void:
	if FileAccess.file_exists(LEGACY_SAVE_PATH) and not has_save_slot(1):
		var legacy := FileAccess.open(LEGACY_SAVE_PATH, FileAccess.READ)
		if legacy == null:
			return
		var contents := legacy.get_as_text()
		legacy.close()
		var migrated := FileAccess.open(_manual_save_path(1), FileAccess.WRITE)
		if migrated != null:
			migrated.store_string(contents)
			migrated.close()


func _start_autosave_timer() -> void:
	if _autosave_timer != null:
		return
	_autosave_timer = Timer.new()
	_autosave_timer.name = "AutosaveTimer"
	_autosave_timer.wait_time = AUTOSAVE_INTERVAL_SECONDS
	_autosave_timer.one_shot = false
	_autosave_timer.autostart = true
	add_child(_autosave_timer)
	_autosave_timer.timeout.connect(_on_autosave_timeout)


func _on_autosave_timeout() -> void:
	if game_started:
		save_autosave()


func _serialize_inventory(inventory: Inventory) -> Dictionary:
	if inventory == null:
		return {"width": BACKPACK_WIDTH, "height": BACKPACK_HEIGHT, "items": []}

	var item_entries: Array[Dictionary] = []
	for item in inventory.items:
		if item == null or item.item_data == null:
			continue
		item_entries.append(_serialize_inventory_item(item))

	return {
		"width": inventory.width,
		"height": inventory.height,
		"items": item_entries
	}


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
	current_save_slot = clampi(int(save_data.get("current_save_slot", current_save_slot)), 1, MANUAL_SAVE_SLOT_COUNT)
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
		var stored_health := int(character_entry.get("current_health", -1))
		# Keep the saved current HP until equipment has been restored; the final
		# maximum is recalculated below from class, level and equipped modifiers.
		character.current_health = maxi(stored_health, -1)
		character.inventory = _deserialize_inventory(
			character_entry.get("inventory", {}),
			BACKPACK_WIDTH,
			BACKPACK_HEIGHT
		)
		character.equipment = _deserialize_equipment(character_entry.get("equipment", {}))
		character.base_stats = character_entry.get("base_stats", {}).duplicate(true)
		character.derived_stats = character_entry.get("derived_stats", {}).duplicate(true)
		characters.append(character)

	stash = _deserialize_inventory(save_data.get("stash", {}), STASH_WIDTH, STASH_HEIGHT)
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
	_recalculate_all_character_stats()
	return true


func _deserialize_equipment(data: Variant) -> Dictionary:
	var result: Dictionary = {}
	if typeof(data) != TYPE_DICTIONARY:
		return result
	for slot_key in data:
		var item_data_variant: Variant = data[slot_key]
		if typeof(item_data_variant) != TYPE_DICTIONARY:
			continue
		var restored_item := _deserialize_inventory_item(item_data_variant)
		if restored_item == null or restored_item.item_data == null:
			continue
		if restored_item.item_data.equipment_slot != StringName(str(slot_key)):
			push_warning("A mentett felszerelési hely nem egyezik a tárggyal: " + str(slot_key))
			continue
		result[StringName(str(slot_key))] = restored_item
	return result


func _deserialize_inventory_item(item_info: Dictionary) -> InventoryItem:
	var item_data := _resolve_item_data(
		str(item_info.get("resource_path", "")),
		StringName(str(item_info.get("id", "")))
	)
	if item_data == null:
		return null
	var restored_item := InventoryItem.new()
	restored_item.item_data = item_data
	restored_item.position = Vector2i(int(item_info.get("x", 0)), int(item_info.get("y", 0)))
	restored_item.amount = max(int(item_info.get("amount", 1)), 1)
	restored_item.upgrade_level = clampi(int(item_info.get("upgrade_level", 0)), 0, mini(item_data.max_upgrade_level, 5))
	var stored_enchantments: Array = item_info.get("enchantment_ids", [])
	restored_item.enchantment_ids = PackedStringArray()
	for enchantment_id in stored_enchantments:
		if get_enchantment(StringName(str(enchantment_id))) != null:
			restored_item.enchantment_ids.append(str(enchantment_id))
	return restored_item


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
		var restored_item := _deserialize_inventory_item(item_info)
		if restored_item == null or restored_item.item_data == null:
			push_warning("A mentésben szereplő tárgy nem található: " + str(item_info.get("id", "ismeretlen")))
			continue
		var added_item := result.add_item(restored_item.item_data, restored_item.position, restored_item.amount, false)
		if added_item == null:
			push_warning("Egy tárgyat nem lehetett visszatölteni az inventoryba: " + String(restored_item.item_data.id))
			continue
		added_item.upgrade_level = restored_item.upgrade_level
		added_item.enchantment_ids = restored_item.enchantment_ids.duplicate()
	return result


func _resolve_item_data(resource_path: String, item_id: StringName) -> ItemData:
	if not resource_path.is_empty() and ResourceLoader.exists(resource_path):
		var by_path := load(resource_path) as ItemData
		if by_path != null:
			return by_path
	if not String(item_id).is_empty():
		return _find_item_data_by_id(ITEM_DATA_DIRECTORY, item_id)
	return null


func _find_item_data_by_id(directory_path: String, target_id: StringName) -> ItemData:
	var directory := DirAccess.open(directory_path)
	if directory == null:
		return null

	directory.list_dir_begin()
	var entry := directory.get_next()
	while not entry.is_empty():
		if directory.current_is_dir():
			if not entry.begins_with("."):
				var nested_result := _find_item_data_by_id(directory_path.path_join(entry), target_id)
				if nested_result != null:
					directory.list_dir_end()
					return nested_result
		elif entry.ends_with(".tres") or entry.ends_with(".res"):
			var resource_path := directory_path.path_join(entry)
			var candidate := load(resource_path) as ItemData
			if candidate != null and candidate.id == target_id:
				directory.list_dir_end()
				return candidate
		entry = directory.get_next()
	directory.list_dir_end()
	return null
