extends Node

const RESOURCE_CATALOG := preload("res://Scripts/Utils/ResourceCatalog.gd")

## Global dungeon-selection/configuration service.
## The actual dungeon scene can read GameState.run_state after scene transition.
signal configuration_prepared(configuration: Dictionary)
signal dungeon_started(configuration: Dictionary)

const DUNGEON_DIRECTORY := "res://Data/Dungeons"
const DIFFICULTY_DIRECTORY := "res://Data/DungeonDifficulties"

var dungeons: Dictionary = {}
var difficulties: Dictionary = {}
var _run_rng := RandomNumberGenerator.new()


# -----------------------------------------------------------------------------
# Initialization and data-driven configuration discovery
# -----------------------------------------------------------------------------

func _ready() -> void:
	_load_dungeons()
	_load_difficulties()
	if dungeons.is_empty():
		push_warning("Nem található dungeon definíció a következő mappában: " + DUNGEON_DIRECTORY)
	if GameState.run_state.has("seed"):
		_run_rng.seed = int(GameState.run_state.get("seed", 0))


# -----------------------------------------------------------------------------
# Read-only configuration API for the UI and gameplay systems
# -----------------------------------------------------------------------------

func get_available_dungeons() -> Array[DungeonDefinition]:
	var result: Array[DungeonDefinition] = []
	for value in dungeons.values():
		if value is DungeonDefinition:
			result.append(value as DungeonDefinition)
	result.sort_custom(_sort_dungeons)
	return result


func get_dungeon(dungeon_id: StringName) -> DungeonDefinition:
	return dungeons.get(String(dungeon_id), null) as DungeonDefinition


func get_available_difficulties(dungeon_id: StringName) -> Array[DungeonDifficultyData]:
	var result: Array[DungeonDifficultyData] = []
	for value in difficulties.values():
		if not value is DungeonDifficultyData:
			continue
		var difficulty := value as DungeonDifficultyData
		if difficulty.dungeon_id == dungeon_id:
			result.append(difficulty)
	result.sort_custom(_sort_difficulties)
	return result


func get_difficulty(dungeon_id: StringName, difficulty_id: StringName) -> DungeonDifficultyData:
	return difficulties.get(_difficulty_key(dungeon_id, difficulty_id), null) as DungeonDifficultyData


func get_run_configuration() -> Dictionary:
	## Safe copy of the current dungeon run settings for the gameplay scripts.
	return GameState.run_state.duplicate(true)


func get_spawn_rate_multiplier() -> float:
	## > 1.0 means enemies spawn more often; < 1.0 means less often.
	return maxf(float(GameState.run_state.get("spawn_rate_multiplier", 1.0)), 0.05)


func roll_enemy_level() -> int:
	## Uses the selected difficulty's inclusive enemy level range.
	var minimum := maxi(int(GameState.run_state.get("enemy_level_min", 1)), 1)
	var maximum := maxi(int(GameState.run_state.get("enemy_level_max", minimum)), minimum)
	return _run_rng.randi_range(minimum, maximum)


func roll_enemy_type_id() -> StringName:
	## Returns a configured enemy ID; the team's spawner maps this ID to its enemy scene/data.
	var enemy_ids: Array = GameState.run_state.get("enemy_type_ids", [])
	if enemy_ids.is_empty():
		return &""
	return StringName(str(enemy_ids[_run_rng.randi_range(0, enemy_ids.size() - 1)]))


# -----------------------------------------------------------------------------
# Build and start a dungeon run
# -----------------------------------------------------------------------------

func get_launch_configuration(dungeon_id: StringName, difficulty_id: StringName) -> Dictionary:
	var dungeon := get_dungeon(dungeon_id)
	var difficulty := get_difficulty(dungeon_id, difficulty_id)
	if dungeon == null or difficulty == null:
		return {}

	var enemy_type_ids: Array[String] = []
	for enemy_id in difficulty.enemy_type_ids:
		enemy_type_ids.append(String(enemy_id))
	var enemy_type_names: Array[String] = []
	for enemy_name in difficulty.enemy_type_names:
		enemy_type_names.append(String(enemy_name))

	return {
		"config_version": 1,
		"dungeon_id": String(dungeon.id),
		"dungeon_name": dungeon.display_name,
		"difficulty_id": String(difficulty.id),
		"difficulty_name": difficulty.display_name,
		"scene_path": dungeon.scene_path,
		"spawn_rate_multiplier": dungeon.base_spawn_rate_multiplier * difficulty.spawn_rate_multiplier,
		"encounter_count_multiplier": difficulty.encounter_count_multiplier,
		"enemy_level_min": difficulty.enemy_level_min,
		"enemy_level_max": maxi(difficulty.enemy_level_min, difficulty.enemy_level_max),
		"enemy_level_range": [difficulty.enemy_level_min, maxi(difficulty.enemy_level_min, difficulty.enemy_level_max)],
		"enemy_type_ids": enemy_type_ids,
		"enemy_type_names": enemy_type_names,
		"elite_spawn_chance": difficulty.elite_spawn_chance
	}


func start_dungeon(dungeon_id: StringName, difficulty_id: StringName) -> Dictionary:
	## Saves the entire run configuration before launching the scene.
	## If scene_path is empty, this prepares a run only; the UI tells the player
	## that the dungeon scene has not been connected yet.
	var configuration := get_launch_configuration(dungeon_id, difficulty_id)
	if configuration.is_empty():
		return {
			"ok": false,
			"launched": false,
			"message": "A kiválasztott dungeon vagy nehézség nem található. Ellenőrizd a Data/Dungeons és Data/DungeonDifficulties mappát."
		}

	configuration["run_id"] = "%s_%s_%s" % [
		String(dungeon_id),
		str(Time.get_unix_time_from_system()),
		str(randi())
	]
	configuration["seed"] = randi()
	_run_rng.seed = int(configuration["seed"])
	configuration["floor"] = 1
	configuration["room_index"] = 0
	configuration["encounter_index"] = 0
	configuration["status"] = "prepared"
	GameState.set_run_state(configuration)
	configuration_prepared.emit(configuration.duplicate(true))

	var scene_path := String(configuration.get("scene_path", ""))
	if scene_path.is_empty() or not ResourceLoader.exists(scene_path):
		return {
			"ok": true,
			"launched": false,
			"configuration": configuration.duplicate(true),
			"message": "A dungeon és a nehézség mentve. A pálya jelenete még nincs bekötve, ezért a játék a Lobbyban marad. A Dungeon-mechanika már olvashatja a beállításokat a GameState.run_state mezőből."
		}

	configuration["status"] = "active"
	GameState.set_run_state(configuration)
	var change_error := get_tree().change_scene_to_file(scene_path)
	if change_error != OK:
		configuration["status"] = "prepared"
		GameState.set_run_state(configuration)
		return {
			"ok": false,
			"launched": false,
			"configuration": configuration.duplicate(true),
			"message": "A konfiguráció elmentődött, de a dungeon jelenet betöltése sikertelen: " + error_string(change_error)
		}

	dungeon_started.emit(configuration.duplicate(true))
	return {
		"ok": true,
		"launched": true,
		"configuration": configuration.duplicate(true),
		"message": "Dungeon indítása..."
	}


# -----------------------------------------------------------------------------
# Internal loading, validation and sorting helpers
# -----------------------------------------------------------------------------

func _load_dungeons() -> void:
	dungeons.clear()
	var paths: Array[String] = RESOURCE_CATALOG.collect_resource_paths(DUNGEON_DIRECTORY)
	for resource_path in paths:
		var loaded := load(resource_path)
		if not loaded is DungeonDefinition:
			continue
		var dungeon := loaded as DungeonDefinition
		if String(dungeon.id).strip_edges().is_empty():
			push_warning("Hiányzó dungeon ID: " + resource_path)
			continue
		if dungeons.has(String(dungeon.id)):
			push_warning("Duplikált dungeon ID: " + String(dungeon.id))
			continue
		dungeons[String(dungeon.id)] = dungeon


func _load_difficulties() -> void:
	difficulties.clear()
	var paths: Array[String] = RESOURCE_CATALOG.collect_resource_paths(DIFFICULTY_DIRECTORY)
	for resource_path in paths:
		var loaded := load(resource_path)
		if not loaded is DungeonDifficultyData:
			continue
		var difficulty := loaded as DungeonDifficultyData
		if String(difficulty.dungeon_id).strip_edges().is_empty() or String(difficulty.id).strip_edges().is_empty():
			push_warning("Hiányzó dungeon/difficulty ID: " + resource_path)
			continue
		if not dungeons.has(String(difficulty.dungeon_id)):
			push_warning("A nehézség nem létező dungeonra hivatkozik: " + resource_path)
			continue
		var key := _difficulty_key(difficulty.dungeon_id, difficulty.id)
		if difficulties.has(key):
			push_warning("Duplikált dungeon nehézség: " + key)
			continue
		if difficulty.enemy_level_max < difficulty.enemy_level_min:
			push_warning("Az ellenfélszint felső határa kisebb a minimumnál: " + resource_path)
			difficulty.enemy_level_max = difficulty.enemy_level_min
		difficulties[key] = difficulty


func _difficulty_key(dungeon_id: StringName, difficulty_id: StringName) -> String:
	return "%s::%s" % [String(dungeon_id), String(difficulty_id)]


func _sort_dungeons(a: DungeonDefinition, b: DungeonDefinition) -> bool:
	return a.display_name.naturalnocasecmp_to(b.display_name) < 0


func _sort_difficulties(a: DungeonDifficultyData, b: DungeonDifficultyData) -> bool:
	if a.sort_order == b.sort_order:
		return a.display_name.naturalnocasecmp_to(b.display_name) < 0
	return a.sort_order < b.sort_order
