extends Node

const RESOURCE_CATALOG := preload("res://Scripts/Utils/ResourceCatalog.gd")
const LOADING_SCREEN_SCENE := preload("res://Scenes/UI/loading_screen.tscn")

## Global dungeon-selection/configuration service.
## The actual dungeon scene can read GameState.run_state after scene transition.
signal configuration_prepared(configuration: Dictionary)
signal dungeon_started(configuration: Dictionary)

const DUNGEON_DIRECTORY := "res://Data/Dungeons"
const DIFFICULTY_DIRECTORY := "res://Data/DungeonDifficulties"

var dungeons: Dictionary = {}
var difficulties: Dictionary = {}
var _run_rng := RandomNumberGenerator.new()
var _loading_screen: LoadingScreen = null
var _is_transitioning: bool = false


func is_loading_dungeon() -> bool:
	return _is_transitioning


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

func get_active_hero_level() -> int:
	## Returns the active character class level (>= 1) for dungeon enemy scaling.
	if GameState != null:
		if GameState.has_method("get_active_character"):
			var active_char = GameState.get_active_character()
			if active_char != null and active_char.get("level") != null:
				return maxi(1, int(active_char.level))
		if "level" in GameState:
			return maxi(1, int(GameState.level))
	return 1


func get_scaled_enemy_level_range(difficulty: DungeonDifficultyData, hero_level: int = -1) -> Vector2i:
	## Scales the difficulty's baseline (Lv.1 hero) enemy level range to the active class's level.
	var active_level: int = maxi(1, hero_level if hero_level > 0 else get_active_hero_level())
	if difficulty == null:
		return Vector2i(active_level, active_level + 2)

	var base_min: int = maxi(1, difficulty.enemy_level_min)
	var base_max: int = maxi(base_min, difficulty.enemy_level_max)
	var diff_id: String = String(difficulty.id).strip_edges().to_lower()
	var spread: int = maxi(0, base_max - base_min)

	if "easy" in diff_id:
		if active_level <= 1:
			return Vector2i(base_min, base_max)
		var easy_min: int = maxi(1, active_level - 1)
		return Vector2i(easy_min, easy_min + spread)

	var level_offset: int = maxi(0, active_level - 1)
	var scaled_min: int = base_min + level_offset
	var scaled_max: int = maxi(scaled_min, base_max + level_offset)
	return Vector2i(scaled_min, scaled_max)


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

	var hero_level := get_active_hero_level()
	var scaled_levels := get_scaled_enemy_level_range(difficulty, hero_level)

	return {
		"config_version": 1,
		"dungeon_id": String(dungeon.id),
		"dungeon_name": dungeon.display_name,
		"difficulty_id": String(difficulty.id),
		"difficulty_name": difficulty.display_name,
		"scene_path": dungeon.scene_path,
		"spawn_rate_multiplier": dungeon.base_spawn_rate_multiplier * difficulty.spawn_rate_multiplier,
		"encounter_count_multiplier": difficulty.encounter_count_multiplier,
		"hero_level_at_start": hero_level,
		"enemy_level_min": scaled_levels.x,
		"enemy_level_max": scaled_levels.y,
		"enemy_level_range": [scaled_levels.x, scaled_levels.y],
		"enemy_type_ids": enemy_type_ids,
		"enemy_type_names": enemy_type_names,
		"elite_spawn_chance": difficulty.elite_spawn_chance
	}


func start_dungeon(dungeon_id: StringName, difficulty_id: StringName) -> Dictionary:
	## Saves the entire run configuration before launching the scene.
	## If scene_path is empty, this prepares a run only; the UI tells the player
	## that the dungeon scene has not been connected yet.
	var scene_transition := get_node_or_null("/root/SceneTransition")
	if _is_transitioning or (scene_transition != null and scene_transition.has_method("is_transitioning") and scene_transition.is_transitioning()):
		return {
			"ok": true,
			"launched": true,
			"message": "Dungeon betöltése már folyamatban..."
		}

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
	GameState.reset_dungeon_run_titles()
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
	_is_transitioning = true

	var screen := _ensure_loading_screen()
	if screen != null:
		screen.begin_loading(
			String(configuration.get("dungeon_name", "Dungeon")),
			String(configuration.get("difficulty_name", "Normál"))
		)

	_transition_to_dungeon_scene(scene_path, configuration.duplicate(true))
	return {
		"ok": true,
		"launched": true,
		"configuration": configuration.duplicate(true),
		"message": "Dungeon indítása..."
	}


func _ensure_loading_screen() -> LoadingScreen:
	if _loading_screen != null and is_instance_valid(_loading_screen):
		return _loading_screen
	var instance := LOADING_SCREEN_SCENE.instantiate() as LoadingScreen
	if instance != null:
		add_child(instance)
		_loading_screen = instance
	return _loading_screen


func _transition_to_dungeon_scene(scene_path: String, configuration: Dictionary) -> void:
	get_tree().paused = false
	await get_tree().process_frame

	var packed_scene: PackedScene = null
	var req_err := ResourceLoader.load_threaded_request(scene_path)
	if req_err == OK:
		while true:
			var progress := []
			var status := ResourceLoader.load_threaded_get_status(scene_path, progress)
			var ratio := float(progress[0]) if not progress.is_empty() else 0.0
			if _loading_screen != null:
				_loading_screen.set_progress(clampf(0.02 + ratio * 0.33, 0.02, 0.35), "Dungeon jelenet betöltése...")
			if status == ResourceLoader.THREAD_LOAD_LOADED:
				packed_scene = ResourceLoader.load_threaded_get(scene_path) as PackedScene
				break
			elif status != ResourceLoader.THREAD_LOAD_IN_PROGRESS:
				break
			await get_tree().process_frame

	if packed_scene == null:
		packed_scene = load(scene_path) as PackedScene

	if packed_scene == null:
		configuration["status"] = "prepared"
		GameState.set_run_state(configuration)
		if _loading_screen != null:
			_loading_screen.force_hide()
		_is_transitioning = false
		push_error("[DungeonManager] Sikertelen jelenetbetöltés: " + scene_path)
		return

	var change_error := get_tree().change_scene_to_packed(packed_scene)
	if change_error != OK:
		configuration["status"] = "prepared"
		GameState.set_run_state(configuration)
		if _loading_screen != null:
			_loading_screen.force_hide()
		_is_transitioning = false
		push_error("[DungeonManager] Sikertelen jelenetváltás (%s): %s" % [scene_path, error_string(change_error)])
		return

	# Várjuk meg, amíg az új scene aktívvá válik és a MapGenerator elindul
	for _attempt in range(30):
		await get_tree().process_frame
		var cur := get_tree().current_scene
		if cur != null and cur.scene_file_path == scene_path:
			break

	var current_root := get_tree().current_scene
	if current_root != null:
		var map_gen := current_root.find_child("MapGenerator", true, false)
		if map_gen != null:
			var progress_cb := func(p: float, stage_text: String) -> void:
				if _loading_screen != null:
					_loading_screen.set_progress(0.35 + clampf(p, 0.0, 1.0) * 0.62, stage_text)

			if map_gen.has_signal("map_generation_progress"):
				map_gen.connect("map_generation_progress", progress_cb)

			if bool(map_gen.get("is_generating")) and map_gen.has_signal("map_generation_completed"):
				await map_gen.map_generation_completed

			if map_gen.has_signal("map_generation_progress") and map_gen.is_connected("map_generation_progress", progress_cb):
				map_gen.disconnect("map_generation_progress", progress_cb)

	if _loading_screen != null:
		_loading_screen.set_progress(0.98, "Köd és látótér véglegesítése...")

	# Pár képkocka, hogy a FogOfWar shader, a kamera és a HUD biztosan renderelődjön a függöny mögött
	await get_tree().physics_frame
	await get_tree().process_frame
	await get_tree().process_frame

	dungeon_started.emit(configuration)

	if _loading_screen != null:
		await _loading_screen.finish_and_hide()

	_is_transitioning = false


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
