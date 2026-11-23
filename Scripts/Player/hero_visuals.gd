extends AnimatedSprite2D
class_name HeroVisuals

var controller: HeroController

@export_group("Megjelenés és Köd")
var sprite: AnimatedSprite2D
@export var fog_of_war: FogOfWar
## A látótávolság négyzetsugara rácscellákban (2 = 5x5 mező, 3 = 7x7 mező)
@export var vision_limit: int = 2

var hovered_cell: Vector2i = Vector2i(-99999, -99999)
var _last_hover_hero_cell: Vector2i = Vector2i(-99999, -99999)
var _last_hover_hero_pos: Vector2 = Vector2.INF
var _last_hover_enemy_cell: Vector2i = Vector2i(-99999, -99999)

func _exit_tree() -> void:
	var sm := get_node_or_null("/root/SettingsManager")
	if sm != null and sm.has_signal("settings_changed") and sm.settings_changed.is_connected(queue_redraw):
		sm.settings_changed.disconnect(queue_redraw)

func setup(p_controller: HeroController) -> void:
	controller = p_controller
	sprite = self

	if fog_of_war == null:
		fog_of_war = get_tree().root.find_child("FogOfWar", true, false) as FogOfWar

	var sm := get_node_or_null("/root/SettingsManager")
	if sm != null and sm.has_signal("settings_changed") and not sm.settings_changed.is_connected(queue_redraw):
		sm.settings_changed.connect(queue_redraw)

	play_idle_anim()
	update_fog_of_war()

func play_idle_anim() -> void:
	if controller and not controller.is_alive():
		return

	if sprite and sprite.sprite_frames:
		if sprite.sprite_frames.has_animation("idle"): sprite.play("idle")
		elif sprite.sprite_frames.has_animation("default"): sprite.play("default")

func play_walk_anim() -> void:
	if controller and not controller.is_alive():
		return

	if sprite and sprite.sprite_frames and sprite.sprite_frames.has_animation("walk"):
		sprite.play("walk")

func play_heal_effect() -> void:
	if not is_inside_tree():
		return
	var tween := create_tween()
	tween.tween_property(self, "self_modulate", Color(0.55, 1.0, 0.65, 1.0), 0.12)
	tween.tween_property(self, "self_modulate", Color.WHITE, 0.25)

func play_hurt_reaction() -> void:
	if controller and (not controller.is_alive() or controller.is_death_played):
		return
	if controller and (controller.is_stunned or (controller.has_meta("knockback_in_progress") and bool(controller.get_meta("knockback_in_progress")))):
		return

	if controller.combat and controller.combat.is_blocking_active:
		AudioManager.sfx(&"shield_block", 0.94, 1.06, -1.0)
		await _await_anim_or_interrupt("block", 0.8)
		controller.combat.is_blocking_active = false
		if not controller.is_moving and sprite and sprite.animation in ["block", "idle"]:
			play_idle_anim()
		return

	if controller.is_alive():
		AudioManager.sfx(&"hurt_hero", 0.94, 1.06, -2.0)

	if controller.is_moving:
		return

	if sprite and sprite.sprite_frames and sprite.sprite_frames.has_animation("hurt") and controller.is_alive():
		sprite.play("hurt")
		await _await_anim_or_interrupt("hurt", 0.8)
		if controller and controller.is_alive() and not controller.is_moving and sprite and sprite.animation == "hurt":
			play_idle_anim()

func _await_anim_or_interrupt(anim_name: String, fallback_duration: float = 0.8) -> void:
	if not sprite or not is_instance_valid(sprite) or not sprite.is_playing() or sprite.animation != anim_name:
		return
	var dur := fallback_duration
	if sprite.sprite_frames and sprite.sprite_frames.has_animation(anim_name):
		var frames := sprite.sprite_frames.get_frame_count(anim_name)
		var fps := sprite.sprite_frames.get_animation_speed(anim_name)
		if fps > 0.0:
			dur = float(frames) / fps + 0.05
	var elapsed := 0.0
	while elapsed < dur:
		if not is_instance_valid(sprite) or not sprite.is_inside_tree():
			return
		if not sprite.is_playing() or sprite.animation != anim_name:
			return
		await get_tree().process_frame
		elapsed += get_process_delta_time()

## Kábítási animáció: földre esés, fekvés, majd felkelés
func play_stun_sequence(duration: float = 0.8) -> void:
	if not sprite_frames: return

	if sprite_frames.has_animation("death"):
		play("death")
		await animation_finished
		await get_tree().create_timer(duration).timeout
		play_backwards("death")
		await animation_finished
	else:
		await get_tree().create_timer(duration).timeout

	play_idle_anim()

func update_facing(target_grid_x: int) -> void:
	if not sprite or controller == null: return
	if target_grid_x < controller.grid_pos.x: sprite.flip_h = true
	elif target_grid_x > controller.grid_pos.x: sprite.flip_h = false

func update_fog_of_war() -> void:
	if fog_of_war and controller:
		fog_of_war.update_vision(controller.grid_pos, vision_limit)
		get_tree().call_group("enemies", "update_fog_visibility")
		get_tree().call_group("loot_bags", "update_fog_visibility")

func is_tile_in_vision(cell: Vector2i) -> bool:
	if fog_of_war and fog_of_war.is_initialized:
		return cell in fog_of_war.current_visible_cells
	return _is_tile_within_vision_limit(cell)

func _is_tile_within_vision_limit(cell: Vector2i) -> bool:
	if controller == null:
		return true
	var diff: Vector2i = cell - controller.grid_pos
	var radius_tiles: float = float(vision_limit) + 0.5
	return float(diff.x * diff.x + diff.y * diff.y) <= radius_tiles * radius_tiles

func process_hover() -> void:
	var grid_mgr = controller.mover.grid_manager if (controller and controller.mover) else null
	if not grid_mgr or not grid_mgr.floor_layer or grid_mgr.floor_layer.tile_set == null or not grid_mgr.is_initialized: return

	var fl = grid_mgr.floor_layer
	var mouse_global: Vector2 = get_global_mouse_position()
	var current_cell: Vector2i = fl.local_to_map(fl.to_local(mouse_global))
	var hero_cell: Vector2i = controller.grid_pos if controller else Vector2i.ZERO
	var hero_pos: Vector2 = controller.global_position if controller else Vector2.ZERO
	var enemy_cell := Vector2i(-99999, -99999)
	if controller != null and controller.combat != null and controller.combat.has_method("_get_enemy_at_click"):
		var hovered_enemy: Node2D = controller.combat._get_enemy_at_click(current_cell, mouse_global)
		if hovered_enemy != null and hovered_enemy.get("grid_pos") != null:
			enemy_cell = hovered_enemy.grid_pos as Vector2i
	if current_cell != hovered_cell or hero_cell != _last_hover_hero_cell or not hero_pos.is_equal_approx(_last_hover_hero_pos) or enemy_cell != _last_hover_enemy_cell:
		hovered_cell = current_cell
		_last_hover_hero_cell = hero_cell
		_last_hover_hero_pos = hero_pos
		_last_hover_enemy_cell = enemy_cell
		queue_redraw()

func _draw() -> void:
	var sm := get_node_or_null("/root/SettingsManager")
	if sm != null and not bool(sm.get("show_tile_hover")):
		return
	var grid_mgr = controller.mover.grid_manager if (controller and controller.mover) else null
	if not grid_mgr or not grid_mgr.floor_layer or grid_mgr.floor_layer.tile_set == null or not grid_mgr.is_initialized or (controller and controller.in_battle) or (controller and not controller.is_alive()):
		return

	var allow_click_move: bool = (
		bool(sm.is_click_movement_enabled())
		if (sm != null and sm.has_method("is_click_movement_enabled"))
		else true
	)
	var has_ranged_weapon: bool = (
		controller != null
		and controller.combat != null
		and (controller.combat.is_ranged or controller.combat.get_effective_attack_range() > 1)
	)
	if not allow_click_move and not has_ranged_weapon:
		return

	var fl = grid_mgr.floor_layer
	var cell_size = grid_mgr.cell_size

	var mouse_global: Vector2 = get_global_mouse_position()
	var hovered_enemy: Node2D = null
	if controller != null and controller.combat != null and controller.combat.has_method("_get_enemy_at_click"):
		hovered_enemy = controller.combat._get_enemy_at_click(hovered_cell, mouse_global)
	var target_cell: Vector2i = hovered_cell
	if hovered_enemy != null and hovered_enemy.get("grid_pos") != null:
		target_cell = hovered_enemy.grid_pos as Vector2i

	var target_global = fl.to_global(fl.map_to_local(target_cell))
	var draw_pos = to_local(target_global)
	var rect = Rect2(draw_pos - cell_size / 2.0, cell_size)

	var in_vision: bool = is_tile_in_vision(target_cell) or is_tile_in_vision(hovered_cell)
	if target_cell == controller.grid_pos or not in_vision:
		return

	var has_enemy_target: bool = hovered_enemy != null and hovered_enemy.is_monster_alive()
	var can_shoot_cell: bool = (
		controller != null
		and controller.combat != null
		and controller.combat.can_attack_cell(target_cell)
	)

	# WASD-módban távolsági fegyverrel a kék négyzet helyett célkereszt jelenjen meg
	if not allow_click_move and has_ranged_weapon:
		if has_enemy_target or not grid_mgr.is_cell_solid(target_cell):
			_draw_ranged_crosshair(rect, has_enemy_target, can_shoot_cell)
		return

	# Kattintásos + távolsági módban ellenség felett célkereszt, üres járható mezőn kék mozgásjelző
	if has_ranged_weapon and has_enemy_target and can_shoot_cell:
		_draw_ranged_crosshair(rect, true, true)
		return

	if _is_tile_within_vision_limit(target_cell) and not grid_mgr.is_cell_solid(target_cell):
		_draw_move_target_indicator(rect)

func _draw_ranged_crosshair(rect: Rect2, is_enemy: bool, can_shoot: bool) -> void:
	var center: Vector2 = rect.get_center()
	var min_side: float = minf(rect.size.x, rect.size.y)
	var radius: float = clampf(min_side * 0.34, 4.0, 6.5)
	var tick_inner: float = radius * 0.45
	var tick_outer: float = radius + 2.4

	var ring_col: Color
	var dot_col: Color
	if is_enemy and can_shoot:
		ring_col = Color(1.0, 0.28, 0.25, 0.96)
		dot_col = Color(1.0, 0.88, 0.40, 1.0)
	elif can_shoot:
		ring_col = Color(0.98, 0.84, 0.38, 0.90)
		dot_col = Color(1.0, 0.96, 0.78, 0.95)
	else:
		ring_col = Color(0.68, 0.74, 0.84, 0.42)
		dot_col = Color(0.68, 0.74, 0.84, 0.50)

	# Finom célgyűrű + 4 irányú célkereszt szárak + középpont
	draw_arc(center, radius, 0.0, TAU, 24, ring_col, 1.25, false)
	draw_line(Vector2(center.x - tick_outer, center.y), Vector2(center.x - tick_inner, center.y), ring_col, 1.35)
	draw_line(Vector2(center.x + tick_inner, center.y), Vector2(center.x + tick_outer, center.y), ring_col, 1.35)
	draw_line(Vector2(center.x, center.y - tick_outer), Vector2(center.x, center.y - tick_inner), ring_col, 1.35)
	draw_line(Vector2(center.x, center.y + tick_inner), Vector2(center.x, center.y + tick_outer), ring_col, 1.35)
	draw_circle(center, 1.25, dot_col)

func _draw_move_target_indicator(rect: Rect2) -> void:
	var inner: Rect2 = rect.grow(-1.0)
	if inner.size.x <= 2.0 or inner.size.y <= 2.0:
		inner = rect

	# Finom áttetsző mezőkiemelés és diszkrét belső keret
	draw_rect(inner, Color(0.55, 0.85, 1.0, 0.14), true)
	draw_rect(inner, Color(0.65, 0.90, 1.0, 0.28), false, 1.0)

	# Négy sarkon L-alakú célkereszt (pixel-éles mozgásjelző)
	var arm: float = clampf(minf(inner.size.x, inner.size.y) * 0.28, 3.0, 5.0)
	var corner_col := Color(0.75, 0.94, 1.0, 0.92)
	var l := inner.position.x
	var r := inner.end.x
	var t := inner.position.y
	var b := inner.end.y

	draw_line(Vector2(l, t), Vector2(l + arm, t), corner_col, 1.5)
	draw_line(Vector2(l, t), Vector2(l, t + arm), corner_col, 1.5)
	draw_line(Vector2(r - arm, t), Vector2(r, t), corner_col, 1.5)
	draw_line(Vector2(r, t), Vector2(r, t + arm), corner_col, 1.5)
	draw_line(Vector2(l, b), Vector2(l + arm, b), corner_col, 1.5)
	draw_line(Vector2(l, b - arm), Vector2(l, b), corner_col, 1.5)
	draw_line(Vector2(r - arm, b), Vector2(r, b), corner_col, 1.5)
	draw_line(Vector2(r, b - arm), Vector2(r, b), corner_col, 1.5)
