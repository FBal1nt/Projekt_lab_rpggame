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
	if character_class != null:
		apply_character_class(character_class)
	elif not available_classes.is_empty():
		apply_character_class(available_classes[0])
	else:
		current_hp = max_hp
		update_hud()

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

func select_class_by_index(index: int) -> void:
	if controller.is_moving or controller.in_battle: return
	if index >= 0 and index < available_classes.size():
		var chosen = available_classes[index]
		if chosen != null and chosen != active_class:
			apply_character_class(chosen)
