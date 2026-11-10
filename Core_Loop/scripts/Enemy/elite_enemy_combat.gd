class_name EliteEnemyCombat
extends RefCounted

var combat: EnemyCombat
var controller: EnemyController

## Kétkezes Csontváz körszámlálója (minden 2. körben sújt le)
var greatsword_turn_counter: int = 0

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
# 1. NEKROMANTA (Ranged Summoner/Healer Boss)
# ==============================================================================
func _perform_necromancer_turn(target_hero: HeroController) -> int:
	var hero_adjacent = _is_hero_adjacent(target_hero)
	var allies = _get_adjacent_allies()

	# 1. HA A HŐS KÖZVETLENÜL MELLETTÜNK ÁLL: Támadási prioritás a túlélésért
	if hero_adjacent:
		return await _necromancer_cast_attack(target_hero)

	# 2. HA NINCS SZÖVETSÉGES A SZOMSZÉDOS MEZŐKÖN: Megidézünk egyet
	if allies.is_empty():
		return await _perform_necromancer_summon(target_hero)

	# 3. HA VAN SZÖVETSÉGES ÉS SEBESÜLT: Meggyógyítjuk
	var wounded_ally: EnemyController = null
	for ally in allies:
		if ally.current_hp < ally.max_hp:
			wounded_ally = ally
			break

	if wounded_ally != null:
		return await _necromancer_cast_heal(wounded_ally)

	# 4. HA MINDEN MINION ÉP: Távolsági támadás a hősre
	return await _necromancer_cast_attack(target_hero)

## ==============================================================================
## NEKROMANTA IDÉZÉSI RUTIN (_perform_necromancer_summon)
## ==============================================================================
func _perform_necromancer_summon(target_hero: HeroController) -> int:
	# --------------------------------------------------------------------------
	# 1. LÉPÉS: RÁCSPOZICIONÁLÁS ÉS SZABAD SZOMSZÉDOS MEZŐ KERESÉSE
	# --------------------------------------------------------------------------
	var gm = controller.mover.grid_manager if (controller and controller.mover) else null
	if gm == null and combat != null:
		gm = combat.get_tree().get_first_node_in_group("grid_manager") as GridManager

	var adjacent_dirs = [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]
	adjacent_dirs.shuffle()

	var target_cell := Vector2i.ZERO
	var cell_found := false

	for dir in adjacent_dirs:
		var candidate = controller.grid_pos + dir

		# 1/a. Ellenőrizzük, hogy a csempe nem szilárd (járható a grid_manager szerint)
		if gm != null and gm.is_cell_solid(candidate):
			continue

		# 1/b. Ellenőrizzük a "player" csoportot (hős ne álljon rajta vagy ne lépjen oda)
		var occupied = false
		for player_node in combat.get_tree().get_nodes_in_group("player"):
			if is_instance_valid(player_node) and player_node is HeroController:
				var hero = player_node as HeroController
				if hero.is_alive():
					if hero.grid_pos == candidate:
						occupied = true
						break
					if hero.is_moving and hero.current_step_target == candidate:
						occupied = true
						break

		if occupied:
			continue

		# 1/c. Ellenőrizzük az "enemies" csoportot (ne álljon rajta élő szörny)
		for enemy_node in combat.get_tree().get_nodes_in_group("enemies"):
			if is_instance_valid(enemy_node) and enemy_node is EnemyController:
				var enemy = enemy_node as EnemyController
				if enemy.is_monster_alive():
					if enemy.grid_pos == candidate:
						occupied = true
						break
					if enemy.is_moving and enemy.current_step_target == candidate:
						occupied = true
						break

		if occupied:
			continue

		# Találtunk egy teljesen üres, szilárd akadályoktól mentes mezőt:
		target_cell = candidate
		cell_found = true
		break

	# Ha nincs elérhető szabad mező, megszakítjuk az idézést és normál attack_1-re váltunk
	if not cell_found:
		print("⚠️ [%s] Nincs szabad szomszédos mező az idézéshez! Visszalépés normál támadásra (attack_1)." % controller.monster_name)
		return await _necromancer_cast_attack(target_hero)

	var fl = _get_floor_layer()
	var spawn_world_pos: Vector2 = fl.map_to_local(target_cell) if fl else controller.global_position

	# --------------------------------------------------------------------------
	# 2. LÉPÉS: 3-LÉPÉSES ANIMÁCIÓS SZINKRONIZÁCIÓ (8 FPS IDŐZÍTÉSSEL)
	# --------------------------------------------------------------------------
	# 2/a. Step 1 (Nekromanta): 'summon' animáció lejátszása és várakozás az impact frame-ig
	var necro_anim = safe_play_anim("summon", "attack_2")
	var impact_frame = get_impact_frame("summon", 4)
	await combat.get_tree().create_timer(float(impact_frame) / 8.0).timeout

	# 2/b. Step 2 (Az Effekt): summon_effect.tscn példányosítása pontosan a célmező közepére
	var effect_paths = [
		"res://scenes/Projectiles/summon_effect.tscn",
		"res://Scenes/Projectiles/summon_effect.tscn",
		"res://Scenes/Projectiles/necromancer_summon.tscn",
		"res://scenes/Projectiles/necromancer_summon.tscn"
	]
	for ep in effect_paths:
		if ResourceLoader.exists(ep):
			var eff_res = load(ep) as PackedScene
			if eff_res:
				var eff = eff_res.instantiate() as Node2D
				if eff:
					controller.get_parent().add_child(eff)
					eff.global_position = spawn_world_pos
					eff.z_index = 12
					var anim_spr = eff.get_node_or_null("AnimatedSprite2D") as AnimatedSprite2D
					if anim_spr:
						if anim_spr.sprite_frames and anim_spr.sprite_frames.has_animation("default"):
							anim_spr.play("default")
						anim_spr.animation_finished.connect(eff.queue_free)
					else:
						combat.get_tree().create_timer(1.0).timeout.connect(eff.queue_free)
			break

	# 2/c. Step 3 (A Minion): Véletlenszerű csontváz típus kiválasztása és példányosítása
	var minion_pool = [
		{
			"name": "Páncélozott Csontváz",
			"data_path": "res://resources/Monsters/armored_skeleton_data.tres"
		},
		{
			"name": "Kétkezes Kardos Csontváz",
			"data_path": "res://resources/Monsters/greatsword_skeleton_data.tres"
		},
		{
			"name": "Csontváz Íjász",
			"data_path": "res://resources/Monsters/skeleton_archer_data.tres"
		},
		{
			"name": "Csontváz",
			"data_path": "res://resources/Monsters/skeleton_data.tres"
		}
	]
	var chosen_minion = minion_pool.pick_random()

	var enemy_scene_paths = [
		"res://scenes/Enemy/enemy.tscn",
		"res://Scenes/Enemy/enemy.tscn"
	]
	var enemy_scene: PackedScene = null
	for sp in enemy_scene_paths:
		if ResourceLoader.exists(sp):
			enemy_scene = load(sp) as PackedScene
			break

	if enemy_scene != null:
		var minion = enemy_scene.instantiate() as EnemyController

		# Adatmodell betöltése és klónozása
		if ResourceLoader.exists(chosen_minion["data_path"]):
			var data_res = load(chosen_minion["data_path"]) as EnemyData
			if data_res:
				minion.enemy_data = data_res.duplicate()
				minion.enemy_data.initialize()

		# Hozzáadás a jelenethez és pozicionálás (rács + világkoordináta)
		controller.get_parent().add_child(minion)
		minion.position = spawn_world_pos
		minion.grid_pos = target_cell
		if minion.mover:
			minion.mover.grid_pos = target_cell
			minion.mover.current_step_target = target_cell

		minion.is_dead = false
		minion.visible = true
		if not minion.is_in_group("enemies"):
			minion.add_to_group("enemies")

		# Komponensek inicializálása
		if minion.has_method("setup"):
			minion.setup()
		if minion.visuals and minion.visuals.has_method("setup"):
			minion.visuals.setup(minion)
		if minion.mover and minion.mover.has_method("setup"):
			minion.mover.setup(minion)
		if minion.combat and minion.combat.has_method("setup"):
			minion.combat.setup(minion)
		if minion.brain and minion.brain.has_method("setup"):
			minion.brain.setup(minion)

		# AI timer megállítása az idézési animáció lejátszása alatt
		if minion.brain and minion.brain.ai_timer and is_instance_valid(minion.brain.ai_timer):
			minion.brain.ai_timer.stop()

		# ----------------------------------------------------------------------
		# 3. LÉPÉS: MINION 'summon' ANIMÁCIÓ LEJÁTSZÁSA ÉS MEGINTÉSE
		# ----------------------------------------------------------------------
		var minion_sprite: AnimatedSprite2D = null
		if minion.visuals and minion.visuals.sprite:
			minion_sprite = minion.visuals.sprite
		elif minion.has_node("Visuals"):
			minion_sprite = minion.get_node("Visuals") as AnimatedSprite2D

		if minion_sprite and minion_sprite.sprite_frames and minion_sprite.sprite_frames.has_animation("summon"):
			minion_sprite.play("summon")
			await minion_sprite.animation_finished
		elif minion.visuals and minion.visuals.has_method("play_respawn_animation"):
			await minion.visuals.play_respawn_animation()
		else:
			await combat.get_tree().create_timer(0.6).timeout

		# Visszaállás idle-re és az AI timer elindítása
		if minion.visuals and minion.visuals.has_method("play_idle_anim"):
			minion.visuals.play_idle_anim()
		elif minion_sprite and minion_sprite.sprite_frames and minion_sprite.sprite_frames.has_animation("idle"):
			minion_sprite.play("idle")

		if minion.brain and minion.brain.ai_timer and is_instance_valid(minion.brain.ai_timer):
			minion.brain.ai_timer.start()

		print("💀 [%s MEGIDÉZVE] %s megjelent a (%d, %d) koordinátán!" % [controller.monster_name, minion.monster_name, target_cell.x, target_cell.y])

	var battle_ui = _get_battle_dialog()
	if battle_ui and battle_ui.combat_active:
		battle_ui._append_log("[color=purple]💀 [%s IDÉZÉS] Megidézett egy szövetségest (%s) a csatatérre![/color]" % [controller.monster_name, chosen_minion["name"]])

	await await_anim_finish(necro_anim)
	return 0

## Nekromanta gyógyítás logikája
func _necromancer_cast_heal(wounded_ally: EnemyController) -> int:
	var anim = safe_play_anim("heal", "attack_2")
	var impact_frame = get_impact_frame("attack_2", 3)

	await combat.get_tree().create_timer(float(impact_frame) / 8.0).timeout

	var missing = wounded_ally.max_hp - wounded_ally.current_hp
	var heal_amount = mini(missing, maxi(15, ceili(float(wounded_ally.max_hp) * 0.40)))
	wounded_ally.enemy_data._current_hp += heal_amount

	show_floating_text(wounded_ally.global_position, "+%d HP" % heal_amount, Color.GREEN)
	_flash_sprite(wounded_ally.visuals.sprite if wounded_ally.visuals else null, Color.GREEN)

	var battle_ui = _get_battle_dialog()
	if battle_ui and battle_ui.combat_active:
		battle_ui._append_log("[color=green]✨ [%s GYÓGYÍTÁS] A Nekromanta meggyógyította %s szövetségesét (+%d HP)![/color]" % [controller.monster_name, wounded_ally.monster_name, heal_amount])
		battle_ui._update_ui_cards()

	await await_anim_finish(anim)
	return 0

## Nekromanta távolsági támadás logikája
func _necromancer_cast_attack(target_hero: HeroController) -> int:
	var anim = safe_play_anim("attack_1", "attack_1")
	if target_hero.has_method("try_trigger_block"):
		target_hero.try_trigger_block()

	var impact_frame = get_impact_frame("attack_1", 2)
	await combat.get_tree().create_timer(float(impact_frame) / 8.0).timeout

	var raw_dmg = combat.roll_attack_damage()
	var proj_scene: PackedScene = controller.enemy_data.projectile_scene if controller.enemy_data else null
	if proj_scene == null:
		var default_proj = "res://Scenes/Projectiles/necromancer_attack.tscn"
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

		show_floating_text(target_hero.global_position, "KRITIKUS! -%d" % raw_dmg, Color(1.0, 0.25, 0.1))

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
		var anim = safe_play_anim(prep_anim, "idle")

		var battle_ui = _get_battle_dialog()
		if battle_ui and battle_ui.combat_active:
			battle_ui._append_log("[color=yellow]⚔️ [%s FELKÉSZÜL] Felemeli óriási kétkezes kardját, és hatalmas erőt gyűjt a következő csapásra![/color]" % controller.monster_name)

		await combat.get_tree().create_timer(1.0).timeout
		await await_anim_finish(anim)
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

	show_floating_text(target_hero.global_position, "TISZTA SEBZÉS! -%d" % devastating_dmg, Color(0.95, 0.25, 0.95))

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
			target_hero.play_hurt_reaction()

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
		show_floating_text(controller.global_position, "+%d HP" % actually_healed, Color(0.2, 0.9, 0.3))
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

func show_floating_text(pos: Vector2, text: String, color: Color) -> void:
	if combat == null: return
	var tree = combat.get_tree()
	if tree == null: return

	var label = Label.new()
	label.text = text
	label.modulate = color
	label.z_index = 200
	label.global_position = pos + Vector2(-20, -30)
	label.add_theme_font_size_override("font_size", 16)
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	label.add_theme_constant_override("outline_size", 4)

	tree.root.add_child(label)

	var tween = label.create_tween()
	tween.set_parallel(true)
	tween.tween_property(label, "position:y", label.position.y - 30.0, 0.9).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(label, "modulate:a", 0.0, 0.9).set_delay(0.3)
	tween.chain().tween_callback(label.queue_free)

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
			elite_combat.show_floating_text(target_hero.global_position, "-%d HP (Vérzés)" % damage_per_turn, Color(0.9, 0.15, 0.15))
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
