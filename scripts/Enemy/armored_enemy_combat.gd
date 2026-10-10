class_name ArmoredEnemyCombat
extends RefCounted

var combat: EnemyCombat
var controller: EnemyController

func _init(p_combat: EnemyCombat) -> void:
	combat = p_combat
	controller = p_combat.controller

## ESÉLYALAPÚ (ODDS) TÁMADÁSMEGHATÁROZÁS
func resolve_attack(is_extra_attack: bool = false) -> Dictionary:
	var data = controller.enemy_data if controller else null
	var profile = data.special_profile if (data and data.get("special_profile") != null) else 0

	var anim: String = "attack_1"
	var multiplier: float = 1.0
	var hits: int = 1
	var knockback: int = 0
	var causes_stun: bool = false
	var push_and_chase: bool = false

	var roll = randf()

	match profile:
		# 1. PÁNCÉLOZOTT CSONTVÁZ
		1: # ARMORED_SKELETON
			if roll < 0.60:
				anim = "attack_1"
				multiplier = 1.0
				hits = 1
				knockback = 1
				push_and_chase = not is_extra_attack
			else:
				anim = "attack_2"
				multiplier = 0.55
				hits = 3
				knockback = 0

		# 2. PÁNCÉLOZOTT ORK
		2: # ARMORED_ORC
			if roll < 0.50:
				anim = "attack_1"
				multiplier = 1.0
				hits = 1
			elif roll < 0.80:
				anim = "attack_2"
				multiplier = 1.4
				hits = 1
				knockback = 1
				push_and_chase = not is_extra_attack
			else:
				anim = "attack_3"
				multiplier = 1.3
				hits = 1
				knockback = 2
				causes_stun = true

		# 3. PÁNCÉLOZOTT FEJSZÉS
		3: # ARMORED_AXEMAN
			if roll < 0.50:
				anim = "attack_1"
				multiplier = 1.0
				hits = 1
				knockback = 1
				push_and_chase = not is_extra_attack
			elif roll < 0.80:
				anim = "attack_2"
				multiplier = 0.75
				hits = 2
			else:
				anim = "attack_3"
				multiplier = 1.6
				hits = 1
				knockback = 2
				causes_stun = true

	return {
		"anim": anim,
		"multiplier": multiplier,
		"hits": hits,
		"knockback": knockback,
		"causes_stun": causes_stun,
		"push_and_chase": push_and_chase
	}

## PÁNCÉLOZOTT KÖR LEVEZÉNYLÉSE (KÉPKOCKA-IDŐZÍTÉSEK ÉS KOMBÓK)
func perform_turn(target_hero: HeroController, is_extra_attack: bool = false) -> int:
	var attack_info = resolve_attack(is_extra_attack)
	var anim: String = attack_info["anim"]
	var multiplier: float = attack_info["multiplier"]
	var hit_count: int = attack_info["hits"]
	var knockback_tiles: int = attack_info["knockback"]
	var causes_stun: bool = attack_info["causes_stun"]
	var push_and_chase: bool = attack_info["push_and_chase"]

	var sprite = controller.visuals.sprite if controller.visuals else null
	var single_raw = ceili(float(combat.roll_attack_damage()) * multiplier)
	var total_dealt = 0

	# BIZTONSÁGI ELLENŐRZÉS: Ha az animáció nem létezik a SpriteFrames-ben, visszalépünk attack_1-re
	if sprite and sprite.sprite_frames and not sprite.sprite_frames.has_animation(anim):
		if sprite.sprite_frames.has_animation("attack_1"):
			anim = "attack_1"
		elif sprite.sprite_frames.has_animation("default"):
			anim = "default"

	var data = controller.enemy_data
	var fps: float = 8.0
	if sprite and sprite.sprite_frames and sprite.sprite_frames.has_animation(anim):
		var s_fps = sprite.sprite_frames.get_animation_speed(anim)
		if s_fps > 0.0: fps = s_fps

	# 1. SÚLYOS KÁBÍTÓ CSAPÁS (Ork / Fejszés 3. támadása)
	if knockback_tiles > 0 and causes_stun:
		if anim != "" and sprite and sprite.sprite_frames and sprite.sprite_frames.has_animation(anim):
			sprite.play(anim)
			if target_hero.has_method("try_trigger_block"): target_hero.try_trigger_block()

			var target_frame = data.get_knockback_frame(anim) if data else 3
			await combat.get_tree().create_timer(float(target_frame) / fps).timeout

			target_hero.take_damage(single_raw)
			await execute_knockback_stun_sequence(target_hero, knockback_tiles, combat.stun_duration)

			if sprite.is_playing() and sprite.animation == anim:
				await sprite.animation_finished
			if not combat.is_dead and controller.visuals:
				controller.visuals.play_idle_anim()

			return single_raw

	# 2. SIMA HÁTRALÖKÉS (Impact frame-nél becsapódás és lökés)
	elif knockback_tiles > 0:
		if anim != "" and sprite and sprite.sprite_frames and sprite.sprite_frames.has_animation(anim):
			sprite.play(anim)
			if target_hero.has_method("try_trigger_block"): target_hero.try_trigger_block()

			var target_frame = data.get_knockback_frame(anim) if data else 2
			await combat.get_tree().create_timer(float(target_frame) / fps).timeout

			target_hero.take_damage(single_raw)
			total_dealt += single_raw
			if target_hero.has_method("play_hurt_reaction"): target_hero.play_hurt_reaction()

			await apply_knockback(target_hero, knockback_tiles)

			if sprite.is_playing() and sprite.animation == anim:
				await sprite.animation_finished
			if not combat.is_dead and controller.visuals:
				controller.visuals.play_idle_anim()

			if push_and_chase and is_instance_valid(target_hero) and target_hero.is_alive():
				await step_closer_to_hero(target_hero)
				print("⚡ [%s ROZSDÁS LENDÜLET] Hátralökte a hőst, utánalépett és újra lecsap!" % controller.monster_name)
				await combat.get_tree().create_timer(0.15).timeout
				var followup_dmg = await combat.perform_combat_turn(target_hero, true)
				total_dealt += followup_dmg

			return total_dealt

	# 3. CSONTVÁZ PÖRGÉS (2., 4., 6. képkockánál kiosztott sebzéssel)
	var profile = data.special_profile if data else 0
	if profile == 1 and anim == "attack_2" and sprite and sprite.sprite_frames and sprite.sprite_frames.has_animation(anim):
		sprite.play(anim)
		if target_hero.has_method("try_trigger_block"): target_hero.try_trigger_block()

		# A fix 3 helyett a hit_count változót használjuk:
		for _i in range(hit_count):
			await combat.get_tree().create_timer(2.0 / fps).timeout
			target_hero.take_damage(single_raw)
			total_dealt += single_raw
			if target_hero.has_method("play_hurt_reaction"): target_hero.play_hurt_reaction()

		if sprite.is_playing() and sprite.animation == anim:
			await sprite.animation_finished
		if not combat.is_dead and controller.visuals:
			controller.visuals.play_idle_anim()
		return total_dealt

	# 4. FEJSZÉS PÖRGÉS (4. és 8. képkockánál kiosztott sebzéssel)
	elif profile == 3 and anim == "attack_2" and sprite and sprite.sprite_frames and sprite.sprite_frames.has_animation(anim):
		sprite.play(anim)
		if target_hero.has_method("try_trigger_block"): target_hero.try_trigger_block()

		# A fix 2 helyett a hit_count változót használjuk:
		for _i in range(hit_count):
			await combat.get_tree().create_timer(4.0 / fps).timeout
			target_hero.take_damage(single_raw)
			total_dealt += single_raw
			if target_hero.has_method("play_hurt_reaction"): target_hero.play_hurt_reaction()

		if sprite.is_playing() and sprite.animation == anim:
			await sprite.animation_finished
		if not combat.is_dead and controller.visuals:
			controller.visuals.play_idle_anim()
		return total_dealt

	# 5. EGYÉB TÁMADÁSOK
	if anim != "" and sprite and sprite.sprite_frames and sprite.sprite_frames.has_animation(anim):
		sprite.play(anim)
		if target_hero.has_method("try_trigger_block"): target_hero.try_trigger_block()
		await sprite.animation_finished
		if not combat.is_dead and controller.visuals:
			controller.visuals.play_idle_anim()

	for _h in range(hit_count):
		target_hero.take_damage(single_raw)
		total_dealt += single_raw
		if hit_count > 1:
			if target_hero.has_method("play_hurt_reaction"): target_hero.play_hurt_reaction()
			await combat.get_tree().create_timer(0.125).timeout

	if target_hero.has_method("play_hurt_reaction") and hit_count == 1:
		await target_hero.play_hurt_reaction()

	return total_dealt

## SÚLYOS HÁTRALÖKÉS (HARCBÓL KILÉPÉS, HÁTRAESÉS, 1.5 MP FEKVÉS ÉS FELÁLLÁS)
func execute_knockback_stun_sequence(target_hero: HeroController, tiles: int, duration: float) -> void:
	var battle_ui = combat.get_tree().get_first_node_in_group("battle_ui") as BattleDialog
	if battle_ui != null and battle_ui.combat_active:
		battle_ui.interrupt_combat_due_to_knockback()

	target_hero.is_stunned = true
	combat.set_all_monsters_ai_frozen(true)

	var diff = target_hero.grid_pos - controller.grid_pos
	var dir = Vector2i(signi(diff.x), signi(diff.y))
	if dir == Vector2i.ZERO: dir = Vector2i.RIGHT

	var gm = controller.mover.grid_manager if (controller and controller.mover) else null
	var current = target_hero.grid_pos
	var actual_steps = 0

	if gm and gm.floor_layer:
		for i in range(tiles):
			var next_cell = current + dir
			if gm.is_cell_solid(next_cell): break
			var blocked = false
			for enemy in combat.get_tree().get_nodes_in_group("enemies"):
				if is_instance_valid(enemy) and enemy != controller and enemy.grid_pos == next_cell:
					blocked = true
					break
			if blocked: break
			current = next_cell
			actual_steps += 1

	var hero_sprite = target_hero.sprite
	var knockback_slide_duration: float = 0.65

	if hero_sprite and hero_sprite.sprite_frames and hero_sprite.sprite_frames.has_animation("death"):
		hero_sprite.play("death")

	if actual_steps > 0 and gm and gm.floor_layer:
		target_hero.grid_pos = current
		var target_world = gm.floor_layer.map_to_local(current)
		var tween = target_hero.create_tween()
		tween.tween_property(target_hero, "position", target_world, knockback_slide_duration).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		await tween.finished
		if target_hero.visuals:
			target_hero.visuals.update_fog_of_war()
	else:
		await combat.get_tree().create_timer(knockback_slide_duration).timeout

	if hero_sprite and hero_sprite.is_playing() and hero_sprite.animation == "death":
		await hero_sprite.animation_finished

	if hero_sprite and hero_sprite.sprite_frames and hero_sprite.sprite_frames.has_animation("death"):
		var last_frame = hero_sprite.sprite_frames.get_frame_count("death") - 1
		hero_sprite.frame = last_frame
		hero_sprite.pause()

	# Ha a hős meghalt, nem áll fel:
	if not target_hero.is_alive():
		print("☠️ [A HŐS ELESETT] Az életerő elfogyott, a hős a földön marad!")
		target_hero.is_stunned = true
		if target_hero.has_method("play_overworld_death"):
			await target_hero.play_overworld_death()
		return

	print("💫 [KÁBÍTÁS] A hős a földön fekszik %.1f másodpercig..." % duration)
	await combat.get_tree().create_timer(duration).timeout

	if not target_hero.is_alive(): return

	if hero_sprite and hero_sprite.sprite_frames and hero_sprite.sprite_frames.has_animation("death"):
		hero_sprite.play_backwards("death")
		await hero_sprite.animation_finished

	if hero_sprite:
		if target_hero.visuals and target_hero.visuals.has_method("play_idle_anim"):
			target_hero.visuals.play_idle_anim()
		else:
			hero_sprite.play("idle")

	target_hero.is_stunned = false
	combat.set_all_monsters_ai_frozen(false)
	print("✨ [KÁBÍTÁS LEJÁRT] A hős felkelt a földről!")

## SIMA HÁTRALÖKÉS (1 CSEMPE)
func apply_knockback(target_hero: HeroController, tiles: int) -> void:
	var diff = target_hero.grid_pos - controller.grid_pos
	var dir = Vector2i(signi(diff.x), signi(diff.y))
	if dir == Vector2i.ZERO: dir = Vector2i.RIGHT

	var gm = controller.mover.grid_manager if (controller and controller.mover) else null
	if not gm or not gm.floor_layer: return

	var current = target_hero.grid_pos
	var actual_steps = 0

	for i in range(tiles):
		var next_cell = current + dir
		if gm.is_cell_solid(next_cell): break
		var blocked = false
		for enemy in combat.get_tree().get_nodes_in_group("enemies"):
			if is_instance_valid(enemy) and enemy != controller and enemy.grid_pos == next_cell:
				blocked = true
				break
		if blocked: break
		current = next_cell
		actual_steps += 1

	if actual_steps > 0:
		target_hero.grid_pos = current
		var target_world = gm.floor_layer.map_to_local(current)
		var tween = target_hero.create_tween()
		tween.tween_property(target_hero, "position", target_world, 0.15 * actual_steps).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		await tween.finished
		if target_hero.visuals:
			target_hero.visuals.update_fog_of_war()

## SZÖRNY UTÁNALÉPÉSE A HŐS MELLÉ
func step_closer_to_hero(target_hero: HeroController) -> void:
	var gm = controller.mover.grid_manager if (controller and controller.mover) else null
	if not gm or not gm.floor_layer: return

	var diff = target_hero.grid_pos - controller.grid_pos
	var dir_x = signi(diff.x)
	var dir_y = signi(diff.y)

	var ideal_cell = controller.grid_pos
	if dir_x != 0:
		ideal_cell = target_hero.grid_pos - Vector2i(dir_x, 0)
	elif dir_y != 0:
		ideal_cell = target_hero.grid_pos - Vector2i(0, dir_y)

	if not gm.is_cell_solid(ideal_cell):
		controller.grid_pos = ideal_cell
		if controller.mover:
			controller.mover.grid_pos = ideal_cell
			if controller.mover.get("current_step_target") != null:
				controller.mover.current_step_target = ideal_cell

		var target_world = gm.floor_layer.map_to_local(ideal_cell)
		var tween = controller.create_tween()
		tween.tween_property(controller, "position", target_world, 0.18)
		await tween.finished
