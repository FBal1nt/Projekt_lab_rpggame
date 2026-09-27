@tool
extends Resource
class_name CharacterClass

@export var class_name_id: String = ""
@export var max_hp: int = 120
@export var base_damage: int = 18
@export var base_defense: int = 1
## Lebegőpontos kezdeményezés: ha magasabb, nagyobb gyorsaságot jelent
@export var initiative: float = 10.0
@export var move_duration: float = 0.15

@export_group("Harci Típus és Lőtáv")
@export var is_ranged: bool = false
@export var attack_range: int = 1

## Csak akkor szükséges, ha a karakter lövedéket használ (pl. Arrow, HolySpell, WizardSpell)
@export var projectile_scene: PackedScene:
	set(val):
		projectile_scene = val
		notify_property_list_changed()

@export_group("Lövedék Időzítés")
@export var release_frame: int = 4
@export var attack_fps: float = 10.0

@export_group("Megjelenés")
@export var sprite_frames: SpriteFrames
@export var sprite_scale: Vector2 = Vector2(1.0, 1.0)
@export var sprite_offset: Vector2 = Vector2(0, -6)

func _validate_property(property: Dictionary) -> void:
	if property.name in ["release_frame", "attack_fps"]:
		if projectile_scene == null:
			property.usage = PROPERTY_USAGE_NO_EDITOR
