extends Node
class_name EnemyBrain

var controller: EnemyController
var ai_timer: Timer

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
	if controller == null or controller.is_dead or controller.is_moving or controller.is_attacking or not controller.is_monster_alive():
		return

	var hero = target_hero if is_instance_valid(target_hero) else _find_hero()
	if hero != null and hero.in_battle:
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
			var target_cell = _find_best_flank_cell(hero.grid_pos)
			var full_path = controller.mover.astar.get_id_path(controller.grid_pos, target_cell)
			
			if full_path.size() > 1:
				full_path.remove_at(0) # A kiindulási mezőnket levesszük
				var max_steps = controller.enemy_data.move_distance if controller.enemy_data else 1
				var sliced: Array[Vector2i] = []
				for i in range(mini(max_steps, full_path.size())):
					sliced.append(full_path[i])
				
				if not sliced.is_empty():
					controller.mover._start_moving_path(sliced)
					return

	# 3. KÓBORLÁS (ha nincs célpont a közelben)
	_wander_multiple_tiles()

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

func _wander_multiple_tiles() -> void:
	if randf() < 0.35: return
	if controller == null or controller.mover == null: return

	var directions = [Vector2i.RIGHT, Vector2i.LEFT, Vector2i.DOWN, Vector2i.UP]
	directions.shuffle()
	var max_steps = controller.enemy_data.move_distance if controller.enemy_data else 1

	for dir in directions:
		var test_path: Array[Vector2i] = []
		var current = controller.grid_pos
		for step in range(randi_range(1, max_steps)):
			var next = current + dir
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
