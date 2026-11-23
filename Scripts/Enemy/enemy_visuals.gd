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
		await _await_anim_or_interrupt(d_anim, 1.2)

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
		AudioManager.sfx(&"shield_block", 0.94, 1.06, -1.5)
		var b_anim = _get_block_anim_name()
		if b_anim != "":
			await _await_anim_or_interrupt(b_anim, 0.8)
		if controller and controller.combat:
			controller.combat.is_blocking_active = false
		if not is_dead: play_idle_anim()
		return

	var h_anim = _get_hurt_anim_name()
	if h_anim != "" and not is_dead:
		AudioManager.sfx(&"hurt_enemy", 0.90, 1.12, -2.5)
		play(h_anim)
		await _await_anim_or_interrupt(h_anim, 0.8)
		if not is_dead and controller and not controller.is_moving and not controller.is_attacking:
			play_idle_anim()

func play_respawn_animation() -> void:
	if not sprite or not sprite.sprite_frames: return
	AudioManager.sfx(&"enemy_revive", 0.94, 1.06, -1.0)
	update_fog_visibility()

	if sprite.sprite_frames.has_animation("respawn"):
		play("respawn")
		await _await_anim_or_interrupt("respawn", 1.0)
	else:
		var d_anim = _get_death_anim_name()
		if d_anim != "":
			play_backwards(d_anim)
			await _await_anim_or_interrupt(d_anim, 1.2)

	play_idle_anim()
	update_fog_visibility()

func _await_anim_or_interrupt(anim_name: String, fallback_duration: float = 0.8) -> void:
	if not sprite or not is_instance_valid(sprite) or not sprite.is_playing() or sprite.animation != anim_name:
		return
	var dur: float = fallback_duration
	if sprite.sprite_frames and sprite.sprite_frames.has_animation(anim_name):
		var frames: int = sprite.sprite_frames.get_frame_count(anim_name)
		var fps: float = sprite.sprite_frames.get_animation_speed(anim_name)
		if fps > 0.0:
			dur = float(frames) / fps + 0.05
	var elapsed: float = 0.0
	while elapsed < dur:
		if not is_instance_valid(sprite) or not sprite.is_inside_tree():
			return
		if not sprite.is_playing() or sprite.animation != anim_name:
			return
		await get_tree().process_frame
		elapsed += get_process_delta_time()

func update_facing(target_grid_x: int) -> void:
	if not sprite or controller == null: return
	if target_grid_x < controller.grid_pos.x:
		sprite.flip_h = true
	elif target_grid_x > controller.grid_pos.x:
		sprite.flip_h = false

func update_fog_visibility() -> void:
	if controller == null: return
	if controller.combat and controller.combat.elite_combat and controller.combat.elite_combat.is_necromancer_vanished():
		controller.visible = false
		return
	if fog_of_war and fog_of_war.is_initialized:
		controller.visible = (controller.grid_pos in fog_of_war.current_visible_cells)
	else:
		var hero = _find_hero()
		controller.visible = hero.is_tile_in_vision(controller.grid_pos) if hero else false

func _find_hero() -> HeroController:
	var heroes = get_tree().get_nodes_in_group("player")
	return heroes[0] if not heroes.is_empty() else null


## Waits until target_sprite displays target_frame (0-indexed) of anim_name, falling back to a timed wait if sprite/anim is unavailable.
static func await_sprite_frame(tree_owner: Node, target_sprite: AnimatedSprite2D, anim_name: String, target_frame: int) -> void:
	if target_frame <= 0 or tree_owner == null or not is_instance_valid(tree_owner) or not tree_owner.is_inside_tree():
		return
	if target_sprite == null or not is_instance_valid(target_sprite) or not target_sprite.is_inside_tree() or target_sprite.sprite_frames == null or not target_sprite.sprite_frames.has_animation(anim_name):
		await tree_owner.get_tree().create_timer(float(target_frame) / 8.0).timeout
		return
	var total_frames: int = target_sprite.sprite_frames.get_frame_count(anim_name)
	var clamped_target: int = clampi(target_frame, 0, maxi(0, total_frames - 1))
	while is_instance_valid(target_sprite) and target_sprite.is_inside_tree() and target_sprite.is_playing() and target_sprite.animation == anim_name and target_sprite.frame < clamped_target:
		if not is_instance_valid(tree_owner) or not tree_owner.is_inside_tree():
			return
		await tree_owner.get_tree().process_frame


## Lets the current attack animation finish and returns to idle asynchronously so long stun sequences do not freeze the attacker mid-swing.
func finish_attack_to_idle_async(anim_name: String) -> void:
	if anim_name == "" or not sprite or not is_instance_valid(sprite) or not sprite.is_inside_tree():
		return
	if sprite.is_playing() and sprite.animation == anim_name:
		await _await_anim_or_interrupt(anim_name, 1.5)
	if not is_instance_valid(self) or not is_instance_valid(controller) or not is_instance_valid(sprite):
		return
	if not controller.is_dead and not controller.is_moving and (sprite.animation == anim_name or not sprite.is_playing()):
		play_idle_anim()
