extends CanvasLayer
class_name DeathScreen

const MAIN_MENU_SCENE_PATH := "res://Scenes/Menu/MainMenu.tscn"
const MAIN_DUNGEON_SCENE_PATH := "res://Scenes/Main.tscn"

@onready var hero_summary_label: Label = find_child("HeroSummaryLabel", true, false) as Label
@onready var run_summary_label: Label = find_child("RunSummaryLabel", true, false) as Label
@onready var restart_button: Button = find_child("RestartButton", true, false) as Button
@onready var menu_button: Button = find_child("MenuButton", true, false) as Button

var _is_transitioning: bool = false


func _ready() -> void:
	add_to_group("death_screen")
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 120
	visible = false

	if restart_button and not restart_button.pressed.is_connected(_on_restart_pressed):
		restart_button.pressed.connect(_on_restart_pressed)
	if menu_button and not menu_button.pressed.is_connected(_on_menu_pressed):
		menu_button.pressed.connect(_on_menu_pressed)


## Megjeleníti a halálképernyőt és leállítja a játékot
func show_death_screen(hero: HeroController = null) -> void:
	if visible:
		return

	_is_transitioning = false
	_set_buttons_disabled(false)
	_populate_summary(hero)
	_hide_other_dungeon_uis()
	_freeze_all_enemies()

	visible = true
	get_tree().paused = true

	if restart_button:
		restart_button.grab_focus()


func _populate_summary(hero: HeroController) -> void:
	if hero_summary_label:
		if is_instance_valid(hero):
			var c_name: String = hero.active_class.class_name_id if hero.active_class else "Kalandor"
			hero_summary_label.text = "⚔️ %s  •  %s (Szint %d)" % [hero.hero_name, c_name, hero.level]
		else:
			hero_summary_label.text = "⚔️ A hős elesett a harcban"

	if run_summary_label:
		var gs := get_node_or_null("/root/GameState")
		if gs != null and "run_state" in gs and gs.run_state is Dictionary and not gs.run_state.is_empty():
			var dungeon_name := String(gs.run_state.get("dungeon_name", "Elfeledett Kripta"))
			var diff_name := String(gs.run_state.get("difficulty_name", "Közepes"))
			run_summary_label.text = "🏰 %s  •  Nehézség: %s" % [dungeon_name, diff_name]
		else:
			run_summary_label.text = "🏰 Dungeon felfedezés megszakadt"


func _hide_other_dungeon_uis() -> void:
	var hud := get_tree().get_first_node_in_group("hud")
	if hud != null:
		if hud.has_method("set_battle_mode"):
			hud.set_battle_mode(true)
		elif "visible" in hud:
			hud.visible = false

	var battle_ui := get_tree().get_first_node_in_group("battle_ui")
	if battle_ui != null and "visible" in battle_ui:
		battle_ui.visible = false

	var pause_ui := get_tree().get_first_node_in_group("pause_menu")
	if pause_ui != null and "visible" in pause_ui:
		pause_ui.visible = false


func _freeze_all_enemies() -> void:
	for enemy in get_tree().get_nodes_in_group("enemies"):
		if is_instance_valid(enemy) and enemy.get("brain") != null:
			var timer = enemy.brain.get("ai_timer")
			if timer != null and is_instance_valid(timer):
				timer.stop()


func _set_buttons_disabled(disabled: bool) -> void:
	if restart_button:
		restart_button.disabled = disabled
	if menu_button:
		menu_button.disabled = disabled


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


func _on_menu_pressed() -> void:
	if _is_transitioning:
		return
	_is_transitioning = true
	_set_buttons_disabled(true)

	visible = false
	get_tree().paused = false
	_restore_active_character_full_health()

	var gs := get_node_or_null("/root/GameState")
	if gs != null and gs.has_method("clear_run_state"):
		gs.clear_run_state()

	call_deferred("_perform_menu_transition")


func _perform_menu_transition() -> void:
	if not is_inside_tree():
		_is_transitioning = false
		_set_buttons_disabled(false)
		return
	_request_scene_transition(MAIN_MENU_SCENE_PATH)


func _request_scene_transition(scene_path: String) -> void:
	var st := get_node_or_null("/root/SceneTransition")
	if st != null and st.has_method("request_scene_change"):
		if st.has_signal("transition_failed") and not st.is_connected("transition_failed", _on_scene_transition_failed):
			st.connect("transition_failed", _on_scene_transition_failed)
		if st.call("request_scene_change", scene_path):
			return
	var err := get_tree().change_scene_to_file(scene_path)
	if err != OK:
		_is_transitioning = false
		_set_buttons_disabled(false)
		push_error("[DeathScreen] Nem sikerült betölteni a jelenetet (%s): %s" % [scene_path, error_string(err)])


func _on_scene_transition_failed(_scene_path: String, _reason: String) -> void:
	if is_inside_tree():
		_is_transitioning = false
		_set_buttons_disabled(false)
