extends Node
class_name HeroProgression

var controller: HeroController

@export_group("Kaszt és Fejlődés")
@export var available_classes: Array[CharacterClass] = []
@export var character_class: CharacterClass

var active_class: CharacterClass
var current_hp: int = 100
var max_hp: int = 100
var attack_power: int = 18
var defense: int = 1
var initiative: float = 10.0

const BASE_VISION_LIMIT: int = 2
const MAX_LEVEL_VISION_LIMIT: int = 5

var level: int = 1
var xp: int = 0
var title_crit_chance: float = 0.0
var title_lifesteal: int = 0
var title_vision_bonus: int = 0
var _applied_vision_bonus: int = 0
var _syncing_game_state: bool = false

func _get_game_state() -> Node:
	if Engine.has_singleton("GameState") or get_node_or_null("/root/GameState") != null:
		return get_node_or_null("/root/GameState")
	return null

func _exit_tree() -> void:
	var gs := _get_game_state()
	if gs != null and gs.has_signal("state_changed") and gs.state_changed.is_connected(_on_game_state_changed):
		gs.state_changed.disconnect(_on_game_state_changed)

func setup(p_controller: HeroController) -> void:
	controller = p_controller

	var gs := _get_game_state()
	var active_char = null
	if gs and gs.has_method("get_active_character"):
		active_char = gs.get_active_character()

	var selected_class: CharacterClass = null

	if active_char != null:
		# 1. Név (+ a táborban kiválasztott összevont titulusok) átvétele az aktív karaktertől
		var display_name := ""
		if gs != null and gs.has_method("get_character_display_name"):
			display_name = String(gs.get_character_display_name(active_char))
		if display_name.strip_edges().is_empty():
			display_name = str(active_char.character_name)
		if not display_name.strip_edges().is_empty():
			controller.hero_name = display_name

		# 2. Kaszt kiválasztása a lobby-ban megadott class_id alapján
		selected_class = _find_class_by_id(active_char.class_id)

	if controller != null and controller.debug_default_class != null and (controller.debug_mode_on_start or active_char == null):
		selected_class = controller.debug_default_class
	elif selected_class == null and character_class != null:
		selected_class = character_class
	elif selected_class == null and not available_classes.is_empty():
		selected_class = available_classes[0]

	if active_char != null:
		level = maxi(int(active_char.level), 1)
		xp = clampi(int(active_char.xp), 0, 9)

	if selected_class != null:
		apply_character_class(selected_class)
	else:
		current_hp = max_hp

	if active_char != null:
		_recalculate_stats_from_class_and_equipment(active_char)
		if active_char.current_health > 0:
			current_hp = mini(active_char.current_health, max_hp)
		else:
			current_hp = max_hp
		sync_health_to_game_state(false)

	if gs != null and gs.has_signal("state_changed") and not gs.state_changed.is_connected(_on_game_state_changed):
		gs.state_changed.connect(_on_game_state_changed)

	update_hud()

func _recalculate_stats_from_class_and_equipment(active_char = null) -> void:
	var base_max_hp: int = active_class.max_hp if active_class != null else 100
	var base_atk: int = active_class.base_damage if active_class != null else 18
	var base_def: int = active_class.base_defense if active_class != null else 1
	var base_init: float = active_class.initiative if active_class != null else 10.0

	var level_steps: int = maxi(level - 1, 0)
	base_max_hp += level_steps * 10
	base_atk += level_steps
	base_def += level_steps
	if level_steps > 0:
		base_init *= pow(1.1, level_steps)

	var eq_max_hp: int = 0
	var eq_atk: int = 0
	var eq_def: int = 0
	var eq_speed: float = 0.0

	var gs := _get_game_state()
	if active_char == null and gs != null and gs.has_method("get_active_character"):
		active_char = gs.get_active_character()

	if active_char != null and gs != null and gs.has_method("get_character_stats"):
		var derived: Dictionary = gs.get_character_stats(active_char)
		var base_dict: Dictionary = active_char.base_stats if active_char.base_stats is Dictionary else {}
		if not derived.is_empty() and not base_dict.is_empty():
			eq_max_hp = int(round(float(derived.get("max_health", 0.0)) - float(base_dict.get("max_health", 0.0))))
			eq_atk = int(round(float(derived.get("damage_max", 0.0)) - float(base_dict.get("damage_max", 0.0))))
			eq_def = int(round(float(derived.get("defense", 0.0)) - float(base_dict.get("defense", 0.0))))
			eq_speed = float(derived.get("speed", 0.0)) - float(base_dict.get("speed", 0.0))

	title_crit_chance = 0.0
	title_lifesteal = 0
	title_vision_bonus = 0
	if active_char != null and gs != null and gs.has_method("get_active_title_buffs"):
		var title_buffs: Dictionary = gs.get_active_title_buffs(active_char)
		title_crit_chance = float(title_buffs.get("crit_chance", 0.0))
		title_lifesteal = int(round(float(title_buffs.get("lifesteal", 0.0))))
		title_vision_bonus = int(round(float(title_buffs.get("vision_bonus", 0.0))))

	if controller != null and controller.visuals != null:
		var base_vision: int = mini(BASE_VISION_LIMIT + maxi(level - 1, 0), MAX_LEVEL_VISION_LIMIT)
		var expected_vision: int = maxi(1, base_vision + title_vision_bonus)
		if controller.debug_invincible:
			expected_vision = maxi(controller.visuals.vision_limit, 50)
		var vision_changed: bool = controller.visuals.vision_limit != expected_vision or title_vision_bonus != _applied_vision_bonus
		controller.visuals.vision_limit = expected_vision
		_applied_vision_bonus = title_vision_bonus
		if vision_changed:
			controller.visuals.update_fog_of_war()

	max_hp = maxi(1, base_max_hp + eq_max_hp)
	attack_power = maxi(1, base_atk + eq_atk)
	defense = maxi(0, base_def + eq_def)
	initiative = maxf(1.0, base_init + eq_speed)
	current_hp = clampi(current_hp, 0, max_hp)

func sync_health_to_game_state(sync_progression: bool = false) -> void:
	if _syncing_game_state:
		return
	var gs := _get_game_state()
	if gs == null or not gs.has_method("get_active_character"):
		return
	var active_char = gs.get_active_character()
	if active_char == null:
		return
	_syncing_game_state = true
	if sync_progression:
		active_char.level = level
		active_char.xp = xp
		if gs.has_method("recalculate_character_stats"):
			gs.recalculate_character_stats(active_char)
	if gs.has_method("set_active_character_health"):
		gs.set_active_character_health(current_hp)
	_syncing_game_state = false

func _on_game_state_changed() -> void:
	if _syncing_game_state or controller == null:
		return
	var gs := _get_game_state()
	if gs == null or not gs.has_method("get_active_character"):
		return
	var active_char = gs.get_active_character()
	if active_char == null:
		return
	_syncing_game_state = true
	var prev_hp := current_hp
	_recalculate_stats_from_class_and_equipment(active_char)
	if active_char.current_health >= 0:
		current_hp = clampi(active_char.current_health, 0, max_hp)
	else:
		current_hp = mini(current_hp, max_hp)
	_syncing_game_state = false
	update_hud()
	if current_hp > prev_hp and controller.visuals != null and controller.visuals.has_method("play_heal_effect"):
		controller.visuals.play_heal_effect()

func _find_class_by_id(target_id: StringName) -> CharacterClass:
	var clean_target = String(target_id).to_lower().replace(" ", "_")
	for c in available_classes:
		if c == null: continue
		var c_name = c.class_name_id.to_lower().replace(" ", "_")
		if c_name == clean_target or c.resource_path.get_file().get_basename().to_lower().begins_with(clean_target):
			return c
	return null

func get_initiative() -> float: return initiative
func get_defense() -> int: return defense
func get_current_hp() -> int: return current_hp
func get_max_hp() -> int: return max_hp
func is_alive() -> bool: return current_hp > 0

func heal(amount: int) -> void:
	if not is_alive(): return
	current_hp = mini(current_hp + amount, max_hp)
	sync_health_to_game_state(false)
	update_hud()

func heal_to_max() -> void:
	if not is_alive(): return
	current_hp = max_hp
	sync_health_to_game_state(false)
	update_hud()

func apply_character_class(new_class: CharacterClass) -> void:
	if new_class == null: return
	active_class = new_class

	max_hp = new_class.max_hp
	current_hp = max_hp
	attack_power = new_class.base_damage
	defense = new_class.base_defense
	initiative = new_class.initiative

	if controller and controller.combat:
		controller.combat.is_ranged = new_class.is_ranged
		controller.combat.projectile_scene = new_class.projectile_scene
		if new_class.projectile_scene != null and new_class.attack_fps > 0.0:
			controller.combat.projectile_delay = float(new_class.release_frame) / float(new_class.attack_fps)
		else:
			controller.combat.projectile_delay = 0.0

	if controller and controller.visuals and controller.visuals.sprite:
		var sp = controller.visuals.sprite
		if new_class.sprite_frames: sp.sprite_frames = new_class.sprite_frames
		sp.scale = new_class.sprite_scale
		sp.offset = new_class.sprite_offset
		controller.visuals.play_idle_anim()

	if controller and controller.mover:
		controller.mover.move_duration = new_class.move_duration

	update_hud()

func gain_combat_xp(amount: int = 1) -> void:
	xp += amount
	if xp >= 10:
		xp -= 10
		_level_up()
	else:
		sync_health_to_game_state(true)
	update_hud()

func _level_up() -> void:
	level += 1
	sync_health_to_game_state(true)
	_recalculate_stats_from_class_and_equipment()
	current_hp = max_hp
	sync_health_to_game_state(true)
	AudioManager.sfx(&"level_up", 1.0, 1.0)
	update_hud()

func award_title(slain_title: String) -> void:
	## Collects a defeated enemy's title as pending for this dungeon run.
	## Titles are NOT applied to the hero's name automatically — they unlock upon beating the dungeon
	## and can be selected & merged in the camp's Character menu.
	var clean_title := slain_title.strip_edges()
	if clean_title.is_empty():
		return
	AudioManager.sfx(&"title_unlock", 1.0, 1.0, 0.0, 0.25)
	var gs := _get_game_state()
	if gs != null and gs.has_method("collect_pending_title"):
		gs.collect_pending_title(clean_title)

func update_hud() -> void:
	var hud = get_tree().get_first_node_in_group("hud") as PlayerHUD
	if hud != null and controller != null:
		hud.refresh_stats(controller)
