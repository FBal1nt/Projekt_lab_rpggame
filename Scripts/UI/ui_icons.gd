extends RefCounted
class_name UiIcons

const PLAY_SWORD := "res://Assets/UI/Icons/play_sword.png"
const DUNGEON := "res://Assets/UI/Icons/dungeon.png"
const CHARACTER := "res://Assets/UI/Icons/character.png"
const INVENTORY := "res://Assets/UI/Icons/inventory.png"
const SETTINGS := "res://Assets/UI/Icons/settings.png"
const PLAY := "res://Assets/UI/Icons/play.png"

const SHIELD := "res://Assets/UI/Icons/shield.png"
const INITIATIVE := "res://Assets/UI/Icons/initiative.png"
const VISION := "res://Assets/UI/Icons/vision.png"
const FROST := "res://Assets/UI/Icons/frost.png"
const FIRE := "res://Assets/UI/Icons/fire.png"
const HOURGLASS := "res://Assets/UI/Icons/hourglass.png"
const HEAL := "res://Assets/UI/Icons/heal.png"
const PAUSE := "res://Assets/UI/Icons/pause.png"
const MAP := "res://Assets/UI/Icons/map.png"
const SKULL := "res://Assets/UI/Icons/skull.png"
const HEART := "res://Assets/UI/Icons/heart.png"
const XP_STAR := "res://Assets/UI/Icons/xp_star.png"
const TARGET := "res://Assets/UI/Icons/target.png"
const ARMOR := "res://Assets/UI/Icons/armor.png"
const CROWN := "res://Assets/UI/Icons/crown.png"
const SCROLL := "res://Assets/UI/Icons/scroll.png"
const RESTART := "res://Assets/UI/Icons/restart.png"
const HOME := "res://Assets/UI/Icons/home.png"
const TROPHY := "res://Assets/UI/Icons/trophy.png"
const MEDAL := "res://Assets/UI/Icons/medal.png"
const WARNING := "res://Assets/UI/Icons/warning.png"
const STUN := "res://Assets/UI/Icons/stun.png"
const BLEED := "res://Assets/UI/Icons/bleed.png"
const READY_CHECK := "res://Assets/UI/Icons/ready_check.png"
const KNOCKBACK := "res://Assets/UI/Icons/knockback.png"
const CRIT_BURST := "res://Assets/UI/Icons/crit_burst.png"
const WOLF_FANG := "res://Assets/UI/Icons/wolf_fang.png"
const MIND := "res://Assets/UI/Icons/mind.png"
const LEVEL_UP := "res://Assets/UI/Icons/level_up.png"
const SPARKLE := "res://Assets/UI/Icons/sparkle.png"
const LORE_LAMP := "res://Assets/UI/Icons/lore_lamp.png"
const LOCATION := "res://Assets/UI/Icons/location.png"
const CLOSE := "res://Assets/UI/Icons/close.png"
const TURN_LEFT := "res://Assets/UI/Icons/turn_left.png"
const TURN_RIGHT := "res://Assets/UI/Icons/turn_right.png"


## Formats a BBCode inline PNG icon tag for RichTextLabel controls.
static func bb(icon_path: String, size: int = 15) -> String:
	return "[img=%dx%d]%s[/img]" % [size, size, icon_path]


## Creates a fixed-size, aspect-preserved TextureRect for UI rows and badges.
static func make_icon_rect(icon_path: String, min_size: Vector2 = Vector2(16, 16)) -> TextureRect:
	var rect := TextureRect.new()
	rect.custom_minimum_size = min_size
	rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if ResourceLoader.exists(icon_path):
		rect.texture = load(icon_path) as Texture2D
	return rect


## Attaches a scaled PNG icon to a Button.
static func apply_button_icon(button: Button, icon_path: String, max_width: int = 18) -> void:
	if button == null:
		return
	if ResourceLoader.exists(icon_path):
		button.icon = load(icon_path) as Texture2D
	button.expand_icon = true
	button.add_theme_constant_override("icon_max_width", max_width)
