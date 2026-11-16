extends CanvasLayer
class_name BattleDialog

signal battle_finished(winner: String)

@export_group("Időzítés")
@export var result_display_time: float = 1.2

# Fejléc és kártya stílusok
var title_label: Label
var turn_banner_label: Label
var hero_panel: PanelContainer
var enemy_panel: PanelContainer

# Hős kártya elemei
var hero_portrait_texture: TextureRect
var hero_name_label: Label
var hero_class_label: Label
var hero_hp_text: Label
var hero_hp_bar: ProgressBar
var hero_xp_text: Label
var hero_xp_bar: ProgressBar
var hero_atk_label: Label
var hero_def_label: Label
var hero_init_label: Label
var hero_range_label: Label
var hero_status_label: Label

# Ellenség kártya elemei
var enemy_portrait_texture: TextureRect
var enemy_name_label: Label
var enemy_tier_label: Label
var enemy_hp_text: Label
var enemy_hp_bar: ProgressBar
var enemy_boss_title_label: Label
var enemy_atk_label: Label
var enemy_def_label: Label
var enemy_armor_label: Label
var enemy_init_label: Label
var enemy_traits_label: Label

# Harci napló
var log_scroll: ScrollContainer
var log_text: RichTextLabel

# Aktív harc referencia
var hero_ref: HeroController
var enemy_ref: Node2D

var current_round: int = 1
var is_hero_turn: bool = true
var first_attacker_was_hero: bool = true
var combat_active: bool = false

var _showing_result: bool = false
var _portrait_cache: Dictionary = {}

const HERO_BORDER_ACTIVE := Color(0.50, 0.80, 1.0, 1.0)
const HERO_BORDER_IDLE := Color(0.24, 0.38, 0.56, 1.0)
const ENEMY_BORDER_ACTIVE := Color(0.95, 0.34, 0.34, 1.0)
const ENEMY_BORDER_IDLE := Color(0.50, 0.20, 0.22, 1.0)


func _ready() -> void:
	add_to_group("battle_ui")
	visible = false
	layer = 100

	title_label = find_child("TitleLabel", true, false) as Label
	turn_banner_label = find_child("TurnBannerLabel", true, false) as Label
	hero_panel = find_child("HeroPanel", true, false) as PanelContainer
	enemy_panel = find_child("EnemyPanel", true, false) as PanelContainer

	hero_portrait_texture = find_child("HeroPortraitTexture", true, false) as TextureRect
	hero_name_label = find_child("HeroNameLabel", true, false) as Label
	hero_class_label = find_child("HeroClassLabel", true, false) as Label
	hero_hp_text = find_child("HeroHpText", true, false) as Label
	hero_hp_bar = find_child("HeroHpBar", true, false) as ProgressBar
	hero_xp_text = find_child("HeroXpText", true, false) as Label
	hero_xp_bar = find_child("HeroXpBar", true, false) as ProgressBar
	hero_atk_label = find_child("HeroAtkLabel", true, false) as Label
	hero_def_label = find_child("HeroDefLabel", true, false) as Label
	hero_init_label = find_child("HeroInitLabel", true, false) as Label
	hero_range_label = find_child("HeroRangeLabel", true, false) as Label
	hero_status_label = find_child("HeroStatusLabel", true, false) as Label

	enemy_portrait_texture = find_child("EnemyPortraitTexture", true, false) as TextureRect
	enemy_name_label = find_child("EnemyNameLabel", true, false) as Label
	enemy_tier_label = find_child("EnemyTierLabel", true, false) as Label
	enemy_hp_text = find_child("EnemyHpText", true, false) as Label
	enemy_hp_bar = find_child("EnemyHpBar", true, false) as ProgressBar
	enemy_boss_title_label = find_child("EnemyBossTitleLabel", true, false) as Label
	enemy_atk_label = find_child("EnemyAtkLabel", true, false) as Label
	enemy_def_label = find_child("EnemyDefLabel", true, false) as Label
	enemy_armor_label = find_child("EnemyArmorLabel", true, false) as Label
	enemy_init_label = find_child("EnemyInitLabel", true, false) as Label
	enemy_traits_label = find_child("EnemyTraitsLabel", true, false) as Label

	log_scroll = find_child("LogScroll", true, false) as ScrollContainer
	log_text = find_child("LogText", true, false) as RichTextLabel
	if log_scroll:
		var vbar := log_scroll.get_v_scroll_bar()
		if vbar and not vbar.changed.is_connected(_on_log_scrollbar_changed):
			vbar.changed.connect(_on_log_scrollbar_changed)


func _process(_delta: float) -> void:
	if not visible:
		return
	_refresh_portraits()


func open_battle(hero: HeroController, enemy: Node2D, enemy_initiated: bool = false) -> void:
	if combat_active or get_tree().paused:
		return
	if not is_instance_valid(hero) or not is_instance_valid(enemy):
		return

	var hero_is_ranged: bool = false
	if hero.combat and hero.combat.has_method("is_hero_ranged_attack"):
		hero_is_ranged = hero.combat.is_hero_ranged_attack(enemy.grid_pos)
	elif hero.get("is_ranged") != null:
		hero_is_ranged = bool(hero.get("is_ranged"))

	var enemy_range: int = 1
	if enemy.has_method("get_attack_range"):
		enemy_range = enemy.get_attack_range()
	elif enemy.get("attack_range") != null:
		enemy_range = enemy.get("attack_range")
	var enemy_is_ranged: bool = enemy_range > 1

	if not hero_is_ranged or not enemy_is_ranged:
		var diff = hero.grid_pos - enemy.grid_pos
		if diff.y != 0 or absi(diff.x) != 1:
			print("[BattleDialog] Érvénytelen közelharci pozíció! Harc megszakítva.")
			return

	if hero.has_method("cancel_movement_immediately"):
		hero.cancel_movement_immediately()
	else:
		hero.is_moving = false
		if hero.get("path_queue") != null:
			hero.path_queue.clear()

	hero_ref = hero
	enemy_ref = enemy
	combat_active = true
	_showing_result = false
	current_round = 1
	_portrait_cache.clear()

	hero_ref.in_battle = true
	_set_hud_hidden(true)

	visible = true
	if log_text:
		log_text.clear()

	var hero_init = hero_ref.get_initiative()
	var enemy_init = _get_enemy_initiative()
	var enemy_name = _get_enemy_name()

	is_hero_turn = (hero_init >= enemy_init)
	first_attacker_was_hero = is_hero_turn

	if enemy_initiated:
		_append_log("[color=#f08a6b][b]⚠️ LESBŐL TÁMADÁS[/b][/color]  [color=#b8c4d4]— %s rátámadt a hősre[/color]" % enemy_name)
	else:
		_append_log("[color=#f2c96d][b]⚔️ PÁRBAJ KEZDŐDIK[/b][/color]  [color=#b8c4d4]— %s megtámadta: %s[/color]" % [hero_ref.hero_name, enemy_name])

	_append_log("[color=#8fa3bf]Kezdeményezés:[/color] [color=#8fd4ff]%s (%.1f)[/color] [color=#6c7a8e]vs[/color] [color=#f2a6a6]%s (%.1f)[/color]" % [hero_ref.hero_name, hero_init, enemy_name, enemy_init])
	if is_hero_turn:
		_append_log("[color=#ffd86b]▸ %s gyorsabb, ő támad először[/color]\n" % hero_ref.hero_name)
	else:
		_append_log("[color=#ff8a80]▸ %s gyorsabb, ő támad először[/color]\n" % enemy_name)

	_update_ui_cards()
	_refresh_portraits()

	await get_tree().create_timer(0.35).timeout
	if combat_active and is_instance_valid(hero_ref) and is_instance_valid(enemy_ref):
		_run_world_combat_loop()


func interrupt_combat_due_to_knockback() -> void:
	combat_active = false
	_showing_result = false
	visible = false
	_portrait_cache.clear()
	if is_instance_valid(hero_ref):
		hero_ref.in_battle = false
		if hero_ref.is_alive():
			_set_hud_hidden(false)
	else:
		_set_hud_hidden(false)


func interrupt_combat_due_to_boss_phase() -> void:
	interrupt_combat_due_to_knockback()


func _run_world_combat_loop() -> void:
	while combat_active and is_instance_valid(hero_ref) and is_instance_valid(enemy_ref):
		_update_turn_banner()
		await _execute_tile_turn()

		if not combat_active:
			break

		_update_turn_banner()
		await get_tree().create_timer(0.3).timeout


func _execute_tile_turn() -> void:
	var enemy_name = _get_enemy_name()

	if is_hero_turn:
		if hero_ref.is_stunned:
			_append_log("[color=#c596ff][b][%d. kör][/b] 💫 %s kábultan fekszik, kimarad a körből.[/color]" % [current_round, hero_ref.hero_name])
			hero_ref.is_stunned = false
			is_hero_turn = false
			current_round += 1
			_update_ui_cards()
			return

		_append_log("[color=#6ec3ff][b][%d. kör][/b][/color] [color=#e2ecf7]%s támadásra készül…[/color]" % [current_round, hero_ref.hero_name])
		var raw_dmg = await hero_ref.perform_combat_turn(enemy_ref)
		_append_log("   [color=#9ed0ff]↳ Találat: [b]%d[/b] nyers sebzés[/color]" % raw_dmg)
		if hero_ref.get("combat") != null and hero_ref.combat.get("last_attack_knockback_tiles") != null and int(hero_ref.combat.last_attack_knockback_tiles) > 0:
			_append_log("   [color=#f2c96d]↳ Hátralökés: %d mező[/color]" % int(hero_ref.combat.last_attack_knockback_tiles))
		_update_ui_cards()

		if not is_instance_valid(enemy_ref) or not enemy_ref.is_monster_alive():
			await _finish_combat("HERO")
			return
		if enemy_ref.has_method("handle_post_damage_phase_reaction"):
			var triggered_phase: bool = await enemy_ref.handle_post_damage_phase_reaction(hero_ref)
			if triggered_phase or not combat_active:
				return
	else:
		_append_log("[color=#f08080][b][%d. kör][/b][/color] [color=#f5dada]%s ellentámadásba lendül…[/color]" % [current_round, enemy_name])
		var dealt = await enemy_ref.perform_combat_turn(hero_ref)
		if dealt > 0:
			_append_log("   [color=#ffa399]↳ Találat: [b]%d[/b] sebzés a hősbe[/color]" % dealt)
		else:
			_append_log("   [color=#9fb0c4]↳ A támadás elhalt vagy kivédve[/color]")
		_update_ui_cards()

		if not is_instance_valid(hero_ref) or not hero_ref.is_alive():
			await _finish_combat("MONSTER")
			return

	is_hero_turn = not is_hero_turn

	if is_hero_turn == first_attacker_was_hero:
		current_round += 1


func _finish_combat(victor: String) -> void:
	combat_active = false
	_showing_result = true
	var enemy_name = _get_enemy_name()

	if victor == "HERO":
		_append_log("\n[color=#ffd659][b]🏆 GYŐZELEM — %s elesett![/b][/color]" % enemy_name)
		var title = _get_enemy_title()
		if title != "" and is_instance_valid(hero_ref):
			if hero_ref.has_method("award_title"):
				hero_ref.award_title(title)
			elif hero_ref.get("progression") != null and hero_ref.progression.has_method("award_title"):
				hero_ref.progression.award_title(title)
			_append_log("[color=#7be3ff]🎖️ Új titulus: %s[/color]" % hero_ref.hero_name)
		_set_result_banner("🏆  GYŐZELEM!", "%s elesett a harcban!" % enemy_name, Color(0.98, 0.86, 0.35, 1))
	else:
		_append_log("\n[color=#ff6e6e][b]☠️ VERESÉG — A hős elesett![/b][/color]")
		_set_result_banner("☠️  VERESÉG", "A hős elesett %s ellen..." % enemy_name, Color(0.98, 0.34, 0.36, 1))

	_update_ui_cards()
	battle_finished.emit(victor)

	var death_ui := get_tree().get_first_node_in_group("death_screen")
	var death_already_visible: bool = (death_ui != null and death_ui.visible)
	if not death_already_visible:
		await get_tree().create_timer(result_display_time).timeout

	visible = false
	_showing_result = false
	_portrait_cache.clear()

	if is_instance_valid(hero_ref):
		hero_ref.in_battle = false

	if victor == "HERO":
		_set_hud_hidden(false)
		if is_instance_valid(enemy_ref) and enemy_ref.has_method("play_overworld_death"):
			enemy_ref.play_overworld_death()
	else:
		# Halál esetén a HUD maradjon rejtve, és nyissuk meg a DeathScreen-t
		_set_hud_hidden(true)
		if is_instance_valid(hero_ref):
			if not death_already_visible and hero_ref.has_method("play_overworld_death"):
				await hero_ref.play_overworld_death()
			if is_instance_valid(hero_ref) and hero_ref.has_method("show_death_screen"):
				hero_ref.show_death_screen()


func _set_hud_hidden(hidden: bool) -> void:
	var hud := get_tree().get_first_node_in_group("hud")
	if hud == null:
		return
	if hud.has_method("set_battle_mode"):
		hud.set_battle_mode(hidden)
	elif "visible" in hud:
		hud.visible = not hidden


func _update_ui_cards() -> void:
	if not _showing_result:
		_update_turn_banner()

	if is_instance_valid(hero_ref):
		var hero_hp: int = maxi(0, hero_ref.get_current_hp())
		var hero_max: int = maxi(1, hero_ref.get_max_hp())
		var hero_range: int = 1
		if hero_ref.combat and hero_ref.combat.has_method("get_effective_attack_range"):
			hero_range = hero_ref.combat.get_effective_attack_range()

		if hero_name_label:
			hero_name_label.text = hero_ref.hero_name
		if hero_class_label:
			hero_class_label.text = "%s  •  Lv. %d" % [_get_hero_class_label(), hero_ref.level]
		if hero_hp_bar:
			hero_hp_bar.max_value = hero_max
			hero_hp_bar.value = hero_hp
		if hero_hp_text:
			hero_hp_text.text = "%d / %d" % [hero_hp, hero_max]
		if hero_xp_bar:
			hero_xp_bar.max_value = 10
			hero_xp_bar.value = clampi(hero_ref.xp, 0, 10)
		if hero_xp_text:
			hero_xp_text.text = "%d / 10 XP" % hero_ref.xp
		if hero_atk_label:
			hero_atk_label.text = "⚔️ Támadás\n%d" % hero_ref.attack_power
		if hero_def_label:
			hero_def_label.text = "🛡️ Védekezés\n%d" % hero_ref.get_defense()
		if hero_init_label:
			hero_init_label.text = "⚡ Kezdeményezés\n%.1f" % hero_ref.get_initiative()
		if hero_range_label:
			hero_range_label.text = "🎯 Hatótáv\n%d mező" % hero_range
		if hero_status_label:
			hero_status_label.text = "Állapot: " + _get_hero_status_summary()

	if is_instance_valid(enemy_ref):
		var e_name: String = _get_enemy_name()
		var e_title: String = _get_enemy_title()
		var e_hp: int = maxi(0, _get_enemy_hp())
		var e_max: int = maxi(1, _get_enemy_max_hp())

		if enemy_name_label:
			enemy_name_label.text = e_name
		if enemy_tier_label:
			enemy_tier_label.text = "%s  •  Lv. %d" % [_get_enemy_tier_text(), _get_enemy_level()]
		if enemy_hp_bar:
			enemy_hp_bar.max_value = e_max
			enemy_hp_bar.value = e_hp
		if enemy_hp_text:
			enemy_hp_text.text = "%d / %d" % [e_hp, e_max]
		if enemy_boss_title_label:
			enemy_boss_title_label.visible = e_title != ""
			if e_title != "":
				enemy_boss_title_label.text = "👑 Titulus: %s" % e_title
		if enemy_atk_label:
			enemy_atk_label.text = "⚔️ Támadás\n%d" % _get_enemy_damage()
		if enemy_def_label:
			enemy_def_label.text = "🛡️ Védekezés\n%d" % _get_enemy_defense()
		if enemy_armor_label:
			enemy_armor_label.text = "🪨 Páncél\n%d" % _get_enemy_flat_armor()
		if enemy_init_label:
			enemy_init_label.text = "⚡ Kezdeményezés\n%.1f" % _get_enemy_initiative()
		if enemy_traits_label:
			enemy_traits_label.text = "Képességek: " + _get_enemy_traits_summary()


func _update_turn_banner() -> void:
	if _showing_result:
		return
	if title_label:
		title_label.text = "⚔️  %d. KÖR  •  PÁRBAJ" % current_round
		title_label.add_theme_color_override("font_color", Color(0.98, 0.88, 0.45, 1.0))

	if is_hero_turn:
		if turn_banner_label:
			turn_banner_label.text = "◄  %s KÖVETKEZIK" % (hero_ref.hero_name.to_upper() if is_instance_valid(hero_ref) else "A HŐS")
			turn_banner_label.add_theme_color_override("font_color", Color(0.58, 0.90, 1.0, 1.0))
		_set_panel_border_color(hero_panel, HERO_BORDER_ACTIVE)
		_set_panel_border_color(enemy_panel, ENEMY_BORDER_IDLE)
	else:
		if turn_banner_label:
			turn_banner_label.text = "%s KÖVETKEZIK  ►" % _get_enemy_name().to_upper()
			turn_banner_label.add_theme_color_override("font_color", Color(1.0, 0.50, 0.46, 1.0))
		_set_panel_border_color(hero_panel, HERO_BORDER_IDLE)
		_set_panel_border_color(enemy_panel, ENEMY_BORDER_ACTIVE)


func _set_result_banner(headline: String, subline: String, color: Color) -> void:
	if title_label:
		title_label.text = headline
		title_label.add_theme_color_override("font_color", color)
	if turn_banner_label:
		turn_banner_label.text = subline
		turn_banner_label.add_theme_color_override("font_color", Color(0.92, 0.94, 0.98, 1.0))


func _set_panel_border_color(panel: PanelContainer, color: Color) -> void:
	if panel == null:
		return
	var sb := panel.get_theme_stylebox("panel") as StyleBoxFlat
	if sb != null:
		sb.border_color = color


func _refresh_portraits() -> void:
	if hero_portrait_texture and is_instance_valid(hero_ref):
		var hero_tex := _get_current_sprite_texture(hero_ref.sprite)
		if hero_tex != null:
			hero_portrait_texture.texture = _get_cropped_portrait_texture(hero_tex)

	if enemy_portrait_texture and is_instance_valid(enemy_ref):
		var enemy_sprite := enemy_ref.get("sprite") as AnimatedSprite2D
		var enemy_tex := _get_current_sprite_texture(enemy_sprite)
		if enemy_tex != null:
			enemy_portrait_texture.texture = _get_cropped_portrait_texture(enemy_tex)


func _get_current_sprite_texture(sprite_node: AnimatedSprite2D) -> Texture2D:
	if not is_instance_valid(sprite_node):
		return null
	if sprite_node.sprite_frames == null:
		return null
	var anim_name: StringName = sprite_node.animation
	if not sprite_node.sprite_frames.has_animation(anim_name):
		return null
	var frame_count: int = sprite_node.sprite_frames.get_frame_count(anim_name)
	if frame_count <= 0:
		return null
	var safe_frame: int = clampi(sprite_node.frame, 0, frame_count - 1)
	return sprite_node.sprite_frames.get_frame_texture(anim_name, safe_frame)


func _get_cropped_portrait_texture(tex: Texture2D) -> Texture2D:
	if tex == null:
		return null
	if _portrait_cache.has(tex):
		return _portrait_cache[tex]

	var img := tex.get_image()
	if img != null and not img.is_empty() and not img.is_compressed():
		var used_rect := img.get_used_rect()
		if used_rect.has_area():
			var pad := 2
			var min_x := maxi(0, used_rect.position.x - pad)
			var min_y := maxi(0, used_rect.position.y - pad)
			var max_x := mini(tex.get_width(), used_rect.end.x + pad)
			var max_y := mini(tex.get_height(), used_rect.end.y + pad)
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
			_portrait_cache[tex] = atlas
			return atlas

	_portrait_cache[tex] = tex
	return tex


func _get_hero_class_label() -> String:
	if not is_instance_valid(hero_ref) or hero_ref.active_class == null:
		return "Kalandor"
	return hero_ref.active_class.class_name_id


func _get_hero_status_summary() -> String:
	if not is_instance_valid(hero_ref):
		return "-"
	if not hero_ref.is_alive():
		return "☠️ Elesett"
	var states: Array[String] = []
	if hero_ref.is_stunned:
		states.append("💫 Kábult")
	if hero_ref.has_node("BleedStatusEffect"):
		states.append("🩸 Vérzik")
	if states.is_empty():
		return "✅ Harcra kész"
	return ", ".join(states)


func _get_enemy_name() -> String:
	if not is_instance_valid(enemy_ref): return "Ellenség"
	if enemy_ref.has_method("get_monster_name"): return enemy_ref.get_monster_name()
	if enemy_ref.get("monster_name") != null: return str(enemy_ref.get("monster_name"))
	return enemy_ref.name


func _get_enemy_title() -> String:
	if not is_instance_valid(enemy_ref): return ""
	if enemy_ref.has_method("get_title"): return enemy_ref.get_title()
	if enemy_ref.get("title") != null: return str(enemy_ref.get("title"))
	return ""


func _get_enemy_level() -> int:
	if not is_instance_valid(enemy_ref): return 1
	var data = enemy_ref.get("enemy_data") as EnemyData
	if data != null:
		return data.enemy_level
	if enemy_ref.get("enemy_level") != null:
		return int(enemy_ref.get("enemy_level"))
	return 1


func _get_enemy_tier_text() -> String:
	if not is_instance_valid(enemy_ref): return "Alap"
	var data = enemy_ref.get("enemy_data") as EnemyData
	var tier_val: int = int(data.tier) if data != null else 1
	match tier_val:
		EnemyData.EnemyTier.BASIC:
			return "Alap"
		EnemyData.EnemyTier.ARMORED:
			return "Páncélozott"
		EnemyData.EnemyTier.ELITE:
			return "Elit"
		EnemyData.EnemyTier.BOSS:
			return "Főellenség"
	return "Alap"


func _get_enemy_damage() -> int:
	if not is_instance_valid(enemy_ref): return 0
	var data = enemy_ref.get("enemy_data") as EnemyData
	if data != null:
		return data.base_damage
	if enemy_ref.get("base_damage") != null:
		return int(enemy_ref.get("base_damage"))
	return 0


func _get_enemy_flat_armor() -> int:
	if not is_instance_valid(enemy_ref): return 0
	var data = enemy_ref.get("enemy_data") as EnemyData
	if data != null:
		return data.flat_armor
	return 0


func _get_enemy_initiative() -> float:
	if not is_instance_valid(enemy_ref): return 8.0
	if enemy_ref.has_method("get_initiative"): return enemy_ref.get_initiative()
	if enemy_ref.get("initiative") != null: return float(enemy_ref.get("initiative"))
	return 8.0


func _get_enemy_defense() -> int:
	if not is_instance_valid(enemy_ref): return 0
	if enemy_ref.has_method("get_defense"): return enemy_ref.get_defense()
	if enemy_ref.get("defense") != null: return int(enemy_ref.get("defense"))
	return 0


func _get_enemy_hp() -> int:
	if not is_instance_valid(enemy_ref): return 0
	if enemy_ref.has_method("get_current_hp"): return enemy_ref.get_current_hp()
	if enemy_ref.get("current_hp") != null: return int(enemy_ref.get("current_hp"))
	return 0


func _get_enemy_max_hp() -> int:
	if not is_instance_valid(enemy_ref): return 10
	if enemy_ref.has_method("get_max_hp"): return enemy_ref.get_max_hp()
	if enemy_ref.get("max_hp") != null: return int(enemy_ref.get("max_hp"))
	return 10


func _get_enemy_traits_summary() -> String:
	if not is_instance_valid(enemy_ref):
		return "-"
	var traits: Array[String] = []
	var e_range: int = enemy_ref.get_attack_range() if enemy_ref.has_method("get_attack_range") else 1
	traits.append("Távolsági (%d mező)" % e_range if e_range > 1 else "Közelharci")

	var data := enemy_ref.get("enemy_data") as EnemyData
	if data != null:
		if data.flat_armor > 0:
			traits.append("%d páncél" % data.flat_armor)
		if data.can_block and data.block_chance > 0.0:
			traits.append("Blokk %d%%" % roundi(data.block_chance * 100.0))
		if data.dodge_chance > 0.0:
			traits.append("Kitérés %d%%" % roundi(data.dodge_chance * 100.0))
		if data.life_steal_ratio > 0.0:
			traits.append("Életszívás %d%%" % roundi(data.life_steal_ratio * 100.0))
		if data.can_self_revive:
			traits.append("Ön-feltámadás")
		if data.can_split:
			traits.append("Osztódás")

		match data.special_profile:
			EnemyData.SpecialProfile.NECROMANCER:
				traits.append("Idézés / Gyógyítás")
			EnemyData.SpecialProfile.ELITE_ORC:
				traits.append("Vérszomj")
			EnemyData.SpecialProfile.GREATSWORD_SKELETON:
				traits.append("Bárdzúzás")
			EnemyData.SpecialProfile.WEREBEAR, EnemyData.SpecialProfile.WEREWOLF:
				traits.append("Vérzés")

	return ", ".join(traits)


func _append_log(text_line: String) -> void:
	if log_text:
		log_text.append_text(text_line + "\n")
	if log_scroll:
		log_scroll.call_deferred("set", "scroll_vertical", 999999)


func _on_log_scrollbar_changed() -> void:
	if log_scroll == null:
		return
	var vbar := log_scroll.get_v_scroll_bar()
	if vbar:
		log_scroll.scroll_vertical = int(vbar.max_value)
