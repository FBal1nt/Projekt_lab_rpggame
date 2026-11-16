extends CanvasLayer
class_name PauseMenu

const LOBBY_SCENE_PATH := "res://Scenes/Lobby/Lobby.tscn"
const MAIN_MENU_SCENE_PATH := "res://Scenes/Menu/MainMenu.tscn"
const MAIN_DUNGEON_SCENE_PATH := "res://Scenes/Main.tscn"

@onready var hero_summary_label: Label = find_child("HeroSummaryLabel", true, false) as Label
@onready var run_summary_label: Label = find_child("RunSummaryLabel", true, false) as Label
@onready var resume_button: Button = find_child("ResumeButton", true, false) as Button
@onready var settings_button: Button = find_child("SettingsButton", true, false) as Button
@onready var restart_button: Button = find_child("RestartButton", true, false) as Button
@onready var lobby_button: Button = find_child("LobbyButton", true, false) as Button
@onready var menu_button: Button = find_child("MenuButton", true, false) as Button

var _was_paused_before: bool = false
var _is_transitioning: bool = false


func _ready() -> void:
	add_to_group("pause_menu")
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 105
	visible = false

	if resume_button and not resume_button.pressed.is_connected(close_pause):
		resume_button.pressed.connect(close_pause)
	if settings_button and not settings_button.pressed.is_connected(_on_settings_pressed):
		settings_button.pressed.connect(_on_settings_pressed)
	if restart_button and not restart_button.pressed.is_connected(_on_restart_pressed):
		restart_button.pressed.connect(_on_restart_pressed)
	if lobby_button and not lobby_button.pressed.is_connected(_on_lobby_pressed):
		lobby_button.pressed.connect(_on_lobby_pressed)
	if menu_button and not menu_button.pressed.is_connected(_on_menu_pressed):
		menu_button.pressed.connect(_on_menu_pressed)


func _mark_input_handled() -> void:
	if not is_inside_tree():
		return
	var vp := get_viewport()
	if vp != null and vp.is_inside_tree():
		vp.set_input_as_handled()


func _input(event: InputEvent) -> void:
	if not is_inside_tree() or _is_transitioning:
		return
	if not (event is InputEventKey):
		return
	var key_event := event as InputEventKey
	if not key_event.pressed or key_event.echo:
		return

	var is_esc := (key_event.keycode == KEY_ESCAPE or key_event.physical_keycode == KEY_ESCAPE)
	var is_p := (key_event.keycode == KEY_P or key_event.physical_keycode == KEY_P)
	if not is_esc and not is_p:
		return

	if _is_blocked_by_other_overlays():
		return

	if visible:
		close_pause()
		_mark_input_handled()
		return

	var hud := get_tree().get_first_node_in_group("hud")
	if hud != null and hud.has_method("is_fullscreen_map_open") and hud.is_fullscreen_map_open():
		if is_esc:
			if hud.has_method("toggle_fullscreen_map"):
				hud.toggle_fullscreen_map(false)
				_mark_input_handled()
			return

	open_pause()
	_mark_input_handled()


func _is_blocked_by_other_overlays() -> bool:
	var dm := get_node_or_null("/root/DungeonManager")
	if dm != null and dm.has_method("is_loading_dungeon") and dm.is_loading_dungeon():
		return true

	var sm := get_node_or_null("/root/SettingsManager")
	if sm != null and sm.has_method("is_open") and sm.is_open():
		return true

	var death_ui := get_tree().get_first_node_in_group("death_screen")
	if death_ui != null and death_ui.visible:
		return true

	return false


func open_pause() -> void:
	if visible or _is_transitioning or _is_blocked_by_other_overlays():
		return

	var hud := get_tree().get_first_node_in_group("hud")
	if hud != null and hud.has_method("is_fullscreen_map_open") and hud.is_fullscreen_map_open():
		hud.toggle_fullscreen_map(false)

	_populate_summary()
	_was_paused_before = get_tree().paused
	get_tree().paused = true
	visible = true

	if resume_button:
		resume_button.grab_focus()


func close_pause() -> void:
	if not visible or _is_transitioning:
		return
	var focus_owner := get_viewport().gui_get_focus_owner()
	if focus_owner != null and is_ancestor_of(focus_owner):
		focus_owner.release_focus()
	visible = false
	get_tree().paused = _was_paused_before


func _populate_summary() -> void:
	var hero := get_tree().get_first_node_in_group("player") as HeroController
	if hero_summary_label:
		if is_instance_valid(hero):
			var c_name: String = hero.active_class.class_name_id if hero.active_class else "Kalandor"
			hero_summary_label.text = "⚔️ %s  •  %s (Lv. %d)  •  HP: %d/%d" % [
				hero.hero_name, c_name, hero.level, hero.get_current_hp(), hero.get_max_hp()
			]
		else:
			hero_summary_label.text = "⚔️ Játék szüneteltetve"

	if run_summary_label:
		var gs := get_node_or_null("/root/GameState")
		if gs != null and "run_state" in gs and gs.run_state is Dictionary and not gs.run_state.is_empty():
			var d_name := String(gs.run_state.get("dungeon_name", "Dungeon"))
			var diff_name := String(gs.run_state.get("difficulty_name", "Normál"))
			run_summary_label.text = "🏰 %s  •  Nehézség: %s" % [d_name, diff_name]
		else:
			run_summary_label.text = "🏰 Felfedezés folyamatban"


func _set_buttons_disabled(disabled: bool) -> void:
	for btn in [resume_button, settings_button, restart_button, lobby_button, menu_button]:
		if btn:
			btn.disabled = disabled


func _on_settings_pressed() -> void:
	var sm := get_node_or_null("/root/SettingsManager")
	if sm != null and sm.has_method("open_settings"):
		sm.open_settings()


func _restore_active_character_full_health() -> void:
	var gs := get_node_or_null("/root/GameState")
	if gs == null or not gs.has_method("get_active_character"):
		return
	var active_char = gs.get_active_character()
	if active_char == null:
		return
	var stats: Dictionary = gs.get_character_stats(active_char) if gs.has_method("get_character_stats") else {}
	var full_hp: int = maxi(int(round(float(stats.get("max_health", 9999)))), 1)
	if gs.has_method("set_active_character_health"):
		gs.set_active_character_health(full_hp)


func _on_restart_pressed() -> void:
	if _is_transitioning:
		return
	_is_transitioning = true
	_set_buttons_disabled(true)

	visible = false
	get_tree().paused = false
	_restore_active_character_full_health()

	var gs := get_node_or_null("/root/GameState")
	var dm := get_node_or_null("/root/DungeonManager")
	if gs != null and dm != null and "run_state" in gs and gs.run_state is Dictionary:
		var dungeon_id := StringName(str(gs.run_state.get("dungeon_id", "")))
		var difficulty_id := StringName(str(gs.run_state.get("difficulty_id", "")))
		if dungeon_id != &"" and difficulty_id != &"" and dm.has_method("start_dungeon"):
			var result: Dictionary = dm.start_dungeon(dungeon_id, difficulty_id)
			if bool(result.get("launched", false)):
				return

	call_deferred("_perform_restart_fallback")


func _perform_restart_fallback() -> void:
	if not is_inside_tree():
		_is_transitioning = false
		_set_buttons_disabled(false)
		return
	var reload_err := get_tree().reload_current_scene()
	if reload_err != OK:
		_request_scene_transition(MAIN_DUNGEON_SCENE_PATH)


func _on_lobby_pressed() -> void:
	_leave_dungeon_to_scene(LOBBY_SCENE_PATH)


func _on_menu_pressed() -> void:
	_leave_dungeon_to_scene(MAIN_MENU_SCENE_PATH)


func _leave_dungeon_to_scene(scene_path: String) -> void:
	if _is_transitioning:
		return
	_is_transitioning = true
	_set_buttons_disabled(true)

	visible = false
	get_tree().paused = false

	var gs := get_node_or_null("/root/GameState")
	if gs != null and gs.has_method("clear_run_state"):
		gs.clear_run_state()

	call_deferred("_perform_scene_change", scene_path)


func _perform_scene_change(scene_path: String) -> void:
	if not is_inside_tree():
		_is_transitioning = false
		_set_buttons_disabled(false)
		return
	_request_scene_transition(scene_path)


func _request_scene_transition(scene_path: String) -> void:
	var st := get_node_or_null("/root/SceneTransition")
	if st != null and st.has_method("request_scene_change"):
		if st.has_signal("transition_failed") and not st.is_connected("transition_failed", _on_scene_transition_failed):
			st.connect("transition_failed", _on_scene_transition_failed)
		if st.call("request_scene_change", scene_path):
			return
	var err := get_tree().change_scene_to_file(scene_path)
	if err != OK:
		push_error("[PauseMenu] Nem sikerült jelenetet váltani (%s): %s" % [scene_path, error_string(err)])
		_is_transitioning = false
		_set_buttons_disabled(false)


func _on_scene_transition_failed(_scene_path: String, _reason: String) -> void:
	if is_inside_tree():
		_is_transitioning = false
		_set_buttons_disabled(false)
