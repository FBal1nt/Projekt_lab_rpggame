extends Node2D
class_name HolySpellProjectile

@onready var animated_sprite: AnimatedSprite2D = $AnimatedSprite2D

## 1. TÁMADÁS: az ellenség helyén csap le az "attack_1" animációval
func spawn_at(target_enemy: Node2D, damage: int, source_hero: Object = null) -> void:
	if not is_instance_valid(target_enemy):
		queue_free()
		return

	global_position = target_enemy.global_position
	z_index = 12

	# Sebzés átadása
	if target_enemy.has_method("take_damage"):
		target_enemy.take_damage(damage)
		print("[SZENT CSAPÁS] Fényrobbanás! Nyers erő: %d" % damage)

	if source_hero and source_hero.has_method("gain_combat_xp"):
		source_hero.gain_combat_xp(1)

	# FONTOS: "default" helyett az "attack_1" játszódik le!
	if animated_sprite and animated_sprite.sprite_frames:
		if animated_sprite.sprite_frames.has_animation("attack_1"):
			animated_sprite.play("attack_1")
		elif animated_sprite.sprite_frames.has_animation("default"):
			animated_sprite.play("default")
		
		await animated_sprite.animation_finished
		queue_free()
	else:
		queue_free()

## 2. GYÓGYÍTÁS: a hős saját helyén jelenik meg a "heal" animációval ('H' gomb)
func cast_heal_at(caster_position: Vector2) -> void:
	global_position = caster_position
	z_index = 12

	if animated_sprite and animated_sprite.sprite_frames:
		if animated_sprite.sprite_frames.has_animation("heal"):
			animated_sprite.play("heal")
		
		await animated_sprite.animation_finished
		queue_free()
	else:
		queue_free()
