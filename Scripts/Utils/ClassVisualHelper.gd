extends RefCounted
class_name ClassVisualHelper

## Központi segédosztály a karakterosztályok megjelenéséhez (SpriteFrames, portrék, harci adatok).
## Fontos: minden res:// útvonal szó szerinti konstansként szerepel, hogy a projekt-validátor ellenőrizhesse.

const HERO_CLASS_PATHS := {
	&"archer": "res://Data/Heroes/archer_class.tres",
	&"knight": "res://Data/Heroes/knight_class.tres",
	&"knight_templar": "res://Data/Heroes/knight_templar_class.tres",
	&"priest": "res://Data/Heroes/priest_class.tres",
	&"soldier": "res://Data/Heroes/soldier_class.tres",
	&"swordsman": "res://Data/Heroes/swordsman_class.tres",
	&"wizard": "res://Data/Heroes/wizard_class.tres"
}

const HERO_FRAMES_PATHS := {
	&"archer": "res://Data/Heroes/archer_frames.tres",
	&"knight": "res://Data/Heroes/knight_frames.tres",
	&"knight_templar": "res://Data/Heroes/knight_templar_frames.tres",
	&"priest": "res://Data/Heroes/priest_frames.tres",
	&"soldier": "res://Data/Heroes/soldier_frames.tres",
	&"swordsman": "res://Data/Heroes/swordsman_frames.tres",
	&"wizard": "res://Data/Heroes/wizard_frames.tres"
}

const CLASS_GAMEPLAY_META := {
	&"archer": {
		"combat_style": "Távolsági íjász",
		"range_text": "5 mező (Íj)",
		"mobility_text": "Gyors (0.13 mp / lépés)",
		"special_note": "Biztonságos távolságból nyilaz, kiemelkedő pontossággal és kitéréssel."
	},
	&"knight": {
		"combat_style": "Közelharci védő",
		"range_text": "1 mező (Közelharc)",
		"mobility_text": "Normál (0.15 mp / lépés)",
		"special_note": "Pajzshárításával aktívan tompítja a beérkező támadásokat."
	},
	&"knight_templar": {
		"combat_style": "Nehézpáncélos tank",
		"range_text": "1 mező (Közelharc)",
		"mobility_text": "Megfontolt (0.18 mp / lépés)",
		"special_note": "A legmagasabb életerő (160 HP) és védelem, pajzshárítással kombinálva."
	},
	&"priest": {
		"combat_style": "Szent gyógyító",
		"range_text": "4 mező (Szent fény)",
		"mobility_text": "Normál (0.15 mp / lépés)",
		"special_note": "H billentyűvel képes önmagát gyógyítani, és 4 mezőről sújt le szent mágiával."
	},
	&"soldier": {
		"combat_style": "Sokoldalú harcos",
		"range_text": "1–4 mező (Kard & Íj)",
		"mobility_text": "Fürge (0.14 mp / lépés)",
		"special_note": "Közelharcban karddal csap le, távolról pedig íjjal és korlátozott számú nyílvesszővel támad."
	},
	&"swordsman": {
		"combat_style": "Gyors közelharci sebző",
		"range_text": "1 mező (Közelharc)",
		"mobility_text": "Villámgyors (0.12 mp / lépés)",
		"special_note": "Legmagasabb kezdeményezés (15.0), pusztító sebzés és magas kritikus esély."
	},
	&"wizard": {
		"combat_style": "Elemi mágus",
		"range_text": "5 mező (Tűz / Jég)",
		"mobility_text": "Normál (0.15 mp / lépés)",
		"special_note": "F billentyűvel válthatsz a perzselő Tűz és a bénító Fagyasztó Jég elem között."
	}
}

const PREBAKED_IDLE_FRAME_SIZE := Vector2i(100, 100)

const PREBAKED_IDLE_USED_RECTS := {
	&"archer": Rect2i(40, 40, 22, 17),
	&"knight": Rect2i(41, 39, 26, 18),
	&"knight_templar": Rect2i(43, 40, 27, 17),
	&"priest": Rect2i(44, 38, 16, 20),
	&"soldier": Rect2i(41, 39, 17, 21),
	&"swordsman": Rect2i(42, 39, 24, 21),
	&"wizard": Rect2i(43, 39, 17, 19)
}

const PREBAKED_IDLE_VISUAL_CENTERS := {
	&"archer": Vector2(1.0, -1.5),
	&"knight": Vector2(4.0, -2.0),
	&"knight_templar": Vector2(6.5, -1.5),
	&"priest": Vector2(2.0, -2.0),
	&"soldier": Vector2(-0.5, -0.5),
	&"swordsman": Vector2(4.0, -0.5),
	&"wizard": Vector2(1.5, -1.5)
}

static var _hero_class_cache: Dictionary = {}
static var _sprite_frames_cache: Dictionary = {}
static var _portrait_cache: Dictionary = {}
static var _portrait_by_key_cache: Dictionary = {}
static var _visual_center_offset_cache: Dictionary = {}


static func _normalize_class_id(class_id: StringName) -> StringName:
	return StringName(String(class_id).strip_edges().to_lower())


static func get_hero_class(class_id: StringName) -> CharacterClass:
	var normalized := _normalize_class_id(class_id)
	if _hero_class_cache.has(normalized):
		return _hero_class_cache[normalized] as CharacterClass
	var path: String = str(HERO_CLASS_PATHS.get(normalized, ""))
	if path.is_empty():
		return null
	var loaded := load(path) as CharacterClass
	if loaded != null:
		_hero_class_cache[normalized] = loaded
	return loaded


static func get_sprite_frames(class_id: StringName) -> SpriteFrames:
	var normalized := _normalize_class_id(class_id)
	if _sprite_frames_cache.has(normalized):
		var cached := _sprite_frames_cache[normalized] as SpriteFrames
		if cached != null:
			return cached
	var path: String = str(HERO_FRAMES_PATHS.get(normalized, ""))
	if not path.is_empty():
		var loaded := load(path) as SpriteFrames
		if loaded != null:
			_sprite_frames_cache[normalized] = loaded
			return loaded
	var hero_cls := get_hero_class(normalized)
	if hero_cls != null and hero_cls.sprite_frames != null:
		_sprite_frames_cache[normalized] = hero_cls.sprite_frames
		return hero_cls.sprite_frames
	return null


static func get_portrait_texture(
	class_id: StringName,
	class_data: CharacterClassData = null,
	anim_name: StringName = &"idle",
	frame_index: int = 0
) -> Texture2D:
	if class_data != null and class_data.portrait != null:
		return class_data.portrait

	var normalized := _normalize_class_id(class_id)
	var cache_key := "%s|%s|%d" % [String(normalized), String(anim_name), frame_index]
	if _portrait_by_key_cache.has(cache_key):
		return _portrait_by_key_cache[cache_key] as Texture2D

	var frames := get_sprite_frames(normalized)
	if frames == null:
		return null

	var chosen_anim := anim_name
	if not frames.has_animation(chosen_anim):
		if frames.has_animation(&"idle"):
			chosen_anim = &"idle"
		elif frames.has_animation(&"default"):
			chosen_anim = &"default"
		else:
			var anims := frames.get_animation_names()
			if anims.is_empty():
				return null
			chosen_anim = StringName(anims[0])

	var frame_count := frames.get_frame_count(chosen_anim)
	if frame_count <= 0:
		return null
	var clamped_index := clampi(frame_index, 0, frame_count - 1)
	var tex := frames.get_frame_texture(chosen_anim, clamped_index)
	var cropped: Texture2D = null
	if (
		chosen_anim == &"idle"
		and clamped_index == 0
		and tex != null
		and PREBAKED_IDLE_USED_RECTS.has(normalized)
		and tex.get_width() == PREBAKED_IDLE_FRAME_SIZE.x
		and tex.get_height() == PREBAKED_IDLE_FRAME_SIZE.y
	):
		cropped = _make_cropped_atlas(tex, PREBAKED_IDLE_USED_RECTS[normalized], 2)
		_portrait_cache["%d:2" % tex.get_instance_id()] = cropped
	else:
		cropped = crop_transparent_texture(tex)
	if cropped != null:
		_portrait_by_key_cache[cache_key] = cropped
	return cropped


static func _make_cropped_atlas(tex: Texture2D, used_rect: Rect2i, padding: int = 2) -> Texture2D:
	var min_x := maxi(0, used_rect.position.x - padding)
	var min_y := maxi(0, used_rect.position.y - padding)
	var max_x := mini(tex.get_width(), used_rect.end.x + padding)
	var max_y := mini(tex.get_height(), used_rect.end.y + padding)
	var padded := Rect2i(min_x, min_y, max_x - min_x, max_y - min_y)

	var atlas := AtlasTexture.new()
	if tex is AtlasTexture:
		var src_atlas := tex as AtlasTexture
		atlas.atlas = src_atlas.atlas
		atlas.region = Rect2(
			src_atlas.region.position + Vector2(padded.position),
			Vector2(padded.size)
		)
	else:
		atlas.atlas = tex
		atlas.region = Rect2(Vector2(padded.position), Vector2(padded.size))
	return atlas


static func crop_transparent_texture(tex: Texture2D, padding: int = 2) -> Texture2D:
	if tex == null:
		return null
	var cache_key := "%d:%d" % [tex.get_instance_id(), padding]
	if _portrait_cache.has(cache_key):
		return _portrait_cache[cache_key] as Texture2D

	var img := tex.get_image()
	if img != null and not img.is_empty() and not img.is_compressed():
		var used_rect := img.get_used_rect()
		if used_rect.has_area():
			var atlas := _make_cropped_atlas(tex, used_rect, padding)
			_portrait_cache[cache_key] = atlas
			return atlas

	_portrait_cache[cache_key] = tex
	return tex


static func get_visual_center_offset(class_id: StringName, anim_name: StringName = &"idle") -> Vector2:
	var normalized := _normalize_class_id(class_id)
	var cache_key := "%s|%s" % [String(normalized), String(anim_name)]
	if _visual_center_offset_cache.has(cache_key):
		return _visual_center_offset_cache[cache_key]
	if anim_name == &"idle" and PREBAKED_IDLE_VISUAL_CENTERS.has(normalized):
		var prebaked: Vector2 = PREBAKED_IDLE_VISUAL_CENTERS[normalized]
		_visual_center_offset_cache[cache_key] = prebaked
		return prebaked

	var frames := get_sprite_frames(normalized)
	if frames == null or not frames.has_animation(anim_name) or frames.get_frame_count(anim_name) <= 0:
		return Vector2.ZERO
	var tex := frames.get_frame_texture(anim_name, 0)
	if tex == null:
		return Vector2.ZERO
	var img := tex.get_image()
	if img == null or img.is_empty() or img.is_compressed():
		return Vector2.ZERO
	var used_rect := img.get_used_rect()
	if not used_rect.has_area():
		return Vector2.ZERO
	var tex_center := Vector2(tex.get_width(), tex.get_height()) * 0.5
	var used_center := Vector2(used_rect.position) + Vector2(used_rect.size) * 0.5
	var offset := used_center - tex_center
	_visual_center_offset_cache[cache_key] = offset
	return offset


static func get_class_gameplay_meta(class_id: StringName) -> Dictionary:
	var normalized := StringName(String(class_id).strip_edges().to_lower())
	if CLASS_GAMEPLAY_META.has(normalized):
		return CLASS_GAMEPLAY_META[normalized]
	var hero_cls := get_hero_class(normalized)
	if hero_cls != null:
		var range_str := "%d mező (Távolsági)" % hero_cls.attack_range if hero_cls.is_ranged else "1 mező (Közelharc)"
		return {
			"combat_style": "Távolsági harcos" if hero_cls.is_ranged else "Közelharci hős",
			"range_text": range_str,
			"mobility_text": "%.2f mp / lépés" % hero_cls.move_duration,
			"special_note": ""
		}
	return {
		"combat_style": "Kalandor",
		"range_text": "1 mező (Közelharc)",
		"mobility_text": "Normál",
		"special_note": ""
	}
