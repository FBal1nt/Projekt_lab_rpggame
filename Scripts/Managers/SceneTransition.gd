extends Node

signal transition_failed(scene_path: String, reason: String)

const LOADING_SCREEN_SCENE := preload("res://Scenes/UI/loading_screen.tscn")

const LOBBY_SCENE_PATH := "res://Scenes/Lobby/Lobby.tscn"
const MAIN_MENU_SCENE_PATH := "res://Scenes/Menu/MainMenu.tscn"
const MAIN_DUNGEON_SCENE_PATH := "res://Scenes/Main.tscn"

const SCENE_PRESETS := {
	LOBBY_SCENE_PATH: {
		"title": "TÁBOR BETÖLTÉSE",
		"info": "Városi Tábor  •  Felszerelés, bolt és küldetések",
		"stage": "Tábor jelenet betöltése...",
		"icon": UiIcons.DUNGEON,
		"info_icon": UiIcons.DUNGEON,
		"finished_title": "TÁBOR BETÖLTVE",
		"finished_stage": "Üdvözlünk a Táborban!"
	},
	MAIN_DUNGEON_SCENE_PATH: {
		"title": "DUNGEON BETÖLTÉSE",
		"info": "Kaland előkészítése...",
		"stage": "Dungeon jelenet betöltése...",
		"icon": UiIcons.PLAY_SWORD,
		"info_icon": UiIcons.DUNGEON,
		"finished_title": "DUNGEON BETÖLTVE",
		"finished_stage": "Készen állsz! Jó felfedezést!"
	},
	MAIN_MENU_SCENE_PATH: {
		"title": "FŐMENÜ BETÖLTÉSE",
		"info": "Főmenü  •  Mentések és beállítások",
		"stage": "Főmenü betöltése...",
		"icon": UiIcons.SCROLL,
		"info_icon": UiIcons.SCROLL,
		"finished_title": "FŐMENÜ BETÖLTVE",
		"finished_stage": "Kész!"
	}
}

var _loading_screen: LoadingScreen = null
var _is_transitioning: bool = false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


func is_transitioning() -> bool:
	return _is_transitioning


func request_scene_change(scene_path: String, options: Dictionary = {}) -> bool:
	if _is_transitioning:
		return false
	if DungeonManager != null and DungeonManager.is_loading_dungeon():
		return false
	if scene_path.is_empty() or not ResourceLoader.exists(scene_path):
		push_error("[SceneTransition] Érvénytelen jelenet útvonal: %s" % scene_path)
		return false

	_is_transitioning = true
	_perform_threaded_transition(scene_path, options.duplicate())
	return true


func _ensure_loading_screen() -> LoadingScreen:
	if _loading_screen != null and is_instance_valid(_loading_screen):
		return _loading_screen
	var instance := LOADING_SCREEN_SCENE.instantiate() as LoadingScreen
	if instance != null:
		add_child(instance)
		_loading_screen = instance
	return _loading_screen


func _perform_threaded_transition(scene_path: String, options: Dictionary) -> void:
	var preset: Dictionary = SCENE_PRESETS.get(scene_path, {})
	var title_text := str(options.get("title", preset.get("title", "JELENET BETÖLTÉSE")))
	var info_text := str(options.get("info", preset.get("info", "Jelenet előkészítése...")))
	var stage_text := str(options.get("stage", preset.get("stage", "Jelenet betöltése...")))
	var icon_text := str(options.get("icon", preset.get("icon", UiIcons.HOURGLASS)))
	var info_icon_path := str(options.get("info_icon", preset.get("info_icon", UiIcons.DUNGEON)))
	var finished_title := str(options.get("finished_title", preset.get("finished_title", "BETÖLTVE")))
	var finished_stage := str(options.get("finished_stage", preset.get("finished_stage", "Kész!")))

	get_tree().paused = false

	var screen := _ensure_loading_screen()
	if screen != null:
		screen.begin_scene_loading(
			title_text,
			info_text,
			stage_text,
			icon_text,
			finished_title,
			finished_stage,
			info_icon_path
		)

	await get_tree().process_frame

	var packed_scene: PackedScene = null
	var existing_status := ResourceLoader.load_threaded_get_status(scene_path)
	var req_err := OK
	if existing_status != ResourceLoader.THREAD_LOAD_IN_PROGRESS and existing_status != ResourceLoader.THREAD_LOAD_LOADED:
		req_err = ResourceLoader.load_threaded_request(scene_path)

	if req_err == OK:
		while true:
			var progress := []
			var status := ResourceLoader.load_threaded_get_status(scene_path, progress)
			var ratio := float(progress[0]) if not progress.is_empty() else 0.0
			if screen != null:
				screen.set_progress(clampf(0.05 + ratio * 0.85, 0.05, 0.90), stage_text)
			if status == ResourceLoader.THREAD_LOAD_LOADED:
				packed_scene = ResourceLoader.load_threaded_get(scene_path) as PackedScene
				break
			elif status != ResourceLoader.THREAD_LOAD_IN_PROGRESS:
				break
			await get_tree().process_frame

	if packed_scene == null:
		if screen != null:
			screen.set_progress(0.85, stage_text)
		packed_scene = load(scene_path) as PackedScene

	if packed_scene == null:
		if screen != null:
			screen.force_hide()
		_is_transitioning = false
		var reason := "Sikertelen jelenetbetöltés: %s" % scene_path
		push_error("[SceneTransition] " + reason)
		transition_failed.emit(scene_path, reason)
		return

	if screen != null:
		screen.set_progress(0.94, "Jelenet aktiválása...")
	await get_tree().process_frame

	var change_err := get_tree().change_scene_to_packed(packed_scene)
	if change_err != OK:
		if screen != null:
			screen.force_hide()
		_is_transitioning = false
		var reason := "Sikertelen jelenetváltás (%s): %s" % [scene_path, error_string(change_err)]
		push_error("[SceneTransition] " + reason)
		transition_failed.emit(scene_path, reason)
		return

	for _attempt in range(30):
		await get_tree().process_frame
		var cur := get_tree().current_scene
		if cur != null and cur.scene_file_path == scene_path:
			break

	await get_tree().process_frame

	if screen != null:
		await screen.finish_and_hide()

	_is_transitioning = false
