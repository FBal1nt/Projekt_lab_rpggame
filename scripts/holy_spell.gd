extends Node2D
class_name HolySpellProjectile

@onready var animated_sprite: AnimatedSprite2D = $AnimatedSprite2D

func spawn_at(target_enemy: Node2D, damage: int, source_hero: Object = null) -> void:
	if not is_instance_valid(target_enemy):
		queue_free()
		return

	global_position = target_enemy.global_position
	z_index = 12

	# Csak metódushíváson keresztüli sebzésátadás
	if target_enemy.has_method("take_damage"):
		target_enemy.take_damage(damage)
		print("[SZENT CSAPÁS] Fényrobbanás! Nyers erő: %d" % damage)

	if source_hero and source_hero.has_method("gain_combat_xp"):
		source_hero.gain_combat_xp(1)

	if animated_sprite:
		animated_sprite.play("default")
		animated_sprite.animation_finished.connect(queue_free)
	else:
		queue_free()
