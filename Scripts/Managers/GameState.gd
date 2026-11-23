extends Node

# -----------------------------------------------------------------------------
# Shared game state and compatibility properties
# -----------------------------------------------------------------------------

const RESOURCE_CATALOG := preload("res://Scripts/Utils/ResourceCatalog.gd")
const CLASS_VISUAL_HELPER := preload("res://Scripts/Utils/ClassVisualHelper.gd")
const SAVE_SERIALIZER := preload("res://Scripts/Managers/GameSaveSerializer.gd")
const SAVE_VERSION := 4

signal state_changed
signal characters_changed
signal active_character_changed(character_id: String)

const SAVES_FOLDER_NAME := "Saves"
const LEGACY_SAVE_PATH := "user://savegame.json"
const LEGACY_MANUAL_SAVE_TEMPLATE := "user://save_slot_%d.json"
const LEGACY_AUTOSAVE_PATH := "user://autosave.json"
const LEGACY_MIGRATION_MARKER := "user://.saves_migrated_to_game_folder"
const MANUAL_SAVE_FILENAME_TEMPLATE := "save_slot_%d.json"
const AUTOSAVE_FILENAME := "autosave.json"
const MANUAL_SAVE_SLOT_COUNT := 3
const AUTOSAVE_INTERVAL_SECONDS := 60.0

var current_save_slot: int = 1
var _autosave_timer: Timer
const ITEM_DATA_DIRECTORY := "res://Data/Items"
const CHARACTER_CLASS_DIRECTORY := "res://Data/CharacterClasses"
const SMITHING_RECIPE_DIRECTORY := "res://Data/SmithingRecipes"
const ENCHANTMENT_DIRECTORY := "res://Data/Enchantments"
const MONSTER_DATA_DIRECTORY := "res://Data/Monsters"
const BACKPACK_WIDTH := 8
const BACKPACK_HEIGHT := 4
const STASH_WIDTH := 10
const STASH_HEIGHT := 5
const STARTING_GOLD := 200

var gold: int = STARTING_GOLD
var characters: Array[CharacterProfile] = []
var character_classes: Dictionary = {}
var smithing_recipes: Array[SmithingRecipeData] = []
var enchantments: Dictionary = {}
var active_character_id: String = ""
var stash: Inventory
## Shared, persistent dungeon/run data. Use JSON-compatible values only.
## Example: {"dungeon_id":"crypt_01", "floor":2, "seed":12345, "turn":8}.
var run_state: Dictionary = {}
## Titles collected during the active dungeon run; only committed to the character on victory.
var pending_run_titles: PackedStringArray = PackedStringArray()
var completed_run_newly_unlocked: PackedStringArray = PackedStringArray()
var completed_run_titles: PackedStringArray = PackedStringArray()
var current_run_completed: bool = false

var _loading_save: bool = false
var _item_data_cache: Dictionary = {}
var _collectible_titles_cache: Array[Dictionary] = []

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
	_recalculate_all_character_stats()
	_start_autosave_timer()

	state_changed.emit()
	characters_changed.emit()
	active_character_changed.emit(active_character_id)


func get_saves_directory() -> String:
	if OS.has_feature("editor"):
		return ProjectSettings.globalize_path("res://").path_join(SAVES_FOLDER_NAME)
	var exe_dir := OS.get_executable_path().get_base_dir()
	if exe_dir.is_empty():
		return ProjectSettings.globalize_path("user://").path_join(SAVES_FOLDER_NAME)
	return exe_dir.path_join(SAVES_FOLDER_NAME)


func _ensure_saves_directory() -> bool:
	var saves_dir := get_saves_directory()
	if DirAccess.dir_exists_absolute(saves_dir):
		return true
	var err := DirAccess.make_dir_recursive_absolute(saves_dir)
	if err != OK:
		push_warning("Nem sikerült létrehozni a mentési mappát (%s): %s" % [saves_dir, error_string(err)])
		return false
	return true


func _copy_file_if_missing(source_path: String, destination_path: String) -> void:
	if FileAccess.file_exists(destination_path) or not FileAccess.file_exists(source_path):
		return
	var source := FileAccess.open(source_path, FileAccess.READ)
	if source == null:
		return
	var contents := source.get_as_text()
	source.close()
	var destination := FileAccess.open(destination_path, FileAccess.WRITE)
	if destination == null:
		return
	destination.store_string(contents)
	destination.close()


func _migrate_legacy_save_if_needed() -> void:
	_ensure_saves_directory()
	# Migrate old user:// saves once into the game's dedicated Saves folder.
	# Using a one-time marker ensures deleted saves do not reappear on restart.
	if FileAccess.file_exists(LEGACY_MIGRATION_MARKER):
		return
	for slot in range(1, MANUAL_SAVE_SLOT_COUNT + 1):
		_copy_file_if_missing(LEGACY_MANUAL_SAVE_TEMPLATE % slot, _manual_save_path(slot))
	_copy_file_if_missing(LEGACY_SAVE_PATH, _manual_save_path(1))
	_copy_file_if_missing(LEGACY_AUTOSAVE_PATH, _autosave_path())

	var marker := FileAccess.open(LEGACY_MIGRATION_MARKER, FileAccess.WRITE)
	if marker != null:
		marker.store_string("1")
		marker.close()


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
	pending_run_titles = PackedStringArray()
	completed_run_newly_unlocked = PackedStringArray()
	completed_run_titles = PackedStringArray()
	current_run_completed = false
	_save_and_emit_state()


# -----------------------------------------------------------------------------
# Collectible hero titles (single active title with passive stat buffs)
# -----------------------------------------------------------------------------

const TITLE_BUFFS: Dictionary = {
	"a Földhasító": {
		"damage": 3.0,
		"max_health": 10.0
	},
	"a Törhetetlen Pajzsú": {
		"defense": 2.0,
		"max_health": 15.0
	},
	"a Vascsontú": {
		"defense": 2.0,
		"damage": 2.0,
		"max_health": 5.0
	},
	"a Vérszomjas": {
		"damage": 4.0,
		"crit_chance": 8.0,
		"lifesteal": 2.0
	},
	"a Zúzó": {
		"damage": 5.0,
		"defense": 1.0
	},
	"a Megtörhetetlen": {
		"max_health": 25.0,
		"defense": 3.0
	},
	"az Éjszakai Vadász": {
		"speed": 3.0,
		"crit_chance": 10.0,
		"vision_bonus": 1.0
	},
	"a Sötétség Ura": {
		"max_health": 20.0,
		"damage": 4.0,
		"defense": 2.0,
		"speed": 2.0,
		"crit_chance": 8.0
	}
}


func get_title_buffs(title: String) -> Dictionary:
	var clean_title := title.strip_edges()
	if clean_title.is_empty():
		return {}
	if TITLE_BUFFS.has(clean_title):
		return (TITLE_BUFFS[clean_title] as Dictionary).duplicate(true)
	return {"max_health": 10.0, "damage": 2.0}


func format_title_buff_summary(title: String) -> String:
	var buffs: Dictionary = get_title_buffs(title)
	if buffs.is_empty():
		return "Nincs bónusz"
	var parts: Array[String] = []
	var hp_bonus := int(round(float(buffs.get("max_health", 0.0))))
	var dmg_bonus := int(round(float(buffs.get("damage", 0.0))))
	var def_bonus := int(round(float(buffs.get("defense", 0.0))))
	var spd_bonus := int(round(float(buffs.get("speed", 0.0))))
	var crit_bonus := int(round(float(buffs.get("crit_chance", 0.0))))
	var ls_bonus := int(round(float(buffs.get("lifesteal", 0.0))))
	var vis_bonus := int(round(float(buffs.get("vision_bonus", 0.0))))

	if hp_bonus > 0:
		parts.append("+%d Max HP" % hp_bonus)
	if dmg_bonus > 0:
		parts.append("+%d Sebzés" % dmg_bonus)
	if def_bonus > 0:
		parts.append("+%d Passzív páncél" % def_bonus)
	if spd_bonus > 0:
		parts.append("+%d Kezdeményezés" % spd_bonus)
	if crit_bonus > 0:
		parts.append("+%d%% Kritikus" % crit_bonus)
	if ls_bonus > 0:
		parts.append("+%d HP elszívás/találat" % ls_bonus)
	if vis_bonus > 0:
		parts.append("+%d Látótáv" % vis_bonus)
	return " · ".join(parts) if not parts.is_empty() else "Nincs bónusz"


func get_active_title(character: CharacterProfile = null) -> String:
	var target := character if character != null else get_active_character()
	if target == null or target.selected_titles.is_empty():
		return ""
	for raw in target.selected_titles:
		var clean := String(raw).strip_edges()
		if not clean.is_empty() and target.unlocked_titles.has(clean):
			return clean
	return ""


func get_active_title_buffs(character: CharacterProfile = null) -> Dictionary:
	var active_title := get_active_title(character)
	if active_title.is_empty():
		return {}
	return get_title_buffs(active_title)


func get_all_collectible_titles() -> Array[Dictionary]:
	if not _collectible_titles_cache.is_empty():
		return _collectible_titles_cache.duplicate(true)

	var seen: Dictionary = {}
	var paths: Array[String] = RESOURCE_CATALOG.collect_resource_paths(MONSTER_DATA_DIRECTORY)
	for resource_path in paths:
		var loaded := load(resource_path)
		if not (loaded is EnemyData):
			continue
		var enemy_data := loaded as EnemyData
		var clean_title := enemy_data.title.strip_edges()
		if clean_title.is_empty() or seen.has(clean_title):
			continue
		seen[clean_title] = true
		_collectible_titles_cache.append({
			"title": clean_title,
			"monster_name": enemy_data.monster_name,
			"tier": int(enemy_data.tier)
		})

	_collectible_titles_cache.sort_custom(_sort_collectible_titles)
	return _collectible_titles_cache.duplicate(true)


func _sort_collectible_titles(a: Dictionary, b: Dictionary) -> bool:
	var tier_a := int(a.get("tier", 0))
	var tier_b := int(b.get("tier", 0))
	if tier_a != tier_b:
		return tier_a < tier_b
	return String(a.get("title", "")).naturalnocasecmp_to(String(b.get("title", ""))) < 0


func _order_titles_canonically(titles: PackedStringArray) -> PackedStringArray:
	var clean_unique: Array[String] = []
	for raw in titles:
		var t := String(raw).strip_edges()
		if not t.is_empty() and not clean_unique.has(t):
			clean_unique.append(t)

	var ordered := PackedStringArray()
	for entry in get_all_collectible_titles():
		var catalog_title := String(entry.get("title", ""))
		if clean_unique.has(catalog_title):
			ordered.append(catalog_title)
			clean_unique.erase(catalog_title)
	for remaining in clean_unique:
		ordered.append(remaining)
	return ordered


func format_merged_title_phrase(titles: PackedStringArray) -> String:
	var ordered := _order_titles_canonically(titles)
	if ordered.is_empty():
		return ""
	return "%s legyőzője" % ordered[0]


func get_character_display_name(character: CharacterProfile = null) -> String:
	var target := character if character != null else get_active_character()
	if target == null:
		return ""
	var base_name := target.character_name.strip_edges()
	var active_title := get_active_title(target)
	if active_title.is_empty():
		return base_name
	return "%s, %s legyőzője" % [base_name, active_title]


func reset_dungeon_run_titles() -> void:
	pending_run_titles = PackedStringArray()
	completed_run_newly_unlocked = PackedStringArray()
	completed_run_titles = PackedStringArray()
	current_run_completed = false
	if run_state.has("pending_titles"):
		run_state.erase("pending_titles")


func collect_pending_title(raw_title: String, character: CharacterProfile = null) -> Dictionary:
	## Records a defeated monster's title for the current run.
	## Does NOT modify the hero's active name; becomes permanently unlocked only on dungeon victory.
	var clean_title := raw_title.strip_edges()
	if clean_title.is_empty():
		return {"added": false, "already_unlocked": false, "already_pending": false, "title": "", "unlocked_immediately": false}

	var target := character if character != null else get_active_character()
	var already_unlocked := target != null and target.unlocked_titles.has(clean_title)

	if current_run_completed and target != null:
		if not completed_run_titles.has(clean_title):
			completed_run_titles.append(clean_title)
			completed_run_titles = _order_titles_canonically(completed_run_titles)
		if not already_unlocked:
			target.unlocked_titles.append(clean_title)
			target.unlocked_titles = _order_titles_canonically(target.unlocked_titles)
			if not completed_run_newly_unlocked.has(clean_title):
				completed_run_newly_unlocked.append(clean_title)
				completed_run_newly_unlocked = _order_titles_canonically(completed_run_newly_unlocked)
			_save_and_emit_state()
		return {
			"added": not already_unlocked,
			"already_unlocked": already_unlocked,
			"already_pending": false,
			"title": clean_title,
			"unlocked_immediately": true
		}

	var already_pending := pending_run_titles.has(clean_title)
	if not already_pending:
		pending_run_titles.append(clean_title)
		run_state["pending_titles"] = Array(pending_run_titles)

	return {
		"added": not already_pending,
		"already_unlocked": already_unlocked,
		"already_pending": already_pending,
		"title": clean_title,
		"unlocked_immediately": false
	}


func complete_dungeon_run(character: CharacterProfile = null) -> Dictionary:
	## Marks the current dungeon run as beaten and permanently unlocks all pending titles collected in it.
	var target := character if character != null else get_active_character()
	var run_titles := _order_titles_canonically(pending_run_titles)
	var newly_unlocked := PackedStringArray()

	current_run_completed = true
	run_state["status"] = "completed"

	if target != null:
		for title in run_titles:
			if not target.unlocked_titles.has(title):
				target.unlocked_titles.append(title)
				newly_unlocked.append(title)
		target.unlocked_titles = _order_titles_canonically(target.unlocked_titles)

	completed_run_newly_unlocked = _order_titles_canonically(newly_unlocked)
	completed_run_titles = run_titles
	pending_run_titles = PackedStringArray()
	if run_state.has("pending_titles"):
		run_state.erase("pending_titles")
	_save_and_emit_state()

	return {
		"newly_unlocked": completed_run_newly_unlocked,
		"run_titles": completed_run_titles
	}


func get_completed_run_title_summary() -> Dictionary:
	return {
		"newly_unlocked": completed_run_newly_unlocked,
		"run_titles": completed_run_titles
	}


func set_character_title_selected(title: String, selected: bool, character: CharacterProfile = null) -> bool:
	## Single-title selection: equipping a title replaces any previously active title and recalculates stats.
	var target := character if character != null else get_active_character()
	var clean_title := title.strip_edges()
	if target == null or clean_title.is_empty():
		return false
	if selected and not target.unlocked_titles.has(clean_title):
		return false

	var prev_stats := get_character_stats(target)
	var prev_max_hp := maxi(int(round(float(prev_stats.get("max_health", 1)))), 1)
	var was_full_hp := target.current_health < 0 or target.current_health >= prev_max_hp

	if selected:
		target.selected_titles = PackedStringArray([clean_title])
	elif get_active_title(target) == clean_title:
		target.selected_titles = PackedStringArray()

	var new_stats := recalculate_character_stats(target)
	var new_max_hp := maxi(int(round(float(new_stats.get("max_health", 1)))), 1)
	if was_full_hp:
		target.current_health = new_max_hp
	else:
		target.current_health = clampi(target.current_health, 0, new_max_hp)

	_save_and_emit_state()
	return true


func clear_selected_character_titles(character: CharacterProfile = null) -> bool:
	var target := character if character != null else get_active_character()
	if target == null:
		return false
	var prev_stats := get_character_stats(target)
	var prev_max_hp := maxi(int(round(float(prev_stats.get("max_health", 1)))), 1)
	var was_full_hp := target.current_health < 0 or target.current_health >= prev_max_hp

	target.selected_titles = PackedStringArray()
	var new_stats := recalculate_character_stats(target)
	var new_max_hp := maxi(int(round(float(new_stats.get("max_health", 1)))), 1)
	if was_full_hp:
		target.current_health = new_max_hp
	else:
		target.current_health = clampi(target.current_health, 0, new_max_hp)

	_save_and_emit_state()
	return true


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
	return recalculate_character_stats(target)


func recalculate_character_stats(character: CharacterProfile) -> Dictionary:
	if character == null:
		return {}
	var class_data := get_character_class(character.class_id)
	if class_data == null:
		return {}

	var base := class_data.get_stats_at_level(character.level).duplicate(true)
	for attribute_id in character.attributes:
		base[String(attribute_id)] = character.attributes[attribute_id]

	var final_stats := base.duplicate(true)
	for stat_id in character.stat_modifiers:
		var stat_key := String(stat_id)
		final_stats[stat_key] = float(final_stats.get(stat_key, 0.0)) + float(character.stat_modifiers[stat_id])

	for slot in character.equipment:
		var equipped_value: Variant = character.equipment[slot]
		if not equipped_value is InventoryItem:
			continue
		var equipped_item := equipped_value as InventoryItem
		if equipped_item.item_data == null:
			continue
		var modifiers := get_item_stats(equipped_item)
		for stat_key in modifiers:
			var key_str := String(stat_key)
			var bonus := float(modifiers[stat_key])
			if key_str == "damage":
				final_stats["damage_min"] = float(final_stats.get("damage_min", 0.0)) + bonus
				final_stats["damage_max"] = float(final_stats.get("damage_max", 0.0)) + bonus
			else:
				final_stats[key_str] = float(final_stats.get(key_str, 0.0)) + bonus

	# Normalize legacy saves that had multiple titles selected to a single active title.
	var active_title := get_active_title(character)
	if active_title.is_empty():
		if not character.selected_titles.is_empty():
			character.selected_titles = PackedStringArray()
	elif character.selected_titles.size() != 1 or String(character.selected_titles[0]) != active_title:
		character.selected_titles = PackedStringArray([active_title])

	var title_buffs := get_title_buffs(active_title)
	for stat_key in title_buffs:
		var key_str := String(stat_key)
		var bonus := float(title_buffs[stat_key])
		if key_str == "damage":
			final_stats["damage_min"] = float(final_stats.get("damage_min", 0.0)) + bonus
			final_stats["damage_max"] = float(final_stats.get("damage_max", 0.0)) + bonus
		elif key_str in ["vision_bonus", "lifesteal"]:
			final_stats[key_str] = float(final_stats.get(key_str, 0.0)) + bonus
		else:
			final_stats[key_str] = float(final_stats.get(key_str, 0.0)) + bonus

	character.base_stats = base.duplicate(true)
	character.derived_stats = final_stats.duplicate(true)
	var max_health := maxi(int(round(float(final_stats.get("max_health", 1)))), 1)
	var max_mana := maxi(int(round(float(final_stats.get("max_mana", 0)))), 0)
	if character.current_health < 0:
		character.current_health = max_health
	else:
		character.current_health = clampi(character.current_health, 0, max_health)
	if character.current_mana < 0:
		character.current_mana = max_mana
	else:
		character.current_mana = clampi(character.current_mana, 0, max_mana)
	return character.derived_stats.duplicate(true)


func _recalculate_all_character_stats() -> void:
	for character in characters:
		recalculate_character_stats(character)


func _clamp_character_resources(character: CharacterProfile) -> void:
	if character == null:
		return
	var stats := get_character_stats(character)
	character.current_health = clampi(character.current_health, 0, maxi(int(round(float(stats.get("max_health", 1)))), 1))
	character.current_mana = clampi(character.current_mana, 0, maxi(int(round(float(stats.get("max_mana", 0)))), 0))


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


func can_character_use_shield(character: CharacterProfile = null) -> bool:
	var target := character if character != null else get_active_character()
	if target == null:
		return false
	return CLASS_VISUAL_HELPER.can_class_use_shield(target.class_id)


func get_equip_item_failure_reason(item: InventoryItem, character: CharacterProfile = null) -> String:
	var target := character if character != null else get_active_character()
	if target == null or target.inventory == null or item == null or item.item_data == null:
		return "Érvénytelen tárgy vagy aktív karakter."
	if item.amount != 1 or not target.inventory.items.has(item):
		return "Csak a hátizsákban lévő egyedi felszerelés vehető fel."
	var slot := item.item_data.equipment_slot
	if String(slot).is_empty() or slot == &"none":
		return "Ez a tárgy nem felszerelhető."
	if (slot == &"shield" or item.item_data.item_type == &"shield") and not can_character_use_shield(target):
		var cls_data := get_character_class(target.class_id)
		var cls_name := cls_data.display_name if cls_data != null else String(target.class_id)
		return "A(z) %s osztály nem használhat pajzsot (nincs blokkolás animációja)." % cls_name
	if not target.equipment.has(slot):
		return ""
	var currently_equipped := target.equipment[slot] as InventoryItem
	if currently_equipped == null:
		return ""

	# Test the swap in a temporary inventory before mutating the real state.
	var simulation := _copy_inventory(target.inventory)
	var simulated_source := simulation.get_item_at_cell(item.position)
	if simulated_source == null:
		return "A tárgy nem található a hátizsákban."
	simulation.items.erase(simulated_source)
	if simulation.find_free_position(currently_equipped.item_data) == Vector2i(-1, -1):
		return "Nincs elég szabad hely a hátizsákban a lecserélt tárgynak."
	return ""


func can_equip_item(item: InventoryItem, character: CharacterProfile = null) -> bool:
	return get_equip_item_failure_reason(item, character).is_empty()


func equip_item(item: InventoryItem, character: CharacterProfile = null) -> bool:
	## Move an item from the specified character's backpack into its equipment slot.
	## If the slot was occupied, the previous item is returned to the backpack if it fits.
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
	item.position = Vector2i(-1, -1)
	target.equipment[slot] = item
	recalculate_character_stats(target)
	target.inventory.inventory_changed.emit()
	return true


func can_unequip_item(slot: StringName, character: CharacterProfile = null) -> bool:
	var target := character if character != null else get_active_character()
	if target == null or target.inventory == null:
		return false
	var equipped := target.equipment.get(slot, null) as InventoryItem
	return equipped != null and equipped.item_data != null and target.inventory.find_free_position(equipped.item_data) != Vector2i(-1, -1)


func unequip_item(slot: StringName, character: CharacterProfile = null) -> bool:
	var target := character if character != null else get_active_character()
	if not can_unequip_item(slot, target):
		return false
	var equipped := target.equipment[slot] as InventoryItem
	var free_position := target.inventory.find_free_position(equipped.item_data)
	if free_position == Vector2i(-1, -1):
		return false
	target.equipment.erase(slot)
	equipped.position = free_position
	target.inventory.items.append(equipped)
	recalculate_character_stats(target)
	target.inventory.inventory_changed.emit()
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

func _build_character_profile(clean_name: String, archetype: StringName) -> CharacterProfile:
	var character := CharacterProfile.new()
	character.id = _generate_character_id()
	character.character_name = clean_name
	character.class_id = archetype
	character.level = 1
	character.xp = 0
	var class_data := get_character_class(archetype)
	var initial_stats := class_data.get_stats_at_level(1) if class_data != null else {"max_health": 30, "max_mana": 0}
	character.current_health = int(initial_stats.get("max_health", 30))
	character.current_mana = int(initial_stats.get("max_mana", 0))
	character.stress = 0
	character.equipment = {}
	character.inventory = _new_inventory(BACKPACK_WIDTH, BACKPACK_HEIGHT)
	return character


func create_character(character_name: String, archetype: StringName = &"") -> bool:
	var clean_name := character_name.strip_edges()
	if clean_name.is_empty():
		return false
	if get_character_class(archetype) == null:
		push_warning("Ismeretlen karakterosztály: " + String(archetype))
		return false

	for existing in characters:
		if existing.character_name.strip_edges().to_lower() == clean_name.to_lower():
			return false

	var character := _build_character_profile(clean_name, archetype)
	_setup_starting_inventory(character)

	characters.append(character)
	_connect_inventory(character.inventory)
	active_character_id = character.id
	_sync_coin_items_to_gold(false)
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
	if _item_data_cache.has(item_id):
		return _item_data_cache[item_id] as ItemData
	var found := _find_item_data_by_id(ITEM_DATA_DIRECTORY, item_id)
	if found != null:
		_item_data_cache[item_id] = found
	return found


func consume_active_character_item(item_id: StringName, amount: int = 1) -> bool:
	var inventory := get_active_inventory()
	if inventory == null or amount <= 0:
		return false
	if get_item_count(item_id, false) < amount:
		return false
	var remaining := _consume_item_quantity(inventory, item_id, amount)
	if remaining > 0:
		return false
	inventory.inventory_changed.emit()
	_save_and_emit_state()
	return true


func is_consumable_item(item: InventoryItem) -> bool:
	return item != null and item.item_data != null and item.item_data.item_type == &"consumable"


func get_consumable_heal_amount(item_data: ItemData) -> int:
	if item_data == null or item_data.item_type != &"consumable":
		return 0
	var heal_value := int(round(float(item_data.base_stats.get("heal_amount", 0.0))))
	if heal_value <= 0 and item_data.id == &"health_potion":
		heal_value = 40
	return maxi(heal_value, 0)


func get_use_consumable_failure_reason(item: InventoryItem, character: CharacterProfile = null) -> String:
	var target := character if character != null else get_active_character()
	if target == null or target.inventory == null:
		return "Nincs aktív karakter."
	if not is_consumable_item(item) or item.amount <= 0:
		return "Ez a tárgy nem használható el."
	if not target.inventory.items.has(item):
		return "Csak a hátizsákban lévő tárgy használható."
	var heal_amount := get_consumable_heal_amount(item.item_data)
	if heal_amount <= 0:
		return "Ennek a tárgynak nincs használható hatása."
	var stats := get_character_stats(target)
	var max_health := maxi(int(round(float(stats.get("max_health", 1)))), 1)
	var current_hp := target.current_health if target.current_health >= 0 else max_health
	if current_hp <= 0:
		return "Az elesett hős nem tud gyógyitalt használni."
	if current_hp >= max_health:
		return "Az életerőd már tele van."
	return ""


func can_use_consumable_item(item: InventoryItem, character: CharacterProfile = null) -> bool:
	return get_use_consumable_failure_reason(item, character).is_empty()


func use_consumable_item(item: InventoryItem, character: CharacterProfile = null) -> Dictionary:
	var target := character if character != null else get_active_character()
	var item_name := item.item_data.display_name if (item != null and item.item_data != null) else "Tárgy"
	var failure_reason := get_use_consumable_failure_reason(item, target)
	if not failure_reason.is_empty():
		return {
			"ok": false,
			"healed": 0,
			"message": failure_reason,
			"item_name": item_name,
			"consumed_stack": false
		}

	var stats := get_character_stats(target)
	var max_health := maxi(int(round(float(stats.get("max_health", 1)))), 1)
	var before_hp := clampi(target.current_health if target.current_health >= 0 else max_health, 0, max_health)
	var heal_amount := get_consumable_heal_amount(item.item_data)
	var after_hp := clampi(before_hp + heal_amount, 0, max_health)
	var actual_healed := after_hp - before_hp

	item.amount -= 1
	var consumed_stack := false
	if item.amount <= 0:
		target.inventory.items.erase(item)
		consumed_stack = true

	target.current_health = after_hp
	target.inventory.inventory_changed.emit()

	return {
		"ok": true,
		"healed": actual_healed,
		"message": "Elhasználva: %s (+%d ÉP)." % [item_name, actual_healed],
		"item_name": item_name,
		"consumed_stack": consumed_stack
	}


func use_consumable_by_id(item_id: StringName, character: CharacterProfile = null) -> Dictionary:
	var target := character if character != null else get_active_character()
	if target == null or target.inventory == null:
		return {
			"ok": false,
			"healed": 0,
			"message": "Nincs aktív karakter.",
			"item_name": "",
			"consumed_stack": false
		}
	for item in target.inventory.items:
		if item != null and item.item_data != null and item.item_data.id == item_id and item.amount > 0:
			return use_consumable_item(item, target)
	return {
		"ok": false,
		"healed": 0,
		"message": "Nincs gyógyital a hátizsákban.",
		"item_name": "",
		"consumed_stack": false
	}


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

func _count_item_in_inventory(inventory: Inventory, item_id: StringName) -> int:
	if inventory == null or String(item_id).is_empty():
		return 0
	var total := 0
	for item in inventory.items:
		if item != null and item.item_data != null and item.item_data.id == item_id:
			total += item.amount
	return total


func get_item_count(item_id: StringName, include_stash: bool = true) -> int:
	var total := _count_item_in_inventory(get_active_inventory(), item_id)
	if include_stash:
		total += _count_item_in_inventory(stash, item_id)
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
	if not spend_gold(recipe.gold_cost, false):
		return false
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
	if not spend_gold(recipe.gold_cost, false):
		return false
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
	if not spend_gold(enchantment.gold_cost, false):
		return false
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
	active_character_id = ""
	gold = STARTING_GOLD
	run_state.clear()
	pending_run_titles = PackedStringArray()
	completed_run_newly_unlocked = PackedStringArray()
	completed_run_titles = PackedStringArray()
	current_run_completed = false
	stash = _new_inventory(STASH_WIDTH, STASH_HEIGHT)
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


func _setup_starting_inventory(target: Variant) -> void:
	var character: CharacterProfile = target as CharacterProfile
	var target_inventory: Inventory = character.inventory if character != null else target as Inventory
	if target_inventory == null:
		return

	if character != null:
		var class_data := get_character_class(character.class_id)
		if class_data != null:
			for raw_item_id in class_data.starting_equipment_ids:
				var item_id := StringName(String(raw_item_id).strip_edges())
				if String(item_id).is_empty():
					continue
				var item_data := get_item_data(item_id)
				if item_data == null:
					push_warning("Hiányzó kezdőtárgy az osztályhoz (%s): %s" % [String(character.class_id), String(item_id)])
					continue
				var amount := _get_starting_item_amount(character.class_id, item_id)
				var is_shield_item := item_data.equipment_slot == &"shield" or item_data.item_type == &"shield"
				if (
					amount == 1
					and item_data.equipment_slot != &""
					and item_data.equipment_slot != &"none"
					and (not is_shield_item or can_character_use_shield(character))
					and not character.equipment.has(item_data.equipment_slot)
				):
					var equipped := InventoryItem.new()
					equipped.item_data = item_data
					equipped.position = Vector2i(-1, -1)
					equipped.amount = 1
					character.equipment[item_data.equipment_slot] = equipped
				else:
					target_inventory.try_add_item(item_data, amount)

	var potion := get_item_data(&"health_potion")
	if potion != null:
		target_inventory.try_add_item(potion, 3)


func _get_starting_item_amount(class_id: StringName, item_id: StringName) -> int:
	if item_id == &"arrow":
		if class_id == &"soldier":
			return 10
		if class_id == &"archer":
			return 24
		return 15
	return 1


# -----------------------------------------------------------------------------
# Economy: purchases, sales and synchronized gold coins
# -----------------------------------------------------------------------------

func add_gold(amount: int, emit_changes: bool = true) -> void:
	if amount <= 0:
		return
	gold += amount
	_sync_coin_items_to_gold(emit_changes)
	if emit_changes:
		_save_and_emit_state()


func grant_dungeon_loot(gold_amount: int, material_drops: Array) -> Dictionary:
	## Grants gold coins and crafting materials from a dungeon loot bag into the active backpack (overflowing to camp stash).
	var added_gold: int = maxi(0, gold_amount)
	if added_gold > 0:
		add_gold(added_gold, false)

	var active_inv := get_active_inventory()
	var touched_invs: Array[Inventory] = []
	var granted_items: Array[Dictionary] = []

	for raw_entry in material_drops:
		if not (raw_entry is Dictionary):
			continue
		var entry: Dictionary = raw_entry as Dictionary
		var item_id := StringName(String(entry.get("item_id", "")).strip_edges())
		var amount: int = int(entry.get("amount", 0))
		if String(item_id).is_empty() or amount <= 0:
			continue
		var item_data := get_item_data(item_id)
		if item_data == null:
			continue

		var remaining: int = amount
		var to_backpack: int = 0
		var to_stash: int = 0

		if active_inv != null:
			var left_after_bp: int = active_inv.try_add_item(item_data, remaining, false)
			to_backpack = remaining - left_after_bp
			remaining = left_after_bp
			if to_backpack > 0 and not touched_invs.has(active_inv):
				touched_invs.append(active_inv)

		if remaining > 0 and stash != null:
			var left_after_stash: int = stash.try_add_item(item_data, remaining, false)
			to_stash = remaining - left_after_stash
			remaining = left_after_stash
			if to_stash > 0 and not touched_invs.has(stash):
				touched_invs.append(stash)

		var total_added: int = to_backpack + to_stash
		if total_added > 0:
			granted_items.append({
				"item_id": item_id,
				"display_name": item_data.display_name,
				"description": item_data.description,
				"icon": item_data.icon,
				"amount": total_added,
				"added_to_backpack": to_backpack,
				"added_to_stash": to_stash
			})

	for inv in touched_invs:
		inv.inventory_changed.emit()

	_save_and_emit_state()
	return {
		"gold": added_gold,
		"items": granted_items
	}


func spend_gold(amount: int, emit_changes: bool = true) -> bool:
	if amount < 0 or gold < amount:
		return false
	if amount > 0:
		gold -= amount
		_sync_coin_items_to_gold(emit_changes)
	if emit_changes:
		_save_and_emit_state()
	return true


func _get_currency_inventories() -> Array[Inventory]:
	var result: Array[Inventory] = []
	var active_inv := get_active_inventory()
	if active_inv != null:
		result.append(active_inv)
	if stash != null and not result.has(stash):
		result.append(stash)
	for character in characters:
		if character != null and character.inventory != null and not result.has(character.inventory):
			result.append(character.inventory)
	return result


func _count_gold_coins() -> int:
	var total := 0
	for inv in _get_currency_inventories():
		total += _count_item_in_inventory(inv, &"gold_coin")
	return total


func _inventory_has_item_id(inventory: Inventory, item_id: StringName) -> bool:
	if inventory == null:
		return false
	for inventory_item in inventory.items:
		if inventory_item != null and inventory_item.item_data != null and inventory_item.item_data.id == item_id:
			return true
	return false


func _sync_coin_items_to_gold(emit_inventory_signals: bool = false) -> void:
	var coin_data := get_item_data(&"gold_coin")
	if coin_data == null:
		return

	var inventories := _get_currency_inventories()
	if inventories.is_empty():
		return

	var target_gold := maxi(gold, 0)
	var current_coins := _count_gold_coins()
	if current_coins == target_gold:
		return

	var touched: Array[Inventory] = []
	if current_coins > target_gold:
		var to_remove := current_coins - target_gold
		for inv in inventories:
			if to_remove <= 0:
				break
			var before := _count_item_in_inventory(inv, &"gold_coin")
			if before <= 0:
				continue
			to_remove = _consume_item_quantity(inv, &"gold_coin", to_remove)
			if _count_item_in_inventory(inv, &"gold_coin") != before:
				touched.append(inv)
	else:
		var to_add := target_gold - current_coins
		# First top up inventories that already hold gold coins so coins stay consolidated.
		for inv in inventories:
			if to_add <= 0:
				break
			if not _inventory_has_item_id(inv, &"gold_coin"):
				continue
			var before := _count_item_in_inventory(inv, &"gold_coin")
			to_add = inv.try_add_item(coin_data, to_add, false)
			if _count_item_in_inventory(inv, &"gold_coin") != before and not touched.has(inv):
				touched.append(inv)
		# Otherwise place the coin stack in the active backpack (or stash fallback).
		for inv in inventories:
			if to_add <= 0:
				break
			var before := _count_item_in_inventory(inv, &"gold_coin")
			to_add = inv.try_add_item(coin_data, to_add, false)
			if _count_item_in_inventory(inv, &"gold_coin") != before and not touched.has(inv):
				touched.append(inv)

	if emit_inventory_signals:
		for inv in touched:
			inv.inventory_changed.emit()


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

	spend_gold(total_price, true)
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

	if not spend_gold(item_data.buy_price * amount, false):
		return false
	# Inventory UI and the save manager both refresh from this single signal.
	inventory.inventory_changed.emit()
	if stash != null:
		stash.inventory_changed.emit()
	return true


func sell_item(inventory_item: InventoryItem) -> bool:
	var inventory := get_active_inventory()
	if inventory_item == null or inventory_item.item_data == null or inventory == null:
		return false
	if inventory_item.item_data.id == &"gold_coin":
		return false
	if not inventory.items.has(inventory_item):
		return false

	var sell_price := inventory_item.item_data.sell_price * inventory_item.amount
	if sell_price <= 0:
		return false
	if not inventory.remove_item(inventory_item):
		return false

	add_gold(sell_price, true)
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
	_recalculate_all_character_stats()
	save_autosave()
	state_changed.emit()


func _save_and_emit_state() -> void:
	if not _loading_save:
		_recalculate_all_character_stats()
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
	_ensure_saves_directory()
	current_save_slot = slot
	return _write_save_file(_manual_save_path(slot))


func save_autosave() -> bool:
	if _loading_save or characters.is_empty():
		return false
	_ensure_saves_directory()
	return _write_save_file(_autosave_path())


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
	return FileAccess.file_exists(_autosave_path())


func load_autosave() -> bool:
	if not has_autosave() or not _load_game(_autosave_path()):
		return false
	state_changed.emit()
	characters_changed.emit()
	active_character_changed.emit(active_character_id)
	return true


func get_save_slot_summary(slot: int) -> Dictionary:
	if slot < 1 or slot > MANUAL_SAVE_SLOT_COUNT:
		return {"exists": false, "file_exists": false, "corrupt": false, "label": "Érvénytelen hely"}
	return _read_save_summary(_manual_save_path(slot), "Hely %d" % slot)


func get_autosave_summary() -> Dictionary:
	return _read_save_summary(_autosave_path(), "Automatikus")


func _read_save_summary(path: String, label_prefix: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {"exists": false, "file_exists": false, "corrupt": false, "label": "Üres mentési hely"}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {"exists": false, "file_exists": true, "corrupt": true, "label": "Nem olvasható mentés"}
	var parser := JSON.new()
	var error := parser.parse(file.get_as_text())
	file.close()
	if error != OK or typeof(parser.data) != TYPE_DICTIONARY:
		return {"exists": false, "file_exists": true, "corrupt": true, "label": "Hibás mentés"}

	var data: Dictionary = parser.data
	var characters_data: Array = data.get("characters", [])
	var hero_entry: Dictionary = {}
	var active_id := str(data.get("active_character_id", ""))
	for entry in characters_data:
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		if hero_entry.is_empty():
			hero_entry = entry
		if not active_id.is_empty() and str(entry.get("id", "")) == active_id:
			hero_entry = entry
			break

	var hero_name := str(hero_entry.get("name", "Kalandor"))
	var cls_id := StringName(str(hero_entry.get("class_id", hero_entry.get("archetype", ""))))
	var cls_data := get_character_class(cls_id)
	var cls_name := cls_data.display_name if cls_data != null else String(cls_id)
	var hero_level := maxi(int(hero_entry.get("level", 1)), 1)
	var saved_gold := int(data.get("gold", 0))
	var summary_label := "%s — %s" % [label_prefix, hero_name]
	if not cls_name.is_empty():
		summary_label += " (%s, Lv.%d)" % [cls_name, hero_level]
	summary_label += " · %d karakter · %d arany" % [characters_data.size(), saved_gold]

	return {
		"exists": true,
		"file_exists": true,
		"corrupt": false,
		"label": summary_label,
		"character_name": hero_name,
		"class_name": cls_name,
		"level": hero_level,
		"character_count": characters_data.size(),
		"gold": saved_gold
	}


func delete_save_slot(slot: int) -> bool:
	if slot < 1 or slot > MANUAL_SAVE_SLOT_COUNT:
		return false
	var path := _manual_save_path(slot)
	if not FileAccess.file_exists(path):
		return false
	var err := DirAccess.remove_absolute(path)
	if err != OK:
		push_warning("Nem sikerült törölni a mentést (%s): %s" % [path, error_string(err)])
		return false
	if current_save_slot == slot:
		_reset_if_in_menu()
	return true


func delete_autosave() -> bool:
	var path := _autosave_path()
	if not FileAccess.file_exists(path):
		return false
	var err := DirAccess.remove_absolute(path)
	if err != OK:
		push_warning("Nem sikerült törölni az automatikus mentést (%s): %s" % [path, error_string(err)])
		return false
	return true


func delete_saves(slots: Array[int], include_autosave: bool = false) -> int:
	var deleted_count := 0
	for slot in slots:
		if delete_save_slot(slot):
			deleted_count += 1
	if include_autosave and delete_autosave():
		deleted_count += 1
	if deleted_count > 0:
		_reset_if_in_menu()
	return deleted_count


func _reset_if_in_menu() -> void:
	var current_scene := get_tree().current_scene if get_tree() != null else null
	if current_scene == null or current_scene.name == "MainMenu":
		_loading_save = true
		_create_new_game()
		_loading_save = false
		_connect_all_inventories()
		state_changed.emit()
		characters_changed.emit()
		active_character_changed.emit(active_character_id)


func start_new_game(slot: int, character_name: String = "", class_id: StringName = &"") -> bool:
	if slot < 1 or slot > MANUAL_SAVE_SLOT_COUNT:
		return false
	var clean_name := character_name.strip_edges()
	if clean_name.is_empty():
		push_warning("Új mentés indításához kötelező karakternevet megadni.")
		return false
	if get_character_class(class_id) == null:
		push_warning("Új mentés indításához érvényes karakterosztály szükséges: " + String(class_id))
		return false

	_loading_save = true
	_create_new_game()
	var starter := _build_character_profile(clean_name, class_id)
	_setup_starting_inventory(starter)
	characters.append(starter)
	active_character_id = starter.id
	_sync_coin_items_to_gold(false)
	_loading_save = false

	current_save_slot = slot
	_connect_all_inventories()
	_recalculate_all_character_stats()
	var saved := save_to_slot(slot)
	state_changed.emit()
	characters_changed.emit()
	active_character_changed.emit(active_character_id)
	return saved


func _manual_save_path(slot: int) -> String:
	return get_saves_directory().path_join(MANUAL_SAVE_FILENAME_TEMPLATE % slot)


func _autosave_path() -> String:
	return get_saves_directory().path_join(AUTOSAVE_FILENAME)


func _start_autosave_timer() -> void:
	_autosave_timer = Timer.new()
	_autosave_timer.name = "AutosaveTimer"
	_autosave_timer.wait_time = AUTOSAVE_INTERVAL_SECONDS
	_autosave_timer.one_shot = false
	_autosave_timer.autostart = true
	_autosave_timer.timeout.connect(_on_autosave_timeout)
	add_child(_autosave_timer)
	call_deferred("_bind_autosave_settings")


func _bind_autosave_settings() -> void:
	var sm := get_node_or_null("/root/SettingsManager")
	if sm != null and sm.has_signal("settings_changed"):
		if not sm.settings_changed.is_connected(_apply_autosave_settings):
			sm.settings_changed.connect(_apply_autosave_settings)
	_apply_autosave_settings()


func _apply_autosave_settings() -> void:
	if _autosave_timer == null or not is_instance_valid(_autosave_timer):
		return
	var sm := get_node_or_null("/root/SettingsManager")
	var enabled := true
	var interval := AUTOSAVE_INTERVAL_SECONDS
	if sm != null:
		enabled = bool(sm.get("autosave_enabled"))
		interval = clampf(float(sm.get("autosave_interval_seconds")), 15.0, 600.0)
	var interval_changed := not is_equal_approx(_autosave_timer.wait_time, interval)
	_autosave_timer.wait_time = interval
	if enabled:
		if _autosave_timer.is_stopped() or interval_changed:
			_autosave_timer.start()
	else:
		_autosave_timer.stop()


func _on_autosave_timeout() -> void:
	var sm := get_node_or_null("/root/SettingsManager")
	if sm != null and not bool(sm.get("autosave_enabled")):
		return
	var current_scene := get_tree().current_scene if get_tree() != null else null
	if current_scene != null and current_scene.name == "MainMenu":
		return
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
	gold = int(save_data.get("gold", STARTING_GOLD))
	characters.clear()

	var stored_characters: Array = save_data.get("characters", [])
	for character_entry in stored_characters:
		if typeof(character_entry) != TYPE_DICTIONARY:
			continue
		var character := CharacterProfile.new()
		character.id = str(character_entry.get("id", ""))
		if character.id.is_empty():
			character.id = _generate_character_id()
		character.character_name = str(character_entry.get("name", "Kalandor"))
		var stored_class_id := StringName(str(character_entry.get("class_id", character_entry.get("archetype", ""))))
		if get_character_class(stored_class_id) == null:
			push_warning("A mentett karakter osztálya nem található (" + String(stored_class_id) + "); alapértelmezett osztályra állítva.")
			if get_character_class(&"swordsman") != null:
				stored_class_id = &"swordsman"
			elif not character_classes.is_empty():
				stored_class_id = character_classes.keys()[0]
		character.class_id = stored_class_id
		character.level = max(int(character_entry.get("level", 1)), 1)
		character.xp = max(int(character_entry.get("xp", 0)), 0)
		character.stress = clampi(int(character_entry.get("stress", 0)), 0, 100)
		var stored_quirks: Array = character_entry.get("quirk_ids", [])
		character.quirk_ids = PackedStringArray()
		for quirk_id in stored_quirks:
			character.quirk_ids.append(str(quirk_id))
		var stored_unlocked_titles: Variant = character_entry.get("unlocked_titles", [])
		var loaded_unlocked := PackedStringArray()
		if typeof(stored_unlocked_titles) == TYPE_ARRAY:
			for raw_title in stored_unlocked_titles:
				var clean_t := str(raw_title).strip_edges()
				if not clean_t.is_empty() and not loaded_unlocked.has(clean_t):
					loaded_unlocked.append(clean_t)
		character.unlocked_titles = _order_titles_canonically(loaded_unlocked)
		var stored_selected_titles: Variant = character_entry.get("selected_titles", [])
		var loaded_selected := PackedStringArray()
		if typeof(stored_selected_titles) == TYPE_ARRAY:
			for raw_sel in stored_selected_titles:
				var clean_s := str(raw_sel).strip_edges()
				if not clean_s.is_empty() and character.unlocked_titles.has(clean_s) and not loaded_selected.has(clean_s):
					loaded_selected.append(clean_s)
		character.selected_titles = _order_titles_canonically(loaded_selected)
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
		var stored_base_stats: Variant = character_entry.get("base_stats", {})
		character.base_stats = stored_base_stats.duplicate(true) if typeof(stored_base_stats) == TYPE_DICTIONARY else {}
		var stored_derived_stats: Variant = character_entry.get("derived_stats", {})
		character.derived_stats = stored_derived_stats.duplicate(true) if typeof(stored_derived_stats) == TYPE_DICTIONARY else {}
		character.equipment = _deserialize_equipment(character_entry.get("equipment", {}))
		character.inventory = _deserialize_inventory(
			character_entry.get("inventory", {}),
			BACKPACK_WIDTH,
			BACKPACK_HEIGHT
		)
		characters.append(character)
		var stats_after_load := get_character_stats(character)
		var max_health := maxi(int(round(float(stats_after_load.get("max_health", 30)))), 1)
		var max_mana := maxi(int(round(float(stats_after_load.get("max_mana", 0)))), 0)
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
	_sync_coin_items_to_gold(false)
	_connect_all_inventories()
	_recalculate_all_character_stats()
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
