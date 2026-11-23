extends CanvasLayer
class_name BattleDialog

signal battle_finished(winner: String)
signal _result_acknowledged

@export_group("Időzítés")
@export var result_display_time: float = 1.2

# Fejléc és kártya stílusok
var title_icon: TextureRect
var title_label: Label
var turn_left_icon: TextureRect
var turn_right_icon: TextureRect
var turn_banner_label: Label
var hero_panel: PanelContainer
var enemy_panel: PanelContainer

# Hős kártya elemei
var hero_portrait_texture: TextureRect
var hero_name_label: Label
var hero_class_label: Label
var hero_title_row: Control
var hero_title_label: Label
var hero_hp_text: Label
var hero_hp_bar: ProgressBar
var hero_xp_text: Label
var hero_xp_bar: ProgressBar
var hero_atk_label: Label
var hero_def_label: Label
var hero_init_label: Label
var hero_range_label: Label
var hero_status_label: RichTextLabel

# Ellenség kártya elemei
var enemy_portrait_texture: TextureRect
var enemy_name_label: Label
var enemy_tier_label: Label
var enemy_hp_text: Label
var enemy_hp_bar: ProgressBar
var enemy_boss_title_row: Control
var enemy_boss_title_label: Label
var enemy_atk_label: Label
var enemy_def_label: Label
var enemy_armor_label: Label
var enemy_init_label: Label
var enemy_traits_label: Label

# Harci napló
var log_scroll: ScrollContainer
var log_text: RichTextLabel
var _potion_button: Button
var _continue_button: Button

# Aktív harc referencia
var hero_ref: HeroController
var enemy_ref: Node2D

var current_round: int = 1
var is_hero_turn: bool = true
var first_attacker_was_hero: bool = true
var combat_active: bool = false

var _showing_result: bool = false
var _awaiting_dismiss: bool = false
var _result_shown_frame: int = 0
var _portrait_cache: Dictionary = {}

const HERO_BORDER_ACTIVE := Color(0.50, 0.80, 1.0, 1.0)
const HERO_BORDER_IDLE := Color(0.24, 0.38, 0.56, 1.0)
const ENEMY_BORDER_ACTIVE := Color(0.95, 0.34, 0.34, 1.0)
const ENEMY_BORDER_IDLE := Color(0.50, 0.20, 0.22, 1.0)


func _ready() -> void:
	add_to_group("battle_ui")
	visible = false
	layer = 100

	title_icon = find_child("TitleIcon", true, false) as TextureRect
	title_label = find_child("TitleLabel", true, false) as Label
	turn_left_icon = find_child("TurnLeftIcon", true, false) as TextureRect
	turn_right_icon = find_child("TurnRightIcon", true, false) as TextureRect
	turn_banner_label = find_child("TurnBannerLabel", true, false) as Label
	hero_panel = find_child("HeroPanel", true, false) as PanelContainer
	enemy_panel = find_child("EnemyPanel", true, false) as PanelContainer

	hero_portrait_texture = find_child("HeroPortraitTexture", true, false) as TextureRect
	hero_name_label = find_child("HeroNameLabel", true, false) as Label
	hero_class_label = find_child("HeroClassLabel", true, false) as Label
	hero_title_row = find_child("HeroTitleRow", true, false) as Control
	hero_title_label = find_child("HeroTitleLabel", true, false) as Label
	hero_hp_text = find_child("HeroHpText", true, false) as Label
	hero_hp_bar = find_child("HeroHpBar", true, false) as ProgressBar
	hero_xp_text = find_child("HeroXpText", true, false) as Label
	hero_xp_bar = find_child("HeroXpBar", true, false) as ProgressBar
	hero_atk_label = find_child("HeroAtkLabel", true, false) as Label
	hero_def_label = find_child("HeroDefLabel", true, false) as Label
	hero_init_label = find_child("HeroInitLabel", true, false) as Label
	hero_range_label = find_child("HeroRangeLabel", true, false) as Label
	hero_status_label = find_child("HeroStatusLabel", true, false) as RichTextLabel

	enemy_portrait_texture = find_child("EnemyPortraitTexture", true, false) as TextureRect
	enemy_name_label = find_child("EnemyNameLabel", true, false) as Label
	enemy_tier_label = find_child("EnemyTierLabel", true, false) as Label
	enemy_hp_text = find_child("EnemyHpText", true, false) as Label
	enemy_hp_bar = find_child("EnemyHpBar", true, false) as ProgressBar
	enemy_boss_title_row = find_child("EnemyBossTitleRow", true, false) as Control
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
	_setup_log_header_buttons()


func _exit_tree() -> void:
	if _awaiting_dismiss:
		_awaiting_dismiss = false
		_result_acknowledged.emit()


func _input(event: InputEvent) -> void:
	if not visible or not is_inside_tree() or get_tree().paused:
		return
	if not (event is InputEventKey):
		return
	var key_event := event as InputEventKey
	if not key_event.pressed or key_event.echo:
		return

	if _awaiting_dismiss:
		if Engine.get_process_frames() == _result_shown_frame:
			return
		if _matches_keybind(key_event, "interact", KEY_E):
			var vp := get_viewport()
			if vp != null:
				vp.set_input_as_handled()
			_dismiss_result_dialog()
	elif combat_active and not _showing_result:
		if _matches_keybind(key_event, "quick_potion", KEY_Q):
			var vp := get_viewport()
			if vp != null:
				vp.set_input_as_handled()
			_try_use_battle_potion()


func _process(_delta: float) -> void:
	if not visible:
		return
	_refresh_portraits()


func open_battle(hero: HeroController, enemy: Node2D, enemy_initiated: bool = false) -> void:
	if combat_active or _showing_result or _awaiting_dismiss or visible or get_tree().paused:
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

	if enemy.has_method("cancel_movement_immediately"):
		enemy.cancel_movement_immediately()
	if enemy.get("is_attacking") != null:
		enemy.is_attacking = false

	hero_ref = hero
	enemy_ref = enemy
	combat_active = true
	_showing_result = false
	_awaiting_dismiss = false
	if _potion_button:
		_potion_button.visible = false
	if _continue_button:
		_continue_button.visible = false
	current_round = 1
	_portrait_cache.clear()

	hero_ref.in_battle = true
	_set_hud_hidden(true)

	visible = true
	var enemy_data: EnemyData = enemy_ref.get("enemy_data") as EnemyData if is_instance_valid(enemy_ref) else null
	if enemy_data != null and (int(enemy_data.special_profile) == 4 or int(enemy_data.tier) == EnemyData.EnemyTier.BOSS):
		AudioManager.set_boss_encounter_active(true)
		var map_gen := get_tree().get_first_node_in_group("map_generator")
		if map_gen != null and map_gen.has_method("on_boss_fight_started"):
			map_gen.on_boss_fight_started()
	else:
		AudioManager.refresh_music_context()
	if log_text:
		log_text.clear()

	var hero_init = hero_ref.get_initiative()
	var enemy_init = _get_enemy_initiative()
	var enemy_name = _get_enemy_name()

	is_hero_turn = (hero_init >= enemy_init)
	first_attacker_was_hero = is_hero_turn

	if enemy_initiated:
		_append_log("[color=#f08a6b]%s [b]LESBŐL TÁMADÁS[/b][/color]  [color=#b8c4d4]— %s rátámadt a hősre[/color]" % [UiIcons.bb(UiIcons.WARNING), enemy_name])
	else:
		_append_log("[color=#f2c96d]%s [b]PÁRBAJ KEZDŐDIK[/b][/color]  [color=#b8c4d4]— %s megtámadta: %s[/color]" % [UiIcons.bb(UiIcons.PLAY_SWORD), hero_ref.hero_name, enemy_name])

	_append_log("[color=#8fa3bf]Kezdeményezés:[/color] [color=#8fd4ff]%s (%.1f)[/color] [color=#6c7a8e]vs[/color] [color=#f2a6a6]%s (%.1f)[/color]" % [hero_ref.hero_name, hero_init, enemy_name, enemy_init])
	if is_hero_turn:
		_append_log("[color=#ffd86b]%s %s gyorsabb, ő támad először[/color]\n" % [UiIcons.bb(UiIcons.TURN_RIGHT, 12), hero_ref.hero_name])
	else:
		_append_log("[color=#ff8a80]%s %s gyorsabb, ő támad először[/color]\n" % [UiIcons.bb(UiIcons.TURN_RIGHT, 12), enemy_name])

	_update_ui_cards()
	_refresh_portraits()
	_apply_turn_z_order(is_hero_turn)

	await get_tree().create_timer(_scaled_combat_wait(0.35)).timeout
	if combat_active and is_instance_valid(hero_ref) and is_instance_valid(enemy_ref):
		_run_world_combat_loop()


func _scaled_combat_wait(base_seconds: float) -> float:
	var speed := 1.0
	var sm := get_node_or_null("/root/SettingsManager")
	if sm != null:
		speed = clampf(float(sm.get("combat_speed")), 1.0, 2.0)
	return maxf(0.05, base_seconds / speed)


func _apply_turn_z_order(hero_attacking: bool) -> void:
	if is_instance_valid(hero_ref):
		hero_ref.z_index = 11 if hero_attacking else 8
	if is_instance_valid(enemy_ref):
		enemy_ref.z_index = 8 if hero_attacking else 11


func _restore_combat_z_order(hero: HeroController = null, enemy: Node2D = null) -> void:
	var h: HeroController = hero if hero != null else hero_ref
	var e: Node2D = enemy if enemy != null else enemy_ref
	if is_instance_valid(h):
		h.z_index = 10
	if is_instance_valid(e):
		e.z_index = 8


func interrupt_combat_due_to_knockback() -> void:
	combat_active = false
	_showing_result = false
	if _potion_button:
		_potion_button.visible = false
	if _continue_button:
		_continue_button.visible = false
	if _awaiting_dismiss:
		_awaiting_dismiss = false
		_result_acknowledged.emit()
	visible = false
	_portrait_cache.clear()
	_restore_combat_z_order(hero_ref, enemy_ref)
	enemy_ref = null
	if is_instance_valid(hero_ref):
		hero_ref.in_battle = false
		if hero_ref.is_alive():
			_set_hud_hidden(false)
	else:
		_set_hud_hidden(false)
	AudioManager.refresh_music_context()


func interrupt_combat_due_to_boss_phase() -> void:
	interrupt_combat_due_to_knockback()


func _run_world_combat_loop() -> void:
	while combat_active and is_instance_valid(hero_ref) and is_instance_valid(enemy_ref):
		_update_turn_banner()
		await _execute_tile_turn()

		if not combat_active:
			break

		_update_turn_banner()
		await get_tree().create_timer(_scaled_combat_wait(0.3)).timeout


func _execute_tile_turn() -> void:
	var enemy_name = _get_enemy_name()
	_apply_turn_z_order(is_hero_turn)

	if is_hero_turn:
		if hero_ref.is_stunned:
			_append_log("[color=#c596ff][b][%d. kör][/b] %s %s kábultan fekszik, kimarad a körből.[/color]" % [current_round, UiIcons.bb(UiIcons.STUN), hero_ref.hero_name])
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
		if not combat_active:
			if not is_instance_valid(hero_ref) or not hero_ref.is_alive():
				await _finish_combat("MONSTER")
			return
		if dealt > 0:
			_append_log("   [color=#ffa399]↳ Találat: [b]%d[/b] sebzés a hősbe[/color]" % dealt)
		else:
			_append_log("   [color=#9fb0c4]↳ A támadás elhalt vagy kivédve[/color]")
		_update_ui_cards()

		if not is_instance_valid(hero_ref) or not hero_ref.is_alive():
			await _finish_combat("MONSTER")
			return

	is_hero_turn = not is_hero_turn
	_apply_turn_z_order(is_hero_turn)

	if is_hero_turn == first_attacker_was_hero:
		current_round += 1


func _finish_combat(victor: String) -> void:
	combat_active = false
	_showing_result = true
	var enemy_name = _get_enemy_name()
	var was_boss := false
	if is_instance_valid(enemy_ref):
		var e_data = enemy_ref.get("enemy_data") as EnemyData
		was_boss = e_data != null and int(e_data.tier) == EnemyData.EnemyTier.BOSS

	if victor == "HERO":
		_append_log("\n[color=#ffd659]%s [b]GYŐZELEM — %s elesett![/b][/color]" % [UiIcons.bb(UiIcons.TROPHY), enemy_name])
		var title = _get_enemy_title()
		if title != "" and is_instance_valid(hero_ref):
			if hero_ref.has_method("award_title"):
				hero_ref.award_title(title)
			elif hero_ref.get("progression") != null and hero_ref.progression.has_method("award_title"):
				hero_ref.progression.award_title(title)
			if was_boss:
				_append_log("[color=#7be3ff]%s Titulus összegyűjtve: %s[/color]" % [UiIcons.bb(UiIcons.MEDAL), title])
			else:
				_append_log("[color=#7be3ff]%s Titulus összegyűjtve: %s (a dungeon teljesítésekor feloldódik)[/color]" % [UiIcons.bb(UiIcons.MEDAL), title])
		_set_result_banner("GYŐZELEM!", "%s elesett a harcban!" % enemy_name, Color(0.98, 0.86, 0.35, 1), UiIcons.TROPHY)
	else:
		_append_log("\n[color=#ff6e6e]%s [b]VERESÉG — A hős elesett![/b][/color]" % UiIcons.bb(UiIcons.SKULL))
		_set_result_banner("VERESÉG", "A hős elesett %s ellen..." % enemy_name, Color(0.98, 0.34, 0.36, 1), UiIcons.SKULL)

	_update_ui_cards()
	battle_finished.emit(victor)

	var death_ui := get_tree().get_first_node_in_group("death_screen")
	var death_already_visible: bool = (death_ui != null and death_ui.visible)
	if not death_already_visible:
		await _await_interact_to_dismiss()

	visible = false
	_showing_result = false
	_awaiting_dismiss = false
	if _potion_button:
		_potion_button.visible = false
	if _continue_button:
		_continue_button.visible = false
	_portrait_cache.clear()

	if is_instance_valid(hero_ref):
		hero_ref.in_battle = false

	if victor == "HERO":
		_set_hud_hidden(false)
		var defeated_enemy: Node2D = enemy_ref
		_restore_combat_z_order(hero_ref, defeated_enemy)
		enemy_ref = null
		if is_instance_valid(defeated_enemy) and defeated_enemy.has_method("play_overworld_death"):
			defeated_enemy.play_overworld_death()
		if was_boss:
			AudioManager.set_boss_encounter_active(false)
		else:
			AudioManager.refresh_music_context()
		if was_boss and is_instance_valid(hero_ref) and hero_ref.has_method("on_boss_defeated"):
			hero_ref.on_boss_defeated()
	else:
		# Halál esetén a HUD maradjon rejtve, és nyissuk meg a DeathScreen-t
		_restore_combat_z_order(hero_ref, enemy_ref)
		enemy_ref = null
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

		var hero_identity: Dictionary = _get_hero_base_name_and_title()
		var clean_hero_name: String = String(hero_identity.get("name", hero_ref.hero_name))
		var active_hero_title: String = String(hero_identity.get("title", ""))

		if hero_name_label:
			hero_name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			hero_name_label.clip_text = false
			hero_name_label.text = clean_hero_name
			hero_name_label.tooltip_text = hero_ref.hero_name
			var name_font_size: int = 15
			if clean_hero_name.length() > 26:
				name_font_size = 12
			elif clean_hero_name.length() > 16:
				name_font_size = 13
			hero_name_label.add_theme_font_size_override("font_size", name_font_size)
		if hero_class_label:
			hero_class_label.text = "%s  •  Szint %d" % [_get_hero_class_label(), hero_ref.level]
		if hero_title_row:
			hero_title_row.visible = not active_hero_title.is_empty()
		if hero_title_label and not active_hero_title.is_empty():
			hero_title_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			hero_title_label.text = "Titulus: %s" % active_hero_title
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
			hero_atk_label.text = "Támadás\n%d" % hero_ref.attack_power
		if hero_def_label:
			hero_def_label.text = "Védekezés\n%d" % hero_ref.get_defense()
		if hero_init_label:
			hero_init_label.text = "Kezdeményezés\n%.1f" % hero_ref.get_initiative()
		if hero_range_label:
			hero_range_label.text = "Hatótáv\n%d mező" % hero_range
		if hero_status_label:
			hero_status_label.text = "Állapot: " + _get_hero_status_summary()

	if _potion_button:
		_refresh_battle_potion_button()
	if is_instance_valid(enemy_ref):
		var e_name: String = _get_enemy_name()
		var e_title: String = _get_enemy_title()
		var e_hp: int = maxi(0, _get_enemy_hp())
		var e_max: int = maxi(1, _get_enemy_max_hp())

		if enemy_name_label:
			enemy_name_label.text = e_name
		if enemy_tier_label:
			enemy_tier_label.text = "%s  •  Szint %d" % [_get_enemy_tier_text(), _get_enemy_level()]
		if enemy_hp_bar:
			enemy_hp_bar.max_value = e_max
			enemy_hp_bar.value = e_hp
		if enemy_hp_text:
			enemy_hp_text.text = "%d / %d" % [e_hp, e_max]
		if enemy_boss_title_row:
			enemy_boss_title_row.visible = e_title != ""
		if enemy_boss_title_label and e_title != "":
			enemy_boss_title_label.text = "Titulus: %s" % e_title
		if enemy_atk_label:
			enemy_atk_label.text = "Támadás\n%d" % _get_enemy_damage()
		if enemy_def_label:
			enemy_def_label.text = "Védekezés\n%d" % _get_enemy_defense()
		if enemy_armor_label:
			enemy_armor_label.text = "Páncél\n%d" % _get_enemy_flat_armor()
		if enemy_init_label:
			enemy_init_label.text = "Kezdeményezés\n%.1f" % _get_enemy_initiative()
		if enemy_traits_label:
			enemy_traits_label.text = "Képességek: " + _get_enemy_traits_summary()


func _set_title_icon(icon_path: String) -> void:
	if title_icon == null:
		return
	if ResourceLoader.exists(icon_path):
		title_icon.texture = load(icon_path) as Texture2D
	title_icon.visible = title_icon.texture != null


func _update_turn_banner() -> void:
	if _showing_result:
		return
	_set_title_icon(UiIcons.PLAY_SWORD)
	if title_label:
		title_label.text = "%d. KÖR  •  PÁRBAJ" % current_round
		title_label.add_theme_color_override("font_color", Color(0.98, 0.88, 0.45, 1.0))

	if is_hero_turn:
		if turn_left_icon:
			turn_left_icon.visible = true
		if turn_right_icon:
			turn_right_icon.visible = false
		if turn_banner_label:
			turn_banner_label.text = "%s KÖVETKEZIK" % (hero_ref.hero_name.to_upper() if is_instance_valid(hero_ref) else "A HŐS")
			turn_banner_label.add_theme_color_override("font_color", Color(0.58, 0.90, 1.0, 1.0))
		_set_panel_border_color(hero_panel, HERO_BORDER_ACTIVE)
		_set_panel_border_color(enemy_panel, ENEMY_BORDER_IDLE)
	else:
		if turn_left_icon:
			turn_left_icon.visible = false
		if turn_right_icon:
			turn_right_icon.visible = true
		if turn_banner_label:
			turn_banner_label.text = "%s KÖVETKEZIK" % _get_enemy_name().to_upper()
			turn_banner_label.add_theme_color_override("font_color", Color(1.0, 0.50, 0.46, 1.0))
		_set_panel_border_color(hero_panel, HERO_BORDER_IDLE)
		_set_panel_border_color(enemy_panel, ENEMY_BORDER_ACTIVE)


func _set_result_banner(headline: String, subline: String, color: Color, icon_path: String = UiIcons.TROPHY) -> void:
	_set_title_icon(icon_path)
	if turn_left_icon:
		turn_left_icon.visible = false
	if turn_right_icon:
		turn_right_icon.visible = false
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


func _get_hero_base_name_and_title() -> Dictionary:
	var fallback_name: String = hero_ref.hero_name if is_instance_valid(hero_ref) else "Kalandor"
	var gs := get_node_or_null("/root/GameState")
	if gs != null and gs.has_method("get_active_character"):
		var active_char = gs.get_active_character()
		if active_char != null:
			var base_name: String = String(active_char.character_name).strip_edges()
			if base_name.is_empty():
				base_name = fallback_name
			var active_title: String = String(gs.get_active_title(active_char)).strip_edges() if gs.has_method("get_active_title") else ""
			var full_title: String = ("%s legyőzője" % active_title) if not active_title.is_empty() else ""
			return {"name": base_name, "title": full_title}
	var comma_idx: int = fallback_name.find(", ")
	if comma_idx > 0:
		return {
			"name": fallback_name.substr(0, comma_idx).strip_edges(),
			"title": fallback_name.substr(comma_idx + 2).strip_edges()
		}
	return {"name": fallback_name, "title": ""}


func _get_hero_class_label() -> String:
	if not is_instance_valid(hero_ref) or hero_ref.active_class == null:
		return "Kalandor"
	var raw_name: String = hero_ref.active_class.class_name_id
	var gs := get_node_or_null("/root/GameState")
	if gs != null and gs.has_method("get_active_character") and gs.has_method("get_character_class"):
		var active_char = gs.get_active_character()
		if active_char != null:
			var cls_data = gs.get_character_class(active_char.class_id)
			if cls_data != null and not String(cls_data.display_name).strip_edges().is_empty():
				return String(cls_data.display_name)
	return _localize_class_name(raw_name)


func _localize_class_name(raw_name: String) -> String:
	match raw_name.strip_edges().to_lower():
		"archer":
			return "Íjász"
		"knight":
			return "Lovag"
		"knight templar", "knight_templar", "templar":
			return "Templomos lovag"
		"priest":
			return "Papnő"
		"soldier":
			return "Katona"
		"swordsman":
			return "Kardforgató"
		"wizard":
			return "Varázsló"
	return raw_name if not raw_name.strip_edges().is_empty() else "Kalandor"


func _get_hero_status_summary() -> String:
	if not is_instance_valid(hero_ref):
		return "-"
	if not hero_ref.is_alive():
		return "%s Elesett" % UiIcons.bb(UiIcons.SKULL, 13)
	var states: Array[String] = []
	if hero_ref.is_stunned:
		states.append("%s Kábult" % UiIcons.bb(UiIcons.STUN, 13))
	if hero_ref.has_node("BleedStatusEffect"):
		states.append("%s Vérzik" % UiIcons.bb(UiIcons.BLEED, 13))
	if states.is_empty():
		return "%s Harcra kész" % UiIcons.bb(UiIcons.READY_CHECK, 13)
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


func _setup_log_header_buttons() -> void:
	var header_row := find_child("LogHeaderRow", true, false) as HBoxContainer
	if header_row == null:
		return

	var spacer := Control.new()
	spacer.name = "LogHeaderSpacer"
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header_row.add_child(spacer)

	var pot_btn := Button.new()
	pot_btn.name = "BattlePotionButton"
	pot_btn.focus_mode = Control.FOCUS_NONE
	pot_btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	pot_btn.custom_minimum_size = Vector2(150, 24)
	pot_btn.expand_icon = true
	if ResourceLoader.exists("res://Assets/Items/Consumables/health_potion.png"):
		pot_btn.icon = load("res://Assets/Items/Consumables/health_potion.png") as Texture2D
	pot_btn.visible = false

	var pot_normal := StyleBoxFlat.new()
	pot_normal.bg_color = Color(0.11, 0.22, 0.16, 0.96)
	pot_normal.border_width_left = 1
	pot_normal.border_width_top = 1
	pot_normal.border_width_right = 1
	pot_normal.border_width_bottom = 1
	pot_normal.border_color = Color(0.36, 0.80, 0.52, 1.0)
	pot_normal.content_margin_left = 8
	pot_normal.content_margin_right = 10
	pot_normal.content_margin_top = 2
	pot_normal.content_margin_bottom = 2
	pot_normal.anti_aliasing = false

	var pot_hover := pot_normal.duplicate() as StyleBoxFlat
	pot_hover.bg_color = Color(0.16, 0.31, 0.22, 1.0)
	pot_hover.border_color = Color(0.55, 0.96, 0.68, 1.0)

	var pot_disabled := pot_normal.duplicate() as StyleBoxFlat
	pot_disabled.bg_color = Color(0.10, 0.12, 0.16, 0.85)
	pot_disabled.border_color = Color(0.26, 0.30, 0.38, 0.8)

	pot_btn.add_theme_stylebox_override("normal", pot_normal)
	pot_btn.add_theme_stylebox_override("hover", pot_hover)
	pot_btn.add_theme_stylebox_override("pressed", pot_hover)
	pot_btn.add_theme_stylebox_override("disabled", pot_disabled)
	pot_btn.add_theme_color_override("font_color", Color(0.76, 0.98, 0.84, 1.0))
	pot_btn.add_theme_color_override("font_hover_color", Color(0.92, 1.0, 0.95, 1.0))
	pot_btn.add_theme_color_override("font_disabled_color", Color(0.52, 0.56, 0.64, 0.85))
	pot_btn.add_theme_font_size_override("font_size", 11)
	AudioManager.mark_custom_button_sfx(pot_btn)
	pot_btn.pressed.connect(_try_use_battle_potion)
	header_row.add_child(pot_btn)
	_potion_button = pot_btn

	var btn := Button.new()
	btn.name = "ContinueButton"
	btn.focus_mode = Control.FOCUS_NONE
	btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	btn.custom_minimum_size = Vector2(124, 24)
	btn.text = "Folytatás [%s]" % _get_keybind_label("interact", "E")
	btn.visible = false

	var normal_sb := StyleBoxFlat.new()
	normal_sb.bg_color = Color(0.20, 0.15, 0.08, 0.96)
	normal_sb.border_width_left = 1
	normal_sb.border_width_top = 1
	normal_sb.border_width_right = 1
	normal_sb.border_width_bottom = 1
	normal_sb.border_color = Color(0.86, 0.68, 0.34, 1.0)
	normal_sb.content_margin_left = 10
	normal_sb.content_margin_right = 10
	normal_sb.content_margin_top = 2
	normal_sb.content_margin_bottom = 2
	normal_sb.anti_aliasing = false

	var hover_sb := normal_sb.duplicate() as StyleBoxFlat
	hover_sb.bg_color = Color(0.30, 0.22, 0.11, 1.0)
	hover_sb.border_color = Color(1.0, 0.84, 0.45, 1.0)

	btn.add_theme_stylebox_override("normal", normal_sb)
	btn.add_theme_stylebox_override("hover", hover_sb)
	btn.add_theme_stylebox_override("pressed", hover_sb)
	btn.add_theme_color_override("font_color", Color(0.98, 0.88, 0.56, 1.0))
	btn.add_theme_color_override("font_hover_color", Color(1.0, 0.95, 0.78, 1.0))
	btn.add_theme_font_size_override("font_size", 11)
	btn.pressed.connect(_dismiss_result_dialog)
	header_row.add_child(btn)
	_continue_button = btn


func _matches_keybind(key_event: InputEventKey, action_id: String, fallback_code: int) -> bool:
	var sm := get_node_or_null("/root/SettingsManager")
	if sm != null and sm.has_method("matches_keybind"):
		return bool(sm.matches_keybind(key_event, action_id))
	return key_event.keycode == fallback_code or key_event.physical_keycode == fallback_code


func _get_keybind_label(action_id: String, fallback: String) -> String:
	var sm := get_node_or_null("/root/SettingsManager")
	if sm != null and sm.has_method("get_keybind_label"):
		var label := String(sm.get_keybind_label(action_id)).strip_edges()
		if not label.is_empty() and label != "-":
			return label
	return fallback


func _refresh_battle_potion_button() -> void:
	if not is_instance_valid(_potion_button):
		return
	var show_btn: bool = visible and combat_active and not _showing_result and not _awaiting_dismiss
	_potion_button.visible = show_btn
	if not show_btn:
		return

	var potion_count: int = 0
	var gs := get_node_or_null("/root/GameState")
	if gs != null and gs.has_method("get_item_count"):
		potion_count = int(gs.get_item_count(&"health_potion", false))

	var key_label := _get_keybind_label("quick_potion", "Q")
	_potion_button.text = "Gyógyital (%d) [%s]" % [potion_count, key_label]
	var can_heal: bool = is_instance_valid(hero_ref) and hero_ref.is_alive() and hero_ref.current_hp < hero_ref.max_hp
	_potion_button.disabled = potion_count <= 0 or not can_heal
	if potion_count <= 0:
		_potion_button.tooltip_text = "Nincs gyógyital a hátizsákban."
	elif not can_heal:
		_potion_button.tooltip_text = "A hős életereje már tele van."
	else:
		_potion_button.tooltip_text = "Gyógyital használata harc közben [%s]" % key_label


func _try_use_battle_potion() -> void:
	if not combat_active or _showing_result or _awaiting_dismiss or not visible:
		return
	if not is_instance_valid(hero_ref) or not hero_ref.is_alive():
		return

	var gs := get_node_or_null("/root/GameState")
	if gs == null or not gs.has_method("get_item_count") or not gs.has_method("consume_active_character_item"):
		return

	var potion_count: int = int(gs.get_item_count(&"health_potion", false))
	if potion_count <= 0:
		AudioManager.sfx(&"ui_error", 0.96, 1.04)
		_append_log("[color=#9fb0c4]Nincs gyógyital a hátizsákban.[/color]")
		_refresh_battle_potion_button()
		return

	var before_hp: int = hero_ref.current_hp
	var max_hp: int = maxi(1, hero_ref.max_hp)
	if before_hp >= max_hp:
		AudioManager.sfx(&"ui_error", 0.96, 1.04)
		_append_log("[color=#9fb0c4]A hős életereje már tele van.[/color]")
		_refresh_battle_potion_button()
		return

	var heal_amount: int = 40
	if gs.has_method("get_item_data") and gs.has_method("get_consumable_heal_amount"):
		var potion_data = gs.get_item_data(&"health_potion")
		if potion_data != null:
			var resolved_heal: int = int(gs.get_consumable_heal_amount(potion_data))
			if resolved_heal > 0:
				heal_amount = resolved_heal

	var actual_heal: int = mini(heal_amount, max_hp - before_hp)
	if actual_heal <= 0 or not bool(gs.consume_active_character_item(&"health_potion", 1)):
		AudioManager.sfx(&"ui_error", 0.96, 1.04)
		return

	if hero_ref.progression != null and hero_ref.progression.has_method("heal"):
		hero_ref.progression.heal(actual_heal)
	else:
		hero_ref.current_hp = mini(max_hp, before_hp + actual_heal)

	if hero_ref.visuals != null and hero_ref.visuals.has_method("play_heal_effect"):
		hero_ref.visuals.play_heal_effect()

	AudioManager.sfx(&"potion_drink", 0.96, 1.06)
	var gained_hp: int = maxi(0, hero_ref.current_hp - before_hp)
	_append_log("[color=#6ee89a]%s [GYÓGYITAL] %s ivott egy gyógyitalt (+%d HP)! (%d / %d)[/color]" % [UiIcons.bb(UiIcons.HEART), hero_ref.hero_name, gained_hp, hero_ref.current_hp, max_hp])
	_update_ui_cards()

	var hud := get_tree().get_first_node_in_group("hud")
	if hud != null and hud.has_method("_refresh_potion_button"):
		hud._refresh_potion_button()


func _await_interact_to_dismiss() -> void:
	_awaiting_dismiss = true
	_result_shown_frame = Engine.get_process_frames()
	_refresh_battle_potion_button()
	var key_label := _get_keybind_label("interact", "E")
	if _continue_button:
		_continue_button.text = "Folytatás [%s]" % key_label
		_continue_button.visible = true
	_append_log("[color=#9fb0c4]Nyomd meg a(z) [b]%s[/b] gombot a folytatáshoz…[/color]" % key_label)
	await _result_acknowledged


func _dismiss_result_dialog() -> void:
	if not _awaiting_dismiss:
		return
	_awaiting_dismiss = false
	if _potion_button:
		_potion_button.visible = false
	if _continue_button:
		_continue_button.visible = false
	_refresh_battle_potion_button()
	_result_acknowledged.emit()


func _on_log_scrollbar_changed() -> void:
	if log_scroll == null:
		return
	var vbar := log_scroll.get_v_scroll_bar()
	if vbar:
		log_scroll.scroll_vertical = int(vbar.max_value)
