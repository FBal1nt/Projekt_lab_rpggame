extends Resource
class_name CharacterClass

@export var class_name_id: String = "Knight"
@export var max_hp: int = 120
@export var base_damage: int = 18
@export var initiative: int = 10 # Magasabb kezdeményezés = előbb üt a harcban
@export var move_duration: float = 0.15

@export var sprite_frames: SpriteFrames
@export var sprite_scale: Vector2 = Vector2(1.0, 1.0)
@export var sprite_offset: Vector2 = Vector2(0, -6) # Hogy a lába a 16x16-os csempe talpára essen
