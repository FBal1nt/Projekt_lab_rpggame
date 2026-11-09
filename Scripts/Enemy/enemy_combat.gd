extends Node
class_name EnemyCombat

var controller: EnemyController
var armored_combat: ArmoredEnemyCombat

@export_group("Kábítás és Időzítés")
@export var stun_duration: float = 1.5

var is_attacking: bool = false
var is_blocking_active: bool = false
var is_dead: bool = false

func setup(p_controller: EnemyController) -> void:
	controller = p_controller
	is_attacking = false
	is_blocking_active = false
	armored_combat = ArmoredEnemyCombat.new(self)

func is_armored_enemy() -> bool:
	if controller == null or controller.enemy_data == null: return false
	return controller.enemy_data.special_profile != 0 # Nem STANDARD

func can_attack_hero(hero_cell: Vector2i) -> bool:
	if controller == null: return false
	var diff = hero_cell - controller.grid_pos
	var a_range = controller.attack_range

	if a_range > 1:
		return maxi(absi(diff.x), absi(diff.y)) <= a_range
	else:
		return diff.y == 0 and absi(diff.x) == 1

func roll_attack_damage() -> int:
	return controller.enemy_data.roll_attack_damage() if (controller and controller.enemy_data) else 10

func take_damage(incoming_raw_damage: int) -> int:
	if is_dead or controller == null or controller.enemy_data == null: return 0
	var data = controller.enemy_data

	if data.check_dodge():
		print("💨 [%s KITÉRT] Elsuhant a támadás elől!" % controller.monster_name)
		return 0

	var actual_raw = incoming_raw_damage

	if is_blocking_active:
		var reduction = data.block_reduction if data.get("block_reduction") != null else 0.5
		actual_raw = ceili(float(incoming_raw_damage) * (1.0 - reduction))

	if data.get("flat_armor") != null and data.flat_armor > 0:
		var absorbed = mini(actual_raw, data.flat_armor)
		actual_raw = maxi(0, actual_raw - data.flat_armor)
		print("🛡️ [%s PÁNCÉL] -%d sebzés elnyelve! (Maradt: %d)" % [controller.monster_name, absorbed, actual_raw])

	var dealt = data.take_damage(actual_raw)

	if not data.is_alive():
		is_dead = true
		if controller.brain and controller.brain.ai_timer and is_instance_valid(controller.brain.ai_timer):
			controller.brain.ai_timer.stop()
		if controller.mover:
			controller.mover.path_queue.clear()

	return dealt

func try_trigger_block() -> bool:
	if is_dead or not controller.is_monster_alive(): return false
	if controller.visuals == null: return false

	var block_anim = controller.visuals._get_block_anim_name()
	if block_anim == "": return false

	var chance = controller.enemy_data.block_chance if (controller.enemy_data and controller.enemy_data.get("block_chance") != null) else 0.35
	if randf() < chance:
		is_blocking_active = true
		if controller.visuals.sprite:
			controller.visuals.sprite.play(block_anim)
		print("🛡️ [%s BLOKKOL] Felemeli a pajzsát a csapás ellen!" % controller.monster_name)
		return true

	is_blocking_active = false
	return false

func attack_hero(target_hero: HeroController) -> void:
	if is_dead or is_attacking or not controller.is_monster_alive(): return
	if not is_instance_valid(target_hero): return
	if target_hero.is_moving or not can_attack_hero(target_hero.grid_pos): return

	var battle_ui = get_tree().get_first_node_in_group("battle_ui") as BattleDialog
	if battle_ui != null and not battle_ui.combat_active:
		if target_hero.has_method("cancel_movement_immediately"):
			target_hero.cancel_movement_immediately()
		battle_ui.open_battle(target_hero, controller, true)

func opportunity_attack(target_hero: HeroController) -> void:
	if is_dead or not is_instance_valid(target_hero): return
	var dmg = roll_attack_damage()
	print("[%s ELLÉPÉSI CSAPÁS] Ráüt a menekülő hősre: %d sebzéssel!" % [controller.monster_name, dmg])
	target_hero.take_damage(dmg)

## KÖR VÉGREHAJTÁSA A PÁRBAJBAN
func perform_combat_turn(target_hero: HeroController, is_extra_attack: bool = false) -> int:
	if is_dead or not is_instance_valid(target_hero): return 0

	# Ha a hős korábban hátralökődött, odalépünk mellé:
	if controller.attack_range <= 1 and not can_attack_hero(target_hero.grid_pos):
		await armored_combat.step_closer_to_hero(target_hero)

	if controller.visuals:
		controller.visuals.update_facing(target_hero.grid_pos.x)

	# 1. PÁNCÉLOZOTT ELLENSÉG: ÁTADJUK A VEZÉRLÉST AZ ARMORED COMBAT OSZTÁLYNAK!
	if is_armored_enemy():
		return await armored_combat.perform_turn(target_hero, is_extra_attack)

	# 2. STANDARD / SIMA ELLENSÉGEK ALAP TÁMADÁSA:
	var data = controller.enemy_data
	var heavy_chance = data.heavy_attack_chance if data else 0.35
	var heavy_mult = data.heavy_attack_multiplier if data else 1.5
	var light_mult = data.light_attack_multiplier if data else 0.9

	var anim = controller.visuals._get_attack_anim_name() if controller.visuals else "attack_1"
	var multiplier = 1.0

	if controller.visuals and controller.visuals.has_combo_attacks():
		if randf() < heavy_chance:
			anim = controller.visuals.get_combo_anim(1)
			multiplier = heavy_mult
		else:
			anim = controller.visuals.get_combo_anim(0)
			multiplier = light_mult

	var sprite = controller.visuals.sprite if controller.visuals else null
	if anim != "" and sprite and sprite.sprite_frames and sprite.sprite_frames.has_animation(anim):
		sprite.play(anim)
		if target_hero.has_method("try_trigger_block"): target_hero.try_trigger_block()
		await sprite.animation_finished
		if not is_dead and controller.visuals:
			controller.visuals.play_idle_anim()

	var raw_dmg = ceili(float(roll_attack_damage()) * multiplier)

	if data and data.projectile_scene != null:
		var proj = data.projectile_scene.instantiate()
		controller.get_parent().add_child(proj)
		if proj.has_method("launch"):
			proj.launch(controller.global_position, target_hero, raw_dmg, controller)
		await proj.tree_exited
	else:
		target_hero.take_damage(raw_dmg)

	var drained = data.apply_life_steal(raw_dmg) if data else 0
	if drained > 0:
		print("🩸 [%s VÁMPÍRIZMUS] Visszaszívott %d HP-t!" % [controller.monster_name, drained])

	if target_hero.has_method("play_hurt_reaction"):
		await target_hero.play_hurt_reaction()

	return raw_dmg

func set_all_monsters_ai_frozen(frozen: bool) -> void:
	for enemy in get_tree().get_nodes_in_group("enemies"):
		if is_instance_valid(enemy) and enemy.get("brain") != null:
			if enemy.brain.get("ai_timer") != null and is_instance_valid(enemy.brain.ai_timer):
				enemy.brain.ai_timer.paused = frozen

func _perform_overworld_ranged_initiation(hero: HeroController) -> void:
	if is_dead or is_attacking or not controller.is_monster_alive(): return
	var battle_ui = get_tree().get_first_node_in_group("battle_ui") as BattleDialog
	if battle_ui != null and battle_ui.combat_active: return

	var hero_is_ranged: bool = false
	if hero.combat and hero.combat.has_method("is_hero_ranged_attack"):
		hero_is_ranged = hero.combat.is_hero_ranged_attack(controller.grid_pos)
	elif hero.get("is_ranged") != null:
		hero_is_ranged = bool(hero.get("is_ranged"))

	if hero_is_ranged:
		if battle_ui != null and not battle_ui.combat_active:
			if hero.has_method("cancel_movement_immediately"):
				hero.cancel_movement_immediately()
			battle_ui.open_battle(hero, controller, true)
		return

	is_attacking = true
	if controller.visuals:
		controller.visuals.update_facing(hero.grid_pos.x)

	var anim = controller.visuals._get_attack_anim_name() if controller.visuals else ""
	var sprite = controller.visuals.sprite if controller.visuals else null

	if anim != "" and sprite:
		sprite.play(anim)
		var anim_len = 0.4
		if sprite.sprite_frames:
			var frames = sprite.sprite_frames.get_frame_count(anim)
			var fps = sprite.sprite_frames.get_animation_speed(anim)
			if fps > 0: anim_len = float(frames) / fps
		await get_tree().create_timer(anim_len).timeout
		if not is_dead and controller.visuals:
			controller.visuals.play_idle_anim()

	var raw_dmg = roll_attack_damage()
	if controller.enemy_data and controller.enemy_data.projectile_scene != null:
		var proj = controller.enemy_data.projectile_scene.instantiate()
		controller.get_parent().add_child(proj)
		if proj.has_method("launch"):
			proj.launch(controller.global_position, hero, raw_dmg, controller)
		if is_instance_valid(proj):
			await proj.tree_exited
	else:
		if is_instance_valid(hero):
			hero.take_damage(raw_dmg)

	if is_instance_valid(hero) and hero.is_alive():
		if hero.has_method("try_trigger_block"):
			hero.try_trigger_block()
		if not hero.is_moving and hero.has_method("play_hurt_reaction"):
			hero.play_hurt_reaction()

	is_attacking = false

func play_overworld_death() -> void:
	if controller.visuals:
		controller.visuals.update_fog_visibility()

	var d_anim = controller.visuals._get_death_anim_name() if controller.visuals else ""
	var sprite = controller.visuals.sprite if controller.visuals else null

	if d_anim != "" and sprite:
		sprite.play(d_anim)
		await sprite.animation_finished

	var data = controller.enemy_data
	if data and data.can_self_revive and not data.has_resurrected():
		print("💀 [%s ELTERÜLT] A csontok a földön hevernek..." % controller.monster_name)
		var delay = data.resurrect_delay if data.get("resurrect_delay") != null else 3.0
		await get_tree().create_timer(delay).timeout

		print("✨ [%s FELTÁMADT] A csontok újra összeállnak!" % controller.monster_name)
		if controller.visuals:
			await controller.visuals.play_respawn_animation()

		data.revive(data.resurrect_hp_percent)
		is_dead = false

		if not controller.is_in_group("enemies"):
			controller.add_to_group("enemies")

		if controller.visuals:
			controller.visuals.update_fog_visibility()

		if controller.brain and controller.brain.ai_timer and is_instance_valid(controller.brain.ai_timer):
			controller.brain.ai_timer.start()
		return

	if data and data.can_split:
		if randf() < data.split_chance_on_death:
			_spawn_split_slimes()

	controller.remove_from_group("enemies")
	controller.queue_free()

func _spawn_split_slimes() -> void:
	if controller == null or controller.mover == null: return
	print("🟢 [%s KETTÉVÁLT] Két kis nyálka születik a tócsából!" % controller.monster_name)
	var spawn_dirs = [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]
	spawn_dirs.shuffle()

	var spawned_count = 0
	for dir in spawn_dirs:
		if spawned_count >= 2: break
		var spawn_cell = controller.grid_pos + dir
		if controller.mover.is_cell_walkable(spawn_cell):
			var small_slime = controller.duplicate() as EnemyController

			var child_data = controller.enemy_data.duplicate() as EnemyData
			child_data.can_split = false
			child_data.max_hp = ceili(float(controller.enemy_data.max_hp) * 0.5)
			child_data.base_damage = maxi(4, ceili(float(controller.enemy_data.base_damage) * 0.6))
			child_data.initialize()
			small_slime.enemy_data = child_data

			controller.get_parent().add_child(small_slime)
			small_slime.grid_pos = spawn_cell
			small_slime.position = controller.mover.floor_layer.map_to_local(spawn_cell)

			small_slime.is_dead = false
			small_slime.visible = true

			if small_slime.visuals and small_slime.visuals.sprite and controller.visuals and controller.visuals.sprite:
				small_slime.visuals.sprite.scale = controller.visuals.sprite.scale * 0.65

			if small_slime.visuals:
				small_slime.visuals.play_respawn_animation()

			spawned_count += 1
