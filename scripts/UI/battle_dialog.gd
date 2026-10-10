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

## Harc indítása – az enemy_initiated jelzi, ki támadott először!
func open_battle(hero: HeroController, enemy: Node2D, enemy_initiated: bool = false) -> void:
	if combat_active: return

	# 1. BIZTONSÁGI ZÁR: Közelharc esetén szigorúan csak balról vagy jobbról állhatnak egymás mellett!
	var enemy_range: int = 1
	if enemy.has_method("get_attack_range"):
		enemy_range = enemy.get_attack_range()
	elif enemy.get("attack_range") != null:
		enemy_range = enemy.get("attack_range")

	if enemy_range <= 1:
		var diff = hero.grid_pos - enemy.grid_pos
		# Ha a hős az utolsó pillanatban fel/le lépett (diff.y != 0) vagy nem közvetlen szomszédos:
		if diff.y != 0 or absi(diff.x) != 1:
			print("[BattleDialog] Érvénytelen közelharci pozíció! Harc megszakítva, a hős sikeresen elugrott.")
			return

	# 2. MOZGÁS AZONNALI LEVÁGÁSA: Ha mégis elkapott, megöljük a futó Tween-t, hogy ne csússzon tovább:
	if hero.has_method("cancel_movement_immediately"):
		hero.cancel_movement_immediately()
	else:
		hero.is_moving = false
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

	# DÖNTÉS AZ ELSŐ TÁMADÓRÓL:
	if enemy_initiated:
		# A szörny támadott ránk a mezőn -> KÖTELEZŐEN Ő TÁMAD ELŐSZÖR!
		is_hero_turn = false
		first_attacker_was_hero = false
		_append_log("[b]=== RAJTAÜTÉS! ===[/b]")
		_append_log("%s megrohanta a hőst és támadást indított!" % enemy_name)
		_append_log("[color=red]-> %s támad először![/color]\n" % enemy_name.to_upper())
	else:
		# A hős kezdeményezett a kattintással -> Kezdeményezés vizsgálata
		is_hero_turn = (hero_init >= enemy_init)
		first_attacker_was_hero = is_hero_turn
		_append_log("[b]=== PÁRBAJ KEZDŐDIK ===[/b]")
		_append_log("Kezdeményezés: %s (%.1f) vs %s (%.1f)" % [hero_ref.hero_name, hero_init, enemy_name, enemy_init])
		_append_log("[color=yellow]-> %s támad először![/color]\n" % ("A HŐS" if is_hero_turn else enemy_name.to_upper()))

	_update_ui_cards()

	await get_tree().create_timer(0.35).timeout
	_run_world_combat_loop()

## Harc indítása a térképen már lezajlott távolsági lövés után
func open_battle_after_ranged_shot(hero: HeroController, enemy: Node2D, next_attacker: String = "ENEMY_NEXT") -> void:
	if combat_active: return

	hero_ref = hero
	enemy_ref = enemy
	combat_active = true
	current_round = 1

	hero_ref.in_battle = true
	if hero_ref.has_method("cancel_movement_immediately"):
		hero_ref.cancel_movement_immediately()
	else:
		hero_ref.is_moving = false

	visible = true
	if log_text: log_text.clear()

	var enemy_name = _get_enemy_name()

	if next_attacker == "HERO_NEXT":
		# A szörny lőtt a térképen -> a harci ablakban a HŐS jön válasszal!
		is_hero_turn = true
		first_attacker_was_hero = false
		_append_log("[b]=== PÁRBAJ TÁVOLSÁGI CSAPÁS UTÁN ===[/b]")
		_append_log("%s rád lőtt a távolból!" % enemy_name)
		_append_log("[color=yellow]-> Te következel a válaszcsapással![/color]\n")
	else:
		# A hős lőtt a térképen -> a harci ablakban a SZÖRNY visszatámadása jön!
		is_hero_turn = false
		first_attacker_was_hero = true
		_append_log("[b]=== PÁRBAJ TÁVOLSÁGI CSAPÁS UTÁN ===[/b]")
		_append_log("Eltaláltad %s-t a távolból!" % enemy_name)
		_append_log("[color=red]-> %s visszatámad![/color]\n" % enemy_name.to_upper())

	_update_ui_cards()

	await get_tree().create_timer(0.35).timeout
	_run_world_combat_loop()

func _run_world_combat_loop() -> void:
	while combat_active and is_instance_valid(hero_ref) and is_instance_valid(enemy_ref):
		await _execute_tile_turn()

		if not combat_active:
			break

		await get_tree().create_timer(0.3).timeout

func _execute_tile_turn() -> void:
	var enemy_name = _get_enemy_name()

	if is_hero_turn:
		# --- A HŐS KÖRE ---
		_append_log("[b]-- %d. KÖR: A Hős támad --[/b]" % current_round)
		var raw_dmg = await hero_ref.perform_combat_turn(enemy_ref)
		_append_log("A Hős tüzel/lecsap! Dobás: %d sebzés." % raw_dmg)
		_update_ui_cards()

		if not enemy_ref.is_monster_alive():
			await _finish_combat("HERO")
			return
	else:
		# --- AZ ELLENSÉG KÖRE (SZÖRNY TÁMADÁSA) ---
		_append_log("[b]-- %d. KÖR: %s támad --[/b]" % [current_round, enemy_name])
		var dealt = await enemy_ref.perform_combat_turn(hero_ref)
		_append_log("%s rácsap a hősre! Kiosztott sebzés: %d." % [enemy_name, dealt])
		_update_ui_cards()

		if not hero_ref.is_alive():
			await _finish_combat("MONSTER")
			return

	# Váltás a másik félre
	is_hero_turn = not is_hero_turn

	# Ha lefutott mindkét fél támadása (visszatért a kezdőhöz), szintet lép a kör:
	if is_hero_turn == first_attacker_was_hero:
		current_round += 1

func _finish_combat(victor: String) -> void:
	combat_active = false
	var enemy_name = _get_enemy_name()

	if victor == "HERO":
		_append_log("\n[color=gold][b]★★★ GYŐZELEM! %s elesett! ★★★[/b][/color]" % enemy_name)
		var title = _get_enemy_title()
		if title != "":
			hero_ref.award_title(title)
			_append_log("[color=cyan]Új titulus: %s[/color]" % hero_ref.hero_name)
	else:
		_append_log("\n[color=red][b]☠ ☠ ☠ A HŐS ELESETT! ☠ ☠ ☠[/b][/color]")

	battle_finished.emit(victor)

	await get_tree().create_timer(result_display_time).timeout
	visible = false

	# 1. KISZÁLLUNK A HARCBÓL: A hős azonnal szabadon mozoghat és elmenekülhet!
	if is_instance_valid(hero_ref):
		hero_ref.in_battle = false

	# 2. A szörny a térképen önállóan játssza le a halált és az esetleges feltámadást:
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
