extends Node2D
class_name ProjectileArrow

@export var flight_speed: float = 380.0

func launch(start_pos: Vector2, target_enemy: Node2D, damage: int, source_hero: Object = null) -> void:
	global_position = start_pos
	z_index = 12

	if not is_instance_valid(target_enemy):
		queue_free()
		return

	var target_pos = target_enemy.global_position
	var flight_vector = target_pos - start_pos
	var distance = flight_vector.length()

	rotation = flight_vector.angle()
	var duration = clampf(distance / flight_speed, 0.08, 0.35)

	var tween = create_tween()
	tween.tween_property(self, "global_position", target_pos, duration).set_trans(Tween.TRANS_LINEAR)
	tween.finished.connect(func():
		_on_hit(target_enemy, damage, source_hero)
	)

func _on_hit(target_enemy: Node2D, damage: int, source_hero: Object) -> void:
	if is_instance_valid(target_enemy):
		# Szigorúan metódushívás, tilos a közvetlen 'current_hp' módosítás!
		if target_enemy.has_method("take_damage"):
			target_enemy.take_damage(damage)

		# Találat esetén a hős megkapja az 1 XP-t
		if source_hero and source_hero.has_method("gain_combat_xp"):
			source_hero.gain_combat_xp(1)

	queue_free()
