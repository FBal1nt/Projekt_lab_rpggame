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

var level: int = 1
var xp: int = 0

func setup(p_controller: HeroController) -> void:
	controller = p_controller

	var active_char = null
	if Engine.has_singleton("GameState") or get_node_or_null("/root/GameState") != null:
		var gs = get_node_or_null("/root/GameState")
		if gs and gs.has_method("get_active_character"):
			active_char = gs.get_active_character()

	var selected_class: CharacterClass = null

	if active_char != null:
		# 1. Név átvétele a lobby-ban megadott aktív karaktertől
		if not str(active_char.character_name).strip_edges().is_empty():
			controller.hero_name = active_char.character_name

		# 2. Kaszt kiválasztása a lobby-ban megadott class_id alapján
		selected_class = _find_class_by_id(active_char.class_id)

	if selected_class == null and character_class != null:
		selected_class = character_class
	elif selected_class == null and not available_classes.is_empty():
		selected_class = available_classes[0]

	if selected_class != null:
		apply_character_class(selected_class)
	else:
		current_hp = max_hp
		update_hud()

	if active_char != null:
		if active_char.level > 1:
			level = active_char.level
			max_hp += (level - 1) * 10
			attack_power += (level - 1)
			defense += (level - 1)
		if active_char.current_health > 0:
			current_hp = mini(active_char.current_health, max_hp)
		update_hud()

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
	update_hud()

func heal_to_max() -> void:
	if not is_alive(): return
	current_hp = max_hp
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
	update_hud()

func _level_up() -> void:
	level += 1
	attack_power += 1
	defense += 1
	max_hp += 10
	heal_to_max()
	initiative *= 1.1
	if controller and controller.visuals:
		controller.visuals.vision_limit *= 3
		controller.visuals.update_fog_of_war()
	update_hud()

func award_title(slain_title: String) -> void:
	if slain_title == "": return
	var new_title = "the slayer of " + slain_title
	if not new_title in controller.hero_name:
		controller.hero_name = "%s, %s" % [controller.hero_name, new_title]
	update_hud()

func update_hud() -> void:
	var hud = get_tree().get_first_node_in_group("hud") as PlayerHUD
	if hud != null and controller != null:
		hud.refresh_stats(controller)
