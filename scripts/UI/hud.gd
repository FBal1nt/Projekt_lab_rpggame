extends CanvasLayer
class_name PlayerHUD

@onready var hero_title_label: Label = find_child("HeroTitleLabel", true, false) as Label
@onready var class_level_label: Label = find_child("ClassLevelLabel", true, false) as Label

@onready var hp_text: Label = find_child("HpText", true, false) as Label
@onready var hp_bar: ProgressBar = find_child("HpBar", true, false) as ProgressBar

@onready var xp_text: Label = find_child("XpText", true, false) as Label
@onready var xp_bar: ProgressBar = find_child("XpBar", true, false) as ProgressBar

@onready var atk_label: Label = find_child("AtkLabel", true, false) as Label
@onready var def_label: Label = find_child("DefLabel", true, false) as Label
@onready var init_label: Label = find_child("InitLabel", true, false) as Label
@onready var vision_label: Label = find_child("VisionLabel", true, false) as Label

@onready var tile_info_label: Label = find_child("TileInfoLabel", true, false) as Label

func _ready() -> void:
	add_to_group("hud")

## A hős állapotának kirajzolása a felületre
func refresh_stats(hero: HeroController) -> void:
	if not is_instance_valid(hero):
		return

	# 2. Kaszt és Aktuális szint
	if class_level_label:
		var c_name = hero.active_class.class_name_id if hero.active_class else "Kalandor"
		class_level_label.text = "%s  •  Szint: %d" % [c_name, hero.level]

	# 3. Életerő (Szöveg + Csík)
	if hp_bar:
		hp_bar.max_value = hero.get_max_hp()
		hp_bar.value = hero.get_current_hp()
	if hp_text:
		hp_text.text = "HP: %d / %d" % [hero.get_current_hp(), hero.get_max_hp()]

	# 4. Tapasztalati pont (XP: 0-10)
	if xp_bar:
		xp_bar.max_value = 10
		xp_bar.value = hero.xp
	if xp_text:
		xp_text.text = "XP: %d / 10" % hero.xp

	# 5. Harci attribútumok
	if atk_label:
		atk_label.text = "Támadás: %d" % hero.attack_power
	if def_label:
		def_label.text = "Védelem: %d" % hero.get_defense()
	if init_label:
		init_label.text = "Kezdeményezés: %.1f" % hero.get_initiative()
	if vision_label:
		vision_label.text = "Látótáv: %d (négyzetes)" % hero.vision_limit

	# 6. Aktuális mező információ (A feladat követelménye: mi van az aktuális mezőn)
	if tile_info_label:
		var tile_desc = _get_current_tile_description(hero)
		tile_info_label.text = "Mező: (%d, %d) - %s" % [hero.grid_pos.x, hero.grid_pos.y, tile_desc]

## Megállapítja, mi található a hős aktuális mezőjén
func _get_current_tile_description(hero: HeroController) -> String:
	if hero.floor_layer == null:
		return "Ismeretlen terület"

	var cell = hero.grid_pos
	if hero.decoratives_layer and hero.decoratives_layer.get_cell_source_id(cell) != -1:
		return "Díszített kőpadló"
	elif hero.floor_layer.get_cell_source_id(cell) != -1:
		return "Szoba / Folyosó padlója"
	return "Üres tér"
