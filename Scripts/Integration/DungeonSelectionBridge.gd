extends Node

## Lobby-side contract for the dungeon team's generator.
## This service only discovers selection resources and publishes a selected
## configuration. It does not generate maps, spawn enemies, or change scenes.

signal selection_changed(configuration: Dictionary)
signal dungeon_launch_requested(configuration: Dictionary)

const DUNGEON_DIRECTORY := "res://Data/Dungeons"
const DIFFICULTY_DIRECTORY := "res://Data/DungeonDifficulties"

var _dungeons: Dictionary = {}
var _difficulties: Dictionary = {}
var _selected_configuration: Dictionary = {}


func _ready() -> void:
	_reload_catalog()


func reload_catalog() -> void:
	_reload_catalog()


func _reload_catalog() -> void:
	_dungeons.clear()
	_difficulties.clear()
	_load_resources(DUNGEON_DIRECTORY, true)
	_load_resources(DIFFICULTY_DIRECTORY, false)
	if _dungeons.is_empty():
		push_warning("DungeonSelection: nem található dungeon-adat a Data/Dungeons mappában.")


func _load_resources(directory_path: String, is_dungeon: bool) -> void:
	var paths: Array[String] = []
	_collect_resource_paths(directory_path, paths)
	paths.sort()
	for resource_path in paths:
		var resource := load(resource_path)
		if is_dungeon:
			if not resource is DungeonDefinition:
				continue
			var dungeon := resource as DungeonDefinition
			var dungeon_id := String(dungeon.id).strip_edges()
			if dungeon_id.is_empty() or _dungeons.has(dungeon_id):
				push_warning("DungeonSelection: hibás vagy duplikált dungeon ID: " + resource_path)
				continue
			_dungeons[dungeon_id] = dungeon
		else:
			if not resource is DungeonDifficultyData:
				continue
			var difficulty := resource as DungeonDifficultyData
			var linked_dungeon_id := String(difficulty.dungeon_id).strip_edges()
			var difficulty_id := String(difficulty.id).strip_edges()
			if linked_dungeon_id.is_empty() or difficulty_id.is_empty() or not _dungeons.has(linked_dungeon_id):
				push_warning("DungeonSelection: érvénytelen dungeon-nehezség hivatkozás: " + resource_path)
				continue
			var key := _difficulty_key(linked_dungeon_id, difficulty_id)
			if _difficulties.has(key):
				push_warning("DungeonSelection: duplikált nehézség: " + key)
				continue
			if difficulty.enemy_level_max < difficulty.enemy_level_min:
				difficulty.enemy_level_max = difficulty.enemy_level_min
			_difficulties[key] = difficulty


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


func get_available_dungeons() -> Array[DungeonDefinition]:
	var result: Array[DungeonDefinition] = []
	for value in _dungeons.values():
		if value is DungeonDefinition:
			result.append(value as DungeonDefinition)
	result.sort_custom(_sort_dungeons)
	return result


func get_dungeon(dungeon_id: StringName) -> DungeonDefinition:
	return _dungeons.get(String(dungeon_id), null) as DungeonDefinition


func get_available_difficulties(dungeon_id: StringName) -> Array[DungeonDifficultyData]:
	var result: Array[DungeonDifficultyData] = []
	for value in _difficulties.values():
		if not value is DungeonDifficultyData:
			continue
		var difficulty := value as DungeonDifficultyData
		if difficulty.dungeon_id == dungeon_id:
			result.append(difficulty)
	result.sort_custom(_sort_difficulties)
	return result


func get_difficulty(dungeon_id: StringName, difficulty_id: StringName) -> DungeonDifficultyData:
	return _difficulties.get(_difficulty_key(dungeon_id, difficulty_id), null) as DungeonDifficultyData


func get_selected_configuration() -> Dictionary:
	return _selected_configuration.duplicate(true)


func submit_selection(dungeon_id: StringName, difficulty_id: StringName) -> Dictionary:
	var dungeon := get_dungeon(dungeon_id)
	var difficulty := get_difficulty(dungeon_id, difficulty_id)
	if dungeon == null or difficulty == null:
		return {
			"ok": false,
			"message": "A kiválasztott dungeon vagy nehézség nem található az adatfájlok között."
		}

	var enemy_ids: Array[String] = []
	for enemy_id in difficulty.enemy_type_ids:
		enemy_ids.append(String(enemy_id))
	var enemy_names: Array[String] = []
	for enemy_name in difficulty.enemy_type_names:
		enemy_names.append(String(enemy_name))

	_selected_configuration = {
		"config_version": 1,
		"dungeon_id": String(dungeon.id),
		"dungeon_name": dungeon.display_name,
		"difficulty_id": String(difficulty.id),
		"difficulty_name": difficulty.display_name,
		"scene_path": dungeon.scene_path,
		"recommended_level_min": dungeon.recommended_level_min,
		"recommended_level_max": dungeon.recommended_level_max,
		"base_spawn_rate_multiplier": dungeon.base_spawn_rate_multiplier,
		"spawn_rate_multiplier": dungeon.base_spawn_rate_multiplier * difficulty.spawn_rate_multiplier,
		"encounter_count_multiplier": difficulty.encounter_count_multiplier,
		"enemy_level_min": difficulty.enemy_level_min,
		"enemy_level_max": maxi(difficulty.enemy_level_min, difficulty.enemy_level_max),
		"enemy_type_ids": enemy_ids,
		"enemy_type_names": enemy_names,
		"elite_spawn_chance": difficulty.elite_spawn_chance
	}
	selection_changed.emit(_selected_configuration.duplicate(true))
	dungeon_launch_requested.emit(_selected_configuration.duplicate(true))
	return {
		"ok": true,
		"configuration": _selected_configuration.duplicate(true),
		"message": "A dungeonválasztás átadásra került. A tényleges pályaindítást a Dungeon-generátor integrációja végzi."
	}


func clear_selection() -> void:
	_selected_configuration.clear()
	selection_changed.emit({})


func _difficulty_key(dungeon_id: StringName, difficulty_id: StringName) -> String:
	return "%s::%s" % [String(dungeon_id), String(difficulty_id)]


func _sort_dungeons(a: DungeonDefinition, b: DungeonDefinition) -> bool:
	return a.display_name.naturalnocasecmp_to(b.display_name) < 0


func _sort_difficulties(a: DungeonDifficultyData, b: DungeonDifficultyData) -> bool:
	if a.sort_order == b.sort_order:
		return a.display_name.naturalnocasecmp_to(b.display_name) < 0
	return a.sort_order < b.sort_order
