extends CanvasLayer
class_name BattleDialog

signal battle_finished(winner: String)

@export_group("Időzítés")
@export var result_display_time: float = 1.2

var title_label: Label
var hero_name_label: Label
var hero_hp_bar: ProgressBar
var hero_stats_label: Label

var enemy_name_label: Label
var enemy_hp_bar: ProgressBar
var enemy_stats_label: Label

var log_scroll: ScrollContainer
var log_text: RichTextLabel

var hero_ref: HeroController
var enemy_ref: Node2D

var current_round: int = 1
var is_hero_turn: bool = true
var first_attacker_was_hero: bool = true
var combat_active: bool = false

func _ready() -> void:
	add_to_group("battle_ui")
	visible = false
	layer = 100

	title_label = find_child("TitleLabel", true, false) as Label
	hero_name_label = find_child("HeroNameLabel", true, false) as Label
	hero_hp_bar = find_child("HeroHpBar", true, false) as ProgressBar
	hero_stats_label = find_child("HeroStatsLabel", true, false) as Label

	enemy_name_label = find_child("EnemyNameLabel", true, false) as Label
	enemy_hp_bar = find_child("EnemyHpBar", true, false) as ProgressBar
	enemy_stats_label = find_child("EnemyStatsLabel", true, false) as Label

	log_scroll = find_child("LogScroll", true, false) as ScrollContainer
	log_text = find_child("LogText", true, false) as RichTextLabel

	var button_row = find_child("ButtonRow", true, false)
	if button_row: button_row.visible = false

func open_battle(hero: HeroController, enemy: Node2D, enemy_initiated: bool = false) -> void:
	if combat_active: return

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
	current_round = 1

	hero_ref.in_battle = true

	visible = true
	if log_text: log_text.clear()

	var hero_init = hero_ref.get_initiative()
	var enemy_init = _get_enemy_initiative()
	var enemy_name = _get_enemy_name()

	is_hero_turn = (hero_init >= enemy_init)
	first_attacker_was_hero = is_hero_turn

	if enemy_initiated:
		_append_log("[b]=== ELLENSÉG MEGKÖZELÍTETTE A HŐST! ===[/b]")
		_append_log("%s harcba lépett a hőssel!" % enemy_name)
	else:
		_append_log("[b]=== PÁRBAJ KEZDŐDIK ===[/b]")
		_append_log("%s megtámadta %s ellenfelét!" % [hero_ref.hero_name, enemy_name])

	_append_log("Kezdeményezés: %s (%.1f) vs %s (%.1f)" % [hero_ref.hero_name, hero_init, enemy_name, enemy_init])
	if is_hero_turn:
		_append_log("[color=yellow]-> A HŐS gyorsabb, ő támad először![/color]\n")
	else:
		_append_log("[color=red]-> %s gyorsabb, ő támad először![/color]\n" % enemy_name.to_upper())

	_update_ui_cards()

	await get_tree().create_timer(0.35).timeout
	_run_world_combat_loop()

func interrupt_combat_due_to_knockback() -> void:
	combat_active = false
	visible = false
	if is_instance_valid(hero_ref):
		hero_ref.in_battle = false

func _run_world_combat_loop() -> void:
	while combat_active and is_instance_valid(hero_ref) and is_instance_valid(enemy_ref):
		await _execute_tile_turn()

		if not combat_active:
			break

		await get_tree().create_timer(0.3).timeout

func _execute_tile_turn() -> void:
	var enemy_name = _get_enemy_name()

	if is_hero_turn:
		if hero_ref.is_stunned:
			_append_log("[b]-- %d. KÖR: A Hős köre --[/b]" % current_round)
			_append_log("[color=purple]💫 A Hős kábultan fekszik a földön, kimarad a köre![/color]\n")
			hero_ref.is_stunned = false
			is_hero_turn = false
			current_round += 1
			_update_ui_cards()
			return

		_append_log("[b]-- %d. KÖR: A Hős támad --[/b]" % current_round)
		var raw_dmg = await hero_ref.perform_combat_turn(enemy_ref)
		_append_log("A Hős tüzel/lecsap! Dobás: %d sebzés." % raw_dmg)
		_update_ui_cards()

		if not enemy_ref.is_monster_alive():
			await _finish_combat("HERO")
			return
	else:
		_append_log("[b]-- %d. KÖR: %s támad --[/b]" % [current_round, enemy_name])
		var dealt = await enemy_ref.perform_combat_turn(hero_ref)
		_append_log("%s rácsap a hősre! Kiosztott sebzés: %d." % [enemy_name, dealt])
		_update_ui_cards()

		if not hero_ref.is_alive():
			await _finish_combat("MONSTER")
			return

	is_hero_turn = not is_hero_turn

	if is_hero_turn == first_attacker_was_hero:
		current_round += 1

func _finish_combat(victor: String) -> void:
	combat_active = false
	var enemy_name = _get_enemy_name()

	if victor == "HERO":
		_append_log("\n[color=gold][b]★★★ GYŐZELEM! %s elesett! ★★★[/b][/color]" % enemy_name)
		var title = _get_enemy_title()
		if title != "":
			if hero_ref.has_method("award_title"):
				hero_ref.award_title(title)
			elif hero_ref.get("progression") != null and hero_ref.progression.has_method("award_title"):
				hero_ref.progression.award_title(title)
			_append_log("[color=cyan]Új titulus: %s[/color]" % hero_ref.hero_name)
	else:
		_append_log("\n[color=red][b]☠ ☠ ☠ A HŐS ELESETT! ☠ ☠ ☠[/b][/color]")

	battle_finished.emit(victor)

	await get_tree().create_timer(result_display_time).timeout
	visible = false

	if is_instance_valid(hero_ref):
		hero_ref.in_battle = false

	if victor == "HERO":
		if is_instance_valid(enemy_ref) and enemy_ref.has_method("play_overworld_death"):
			enemy_ref.play_overworld_death()
	else:
		if is_instance_valid(hero_ref) and hero_ref.has_method("play_overworld_death"):
			await hero_ref.play_overworld_death()

func _update_ui_cards() -> void:
	if is_instance_valid(hero_ref):
		if hero_name_label: hero_name_label.text = hero_ref.hero_name
		if hero_hp_bar:
			hero_hp_bar.max_value = hero_ref.get_max_hp()
			hero_hp_bar.value = hero_ref.get_current_hp()
		if hero_stats_label:
			hero_stats_label.text = "HP: %d/%d | DEF: %d | XP: %d/10 (Lv %d)" % [
				hero_ref.get_current_hp(), hero_ref.get_max_hp(), hero_ref.get_defense(), hero_ref.xp, hero_ref.level
			]

	if is_instance_valid(enemy_ref):
		var e_name = _get_enemy_name()
		var e_title = _get_enemy_title()
		if enemy_name_label:
			enemy_name_label.text = e_name + (" (" + e_title + ")" if e_title != "" else "")
		if enemy_hp_bar:
			enemy_hp_bar.max_value = _get_enemy_max_hp()
			enemy_hp_bar.value = _get_enemy_hp()
		if enemy_stats_label:
			enemy_stats_label.text = "HP: %d/%d | DEF: %d | Init: %.1f" % [
				_get_enemy_hp(), _get_enemy_max_hp(), _get_enemy_defense(), _get_enemy_initiative()
			]

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

func _append_log(text_line: String) -> void:
	if log_text: log_text.append_text(text_line + "\n")
	if log_scroll: log_scroll.set_deferred("scroll_vertical", 999999)
