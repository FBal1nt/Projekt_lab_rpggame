extends AnimatedSprite2D
class_name HeroVisuals

var controller: HeroController

@export_group("Megjelenés és Köd")
var sprite: AnimatedSprite2D
@export var fog_of_war: FogOfWar
@export var vision_limit: int = 25

var hovered_cell: Vector2i = Vector2i(-99999, -99999)

func setup(p_controller: HeroController) -> void:
	controller = p_controller

	sprite = self

	if fog_of_war == null:
		fog_of_war = get_tree().root.find_child("FogOfWar", true, false) as FogOfWar

	play_idle_anim()

	update_fog_of_war()

func play_idle_anim() -> void:
	if sprite and sprite.sprite_frames:
		if sprite.sprite_frames.has_animation("idle"): sprite.play("idle")
		elif sprite.sprite_frames.has_animation("default"): sprite.play("default")

func play_walk_anim() -> void:
	if sprite and sprite.sprite_frames and sprite.sprite_frames.has_animation("walk"):
		sprite.play("walk")

func play_hurt_reaction() -> void:
	if controller.combat and controller.combat.is_blocking_active:
		if sprite and sprite.is_playing() and sprite.animation == "block":
			await sprite.animation_finished
		controller.combat.is_blocking_active = false
		play_idle_anim()
		return

	if sprite and sprite.sprite_frames.has_animation("hurt") and controller.is_alive():
		sprite.play("hurt")
		await sprite.animation_finished
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
	if controller:
		var diff = cell - controller.grid_pos
		return (diff.x * diff.x + diff.y * diff.y) <= vision_limit
	return true

func process_hover() -> void:
	var grid_mgr = controller.mover.grid_manager if (controller and controller.mover) else null
	if not grid_mgr or not grid_mgr.floor_layer: return

	var fl = grid_mgr.floor_layer
	var current_cell = fl.local_to_map(fl.to_local(get_global_mouse_position()))
	if current_cell != hovered_cell:
		hovered_cell = current_cell
		queue_redraw()

func _draw() -> void:
	var grid_mgr = controller.mover.grid_manager if (controller and controller.mover) else null
	if not grid_mgr or not grid_mgr.floor_layer or (controller and controller.in_battle):
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
	else:
		var blocked = grid_mgr.is_cell_solid(hovered_cell) or not in_vision
		var fill_color = Color(0.9, 0.2, 0.2, 0.25) if blocked else Color(1.0, 1.0, 1.0, 0.15)
		var border_color = Color(0.9, 0.2, 0.2, 0.9) if blocked else Color(1.0, 0.9, 0.3, 0.9)
		draw_rect(rect, fill_color, true)
		draw_rect(rect, border_color, false, 1.5)
