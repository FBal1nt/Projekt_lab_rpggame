extends Node2D
class_name WizardSpell

@export var flight_speed: float = 130.0
@onready var anim_sprite: AnimatedSprite2D = $AnimatedSprite2D

func launch(_start_pos: Vector2, target_node: Node2D, damage: int, source_actor: Object = null) -> void:
	if not is_instance_valid(target_node):
		queue_free()
		return

	global_position = target_node.global_position
	z_index = 12

	if anim_sprite == null or anim_sprite.sprite_frames == null:
		_deliver_impact(target_node, damage, source_actor, "MÁGIA")
		queue_free()
		return

	var anim_name := "default"
	if not anim_sprite.sprite_frames.has_animation(anim_name):
		var names := anim_sprite.sprite_frames.get_animation_names()
		if names.is_empty():
			_deliver_impact(target_node, damage, source_actor, "MÁGIA")
			queue_free()
			return
		anim_name = String(names[0])

	anim_sprite.stop()
	anim_sprite.frame = 0
	anim_sprite.play(anim_name)
	AudioManager.sfx(&"necro_cast", 0.94, 1.06)

	var frame_count := anim_sprite.sprite_frames.get_frame_count(anim_name)
	var fps := anim_sprite.sprite_frames.get_animation_speed(anim_name)
	if fps <= 0.0:
		fps = 8.0
	var impact_frame := mini(3, maxi(0, frame_count - 1))
	await get_tree().create_timer(float(impact_frame) / fps).timeout

	if is_instance_valid(target_node):
		_deliver_impact(target_node, damage, source_actor, "MÁGIA")

	if is_instance_valid(anim_sprite) and anim_sprite.is_playing():
		anim_sprite.animation_finished.connect(queue_free)
	else:
		queue_free()

func spawn_ice(target_enemy: Node2D, damage: int, source_hero: Object = null) -> void:
	if not is_instance_valid(target_enemy):
		queue_free()
		return

	global_position = target_enemy.global_position
	z_index = 12
	AudioManager.sfx(&"spell_ice", 0.95, 1.06)

	_deliver_impact(target_enemy, damage, source_hero, "JÉGCSAP")

	if anim_sprite:
		anim_sprite.play("ice")
		anim_sprite.animation_finished.connect(queue_free)
	else:
		queue_free()

func launch_fire(start_pos: Vector2, target_enemy: Node2D, damage: int, source_hero: Object = null) -> void:
	if not is_instance_valid(target_enemy):
		queue_free()
		return

	global_position = start_pos
	z_index = 12

	var target_pos = target_enemy.global_position
	var flight_vector = target_pos - start_pos
	var distance = flight_vector.length()

	rotation = flight_vector.angle()
	if anim_sprite:
		anim_sprite.play("fire")
	AudioManager.sfx(&"spell_fire", 0.95, 1.06)

	var duration = clampf(distance / flight_speed, 0.25, 0.6)
	var tween = create_tween()
	tween.tween_property(self, "global_position", target_pos, duration).set_trans(Tween.TRANS_LINEAR)
	tween.finished.connect(func():
		_on_fireball_hit(target_enemy, damage, source_hero)
	)

func _on_fireball_hit(target_enemy: Node2D, damage: int, source_hero: Object) -> void:
	AudioManager.sfx(&"hit_melee", 0.85, 0.95, -2.0)
	if is_instance_valid(target_enemy):
		_deliver_impact(target_enemy, damage, source_hero, "TŰZGOLYÓ")

	if anim_sprite and anim_sprite.is_playing():
		anim_sprite.animation_finished.connect(queue_free)
	else:
		queue_free()

func _deliver_impact(target_enemy: Node2D, damage: int, source_hero: Object, spell_type: String) -> void:
	if target_enemy.has_method("take_damage"):
		target_enemy.take_damage(damage)
		print("[VARÁZSLÓ] %s találat! Nyers erő: %d" % [spell_type, damage])

	if source_hero and source_hero.has_method("gain_combat_xp"):
		source_hero.gain_combat_xp(1)
