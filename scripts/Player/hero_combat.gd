extends Node
class_name HeroCombat

var controller: HeroController

@export_group("Harci Beállítások")
@export var projectile_scene: PackedScene
@export var projectile_delay: float = 0.0
@export var wizard_element: String = "ice"

@export_group("Védekezés és Blokk")
@export_range(0.0, 1.0) var hero_block_chance: float = 0.35
@export_range(0.0, 1.0) var hero_block_reduction: float = 0.5

var attack_range: int = 1
var is_ranged: bool = false
var max_class_range: int = 1
var in_battle: bool = false
var is_attacking: bool = false
var is_blocking_active: bool = false
var is_stunned: bool = false

func setup(p_controller: HeroController) -> void:
	controller = p_controller
	in_battle = false
	is_attacking = false
	is_blocking_active = false
	is_stunned = false

func roll_attack_damage() -> int:
	var power = controller.progression.attack_power if (controller and controller.progression) else 10
	return ceili(float(power) * randf_range(0.8, 1.0))

func take_damage(incoming_raw_damage: int) -> int:
	if not controller.is_alive(): return 0

	var raw = incoming_raw_damage
	if is_blocking_active:
		raw = ceili(float(incoming_raw_damage) * (1.0 - hero_block_reduction))
		print("🛡️ [HŐS TOMPÍTOTT] Sikeres pajzshárítás! Sebzés: %d -> %d" % [incoming_raw_damage, raw])

	var def = controller.progression.defense if controller.progression else 0
	var actual_damage = maxi(0, raw - def)
	controller.current_hp = maxi(0, controller.current_hp - actual_damage)
	controller.progression.update_hud()

	# --- FREE ROAM HALÁL ELLENŐRZÉSE ---
	if controller.current_hp <= 0 and not in_battle:
		if controller.has_method("play_overworld_death"):
			controller.play_overworld_death()

	return actual_damage

func try_trigger_block() -> bool:
	if not controller.is_alive() or controller.active_class == null:
		return false

	var c_name = controller.active_class.class_name_id
	var sprite = controller.sprite
	var can_class_block = c_name in ["Knight", "Knight_Templar", "Templar"] or (sprite and sprite.sprite_frames and sprite.sprite_frames.has_animation("block"))

	if not can_class_block:
		is_blocking_active = false
		return false

	if randf() < hero_block_chance:
		is_blocking_active = true
		if sprite and sprite.sprite_frames and sprite.sprite_frames.has_animation("block"):
			sprite.play("block")
		print("🛡️ [HŐS BLOKKOL] A %s felemeli a pajzsát a csapás ellen!" % c_name)
		return true

	is_blocking_active = false
	return false

func can_attack_cell(target_cell: Vector2i) -> bool:
	var grid_mgr = controller.mover.grid_manager if (controller and controller.mover) else null
	var dist = grid_mgr.get_grid_distance(controller.grid_pos, target_cell) if grid_mgr else 1
	var max_range = get_effective_attack_range()
	if dist > max_range: return false

	if is_hero_ranged_attack(target_cell): return true

	var diff = target_cell - controller.grid_pos
	return diff.y == 0 and absi(diff.x) == 1

## TÁMADÁSI KATTINTÁS
func handle_attack_click() -> void:
	var fl = controller.mover.grid_manager.floor_layer if (controller and controller.mover and controller.mover.grid_manager) else null
	if not fl or controller.is_moving or in_battle or is_attacking or not controller.is_alive() or controller.is_stunned:
		return

	var target_cell = fl.local_to_map(fl.to_local(controller.get_global_mouse_position()))
	if not controller.visuals.is_tile_in_vision(target_cell): return

	var enemy = _get_enemy_at_cell(target_cell)
	if enemy != null and enemy.is_monster_alive():
		if can_attack_cell(target_cell):
			controller.mover.cancel_movement_immediately()

			var is_ranged_shot = is_hero_ranged_attack(target_cell)
			var enemy_range: int = enemy.get_attack_range() if enemy.has_method("get_attack_range") else 1
			var enemy_is_ranged: bool = enemy_range > 1
			var diff = target_cell - controller.grid_pos
			var is_adjacent: bool = (diff.y == 0 and absi(diff.x) == 1)

			# 1. SZABÁLY: Távolsági vs Távolsági
			if is_ranged_shot and enemy_is_ranged:
				var battle_ui = get_tree().get_first_node_in_group("battle_ui") as BattleDialog
				if battle_ui != null and not battle_ui.combat_active:
					battle_ui.open_battle(controller, enemy, false)
				return

			# 2. SZABÁLY: Távolsági vs Közelharci
			elif is_ranged_shot and not enemy_is_ranged:
				if is_adjacent:
					var battle_ui = get_tree().get_first_node_in_group("battle_ui") as BattleDialog
					if battle_ui != null and not battle_ui.combat_active:
						battle_ui.open_battle(controller, enemy, false)
				else:
					await perform_standalone_ranged_shot(enemy, true)
				return

			# 3. SZABÁLY: Közelharci hős
			else:
				var battle_ui = get_tree().get_first_node_in_group("battle_ui") as BattleDialog
				if battle_ui != null and not battle_ui.combat_active:
					battle_ui.open_battle(controller, enemy, false)
				return
		else:
			print("[Harcrendszer] Nem éred el a célpontot szabályosan!")

## KÖR VÉGREHAJTÁSA A PÁRBAJABLAKBAN (BATTLE DIALOG)
func perform_combat_turn(target_enemy: Node2D) -> int:
	if not controller.is_alive() or not is_instance_valid(target_enemy): return 0
	if controller.visuals: controller.visuals.update_facing(target_enemy.grid_pos.x)

	var action = _resolve_hero_attack_action(target_enemy)
	var anim_name: String = action["anim"]
	var multiplier: float = action["multiplier"]
	var is_action_ranged: bool = action["is_ranged"]

	var raw_damage = ceili(float(roll_attack_damage()) * multiplier)
	var sprite = controller.sprite

	if is_action_ranged:
		if sprite and sprite.sprite_frames.has_animation(anim_name): sprite.play(anim_name)
		
		var delay = _get_projectile_delay()
		if delay > 0.0: await get_tree().create_timer(delay).timeout

		await _fire_projectile_at_enemy(target_enemy, raw_damage)
	else:
		if sprite and sprite.sprite_frames.has_animation(anim_name):
			sprite.play(anim_name)
			if target_enemy.has_method("try_trigger_block"): target_enemy.try_trigger_block()
			await sprite.animation_finished

		target_enemy.take_damage(raw_damage)
		controller.progression.gain_combat_xp(1)

	if sprite and controller.is_alive(): sprite.play("idle")
	if target_enemy.has_method("play_hurt_reaction"): await target_enemy.play_hurt_reaction()

	return raw_damage

## TÉRKÉPI TÁVOLSÁGI LÖVÉS (PÁRBAJ NÉLKÜL)
func perform_standalone_ranged_shot(target_enemy: Node2D, triggers_turn: bool = true) -> void:
	is_attacking = true
	if controller.visuals: controller.visuals.update_facing(target_enemy.grid_pos.x)

	var action = _resolve_hero_attack_action(target_enemy)
	var anim_name: String = action["anim"]
	var multiplier: float = action["multiplier"]
	var raw_damage = ceili(float(roll_attack_damage()) * multiplier)

	var sprite = controller.sprite
	if sprite and sprite.sprite_frames.has_animation(anim_name): sprite.play(anim_name)

	var delay = _get_projectile_delay()
	if delay > 0.0: await get_tree().create_timer(delay).timeout

	if target_enemy.has_method("try_trigger_block"): target_enemy.try_trigger_block()

	await _fire_projectile_at_enemy(target_enemy, raw_damage)

	if sprite and controller.is_alive(): sprite.play("idle")
	is_attacking = false

	if is_instance_valid(target_enemy):
		if not target_enemy.is_monster_alive():
			var title = target_enemy.get_title() if target_enemy.has_method("get_title") else ""
			if title != "": controller.progression.award_title(title)
			if target_enemy.has_method("play_overworld_death"): target_enemy.play_overworld_death()
		else:
			if target_enemy.has_method("play_hurt_reaction"): await target_enemy.play_hurt_reaction()
			if triggers_turn: controller.trigger_monsters_turn()

## KÖZÖS LÖVEDÉKKEZELŐ (ARCHER, PRIEST, WIZARD)
func _fire_projectile_at_enemy(target_enemy: Node2D, raw_damage: int) -> void:
	var c_name = controller.active_class.class_name_id if controller.active_class else ""
	var p_scene = _get_active_projectile_scene()

	# 1. VARÁZSLÓ
	if c_name == "Wizard" and p_scene != null:
		var spell = p_scene.instantiate()
		controller.get_parent().add_child(spell)
		if wizard_element == "ice":
			if spell.has_method("spawn_ice"):
				spell.spawn_ice(target_enemy, raw_damage, controller)
		else:
			if spell.has_method("launch_fire"):
				spell.launch_fire(controller.global_position, target_enemy, raw_damage, controller)
		await spell.tree_exited

	# 2. PAPNŐ (PRIEST) – Közvetlenül az ellenség mezőjén jelenik meg
	elif c_name == "Priest" and p_scene != null:
		var spell = p_scene.instantiate()
		controller.get_parent().add_child(spell)
		spell.global_position = target_enemy.global_position
		spell.z_index = 12

		if spell.has_method("cast_attack"):
			await spell.cast_attack(target_enemy, raw_damage, controller)
		elif spell.has_method("spawn_at"):
			spell.spawn_at(target_enemy, raw_damage, controller)
			await spell.tree_exited
		elif spell.has_method("launch"):
			spell.launch(target_enemy.global_position, target_enemy, raw_damage, controller)
			await spell.tree_exited
		else:
			var spell_sprite = spell as AnimatedSprite2D if spell is AnimatedSprite2D else spell.find_child("AnimatedSprite2D", true, false) as AnimatedSprite2D
			if spell_sprite and spell_sprite.sprite_frames:
				var s_anim = "attack_1" if spell_sprite.sprite_frames.has_animation("attack_1") else "default"
				if spell_sprite.sprite_frames.has_animation(s_anim):
					spell_sprite.play(s_anim)
					await spell_sprite.animation_finished
			else:
				await get_tree().create_timer(0.35).timeout

			target_enemy.take_damage(raw_damage)
			controller.progression.gain_combat_xp(1)
			if is_instance_valid(spell): spell.queue_free()

	# 3. ÍJÁSZ ÉS ÁLTALÁNOS LÖVEDÉKEK
	elif p_scene != null:
		var proj = p_scene.instantiate()
		controller.get_parent().add_child(proj)
		if proj.has_method("launch"):
			proj.launch(controller.global_position, target_enemy, raw_damage, controller)
		elif proj.has_method("spawn_at"):
			proj.spawn_at(target_enemy, raw_damage, controller)
		await proj.tree_exited

	# 4. TARTALÉK
	else:
		target_enemy.take_damage(raw_damage)
		controller.progression.gain_combat_xp(1)

func _get_active_projectile_scene() -> PackedScene:
	if controller and controller.active_class and controller.active_class.projectile_scene != null:
		return controller.active_class.projectile_scene
	return projectile_scene

func _get_projectile_delay() -> float:
	if projectile_delay > 0.0:
		return projectile_delay
	if controller and controller.active_class:
		var c = controller.active_class
		if c.get("attack_fps") != null and c.get("release_frame") != null and c.attack_fps > 0.0:
			return float(c.release_frame) / c.attack_fps
	return 0.0

func cast_priest_self_heal() -> void:
	if not controller.is_alive() or in_battle or is_attacking or controller.is_moving or controller.is_stunned:
		return
	var c_name = controller.active_class.class_name_id if controller.active_class else ""
	if c_name != "Priest": return
	if controller.current_hp >= controller.max_hp: return

	is_attacking = true
	var sprite = controller.sprite
	if sprite and sprite.sprite_frames:
		if sprite.sprite_frames.has_animation("heal"): sprite.play("heal")
		elif sprite.sprite_frames.has_animation("attack_1"): sprite.play("attack_1")

	var p_scene = _get_active_projectile_scene()
	if p_scene != null:
		var spell = p_scene.instantiate()
		controller.get_parent().add_child(spell)
		if spell.has_method("cast_heal_at"):
			await spell.cast_heal_at(controller.global_position)
		else:
			spell.queue_free()

	var heal_val = maxi(25, ceili(float(controller.max_hp) * 0.35))
	controller.progression.heal(heal_val)

	if sprite and controller.is_alive(): sprite.play("idle")
	is_attacking = false
	controller.trigger_monsters_turn()

func is_hero_ranged_attack(target_cell: Vector2i) -> bool:
	if controller.active_class == null: return is_ranged
	var c_name = controller.active_class.class_name_id
	if c_name in ["Archer", "Wizard", "Priest"]: return true
	if c_name == "Soldier":
		var grid_mgr = controller.mover.grid_manager
		var dist = grid_mgr.get_grid_distance(controller.grid_pos, target_cell) if grid_mgr else 1
		return dist > 1
	return is_ranged

func get_effective_attack_range() -> int:
	if controller.active_class == null: return 1
	var c_name = controller.active_class.class_name_id
	var vis = controller.visuals.vision_limit if controller.visuals else 25
	if c_name in ["Archer", "Priest"]: return vis
	elif c_name == "Wizard": return mini(5, vis)
	elif c_name == "Soldier": return mini(3, vis)
	return 1

func _resolve_hero_attack_action(target_enemy: Node2D) -> Dictionary:
	var c_name = controller.active_class.class_name_id if controller.active_class else "Adventurer"
	var grid_mgr = controller.mover.grid_manager
	var dist = grid_mgr.get_grid_distance(controller.grid_pos, target_enemy.grid_pos) if (grid_mgr and target_enemy) else 1

	var anim = "attack_1"
	var mult = 1.0
	var ranged = false

	match c_name:
		"Archer":
			ranged = true
			if randf() < 0.25: anim = "attack_2"; mult = 1.75
		"Knight":
			if randf() < 0.12: anim = "attack_3"; mult = 2.0
			elif randf() < 0.38: anim = "attack_2"; mult = 1.25
		"Soldier":
			if dist > 1: anim = "attack_2"; ranged = true
			else: anim = "attack_1"
		"Wizard":
			ranged = true
			anim = "attack_1" if wizard_element == "ice" else "attack_2"
		"Priest":
			ranged = true
			anim = "attack_1"

	return {"anim": anim, "multiplier": mult, "is_ranged": ranged}

func _get_enemy_at_cell(cell: Vector2i) -> Node2D:
	for enemy in get_tree().get_nodes_in_group("enemies"):
		if is_instance_valid(enemy) and enemy.get("grid_pos") == cell: return enemy
	return null
