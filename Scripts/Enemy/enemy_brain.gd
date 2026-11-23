extends Node
class_name EnemyBrain

var controller: EnemyController
var ai_timer: Timer
var _necro_spell_cooldown: float = 0.0

func _process(delta: float) -> void:
	if _necro_spell_cooldown <= 0.0:
		return
	if controller == null or controller.is_dead or controller.is_attacking:
		return
	if controller.combat and controller.combat.elite_combat and controller.combat.elite_combat.is_necromancer_transitioning():
		return
	var hero: HeroController = _find_hero()
	if hero != null and hero.in_battle:
		return
	_necro_spell_cooldown = maxf(0.0, _necro_spell_cooldown - delta)

func can_cast_overworld_spell() -> bool:
	return _necro_spell_cooldown <= 0.0

func mark_overworld_spell_cast(custom_cd: float = -1.0) -> void:
	if custom_cd >= 0.0:
		_necro_spell_cooldown = custom_cd
		return
	var phase: int = 0
	if controller and controller.combat and controller.combat.elite_combat:
		phase = controller.combat.elite_combat.necromancer_phase
	_necro_spell_cooldown = 2.4 if phase >= 3 else 3.0

## Komponens inicializálása a szülő EnemyController által
func setup(p_controller: EnemyController) -> void:
	controller = p_controller
	_setup_autonomous_ai()

func _setup_autonomous_ai() -> void:
	var interval = controller.enemy_data.action_interval if (controller and controller.enemy_data) else 1.5
	ai_timer = Timer.new()
	ai_timer.wait_time = interval
	ai_timer.autostart = true
	ai_timer.one_shot = false
	ai_timer.timeout.connect(_on_ai_tick)
	add_child(ai_timer)
	ai_timer.start()

# --- DÖNTÉSHOZATAL ÉS AI KÖRÖK ---

func _on_ai_tick(target_hero: HeroController = null) -> void:
	var dm := get_node_or_null("/root/DungeonManager")
	if dm != null and dm.has_method("is_loading_dungeon") and dm.is_loading_dungeon():
		return
	if controller == null or controller.is_dead or controller.is_moving or controller.is_attacking or not controller.is_monster_alive():
		return
	if controller.combat and controller.combat.elite_combat and controller.combat.elite_combat.is_necromancer_transitioning():
		return

	var hero = target_hero if is_instance_valid(target_hero) else _find_hero()
	if hero != null and hero.in_battle:
		return

	var is_necro: bool = controller.combat != null and controller.combat.elite_combat != null and controller.combat.elite_combat.is_necromancer()
	if is_necro:
		_handle_necromancer_ai(hero)
		return

	if hero != null and is_instance_valid(hero) and hero.is_alive():
		# 1. TÁMADÁS VIZSGÁLATA (ha a hős már lőtávon belül van)
		if controller.combat and controller.combat.can_attack_hero(hero.grid_pos):
			if controller.visuals:
				controller.visuals.update_facing(hero.grid_pos.x)

			if controller.attack_range > 1:
				controller.combat._perform_overworld_ranged_initiation(hero)
			else:
				controller.combat.attack_hero(hero)
			return

		# 2. ÜLDÖZÉS ÉS MEGKÖZELÍTÉS (Flanking)
		var aggro_range = controller.enemy_data.aggro_range if controller.enemy_data else 3
		var dist = _manhattan_distance(controller.grid_pos, hero.grid_pos)

		if dist <= aggro_range and controller.mover and controller.mover.astar != null:
			var roam_cells := _get_roam_cells()
			var target_cell := _find_best_flank_cell(hero.grid_pos)
			if not roam_cells.is_empty() and not roam_cells.has(target_cell):
				target_cell = _find_closest_roam_cell_to(hero.grid_pos, roam_cells)

			if target_cell != controller.grid_pos:
				var full_path = controller.mover.astar.get_id_path(controller.grid_pos, target_cell)
				if full_path.size() > 1:
					full_path.remove_at(0) # A kiindulási mezőnket levesszük
					var max_steps = controller.enemy_data.move_distance if controller.enemy_data else 1
					var sliced: Array[Vector2i] = []
					for i in range(mini(max_steps, full_path.size())):
						var step_cell: Vector2i = full_path[i]
						if not roam_cells.is_empty() and not roam_cells.has(step_cell):
							break
						sliced.append(step_cell)

					if not sliced.is_empty():
						controller.mover._start_moving_path(sliced)
						return

	# 3. KÓBORLÁS (ha nincs célpont a közelben)
	_wander_multiple_tiles()

func _handle_necromancer_ai(hero: HeroController) -> void:
	var roam_cells: Dictionary = _get_roam_cells()
	if hero == null or not is_instance_valid(hero) or not hero.is_alive():
		_wander_multiple_tiles(2, 0.15)
		return

	var gm: GridManager = controller.mover.grid_manager if controller.mover else null
	var dist: int = gm.get_grid_distance(controller.grid_pos, hero.grid_pos) if gm != null else maxi(absi(controller.grid_pos.x - hero.grid_pos.x), absi(controller.grid_pos.y - hero.grid_pos.y))
	var aggro_range: int = controller.enemy_data.aggro_range if controller.enemy_data else 9
	var sees_hero: bool = controller.combat != null and controller.combat.has_line_of_sight(controller.grid_pos, hero.grid_pos)

	if not sees_hero or dist > aggro_range:
		_wander_multiple_tiles(2, 0.15)
		return

	if controller.visuals:
		controller.visuals.update_facing(hero.grid_pos.x)

	var phase: int = controller.combat.elite_combat.necromancer_phase if (controller.combat and controller.combat.elite_combat) else 0
	var is_final_1v1: bool = phase >= 3
	var diff: Vector2i = hero.grid_pos - controller.grid_pos
	var melee_adjacent: bool = (diff.y == 0 and absi(diff.x) == 1)

	if is_final_1v1:
		if melee_adjacent and (not can_cast_overworld_spell() or randf() < 0.65):
			controller.combat.attack_hero(hero)
			return

		if controller.combat.can_attack_hero(hero.grid_pos) and can_cast_overworld_spell():
			if dist >= 3 or randf() < 0.60:
				mark_overworld_spell_cast()
				controller.combat._perform_overworld_ranged_initiation(hero)
				return

		var prefer_melee: bool = dist > controller.attack_range or randf() < 0.50
		if prefer_melee:
			if _move_necromancer_towards(hero.grid_pos, roam_cells, 2):
				return
		if _move_necromancer_reposition(hero, roam_cells, 3, 5, 2):
			return
		_wander_multiple_tiles(1, 0.0)
		return

	# 0–2. fázis (idézési szakaszok között): mozgás + varázslás cooldownnal
	if controller.combat.can_attack_hero(hero.grid_pos) and can_cast_overworld_spell():
		mark_overworld_spell_cast()
		controller.combat._perform_overworld_ranged_initiation(hero)
		return

	if dist > controller.attack_range:
		if _move_necromancer_towards(hero.grid_pos, roam_cells, 2):
			return
	elif dist <= 2:
		if _move_necromancer_reposition(hero, roam_cells, 4, 6, 2):
			return
	else:
		if _move_necromancer_reposition(hero, roam_cells, 3, 6, 1):
			return

	_wander_multiple_tiles(1, 0.1)

func _move_necromancer_towards(hero_cell: Vector2i, roam_cells: Dictionary, max_steps: int) -> bool:
	if controller == null or controller.mover == null or controller.mover.astar == null:
		return false
	var target_cell: Vector2i = _find_best_flank_cell(hero_cell)
	if not roam_cells.is_empty() and not roam_cells.has(target_cell):
		target_cell = _find_closest_roam_cell_to(hero_cell, roam_cells)
	return _start_path_toward_cell(target_cell, roam_cells, max_steps)

func _move_necromancer_reposition(hero: HeroController, roam_cells: Dictionary, min_pref: int, max_pref: int, max_steps: int) -> bool:
	if controller == null or controller.mover == null or controller.mover.astar == null:
		return false
	var gm: GridManager = controller.mover.grid_manager
	var search_pool: Array = roam_cells.keys() if not roam_cells.is_empty() else []
	if search_pool.is_empty():
		for dx in range(-4, 5):
			for dy in range(-4, 5):
				search_pool.append(controller.grid_pos + Vector2i(dx, dy))

	var best_score: float = INF
	var chosen_cell: Vector2i = controller.grid_pos
	for cell_variant in search_pool:
		var cell: Vector2i = cell_variant as Vector2i
		if cell == controller.grid_pos or not controller.mover.is_cell_walkable(cell):
			continue
		var step_dist: int = gm.get_grid_distance(controller.grid_pos, cell) if gm != null else _manhattan_distance(controller.grid_pos, cell)
		if step_dist > 4:
			continue
		var hero_dist: int = gm.get_grid_distance(cell, hero.grid_pos) if gm != null else maxi(absi(cell.x - hero.grid_pos.x), absi(cell.y - hero.grid_pos.y))
		var penalty: float = 0.0
		if hero_dist < min_pref:
			penalty = float(min_pref - hero_dist) * 3.0
		elif hero_dist > max_pref:
			penalty = float(hero_dist - max_pref) * 3.0
		if controller.combat and not controller.combat.has_line_of_sight(cell, hero.grid_pos):
			penalty += 5.0
		var score: float = penalty + float(step_dist) * 0.25 + randf() * 0.6
		if score < best_score:
			best_score = score
			chosen_cell = cell

	return _start_path_toward_cell(chosen_cell, roam_cells, max_steps)

func _start_path_toward_cell(target_cell: Vector2i, roam_cells: Dictionary, max_steps: int) -> bool:
	if target_cell == controller.grid_pos or controller == null or controller.mover == null or controller.mover.astar == null:
		return false
	var full_path = controller.mover.astar.get_id_path(controller.grid_pos, target_cell)
	if full_path.size() <= 1:
		return false
	full_path.remove_at(0)

	var sliced: Array[Vector2i] = []
	for i in range(mini(max_steps, full_path.size())):
		var step_cell: Vector2i = full_path[i]
		if not roam_cells.is_empty() and not roam_cells.has(step_cell):
			break
		if not controller.mover.is_cell_walkable(step_cell):
			break
		sliced.append(step_cell)

	if sliced.is_empty():
		return false
	controller.mover._start_moving_path(sliced)
	return true

## Külső körátadás a játékostól: lefut az AI lépés, és visszaállítjuk az időzítőt
func take_turn(hero: HeroController) -> void:
	# Időzítő újraindítása, hogy ne csússzon rá azonnal egy automata tick:
	if ai_timer and is_instance_valid(ai_timer) and not controller.is_dead:
		ai_timer.start()
	_on_ai_tick(hero)

func _find_hero() -> HeroController:
	var heroes = get_tree().get_nodes_in_group("player")
	return heroes[0] if not heroes.is_empty() else null

# --- POZÍCIÓSZÁMÍTÁSOK ÉS KÓBORLÁS ---

func _find_best_flank_cell(hero_pos: Vector2i) -> Vector2i:
	if controller == null or controller.mover == null:
		return hero_pos

	# Közelharcos: csak balról vagy jobbról tud támadni
	var left_flank = hero_pos + Vector2i.LEFT
	var right_flank = hero_pos + Vector2i.RIGHT

	var left_walkable = controller.mover.is_cell_walkable(left_flank)
	var right_walkable = controller.mover.is_cell_walkable(right_flank)

	var dist_left = _manhattan_distance(controller.grid_pos, left_flank)
	var dist_right = _manhattan_distance(controller.grid_pos, right_flank)

	if left_walkable and right_walkable:
		return left_flank if dist_left <= dist_right else right_flank
	elif left_walkable:
		return left_flank
	elif right_walkable:
		return right_flank

	# Távolsági szörny vagy ha a közvetlen oldalak foglaltak: a legközelebbi szabad szomszédos mező
	for offset in [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]:
		var neighbor = hero_pos + offset
		if controller.mover.is_cell_walkable(neighbor):
			return neighbor

	return hero_pos

func _get_roam_cells() -> Dictionary:
	if controller != null and controller.has_meta("roam_room_cells"):
		var raw_cells = controller.get_meta("roam_room_cells")
		if raw_cells is Dictionary:
			return raw_cells
	return {}

func _find_closest_roam_cell_to(target: Vector2i, roam_cells: Dictionary) -> Vector2i:
	if controller == null or controller.mover == null:
		return target
	var best_cell := controller.grid_pos
	var best_dist := _manhattan_distance(controller.grid_pos, target)
	for cell_variant in roam_cells.keys():
		var candidate := cell_variant as Vector2i
		if candidate != controller.grid_pos and not controller.mover.is_cell_walkable(candidate):
			continue
		var d := _manhattan_distance(candidate, target)
		if d < best_dist:
			best_dist = d
			best_cell = candidate
	return best_cell

func _wander_multiple_tiles(override_max_steps: int = -1, skip_chance: float = 0.35) -> void:
	if controller == null or controller.mover == null: return
	if randf() < skip_chance: return

	var roam_cells := _get_roam_cells()

	var directions = [Vector2i.RIGHT, Vector2i.LEFT, Vector2i.DOWN, Vector2i.UP]
	directions.shuffle()
	var max_steps: int = override_max_steps if override_max_steps > 0 else (controller.enemy_data.move_distance if controller.enemy_data else 1)

	for dir in directions:
		var test_path: Array[Vector2i] = []
		var current = controller.grid_pos
		for step in range(randi_range(1, max_steps)):
			var next = current + dir
			if not roam_cells.is_empty() and not roam_cells.has(next):
				break
			if controller.mover.is_cell_walkable(next):
				test_path.append(next)
				current = next
			else:
				break

		if not test_path.is_empty():
			controller.mover._start_moving_path(test_path)
			return

func _manhattan_distance(a: Vector2i, b: Vector2i) -> int:
	return absi(a.x - b.x) + absi(a.y - b.y)
