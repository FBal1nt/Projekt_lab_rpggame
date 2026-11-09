extends AnimatedSprite2D
class_name EnemyVisuals

@export_group("Megjelenés és Animáció")
@export var sprite: AnimatedSprite2D
@export var custom_frames: SpriteFrames
@export var sprite_scale: Vector2 = Vector2.ONE
@export var sprite_offset: Vector2 = Vector2.ZERO
@export var start_facing_left: bool = false
@export var resurrect_delay: float = 0.7

@export_group("Köd Referencia")
@export var fog_of_war: FogOfWar

var controller: EnemyController

## Komponens inicializálása a szülő EnemyController által
func setup(p_controller: EnemyController) -> void:
	controller = p_controller
	sprite = self

	if fog_of_war == null:
		fog_of_war = get_tree().root.find_child("FogOfWar", true, false) as FogOfWar

	_setup_visuals()
	update_fog_visibility()

func _setup_visuals() -> void:
	if not sprite: return

	var data = controller.enemy_data if controller else null
	var target_frames: SpriteFrames = null

	if custom_frames != null:
		target_frames = custom_frames
	elif data and data.sprite_frames != null:
		target_frames = data.sprite_frames

	if target_frames != null:
		# Megkeressük az első érvényes alapértelmezett animációt a hibák elkerülésére:
		var safe_anim = "idle"
		if not target_frames.has_animation(safe_anim):
			var all_anims = target_frames.get_animation_names()
			if all_anims.size() > 0:
				safe_anim = all_anims[0]

		# Előbb átállítjuk a sprite-ot a biztonságos névre, majd átadjuk a frame-eket:
		sprite.sprite_frames = target_frames
		if sprite.sprite_frames.has_animation(safe_anim):
			sprite.animation = safe_anim

	if data and data.sprite_scale != Vector2.ONE:
		sprite.scale = data.sprite_scale
	else:
		sprite.scale = sprite_scale

	if data and data.sprite_offset != Vector2.ZERO:
		sprite.offset = data.sprite_offset
	else:
		sprite.offset = sprite_offset

	sprite.flip_h = start_facing_left
	play_idle_anim()

# --- ALAPVETŐ ANIMÁCIÓK LEJÁTSZÁSA ---

func play_idle_anim() -> void:
	if not sprite or not sprite.sprite_frames: return
	for anim in ["idle", "flying", "Flying", "fly"]:
		if sprite.sprite_frames.has_animation(anim):
			play(anim)
			return

func play_move_anim() -> void:
	if not sprite or not sprite.sprite_frames: return
	for anim in ["flying", "Flying", "fly", "walk"]:
		if sprite.sprite_frames.has_animation(anim):
			play(anim)
			return
	play_idle_anim()

# --- HARCI ÉS VÁLTAKOZÓ TÁMADÁSI ANIMÁCIÓK ---

## Megvizsgálja, hogy a szörny rendelkezik-e mindkét támadási fázissal (pl. Ork)
func has_combo_attacks() -> bool:
	return _get_anim_for_step(0) != "" and _get_anim_for_step(1) != ""

## Visszaadja a kívánt fázishoz tartozó animációt (0: gyenge csapás, 1: erős csapás)
func get_combo_anim(step: int) -> String:
	var anim = _get_anim_for_step(step)
	return anim if anim != "" else _get_attack_anim_name()

func _get_anim_for_step(step: int) -> String:
	if not sprite or not sprite.sprite_frames: return ""
	var candidates: Array[String] = []
	if step == 0:
		candidates = ["attack_1", "Attack01", "attack_01", "attack"]
	else:
		candidates = ["attack_2", "Attack02", "attack_02"]

	for anim in candidates:
		if sprite.sprite_frames.has_animation(anim):
			return anim
	return ""

func play_attack_animation() -> String:
	var anim = _get_attack_anim_name()
	if anim != "" and sprite:
		play(anim)
	return anim

func play_death_animation() -> void:
	var d_anim = _get_death_anim_name()
	if d_anim != "" and sprite:
		play(d_anim)
		await sprite.animation_finished

func get_attack_animation_length(anim_name: String) -> float:
	if not sprite or not sprite.sprite_frames or anim_name == "":
		return 0.4
	var frames = sprite.sprite_frames.get_frame_count(anim_name)
	var fps = sprite.sprite_frames.get_animation_speed(anim_name)
	if fps > 0:
		return float(frames) / fps
	return 0.4

func _get_attack_anim_name() -> String:
	if not sprite or not sprite.sprite_frames: return ""
	var available_attacks: Array[String] = []
	for anim in ["attack_1", "Attack01", "attack_01", "attack", "attack_2", "Attack02", "attack_02"]:
		if sprite.sprite_frames.has_animation(anim) and not anim in available_attacks:
			available_attacks.append(anim)

	if not available_attacks.is_empty():
		return available_attacks.pick_random()
	return ""

func _get_block_anim_name() -> String:
	if not sprite or not sprite.sprite_frames: return ""
	for anim in ["block", "Block", "shield_block", "Shield_Block"]:
		if sprite.sprite_frames.has_animation(anim):
			return anim
	return ""

func _get_death_anim_name() -> String:
	if not sprite or not sprite.sprite_frames: return ""
	for anim in ["death", "Death", "Bat_Death"]:
		if sprite.sprite_frames.has_animation(anim):
			return anim
	return ""

func _get_hurt_anim_name() -> String:
	if not sprite or not sprite.sprite_frames: return ""
	for anim in ["hurt", "Hurt", "Bat_Hurt"]:
		if sprite.sprite_frames.has_animation(anim):
			return anim
	return ""

# --- REAKCIÓK ÉS FORGÁS ---

func play_hurt_reaction() -> void:
	var is_blocking = controller.combat.is_blocking_active if (controller and controller.combat) else false
	var is_dead = controller.is_dead if controller else false

	if is_blocking:
		var b_anim = _get_block_anim_name()
		if sprite and sprite.is_playing() and sprite.animation == b_anim:
			await sprite.animation_finished
		if controller and controller.combat:
			controller.combat.is_blocking_active = false
		if not is_dead: play_idle_anim()
		return

	var h_anim = _get_hurt_anim_name()
	if h_anim != "" and not is_dead:
		play(h_anim)
		await sprite.animation_finished
		if not is_dead: play_idle_anim()

func play_respawn_animation() -> void:
	if not sprite or not sprite.sprite_frames: return
	update_fog_visibility()

	if sprite.sprite_frames.has_animation("respawn"):
		play("respawn")
		await sprite.animation_finished
	else:
		var d_anim = _get_death_anim_name()
		if d_anim != "":
			play_backwards(d_anim)
			await sprite.animation_finished

	play_idle_anim()
	update_fog_visibility()

func update_facing(target_grid_x: int) -> void:
	if not sprite or controller == null: return
	if target_grid_x < controller.grid_pos.x:
		sprite.flip_h = true
	elif target_grid_x > controller.grid_pos.x:
		sprite.flip_h = false

func update_fog_visibility() -> void:
	if controller == null: return
	if fog_of_war and fog_of_war.is_initialized:
		controller.visible = (controller.grid_pos in fog_of_war.current_visible_cells)
	else:
		var hero = _find_hero()
		controller.visible = hero.is_tile_in_vision(controller.grid_pos) if hero else false

func _find_hero() -> HeroController:
	var heroes = get_tree().get_nodes_in_group("player")
	return heroes[0] if not heroes.is_empty() else null
