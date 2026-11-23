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

const PRIEST_HEAL_COOLDOWN: float = 2.0

var attack_range: int = 1
var is_ranged: bool = false
var max_class_range: int = 1
var in_battle: bool = false
var is_attacking: bool = false
var is_blocking_active: bool = false
var is_stunned: bool = false
var priest_heal_cooldown_remaining: float = 0.0
var last_attack_knockback_tiles: int = 0

func setup(p_controller: HeroController) -> void:
	controller = p_controller
	in_battle = false
	is_attacking = false
	is_blocking_active = false
	is_stunned = false
	priest_heal_cooldown_remaining = 0.0
	last_attack_knockback_tiles = 0

func _process(delta: float) -> void:
	if priest_heal_cooldown_remaining > 0.0:
		priest_heal_cooldown_remaining = maxf(0.0, priest_heal_cooldown_remaining - delta)

func roll_attack_damage() -> int:
	var power = controller.progression.attack_power if (controller and controller.progression) else 10
	var dmg: int = ceili(float(power) * randf_range(0.8, 1.0))
	var crit_pct: float = controller.progression.title_crit_chance if (controller and controller.progression) else 0.0
	if crit_pct > 0.0 and randf() * 100.0 < crit_pct:
		dmg = ceili(float(dmg) * 1.5)
	return dmg


func _apply_title_lifesteal() -> void:
	if controller == null or controller.progression == null or not controller.is_alive():
		return
	var ls: int = controller.progression.title_lifesteal
	if ls > 0 and controller.current_hp < controller.max_hp:
		controller.progression.heal(ls)

func take_damage(incoming_raw_damage: int) -> int:
	if not controller.is_alive() or controller.debug_invincible: return 0

	var raw = incoming_raw_damage
	if is_blocking_active:
		raw = ceili(float(incoming_raw_damage) * (1.0 - hero_block_reduction))
		print("[HŐS TOMPÍTOTT] Sikeres pajzshárítás! Sebzés: %d -> %d" % [incoming_raw_damage, raw])

	var def = controller.progression.defense if controller.progression else 0
	var actual_damage = maxi(0, raw - def)
	controller.current_hp = maxi(0, controller.current_hp - actual_damage)
	if controller.progression:
		controller.progression.sync_health_to_game_state(false)
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
	var can_class_block = c_name in ["Knight", "Knight Templar", "Knight_Templar", "Templar"] or (sprite and sprite.sprite_frames and sprite.sprite_frames.has_animation("block"))

	if not can_class_block:
		is_blocking_active = false
		return false

	if randf() < hero_block_chance:
		is_blocking_active = true
		if sprite and sprite.sprite_frames and sprite.sprite_frames.has_animation("block"):
			sprite.play("block")
		print("[HŐS BLOKKOL] A %s felemeli a pajzsát a csapás ellen!" % c_name)
		return true

	is_blocking_active = false
	return false

func can_attack_cell(target_cell: Vector2i) -> bool:
	var grid_mgr = controller.mover.grid_manager if (controller and controller.mover) else null
	var dist = grid_mgr.get_grid_distance(controller.grid_pos, target_cell) if grid_mgr else 1
	var max_range = get_effective_attack_range()
	if dist > max_range:
		return false

	if is_hero_ranged_attack(target_cell):
		return has_line_of_sight(controller.grid_pos, target_cell)

	var diff = target_cell - controller.grid_pos
	return diff.y == 0 and absi(diff.x) == 1

func has_line_of_sight(from_cell: Vector2i, to_cell: Vector2i) -> bool:
	var gm = controller.mover.grid_manager if (controller and controller.mover) else null
	if gm == null:
		return true
	var x0: int = from_cell.x
	var y0: int = from_cell.y
	var x1: int = to_cell.x
	var y1: int = to_cell.y
	var dx: int = absi(x1 - x0)
	var dy: int = absi(y1 - y0)
	var sx: int = 1 if x0 < x1 else -1
	var sy: int = 1 if y0 < y1 else -1
	var err: int = dx - dy

	while true:
		var current := Vector2i(x0, y0)
		if current != from_cell and current != to_cell:
			if gm.is_cell_solid(current):
				return false
		if x0 == x1 and y0 == y1:
			break
		var e2: int = 2 * err
		if e2 > -dy:
			err -= dy
			x0 += sx
		if e2 < dx:
			err += dx
			y0 += sy
	return true

## TÁMADÁSI KATTINTÁS
func handle_attack_click() -> bool:
	var fl = controller.mover.grid_manager.floor_layer if (controller and controller.mover and controller.mover.grid_manager) else null
	if not fl or controller.is_moving or in_battle or is_attacking or not controller.is_alive() or controller.is_stunned:
		return false

	var mouse_global: Vector2 = controller.get_global_mouse_position()
	var clicked_cell: Vector2i = fl.local_to_map(fl.to_local(mouse_global))
	var enemy: Node2D = _get_enemy_at_click(clicked_cell, mouse_global)
	if enemy == null:
		return false

	var target_cell: Vector2i = enemy.grid_pos if enemy.get("grid_pos") != null else clicked_cell
	if not controller.visuals.is_tile_in_vision(target_cell) and not controller.visuals.is_tile_in_vision(clicked_cell):
		return false

	if enemy.is_monster_alive() and (not enemy.has_method("is_targetable") or enemy.is_targetable()):
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
				return true

			# 2. SZABÁLY: Távolsági vs Közelharci
			elif is_ranged_shot and not enemy_is_ranged:
				if is_adjacent:
					var battle_ui = get_tree().get_first_node_in_group("battle_ui") as BattleDialog
					if battle_ui != null and not battle_ui.combat_active:
						battle_ui.open_battle(controller, enemy, false)
				else:
					perform_standalone_ranged_shot(enemy, true)
				return true

			# 3. SZABÁLY: Közelharci hős
			else:
				var battle_ui = get_tree().get_first_node_in_group("battle_ui") as BattleDialog
				if battle_ui != null and not battle_ui.combat_active:
					battle_ui.open_battle(controller, enemy, false)
				return true
		else:
			print("[Harcrendszer] Nem éred el a célpontot szabályosan!")
			return true
	return false

## KÖR VÉGREHAJTÁSA A PÁRBAJABLAKBAN (BATTLE DIALOG)
func perform_combat_turn(target_enemy: Node2D) -> int:
	last_attack_knockback_tiles = 0
	if not controller.is_alive() or not is_instance_valid(target_enemy): return 0

	var action = _resolve_hero_attack_action(target_enemy)
	var anim_name: String = action["anim"]
	var multiplier: float = action["multiplier"]
	var is_action_ranged: bool = action["is_ranged"]
	var knockback_tiles: int = int(action.get("knockback", 0))

	if not is_action_ranged and not can_attack_cell(target_enemy.grid_pos):
		await _step_closer_to_enemy(target_enemy)
		if not controller.is_alive() or not is_instance_valid(target_enemy): return 0

	if controller.visuals: controller.visuals.update_facing(target_enemy.grid_pos.x)

	var raw_damage = ceili(float(roll_attack_damage()) * multiplier)
	var sprite = controller.sprite

	if is_action_ranged:
		if sprite and sprite.sprite_frames.has_animation(anim_name): sprite.play(anim_name)
		
		var delay = _get_projectile_delay()
		if delay > 0.0: await get_tree().create_timer(delay).timeout

		await _fire_projectile_at_enemy(target_enemy, raw_damage)
		if raw_damage > 0:
			_apply_title_lifesteal()
	else:
		var is_heavy_strike: bool = knockback_tiles > 0 or multiplier >= 1.25
		AudioManager.sfx(&"heavy_cleave" if is_heavy_strike else &"sword_swing", 0.93, 1.07, -1.5)
		if sprite and sprite.sprite_frames.has_animation(anim_name):
			sprite.play(anim_name)
			if target_enemy.has_method("try_trigger_block"): target_enemy.try_trigger_block()
			await sprite.animation_finished

		var dealt_dmg: int = int(target_enemy.take_damage(raw_damage))
		if dealt_dmg > 0:
			AudioManager.sfx(&"crit_slam" if multiplier >= 1.4 else &"hit_melee", 0.93, 1.07, -1.5)
			_apply_title_lifesteal()
		controller.progression.gain_combat_xp(1)

	if sprite and controller.is_alive(): sprite.play("idle")
	if knockback_tiles > 0 and is_instance_valid(target_enemy) and target_enemy.is_monster_alive():
		last_attack_knockback_tiles = await _apply_enemy_knockback(target_enemy, knockback_tiles)
	if is_instance_valid(target_enemy) and target_enemy.has_method("play_hurt_reaction"):
		await target_enemy.play_hurt_reaction()

	return raw_damage

## TÉRKÉPI TÁVOLSÁGI LÖVÉS (PÁRBAJ NÉLKÜL)
func perform_standalone_ranged_shot(target_enemy: Node2D, triggers_turn: bool = true) -> void:
	is_attacking = true
	controller.z_index = 11
	if is_instance_valid(target_enemy):
		target_enemy.z_index = 8
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
	if raw_damage > 0:
		_apply_title_lifesteal()

	if sprite and controller.is_alive(): sprite.play("idle")
	if is_instance_valid(controller):
		controller.z_index = 10
	is_attacking = false

	if is_instance_valid(target_enemy):
		if not target_enemy.is_monster_alive():
			var e_data = target_enemy.get("enemy_data") as EnemyData
			var was_boss: bool = e_data != null and int(e_data.tier) == EnemyData.EnemyTier.BOSS
			var title = target_enemy.get_title() if target_enemy.has_method("get_title") else ""
			if title != "":
				controller.progression.award_title(title)
				var hud := get_tree().get_first_node_in_group("hud")
				if hud != null and hud.has_method("show_title_collected_toast"):
					hud.show_title_collected_toast(title)
			if target_enemy.has_method("play_overworld_death"): target_enemy.play_overworld_death()
			if was_boss and is_instance_valid(controller) and controller.has_method("on_boss_defeated"):
				controller.on_boss_defeated()
		else:
			if target_enemy.has_method("play_hurt_reaction"): await target_enemy.play_hurt_reaction()
			if is_instance_valid(target_enemy) and target_enemy.has_method("handle_post_damage_phase_reaction"):
				var triggered_phase: bool = await target_enemy.handle_post_damage_phase_reaction(controller)
				if triggered_phase:
					return
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

	# 3. ÍJÁSZ ÉS KATONA LÖVEDÉKEK
	elif p_scene != null:
		_consume_arrow_if_available(c_name)
		AudioManager.sfx(&"bow_release", 0.94, 1.06, -1.5)
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

func get_priest_heal_cooldown_remaining() -> float:
	return priest_heal_cooldown_remaining

func get_priest_heal_cooldown_duration() -> float:
	return PRIEST_HEAL_COOLDOWN

func cast_priest_self_heal() -> void:
	if not controller.is_alive() or in_battle or is_attacking or controller.is_moving or controller.is_stunned:
		return
	var c_name = controller.active_class.class_name_id if controller.active_class else ""
	if c_name != "Priest": return
	if priest_heal_cooldown_remaining > 0.0: return
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
	priest_heal_cooldown_remaining = PRIEST_HEAL_COOLDOWN
	if controller.progression:
		controller.progression.update_hud()

	if sprite and controller.is_alive(): sprite.play("idle")
	if is_instance_valid(controller):
		controller.z_index = 10
	is_attacking = false
	controller.trigger_monsters_turn()

func is_hero_ranged_attack(target_cell: Vector2i) -> bool:
	if controller.active_class == null:
		return is_ranged
	var c_name: String = controller.active_class.class_name_id
	if c_name in ["Archer", "Wizard", "Priest"]:
		return true
	if c_name == "Soldier":
		if not _has_soldier_arrows():
			return false
		var diff: Vector2i = target_cell - controller.grid_pos
		var is_horiz_adjacent: bool = (diff.y == 0 and absi(diff.x) == 1)
		return not is_horiz_adjacent
	return is_ranged

func get_effective_attack_range() -> int:
	if controller.active_class == null:
		return 1
	var c_name: String = controller.active_class.class_name_id
	var class_range: int = maxi(1, int(controller.active_class.attack_range))
	if c_name == "Archer":
		return maxi(5, class_range)
	elif c_name == "Wizard":
		return maxi(5, class_range)
	elif c_name == "Priest":
		return maxi(4, class_range)
	elif c_name == "Soldier":
		return maxi(4, class_range) if _has_soldier_arrows() else 1
	return 1

func _has_soldier_arrows() -> bool:
	var gs := get_node_or_null("/root/GameState")
	if gs == null or not gs.has_method("get_active_character"):
		return true
	var active_char = gs.get_active_character()
	if active_char == null:
		return true
	if gs.has_method("get_item_count"):
		return int(gs.get_item_count(&"arrow", false)) > 0
	return true

func _consume_arrow_if_available(c_name: String) -> void:
	if not c_name in ["Soldier", "Archer"]:
		return
	var gs := get_node_or_null("/root/GameState")
	if gs == null or not gs.has_method("consume_active_character_item"):
		return
	if gs.consume_active_character_item(&"arrow", 1):
		var remaining := int(gs.get_item_count(&"arrow", false))
		if c_name == "Soldier" and remaining == 0:
			print("[ÍJÁSZAT] Elfogytak a nyílvesszők — a katona közelharci kardra vált!")

func _resolve_hero_attack_action(target_enemy: Node2D) -> Dictionary:
	var c_name = controller.active_class.class_name_id if controller.active_class else "Adventurer"
	var grid_mgr = controller.mover.grid_manager
	var dist = grid_mgr.get_grid_distance(controller.grid_pos, target_enemy.grid_pos) if (grid_mgr and target_enemy) else 1

	var anim = "attack_1"
	var mult = 1.0
	var ranged = false
	var knockback = 0

	match c_name:
		"Archer":
			ranged = true
			if randf() < 0.25: anim = "attack_2"; mult = 1.75
		"Knight":
			if randf() < 0.12: anim = "attack_3"; mult = 2.0
			elif randf() < 0.38: anim = "attack_2"; mult = 1.25
		"Knight Templar", "Knight_Templar":
			if anim == "attack_1":
				knockback = 1
		"Soldier":
			var s_diff: Vector2i = (target_enemy.grid_pos - controller.grid_pos) if target_enemy else Vector2i.RIGHT
			var s_horiz_adj: bool = (s_diff.y == 0 and absi(s_diff.x) == 1)
			if not s_horiz_adj and _has_soldier_arrows():
				anim = "attack_2"
				ranged = true
			else:
				anim = "attack_1"
		"Wizard":
			ranged = true
			anim = "attack_1" if wizard_element == "ice" else "attack_2"
		"Priest":
			ranged = true
			anim = "attack_1"

	return {"anim": anim, "multiplier": mult, "is_ranged": ranged, "knockback": knockback}

## Ellenség hátralökése kábítás nélkül (pl. Knight Templar attack_1)
func _apply_enemy_knockback(target_enemy: Node2D, tiles: int) -> int:
	if not is_instance_valid(target_enemy) or not target_enemy.is_monster_alive() or tiles <= 0:
		return 0
	var grid_mgr = controller.mover.grid_manager if (controller and controller.mover) else null
	if grid_mgr == null or grid_mgr.floor_layer == null:
		return 0

	var diff: Vector2i = target_enemy.grid_pos - controller.grid_pos
	var dir := Vector2i(signi(diff.x), signi(diff.y))
	if dir == Vector2i.ZERO:
		dir = Vector2i.RIGHT

	var current: Vector2i = target_enemy.grid_pos
	var actual_steps: int = 0
	var mover = target_enemy.get("mover")

	for i in range(tiles):
		var next_cell := current + dir
		var can_step: bool = mover.is_cell_walkable(next_cell) if (mover != null and mover.has_method("is_cell_walkable")) else not grid_mgr.is_cell_solid(next_cell)
		if not can_step:
			break
		current = next_cell
		actual_steps += 1

	if actual_steps <= 0:
		return 0

	target_enemy.grid_pos = current
	if target_enemy.get("current_step_target") != null:
		target_enemy.current_step_target = current

	var target_world: Vector2 = grid_mgr.floor_layer.map_to_local(current)
	AudioManager.sfx(&"knockback_slide", 0.94, 1.06, -2.0)
	var tween = target_enemy.create_tween()
	tween.tween_property(target_enemy, "position", target_world, 0.15 * actual_steps).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	await tween.finished

	if is_instance_valid(target_enemy) and target_enemy.get("visuals") != null and target_enemy.visuals.has_method("update_fog_visibility"):
		target_enemy.visuals.update_fog_visibility()
	return actual_steps

func _step_closer_to_enemy(target_enemy: Node2D) -> void:
	if controller == null or controller.mover == null or not is_instance_valid(target_enemy):
		return
	var gm = controller.mover.grid_manager
	if gm == null or gm.floor_layer == null:
		return

	var diff: Vector2i = target_enemy.grid_pos - controller.grid_pos
	var dir_x: int = signi(diff.x)
	var dir_y: int = signi(diff.y)

	var ideal_cell: Vector2i = controller.grid_pos
	if dir_x != 0:
		ideal_cell = target_enemy.grid_pos - Vector2i(dir_x, 0)
	elif dir_y != 0:
		ideal_cell = target_enemy.grid_pos - Vector2i(0, dir_y)

	if ideal_cell == controller.grid_pos:
		return

	var next_cell: Vector2i = ideal_cell
	if gm.astar:
		var path = gm.astar.get_id_path(controller.grid_pos, ideal_cell)
		if path.size() > 1:
			next_cell = path[1]

	if gm.is_cell_solid(next_cell) or controller.mover.is_cell_blocked_for_player(next_cell):
		return

	if controller.visuals:
		controller.visuals.update_facing(next_cell.x)
		controller.visuals.play_walk_anim()

	controller.grid_pos = next_cell
	controller.current_step_target = next_cell

	var target_world: Vector2 = gm.floor_layer.map_to_local(next_cell)
	var tween = controller.create_tween()
	tween.tween_property(controller, "position", target_world, 0.18)
	await tween.finished

	if controller.visuals:
		controller.visuals.update_fog_of_war()
		controller.visuals.update_facing(target_enemy.grid_pos.x)
		controller.visuals.play_idle_anim()

func _get_enemy_at_cell(cell: Vector2i) -> Node2D:
	for enemy in get_tree().get_nodes_in_group("enemies"):
		if is_instance_valid(enemy) and enemy.get("grid_pos") == cell:
			return enemy as Node2D
	return null

func _get_enemy_at_click(clicked_cell: Vector2i, click_global_pos: Vector2) -> Node2D:
	var direct: Node2D = _get_enemy_at_cell(clicked_cell)
	if direct != null and direct.is_monster_alive() and (not direct.has_method("is_targetable") or direct.is_targetable()):
		return direct

	# Mozgó vagy magasabb sprite-tal rendelkező ellenfelek (pl. Nekromanta) kényelmes kijelölése
	var best_enemy: Node2D = null
	var best_dist_sq: float = INF
	for node in get_tree().get_nodes_in_group("enemies"):
		var enemy := node as Node2D
		if not is_instance_valid(enemy):
			continue
		if not enemy.is_monster_alive():
			continue
		if enemy.has_method("is_targetable") and not enemy.is_targetable():
			continue

		if enemy.get("current_step_target") != null and enemy.get("current_step_target") == clicked_cell:
			return enemy

		var delta: Vector2 = click_global_pos - enemy.global_position
		if absf(delta.x) <= 13.0 and delta.y >= -22.0 and delta.y <= 10.0:
			var dist_sq: float = delta.length_squared()
			if dist_sq < best_dist_sq:
				best_dist_sq = dist_sq
				best_enemy = enemy

	return best_enemy
