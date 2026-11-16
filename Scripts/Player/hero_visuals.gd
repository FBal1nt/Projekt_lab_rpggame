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

func setup(p_controller: HeroController) -> void:
	controller = p_controller
	sprite = self

	if fog_of_war == null:
		fog_of_war = get_tree().root.find_child("FogOfWar", true, false) as FogOfWar

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

func play_hurt_reaction() -> void:
	if controller and not controller.is_alive():
		return

	if controller.combat and controller.combat.is_blocking_active:
		if sprite and sprite.is_playing() and sprite.animation == "block":
			await sprite.animation_finished
		controller.combat.is_blocking_active = false
		play_idle_anim()
		return

	if sprite and sprite.sprite_frames and sprite.sprite_frames.has_animation("hurt") and controller.is_alive():
		sprite.play("hurt")
		await sprite.animation_finished
		play_idle_anim()

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
	var current_cell = fl.local_to_map(fl.to_local(get_global_mouse_position()))
	var hero_cell: Vector2i = controller.grid_pos if controller else Vector2i.ZERO
	var hero_pos: Vector2 = controller.global_position if controller else Vector2.ZERO
	if current_cell != hovered_cell or hero_cell != _last_hover_hero_cell or not hero_pos.is_equal_approx(_last_hover_hero_pos):
		hovered_cell = current_cell
		_last_hover_hero_cell = hero_cell
		_last_hover_hero_pos = hero_pos
		queue_redraw()

func _draw() -> void:
	var grid_mgr = controller.mover.grid_manager if (controller and controller.mover) else null
	if not grid_mgr or not grid_mgr.floor_layer or grid_mgr.floor_layer.tile_set == null or not grid_mgr.is_initialized or (controller and controller.in_battle) or (controller and not controller.is_alive()):
		return

	var fl = grid_mgr.floor_layer
	var cell_size = grid_mgr.cell_size
	var target_global = fl.to_global(fl.map_to_local(hovered_cell))
	var draw_pos = to_local(target_global)
	var rect = Rect2(draw_pos - cell_size / 2.0, cell_size)

	var enemy_here = controller.combat._get_enemy_at_cell(hovered_cell) if controller.combat else null
	var in_vision = is_tile_in_vision(hovered_cell)

	if enemy_here != null and in_vision and enemy_here.is_monster_alive():
		var dist = grid_mgr.get_grid_distance(controller.grid_pos, hovered_cell)
		var current_range = controller.combat.get_effective_attack_range()
		var in_range = dist <= current_range
		var fill_color = Color(1.0, 0.1, 0.1, 0.45) if in_range else Color(0.5, 0.1, 0.1, 0.25)
		var border_color = Color(1.0, 0.2, 0.2, 1.0) if in_range else Color(0.6, 0.2, 0.2, 0.6)
		draw_rect(rect, fill_color, true)
		draw_rect(rect, border_color, false, 2.0)
	elif hovered_cell != controller.grid_pos and in_vision and _is_tile_within_vision_limit(hovered_cell) and not grid_mgr.is_cell_solid(hovered_cell):
		_draw_move_target_indicator(rect)

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
