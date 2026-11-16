class_name EliteEnemyCombat
extends RefCounted

var combat: EnemyCombat
var controller: EnemyController

## Kétkezes Csontváz körszámlálója (minden 2. körben sújt le)
var greatsword_turn_counter: int = 0
## Nekromanta fázisállapot (0: 100%-75%, 1: 75%-50%, 2: <=50% mágia nélkül)
var necromancer_phase: int = 0
var necromancer_vanished: bool = false
var necromancer_summoned_minions: Array[EnemyController] = []
var necromancer_return_cell: Vector2i = Vector2i.ZERO
var _necromancer_phase_transition_active: bool = false

func _init(p_combat: EnemyCombat) -> void:
	combat = p_combat
	controller = p_combat.controller

## FŐ KÖRVÉGREHAJTÓ FÜGGVÉNY A PÁRBAJBAN
func perform_turn(target_hero: HeroController, is_extra_attack: bool = false) -> int:
	if combat == null or combat.is_dead or not is_instance_valid(target_hero):
		return 0

	var data = controller.enemy_data if controller else null
	var profile = data.special_profile if (data and data.get("special_profile") != null) else 0

	match profile:
		4: # NECROMANCER
			return await _perform_necromancer_turn(target_hero)
		5: # ELITE_ORC
			return await _perform_elite_orc_turn(target_hero, is_extra_attack)
		6: # GREATSWORD_SKELETON
			return await _perform_greatsword_skeleton_turn(target_hero)
		7: # BEARMAN / WEREBEAR
			return await _perform_bearman_turn(target_hero)
		8: # WEREWOLF
			return await _perform_werewolf_turn(target_hero)
		_:
			return await _perform_generic_turn(target_hero)

# ==============================================================================
# 1. NEKROMANTA (3-Fázisú Főellenség: Kasza + Mágia + Idézés/Eltűnés)
# ==============================================================================
func is_necromancer() -> bool:
	var data = controller.enemy_data if controller else null
	return data != null and int(data.special_profile) == 4


func is_necromancer_vanished() -> bool:
	return is_necromancer() and necromancer_vanished


func is_necromancer_out_of_magic() -> bool:
	return is_necromancer() and necromancer_phase >= 2 and not necromancer_vanished


func get_necromancer_phase_hp_floor() -> int:
	if not is_necromancer() or controller == null:
		return 0
	var max_h := maxi(1, controller.max_hp)
	if necromancer_phase == 0:
		return floori(float(max_h) * 0.75)
	if necromancer_phase == 1:
		return floori(float(max_h) * 0.50)
	return 0


func _get_anim_fps(anim: String, default_fps: float = 8.0) -> float:
	var sprite = controller.visuals.sprite if (controller and controller.visuals) else null
	if sprite and sprite.sprite_frames and sprite.sprite_frames.has_animation(anim):
		var s_fps = sprite.sprite_frames.get_animation_speed(anim)
		if s_fps > 0.0:
			return s_fps
	return default_fps


func _perform_necromancer_turn(target_hero: HeroController) -> int:
	if necromancer_vanished or _necromancer_phase_transition_active:
		return 0

	# 3. Fázis (<= 50% HP, mindkét idézési hullám legyőzve): elfogyott a mágiája, egyedül küzd kaszával
	if necromancer_phase >= 2:
		return await _necromancer_cast_scythe_attack(target_hero)

	# 1–2. Fázis: közelben nagy kaszás suhintás ('attack_1' + hátralökés), távolról mágikus lövedék ('attack_2')
	if _is_hero_adjacent(target_hero):
		return await _necromancer_cast_scythe_attack(target_hero)
	return await _necromancer_cast_magic_attack(target_hero)


## 'attack_1': Nagy kaszás suhintás, az 5. képkockánál hátralöki a hőst
func _necromancer_cast_scythe_attack(target_hero: HeroController) -> int:
	if not is_instance_valid(target_hero):
		return 0

	var anim = safe_play_anim("attack_1", "attack_1")
	if target_hero.has_method("try_trigger_block"):
		target_hero.try_trigger_block()

	var fps := _get_anim_fps(anim, 8.0)
	var impact_frame := get_impact_frame("attack_1", 5)
	await combat.get_tree().create_timer(float(impact_frame) / fps).timeout

	if not is_instance_valid(target_hero) or combat.is_dead:
		await await_anim_finish(anim)
		return 0

	var raw_dmg := combat.roll_attack_damage()
	target_hero.take_damage(raw_dmg)
	if target_hero.has_method("play_hurt_reaction"):
		target_hero.play_hurt_reaction()

	if is_instance_valid(target_hero) and target_hero.is_alive() and combat.armored_combat:
		var prev_pos := target_hero.grid_pos
		await combat.armored_combat.apply_knockback(target_hero, 2)
		if target_hero.grid_pos != prev_pos:
			var battle_ui = _get_battle_dialog()
			if battle_ui and battle_ui.combat_active:
				battle_ui._append_log("[color=orange]🌀 [%s KASZACSAPÁS] A Nekromanta kaszájával hátralökte a hőst![/color]" % controller.monster_name)
				battle_ui.interrupt_combat_due_to_knockback()

	await await_anim_finish(anim)
	return raw_dmg


## 'attack_2': Mágikus támadás lövedékkel
func _necromancer_cast_magic_attack(target_hero: HeroController) -> int:
	if not is_instance_valid(target_hero):
		return 0

	var anim = safe_play_anim("attack_2", "attack_1")
	if target_hero.has_method("try_trigger_block"):
		target_hero.try_trigger_block()

	var fps := _get_anim_fps(anim, 8.0)
	var impact_frame := get_impact_frame("attack_2", 5)
	await combat.get_tree().create_timer(float(impact_frame) / fps).timeout

	if not is_instance_valid(target_hero) or combat.is_dead:
		await await_anim_finish(anim)
		return 0

	var raw_dmg := combat.roll_attack_damage()
	var proj_scene: PackedScene = controller.enemy_data.projectile_scene if controller.enemy_data else null
	if proj_scene == null:
		var default_proj := "res://Scenes/Projectiles/necromancer_attack.tscn"
		if ResourceLoader.exists(default_proj):
			proj_scene = load(default_proj) as PackedScene

	if proj_scene != null:
		var proj = proj_scene.instantiate()
		controller.get_parent().add_child(proj)
		if proj.has_method("launch"):
			proj.launch(controller.global_position, target_hero, raw_dmg, controller)
		elif proj.has_method("launch_fire"):
			proj.launch_fire(controller.global_position, target_hero, raw_dmg, controller)
		elif proj.has_method("spawn_ice"):
			proj.spawn_ice(target_hero, raw_dmg, controller)
		elif proj.has_method("spawn_at"):
			proj.spawn_at(target_hero, raw_dmg, controller)
		if is_instance_valid(proj):
			await proj.tree_exited
	else:
		target_hero.take_damage(raw_dmg)

	if is_instance_valid(target_hero) and target_hero.is_alive():
		if target_hero.has_method("play_hurt_reaction"):
			await target_hero.play_hurt_reaction()

	await await_anim_finish(anim)
	return raw_dmg


## Sebzés utáni fázisellenőrzés (75%-nál 1. idézés, 50%-nál 2. erősebb idézés)
func handle_necromancer_post_damage(target_hero: HeroController = null) -> bool:
	if not is_necromancer() or combat.is_dead or controller == null or not controller.is_monster_alive():
		return false
	if necromancer_vanished or _necromancer_phase_transition_active:
		return false

	var max_h := maxi(1, controller.max_hp)
	var cur_h := controller.current_hp
	if necromancer_phase == 0 and cur_h <= floori(float(max_h) * 0.75):
		necromancer_phase = 1
		await _trigger_necromancer_summon_and_vanish(1, target_hero)
		return true
	if necromancer_phase == 1 and cur_h <= floori(float(max_h) * 0.50):
		necromancer_phase = 2
		await _trigger_necromancer_summon_and_vanish(2, target_hero)
		return true
	return false


func _trigger_necromancer_summon_and_vanish(wave_index: int, target_hero: HeroController) -> void:
	_necromancer_phase_transition_active = true
	combat.set_all_monsters_ai_frozen(true)
	if controller.brain and controller.brain.ai_timer and is_instance_valid(controller.brain.ai_timer):
		controller.brain.ai_timer.stop()

	var battle_ui = _get_battle_dialog()
	if battle_ui and battle_ui.combat_active:
		var log_msg := (
			"[color=purple]💀 [%s 75%% HP] 'Szolgáim, állítsátok meg!' — Szörnyeket idéz és eltűnik![/color]"
			if wave_index == 1
			else "[color=purple]💀 [%s 50%% HP] 'Elég! Erősebb élőholtak, pusztítsátok el!' — Újabb idézés![/color]"
		) % controller.monster_name
		battle_ui._append_log(log_msg)
		await combat.get_tree().create_timer(0.35).timeout
		if battle_ui and battle_ui.combat_active:
			battle_ui.interrupt_combat_due_to_boss_phase()

	var hero_locked := is_instance_valid(target_hero)
	if hero_locked:
		target_hero.is_attacking = true

	var necro_anim := safe_play_anim("summon", "attack_2")
	var fps := _get_anim_fps(necro_anim, 8.0)
	var impact_frame := mini(5, 9)
	await combat.get_tree().create_timer(float(impact_frame) / fps).timeout

	var spawned_count := await _spawn_necromancer_wave_minions(wave_index)
	await await_anim_finish(necro_anim)

	if spawned_count > 0 and is_instance_valid(controller) and controller.is_monster_alive():
		necromancer_return_cell = controller.grid_pos
		necromancer_vanished = true
		_play_summon_fx(controller.global_position)
		controller.visible = false
		if controller.is_in_group("enemies"):
			controller.remove_from_group("enemies")
	else:
		# Ha egyáltalán nem volt szabad mező az idézéshez, maradjon látható és küzdjön tovább
		if controller.brain and controller.brain.ai_timer and is_instance_valid(controller.brain.ai_timer):
			controller.brain.ai_timer.start()

	if is_instance_valid(target_hero) and hero_locked:
		target_hero.is_attacking = false
	combat.set_all_monsters_ai_frozen(false)
	_necromancer_phase_transition_active = false


func _spawn_necromancer_wave_minions(wave_index: int) -> int:
	necromancer_summoned_minions.clear()
	var gs = combat.get_tree().root.get_node_or_null("GameState")
	var diff_id := ""
	if gs and "run_state" in gs and gs.run_state is Dictionary:
		diff_id = String(gs.run_state.get("difficulty_id", "normal")).to_lower()

	var wave_specs: Array[Dictionary] = []
	if wave_index == 1:
		wave_specs = [
			{"name": "Páncélozott Csontváz" if "hard" in diff_id else "Csontváz", "data_path": "res://Data/Monsters/armored_skeleton_data.tres" if "hard" in diff_id else "res://Data/Monsters/skeleton_data.tres"},
			{"name": "Csontváz Íjász", "data_path": "res://Data/Monsters/skeleton_archer_data.tres"}
		]
	else:
		wave_specs = [
			{"name": "Páncélozott Ork" if "hard" in diff_id else "Páncélozott Csontváz", "data_path": "res://Data/Monsters/armored_orc_data.tres" if "hard" in diff_id else "res://Data/Monsters/armored_skeleton_data.tres"},
			{"name": "Nagy Kardos Csontváz", "data_path": "res://Data/Monsters/greatsword_skeleton_data.tres"}
		]

	var spawn_cells := _find_summon_cells(wave_specs.size())
	if spawn_cells.is_empty():
		print("⚠️ [%s] Nincs szabad mező a hullám megidézéséhez!" % controller.monster_name)
		return 0

	var enemy_scene := load("res://Scenes/Enemy/enemy.tscn") as PackedScene
	if enemy_scene == null:
		return 0

	var fl := _get_floor_layer()
	var spawned_sprites: Array[AnimatedSprite2D] = []
	var spawned_minions: Array[EnemyController] = []

	for idx in range(mini(wave_specs.size(), spawn_cells.size())):
		var cell := spawn_cells[idx]
		var spec := wave_specs[idx]
		var world_pos: Vector2 = fl.map_to_local(cell) if fl else controller.global_position
		_play_summon_fx(world_pos)

		var minion := enemy_scene.instantiate() as EnemyController
		if minion == null:
			continue
		if ResourceLoader.exists(spec["data_path"]):
			var raw_data := load(spec["data_path"]) as EnemyData
			if raw_data != null:
				var minion_data := raw_data.duplicate() as EnemyData
				# Az idézett szolgák ne támadjanak fel 3 mp múlva, így a legyőzésük azonnal visszahozza a Nekromantát
				minion_data.can_self_revive = false
				minion.enemy_data = minion_data

		minion.fog_of_war = controller.fog_of_war
		minion.position = world_pos
		controller.get_parent().add_child(minion)
		minion.grid_pos = cell
		if minion.mover:
			minion.mover.grid_pos = cell
			minion.mover.current_step_target = cell
		minion.is_dead = false
		if not minion.is_in_group("enemies"):
			minion.add_to_group("enemies")
		minion.update_fog_visibility()
		if minion.brain and minion.brain.ai_timer and is_instance_valid(minion.brain.ai_timer):
			minion.brain.ai_timer.stop()

		necromancer_summoned_minions.append(minion)
		spawned_minions.append(minion)
		minion.tree_exited.connect(_on_summoned_minion_exited.bind(minion))

		var m_sprite: AnimatedSprite2D = minion.visuals.sprite if (minion.visuals and minion.visuals.sprite) else null
		if m_sprite and m_sprite.sprite_frames and m_sprite.sprite_frames.has_animation("summon"):
			m_sprite.play("summon")
			spawned_sprites.append(m_sprite)

		print("💀 [%s IDÉZÉS - %d. HULLÁM] %s megjelent a (%d, %d) mezőn!" % [controller.monster_name, wave_index, minion.monster_name, cell.x, cell.y])

	if not spawned_sprites.is_empty():
		var last_spr := spawned_sprites[0]
		if is_instance_valid(last_spr) and last_spr.is_playing() and last_spr.animation == "summon":
			await last_spr.animation_finished
	elif not spawned_minions.is_empty():
		await combat.get_tree().create_timer(0.45).timeout

	for minion in spawned_minions:
		if not is_instance_valid(minion):
			continue
		if minion.visuals and minion.visuals.has_method("play_idle_anim"):
			minion.visuals.play_idle_anim()
		if minion.brain and minion.brain.ai_timer and is_instance_valid(minion.brain.ai_timer):
			minion.brain.ai_timer.start()

	return spawned_minions.size()


func _is_cell_free_for_spawn(candidate: Vector2i, gm: GridManager) -> bool:
	if gm != null and gm.is_cell_solid(candidate):
		return false
	if gm != null and gm.floor_layer != null and gm.floor_layer.get_cell_source_id(candidate) == -1:
		return false

	for player_node in combat.get_tree().get_nodes_in_group("player"):
		if is_instance_valid(player_node) and player_node is HeroController:
			var hero := player_node as HeroController
			if hero.is_alive():
				if hero.grid_pos == candidate or (hero.is_moving and hero.current_step_target == candidate):
					return false

	for enemy_node in combat.get_tree().get_nodes_in_group("enemies"):
		if is_instance_valid(enemy_node) and enemy_node is EnemyController and enemy_node != controller:
			var enemy := enemy_node as EnemyController
			if enemy.is_monster_alive():
				if enemy.grid_pos == candidate or (enemy.is_moving and enemy.current_step_target == candidate):
					return false

	return true


func _find_summon_cells(wanted_count: int) -> Array[Vector2i]:
	var found: Array[Vector2i] = []
	var gm: GridManager = controller.mover.grid_manager if (controller and controller.mover) else null
	if gm == null and combat != null:
		gm = combat.get_tree().get_first_node_in_group("grid_manager") as GridManager

	var rings: Array[Vector2i] = []
	var cardinals: Array[Vector2i] = [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]
	cardinals.shuffle()
	var diagonals: Array[Vector2i] = [Vector2i(1, 1), Vector2i(-1, 1), Vector2i(1, -1), Vector2i(-1, -1)]
	diagonals.shuffle()
	rings.append_array(cardinals)
	rings.append_array(diagonals)

	for r in [2, 3]:
		var outer: Array[Vector2i] = []
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				if maxi(absi(dx), absi(dy)) == r:
					outer.append(Vector2i(dx, dy))
		outer.shuffle()
		rings.append_array(outer)

	for offset in rings:
		if found.size() >= wanted_count:
			break
		var candidate := controller.grid_pos + offset
		if not found.has(candidate) and _is_cell_free_for_spawn(candidate, gm):
			found.append(candidate)

	return found


func _find_reappear_cell(preferred_cell: Vector2i) -> Vector2i:
	var gm: GridManager = controller.mover.grid_manager if (controller and controller.mover) else null
	if gm == null and combat != null:
		gm = combat.get_tree().get_first_node_in_group("grid_manager") as GridManager

	if _is_cell_free_for_spawn(preferred_cell, gm):
		return preferred_cell

	for r in [1, 2, 3]:
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				var candidate := preferred_cell + Vector2i(dx, dy)
				if _is_cell_free_for_spawn(candidate, gm):
					return candidate

	return preferred_cell


func _play_summon_fx(world_pos: Vector2) -> void:
	var effect_paths := [
		"res://Scenes/Projectiles/summon_effect.tscn",
		"res://Scenes/Projectiles/necromancer_summon.tscn"
	]
	for ep in effect_paths:
		if ResourceLoader.exists(ep):
			var eff_res = load(ep) as PackedScene
			if eff_res:
				var eff = eff_res.instantiate() as Node2D
				if eff and controller and controller.get_parent():
					controller.get_parent().add_child(eff)
					eff.global_position = world_pos
					eff.z_index = 12
					var anim_spr = eff.get_node_or_null("AnimatedSprite2D") as AnimatedSprite2D
					if anim_spr:
						anim_spr.stop()
						anim_spr.frame = 0
						if anim_spr.sprite_frames and anim_spr.sprite_frames.has_animation("default"):
							anim_spr.play("default")
						anim_spr.animation_finished.connect(eff.queue_free)
					else:
						combat.get_tree().create_timer(1.0).timeout.connect(eff.queue_free)
			break


func _on_summoned_minion_exited(_minion: EnemyController) -> void:
	if not is_instance_valid(controller) or not is_instance_valid(combat) or combat.is_dead:
		return
	if not necromancer_vanished:
		return

	var remaining: Array[EnemyController] = []
	for m in necromancer_summoned_minions:
		if is_instance_valid(m) and not m.is_queued_for_deletion() and m.is_monster_alive():
			remaining.append(m)
	necromancer_summoned_minions = remaining

	if remaining.is_empty():
		_reappear_necromancer()


func _reappear_necromancer() -> void:
	if not necromancer_vanished or not is_instance_valid(controller) or combat.is_dead:
		return
	if not controller.is_inside_tree():
		return

	await combat.get_tree().create_timer(0.35).timeout
	if not is_instance_valid(controller) or not controller.is_inside_tree() or combat.is_dead:
		return

	var battle_ui = _get_battle_dialog()
	while battle_ui != null and battle_ui.combat_active:
		await combat.get_tree().create_timer(0.2).timeout
		if not is_instance_valid(controller) or not controller.is_inside_tree() or combat.is_dead:
			return
		battle_ui = _get_battle_dialog()

	var reappear_cell := _find_reappear_cell(necromancer_return_cell)
	var fl := _get_floor_layer()
	controller.grid_pos = reappear_cell
	if controller.mover:
		controller.mover.grid_pos = reappear_cell
		controller.mover.current_step_target = reappear_cell
	if fl:
		controller.position = fl.map_to_local(reappear_cell)

	_play_summon_fx(controller.global_position)
	necromancer_vanished = false
	if not controller.is_in_group("enemies"):
		controller.add_to_group("enemies")
	controller.visible = true
	controller.update_fog_visibility()
	if controller.visuals:
		controller.visuals.play_idle_anim()

	var heroes := combat.get_tree().get_nodes_in_group("player")
	if not heroes.is_empty() and is_instance_valid(heroes[0]) and heroes[0] is HeroController and controller.visuals:
		controller.visuals.update_facing((heroes[0] as HeroController).grid_pos.x)

	if necromancer_phase >= 2:
		print("⚔️ [%s VÉGSŐ FÁZIS] Elfogyott a mágiája — most már egyedül, kaszával küzd tovább!" % controller.monster_name)
	else:
		print("💀 [%s VISSZATÉRT] A csatlósai elestek, újra harcba száll!" % controller.monster_name)

	if controller.brain and controller.brain.ai_timer and is_instance_valid(controller.brain.ai_timer):
		controller.brain.ai_timer.start()

# ==============================================================================
# 2. ELIT ORK (Frenzy / Dühöngés)
# ==============================================================================
func _perform_elite_orc_turn(target_hero: HeroController, is_extra_attack: bool) -> int:
	var max_h = maxi(1, controller.max_hp)
	var cur_h = controller.current_hp
	var hp_pct = float(cur_h) / float(max_h)
	var missing_hp_pct = 1.0 - hp_pct

	# Nyers sebzés skálázódása a hiányzó HP alapján (1.0x-től akár 1.85x-ig)
	var frenzy_multiplier = lerpf(1.0, 1.85, missing_hp_pct)

	# 1. KRITIKUS ÁLLAPOT (HP < 30%): MINDIG attack_3 garantált kritikus csapással
	if hp_pct < 0.30:
		var crit_mult = 1.65
		var anim = safe_play_anim("attack_3", "attack_1")
		if target_hero.has_method("try_trigger_block"):
			target_hero.try_trigger_block()

		var impact_frame = get_impact_frame("attack_3", 4)
		await combat.get_tree().create_timer(float(impact_frame) / 8.0).timeout

		var raw_dmg = ceili(float(combat.roll_attack_damage()) * frenzy_multiplier * crit_mult)
		target_hero.take_damage(raw_dmg)

		var battle_ui = _get_battle_dialog()
		if battle_ui and battle_ui.combat_active:
			battle_ui._append_log("[color=red]🔥 [%s VÉRSZOMJ] Dühöngő kritikus zúzás! Kiosztva: %d sebzés![/color]" % [controller.monster_name, raw_dmg])

		if combat.armored_combat:
			await combat.armored_combat.execute_knockback_stun_sequence(target_hero, 2, combat.stun_duration)

		await await_anim_finish(anim)
		return raw_dmg

	# 2. NORMÁL ÁLLAPOT (HP >= 30%): Random mix attack_1 és attack_2 között
	var use_heavy = randf() >= 0.55
	if use_heavy:
		# attack_2 (nehezebb csapás)
		var anim = safe_play_anim("attack_2", "attack_1")
		if target_hero.has_method("try_trigger_block"):
			target_hero.try_trigger_block()

		var impact_frame = get_impact_frame("attack_2", 2)
		await combat.get_tree().create_timer(float(impact_frame) / 8.0).timeout

		var raw_dmg = ceili(float(combat.roll_attack_damage()) * frenzy_multiplier * 1.40)
		target_hero.take_damage(raw_dmg)

		if target_hero.has_method("play_hurt_reaction"):
			target_hero.play_hurt_reaction()

		if combat.armored_combat:
			await combat.armored_combat.apply_knockback(target_hero, 1)
			if not is_extra_attack and is_instance_valid(target_hero) and target_hero.is_alive():
				await combat.armored_combat.step_closer_to_hero(target_hero)

		await await_anim_finish(anim)
		return raw_dmg
	else:
		# attack_1 (normál gyors csapás)
		var anim = safe_play_anim("attack_1", "attack_1")
		if target_hero.has_method("try_trigger_block"):
			target_hero.try_trigger_block()

		var impact_frame = get_impact_frame("attack_1", 2)
		await combat.get_tree().create_timer(float(impact_frame) / 8.0).timeout

		var raw_dmg = ceili(float(combat.roll_attack_damage()) * frenzy_multiplier)
		target_hero.take_damage(raw_dmg)

		if target_hero.has_method("play_hurt_reaction"):
			target_hero.play_hurt_reaction()

		if combat.armored_combat:
			await combat.armored_combat.apply_knockback(target_hero, 1)
			if not is_extra_attack and is_instance_valid(target_hero) and target_hero.is_alive():
				await combat.armored_combat.step_closer_to_hero(target_hero)

		await await_anim_finish(anim)
		return raw_dmg

# ==============================================================================
# 3. KÉTKEZES KARDOS CSONTVÁZ (Lassú & Pusztító)
# ==============================================================================
func _perform_greatsword_skeleton_turn(target_hero: HeroController) -> int:
	greatsword_turn_counter += 1

	# Turn 1: Előkészület / Lendületvétel (0 sebzés)
	if greatsword_turn_counter % 2 != 0:
		var prep_anim = "charge"
		var sprite = controller.visuals.sprite if (controller and controller.visuals) else null
		if sprite and sprite.sprite_frames:
			if not sprite.sprite_frames.has_animation(prep_anim):
				prep_anim = "summon"
			if not sprite.sprite_frames.has_animation(prep_anim):
				prep_anim = "idle"
		var prep_played_anim = safe_play_anim(prep_anim, "idle")

		var prep_battle_ui = _get_battle_dialog()
		if prep_battle_ui and prep_battle_ui.combat_active:
			prep_battle_ui._append_log("[color=yellow]⚔️ [%s FELKÉSZÜL] Felemeli óriási kétkezes kardját, és hatalmas erőt gyűjt a következő csapásra![/color]" % controller.monster_name)

		await combat.get_tree().create_timer(1.0).timeout
		await await_anim_finish(prep_played_anim)
		return 0

	# Turn 2: Lecsapás garantált Tiszta Sebzéssel (Páncél és Védelem átütése)
	var anim = safe_play_anim("attack_1", "attack_1")
	var impact_frame = get_impact_frame("attack_1", 3)

	await combat.get_tree().create_timer(float(impact_frame) / 8.0).timeout

	var base_dmg = combat.roll_attack_damage()
	var devastating_dmg = ceili(float(base_dmg) * 2.0)
	var hero_def = target_hero.get_defense()

	# Blokkolás és védelem figyelmen kívül hagyása garantált Tiszta Sebzésként
	if target_hero.combat:
		target_hero.combat.is_blocking_active = false
	target_hero.take_damage(devastating_dmg + hero_def)

	var battle_ui = _get_battle_dialog()
	if battle_ui and battle_ui.combat_active:
		battle_ui._append_log("[color=purple]💥 [%s LECSAPÁS] A föld is megremeg a kétkezes kard súlya alatt! Tiszta sebzés: %d![/color]" % [controller.monster_name, devastating_dmg])

	if target_hero.has_method("play_hurt_reaction"):
		target_hero.play_hurt_reaction()

	if combat.armored_combat:
		await combat.armored_combat.apply_knockback(target_hero, 2)

	await await_anim_finish(anim)
	return devastating_dmg

# ==============================================================================
# 4. MEDVEEMBER (Vérzés & Tank)
# ==============================================================================
func _perform_bearman_turn(target_hero: HeroController) -> int:
	var roll = randf()
	var has_bleed = _hero_has_bleed(target_hero)

	# Ha még nincs vérzés a hősön, 50% eséllyel adja be a vérző suhintást
	var use_attack_1 = (roll < 0.50) if not has_bleed else (roll < 0.25)
	var use_attack_3 = (roll >= 0.75) if not has_bleed else (roll >= 0.60)

	if use_attack_1:
		# attack_1: Karmaival megsebesíti a hőst, ami Vérzés DoT-ot okoz 3 körig
		var anim = safe_play_anim("attack_1", "attack_1")
		if target_hero.has_method("try_trigger_block"):
			target_hero.try_trigger_block()

		var impact_frame = get_impact_frame("attack_1", 2)
		await combat.get_tree().create_timer(float(impact_frame) / 8.0).timeout

		var raw_dmg = combat.roll_attack_damage()
		target_hero.take_damage(raw_dmg)

		# Vérzés állapot felhelyezése a hősre (3 körig tartó DoT)
		var dot_dmg = maxi(4, ceili(float(controller.enemy_data.base_damage if controller.enemy_data else 14) * 0.35))
		_apply_bleed_to_hero(target_hero, 3, dot_dmg)

		if target_hero.has_method("play_hurt_reaction"):
			await target_hero.play_hurt_reaction()

		await await_anim_finish(anim)
		return raw_dmg

	elif use_attack_3:
		# attack_3: Nehéz zúzás lökés- és kábítás-szekvenciával
		var anim = safe_play_anim("attack_3", "attack_1")
		if target_hero.has_method("try_trigger_block"):
			target_hero.try_trigger_block()

		var impact_frame = get_impact_frame("attack_3", 3)
		await combat.get_tree().create_timer(float(impact_frame) / 8.0).timeout

		var raw_dmg = ceili(float(combat.roll_attack_damage()) * 1.50)
		target_hero.take_damage(raw_dmg)

		if combat.armored_combat:
			await combat.armored_combat.execute_knockback_stun_sequence(target_hero, 2, combat.stun_duration)

		await await_anim_finish(anim)
		return raw_dmg

	else:
		# attack_2: Normál harapás/karmolás
		var anim = safe_play_anim("attack_2", "attack_1")
		if target_hero.has_method("try_trigger_block"):
			target_hero.try_trigger_block()

		var impact_frame = get_impact_frame("attack_2", 2)
		await combat.get_tree().create_timer(float(impact_frame) / 8.0).timeout

		var raw_dmg = ceili(float(combat.roll_attack_damage()) * 1.15)
		target_hero.take_damage(raw_dmg)

		if target_hero.has_method("play_hurt_reaction"):
			await target_hero.play_hurt_reaction()

		await await_anim_finish(anim)
		return raw_dmg

# ==============================================================================
# 5. VÉRFARKAS (Regenerálódó Párbajhős)
# ==============================================================================
func _perform_werewolf_turn(target_hero: HeroController) -> int:
	# 1. PASSZÍV TULAJDONSÁG: Minden kör elején fix HP-t regenerál (pl. 8% max HP)
	var regen_ratio = 0.08
	var heal_val = maxi(2, ceili(float(controller.max_hp) * regen_ratio))
	var old_hp = controller.current_hp
	controller.enemy_data._current_hp = mini(controller.max_hp, controller.current_hp + heal_val)
	var actually_healed = controller.current_hp - old_hp

	if actually_healed > 0:
		_flash_sprite(controller.visuals.sprite if controller.visuals else null, Color(0.3, 1.3, 0.4))

		var battle_ui = _get_battle_dialog()
		if battle_ui and battle_ui.combat_active:
			battle_ui._append_log("[color=green]🐺 [%s REGENERÁCIÓ] A sebei gyorsan beforrnak: +%d HP! (%d/%d)[/color]" % [controller.monster_name, actually_healed, controller.current_hp, controller.max_hp])
			battle_ui._update_ui_cards()

		await combat.get_tree().create_timer(0.25).timeout

	# 2. KARDOS, GYORS TÖBB-TALÁLATOS CSAPÁSSOROZAT (attack_1 vagy attack_2)
	var is_attack_2 = randf() < 0.45
	var anim_target = "attack_2" if is_attack_2 else "attack_1"
	var anim = safe_play_anim(anim_target, "attack_1")

	if target_hero.has_method("try_trigger_block"):
		target_hero.try_trigger_block()

	var hit_count = 3 if anim_target == "attack_2" else 2
	var mult = 0.50 if anim_target == "attack_2" else 0.65
	var single_dmg = ceili(float(combat.roll_attack_damage()) * mult)
	var total_dealt = 0

	var impact_frame_base = get_impact_frame(anim, 2)

	for i in range(hit_count):
		var step_frame = impact_frame_base if i == 0 else 2
		await combat.get_tree().create_timer(float(step_frame) / 8.0).timeout

		target_hero.take_damage(single_dmg)
		total_dealt += single_dmg

		if target_hero.has_method("play_hurt_reaction"):
			target_hero.play_hurt_reaction()

	await await_anim_finish(anim)
	return total_dealt

# ==============================================================================
# ÁLTALÁNOS TARTALÉK TÁMADÁS (Fallback)
# ==============================================================================
func _perform_generic_turn(target_hero: HeroController) -> int:
	var anim = safe_play_anim("attack_1", "idle")
	if target_hero.has_method("try_trigger_block"):
		target_hero.try_trigger_block()

	var impact_frame = get_impact_frame(anim, 2)
	await combat.get_tree().create_timer(float(impact_frame) / 8.0).timeout

	var raw_dmg = combat.roll_attack_damage()
	target_hero.take_damage(raw_dmg)

	if target_hero.has_method("play_hurt_reaction"):
		await target_hero.play_hurt_reaction()

	await await_anim_finish(anim)
	return raw_dmg

# ==============================================================================
# SEGÉDFÜGGVÉNYEK ÉS RÁCSKEZELÉS
# ==============================================================================

## Animáció biztonságos lejátszása (ha hiányzik, visszalép attack_1-re vagy idle-re)
func safe_play_anim(anim_name: String, fallback_anim: String = "attack_1") -> String:
	var sprite = controller.visuals.sprite if (controller and controller.visuals) else null
	if not sprite or not sprite.sprite_frames:
		return ""

	var chosen_anim = anim_name
	if not sprite.sprite_frames.has_animation(chosen_anim):
		if fallback_anim != "" and sprite.sprite_frames.has_animation(fallback_anim):
			chosen_anim = fallback_anim
		elif sprite.sprite_frames.has_animation("attack_1"):
			chosen_anim = "attack_1"
		elif sprite.sprite_frames.has_animation("idle"):
			chosen_anim = "idle"
		elif sprite.sprite_frames.has_animation("default"):
			chosen_anim = "default"
		else:
			return ""

	sprite.play(chosen_anim)
	return chosen_anim

func get_impact_frame(anim: String, default_frame: int = 2) -> int:
	if controller and controller.enemy_data and controller.enemy_data.has_method("get_knockback_frame"):
		return controller.enemy_data.get_knockback_frame(anim)
	return default_frame

func await_anim_finish(anim: String) -> void:
	var sprite = controller.visuals.sprite if (controller and controller.visuals) else null
	if sprite and sprite.is_playing() and sprite.animation == anim:
		await sprite.animation_finished
	if not combat.is_dead and controller and controller.visuals:
		controller.visuals.play_idle_anim()

func _get_floor_layer() -> TileMapLayer:
	if controller and controller.mover and controller.mover.floor_layer:
		return controller.mover.floor_layer
	var gm = combat.get_tree().get_first_node_in_group("grid_manager") as GridManager
	if gm and gm.floor_layer:
		return gm.floor_layer
	return null

func _get_battle_dialog() -> BattleDialog:
	if combat == null: return null
	return combat.get_tree().get_first_node_in_group("battle_ui") as BattleDialog

func _is_hero_adjacent(target_hero: HeroController) -> bool:
	if not is_instance_valid(target_hero) or controller == null: return false
	var diff = target_hero.grid_pos - controller.grid_pos
	return maxi(absi(diff.x), absi(diff.y)) <= 1

func _find_empty_adjacent_cell() -> Dictionary:
	if controller == null or controller.mover == null:
		return {"found": false, "cell": Vector2i.ZERO}

	var dirs = [
		Vector2i(0, -1), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(1, 0),
		Vector2i(1, 1), Vector2i(-1, 1), Vector2i(1, -1), Vector2i(-1, -1)
	]
	dirs.shuffle()

	for d in dirs:
		var cell = controller.grid_pos + d
		if controller.mover.is_cell_walkable(cell):
			return {"found": true, "cell": cell}

	return {"found": false, "cell": Vector2i.ZERO}

func _get_adjacent_allies() -> Array[EnemyController]:
	var allies: Array[EnemyController] = []
	if controller == null or combat == null: return allies

	var my_pos = controller.grid_pos
	var dirs = [
		Vector2i(0, -1), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(1, 0),
		Vector2i(1, 1), Vector2i(-1, 1), Vector2i(1, -1), Vector2i(-1, -1)
	]

	for node in combat.get_tree().get_nodes_in_group("enemies"):
		if is_instance_valid(node) and node is EnemyController and node != controller:
			var ally = node as EnemyController
			if ally.is_monster_alive() and (ally.grid_pos - my_pos) in dirs:
				allies.append(ally)

	return allies

func _flash_sprite(sprite: AnimatedSprite2D, flash_color: Color) -> void:
	if not sprite: return
	var tween = sprite.create_tween()
	tween.tween_property(sprite, "modulate", flash_color, 0.15)
	tween.tween_property(sprite, "modulate", Color.WHITE, 0.25)

func _hero_has_bleed(target_hero: HeroController) -> bool:
	if not is_instance_valid(target_hero): return false
	return target_hero.has_node("BleedStatusEffect")

func _apply_bleed_to_hero(target_hero: HeroController, duration_turns: int, damage_per_turn: int) -> void:
	if not is_instance_valid(target_hero): return

	var existing = target_hero.get_node_or_null("BleedStatusEffect") as BleedStatusEffect
	if existing != null:
		existing.turns_remaining = duration_turns
		existing.damage_per_turn = maxi(existing.damage_per_turn, damage_per_turn)
		print("🩸 [VÉRZÉS MEGÚJÍTVA] A vérzés meghosszabbodott (%d kör, %d sebzés/kör)!" % [duration_turns, damage_per_turn])
	else:
		var bleed_node = BleedStatusEffect.new()
		bleed_node.name = "BleedStatusEffect"
		bleed_node.target_hero = target_hero
		bleed_node.turns_remaining = duration_turns
		bleed_node.damage_per_turn = damage_per_turn
		bleed_node.elite_combat = self
		target_hero.add_child(bleed_node)
		print("🩸 [VÉRZÉS ALKALMAZVA] A hős mély sebet kapott! Vérzés: %d kör, %d sebzés/kör" % [duration_turns, damage_per_turn])

	var battle_ui = _get_battle_dialog()
	if battle_ui and battle_ui.combat_active:
		battle_ui._append_log("[color=red]🩸 [VÉRZÉS] %s mély sebet ejtett a hősön! (%d körig vérzik)[/color]" % [controller.monster_name, duration_turns])

# ==============================================================================
# BELSŐ OSZTÁLY: HŐS VÉRZÉS STÁTUSZEFFEKT (DoT)
# ==============================================================================
class BleedStatusEffect extends Node:
	var target_hero: HeroController
	var turns_remaining: int = 3
	var damage_per_turn: int = 5
	var elite_combat: EliteEnemyCombat
	var _last_hero_turn_state: bool = false
	var _last_grid_pos: Vector2i = Vector2i.ZERO

	func _ready() -> void:
		if is_instance_valid(target_hero):
			_last_grid_pos = target_hero.grid_pos

	func _process(_delta: float) -> void:
		if not is_instance_valid(target_hero) or not target_hero.is_alive():
			queue_free()
			return

		var battle_ui = target_hero.get_tree().get_first_node_in_group("battle_ui") as BattleDialog
		if battle_ui and battle_ui.combat_active:
			# Amikor a párbajban a hős köre elkezdődik:
			if battle_ui.is_hero_turn and not _last_hero_turn_state:
				_last_hero_turn_state = true
				_trigger_bleed_tick(battle_ui)
			elif not battle_ui.is_hero_turn:
				_last_hero_turn_state = false
		else:
			_last_hero_turn_state = false
			# Szabad mozgás közben lépésenkénti vérzés:
			if target_hero.grid_pos != _last_grid_pos:
				_last_grid_pos = target_hero.grid_pos
				_trigger_bleed_tick(null)

	func _trigger_bleed_tick(battle_ui: BattleDialog) -> void:
		if not is_instance_valid(target_hero) or not target_hero.is_alive():
			queue_free()
			return

		target_hero.take_damage(damage_per_turn)
		turns_remaining -= 1

		if is_instance_valid(elite_combat):
			elite_combat._flash_sprite(target_hero.sprite, Color(1.5, 0.2, 0.2))

		if is_instance_valid(target_hero) and target_hero.has_method("play_hurt_reaction"):
			target_hero.play_hurt_reaction()

		if battle_ui and battle_ui.combat_active:
			battle_ui._append_log("[color=red]🩸 [VÉRZÉS] A hős sebéből szivárog a vér! -%d HP (Hátralévő körök: %d)[/color]" % [damage_per_turn, maxi(0, turns_remaining)])
			battle_ui._update_ui_cards()
			if not target_hero.is_alive():
				battle_ui._finish_combat("MONSTER")

		if turns_remaining <= 0:
			if battle_ui and battle_ui.combat_active:
				battle_ui._append_log("[color=yellow]✨ [VÉRZÉS ELÁLLT] A seb beforrt, a vérzés elállt![/color]")
			print("✨ [VÉRZÉS LEJÁRT] A hős vérzése elállt.")
			queue_free()
