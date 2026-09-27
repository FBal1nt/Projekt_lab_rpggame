extends Node2D
class_name HeroController

@export_group("Hős Adatok")
@export var hero_name: String = "Gandalf"

@export_group("Kaszt és Megjelenés")
@export var available_classes: Array[CharacterClass] = []
@export var character_class: CharacterClass

@export_group("Map Rétegek")
@export var floor_layer: TileMapLayer
@export var wall_layer: TileMapLayer
@export var decoratives_layer: TileMapLayer

@export_group("Játékmenet")
@export var move_duration: float = 0.15
@export var fog_of_war: FogOfWar

@onready var sprite: AnimatedSprite2D = $AnimatedSprite2D

var active_class: CharacterClass
var current_hp: int = 100
var max_hp: int = 100
var attack_power: int = 18
var defense: int = 1
var initiative: float = 10.0
var attack_range: int = 1
var is_ranged: bool = false
var projectile_scene: PackedScene
var projectile_delay: float = 0.0
var wizard_element: String = "ice"

var level: int = 1
var xp: int = 0
var vision_limit: int = 1
var max_class_range: int = 1
var combo_index: int = 0

var in_battle: bool = false
var grid_pos: Vector2i = Vector2i.ZERO
var is_moving: bool = false
var is_attacking: bool = false
var cell_size: Vector2 = Vector2(16, 16)

var astar: AStarGrid2D
var path_queue: Array[Vector2i] = []
var current_step_target: Vector2i = Vector2i.ZERO
var hovered_cell: Vector2i = Vector2i(-99999, -99999)

func _ready() -> void:
	add_to_group("player")

	if sprite:
		sprite.animation_finished.connect(_on_animation_finished)

	if character_class != null:
		apply_character_class(character_class)
	elif not available_classes.is_empty():
		apply_character_class(available_classes[0])

	if not floor_layer: return
	if floor_layer.tile_set: cell_size = Vector2(floor_layer.tile_set.tile_size)

	grid_pos = floor_layer.local_to_map(floor_layer.to_local(global_position))
	position = floor_layer.map_to_local(grid_pos)

	if floor_layer.get_used_rect().size != Vector2i.ZERO:
		setup_grid_astar()
		update_fog_of_war()
	
	update_hud()

func get_initiative() -> float: return initiative
func get_defense() -> int: return defense
func get_current_hp() -> int: return current_hp
func get_max_hp() -> int: return max_hp
func is_alive() -> bool: return current_hp > 0

func roll_attack_damage() -> int:
	return ceili(float(attack_power) * randf_range(0.8, 1.0))

func take_damage(incoming_raw_damage: int) -> int:
	if not is_alive(): return 0
	var actual_damage = maxi(0, incoming_raw_damage - defense)
	current_hp = maxi(0, current_hp - actual_damage)
	update_hud()
	return actual_damage

func heal(amount: int) -> void:
	if not is_alive(): return
	current_hp = mini(current_hp + amount, max_hp)
	update_hud()

func heal_to_max() -> void:
	if not is_alive(): return
	current_hp = max_hp
	update_hud()

func gain_combat_xp(amount: int = 1) -> void:
	xp += amount
	if xp >= 10:
		xp -= 10
		_level_up()
	update_hud()

func _level_up() -> void:
	level += 1
	attack_power += 1
	defense += 1
	max_hp += 10
	heal_to_max()
	initiative *= 1.1
	vision_limit *= 3 # 1 -> 3 -> 9 -> 27
	attack_range = get_effective_attack_range()
	update_fog_of_war()
	update_hud()
	queue_redraw()

func award_title(slain_title: String) -> void:
	if slain_title == "": return
	var new_title = "the slayer of " + slain_title
	if not new_title in hero_name:
		hero_name = "%s, %s" % [hero_name, new_title]
	update_hud()

func play_hurt_reaction() -> void:
	if sprite and sprite.sprite_frames.has_animation("hurt") and is_alive():
		sprite.play("hurt")
		await sprite.animation_finished
		if sprite and is_alive(): sprite.play("idle")

func update_hud() -> void:
	var hud = get_tree().get_first_node_in_group("hud") as PlayerHUD
	if hud != null: hud.refresh_stats(self)

## A hős helyszíni támadása animációkkal és repülő lövedékekkel a csempéken:
func perform_combat_turn(target_enemy: Node2D) -> int:
	if not is_alive() or not is_instance_valid(target_enemy): return 0
	
	# 1. Fordulás a célpont felé
	if sprite:
		if target_enemy.grid_pos.x > grid_pos.x: sprite.flip_h = false
		elif target_enemy.grid_pos.x < grid_pos.x: sprite.flip_h = true

	var dist = _get_grid_distance(grid_pos, target_enemy.grid_pos)
	var raw_damage = roll_attack_damage()

	# A) PAPNŐ (SZENT MÁGIA)
	if active_class and active_class.class_name_id == "Priest":
		if sprite and sprite.sprite_frames.has_animation("attack_1"): sprite.play("attack_1")
		if projectile_delay > 0.0: await get_tree().create_timer(projectile_delay).timeout

		if projectile_scene != null:
			var spell = projectile_scene.instantiate()
			get_parent().add_child(spell)
			if spell.has_method("spawn_at"):
				spell.spawn_at(target_enemy, raw_damage, self)
			await spell.tree_exited
		else:
			target_enemy.take_damage(raw_damage)
			gain_combat_xp(1)

	# B) VARÁZSLÓ (JÉG / TŰZGOLYÓ REPÜLÉSE)
	elif active_class and active_class.class_name_id == "Wizard":
		var anim_name = "attack_1" if wizard_element == "ice" else "attack_2"
		if sprite and sprite.sprite_frames.has_animation(anim_name): sprite.play(anim_name)
		if projectile_delay > 0.0: await get_tree().create_timer(projectile_delay).timeout

		if projectile_scene != null:
			var spell = projectile_scene.instantiate() as WizardSpell
			get_parent().add_child(spell)
			if wizard_element == "ice":
				spell.spawn_ice(target_enemy, raw_damage, self)
			else:
				spell.launch_fire(global_position, target_enemy, raw_damage, self)
			await spell.tree_exited
		else:
			target_enemy.take_damage(raw_damage)
			gain_combat_xp(1)

	# C) KATONA TÁVOLI ÍJA VAGY ÍJÁSZ (NYÍLVESSZŐ REPÜLÉSE)
	elif (active_class and active_class.class_name_id == "Soldier" and dist > 1) or is_ranged:
		var anim_name = "attack_3" if (active_class and active_class.class_name_id == "Soldier") else "attack_1"
		if sprite and sprite.sprite_frames.has_animation(anim_name): sprite.play(anim_name)
		if projectile_delay > 0.0: await get_tree().create_timer(projectile_delay).timeout

		if projectile_scene != null:
			var arrow = projectile_scene.instantiate()
			get_parent().add_child(arrow)
			if arrow.has_method("launch"):
				arrow.launch(global_position, target_enemy, raw_damage, self)
			await arrow.tree_exited
		else:
			target_enemy.take_damage(raw_damage)
			gain_combat_xp(1)

	# D) KÖZELHARCI FEGYVERCSAPÁS A HELYSZÍNEN
	else:
		var anim = "attack_1"
		if active_class and active_class.class_name_id == "Swordsman":
			var attacks = ["attack_1", "attack_2", "attack_3"]
			anim = attacks[combo_index % attacks.size()]
			combo_index += 1

		if sprite and sprite.sprite_frames.has_animation(anim):
			sprite.play(anim)
			await sprite.animation_finished

		target_enemy.take_damage(raw_damage)
		gain_combat_xp(1)

	if sprite and is_alive(): sprite.play("idle")
	target_enemy.play_hurt_reaction()

	return raw_damage

# --- IRÁNYÍTÁS ---

func _unhandled_input(event: InputEvent) -> void:
	if in_battle or not is_alive(): return

	if event is InputEventKey and event.pressed and not event.echo:
		var code = event.physical_keycode if event.physical_keycode != 0 else event.keycode
		match code:
			KEY_1: select_class_by_index(0)
			KEY_2: select_class_by_index(1)
			KEY_3: select_class_by_index(2)
			KEY_4: select_class_by_index(3)
			KEY_5: select_class_by_index(4)
			KEY_6: select_class_by_index(5)
			KEY_7: select_class_by_index(6)
			KEY_8: select_class_by_index(7)
			KEY_F: wizard_element = "fire" if wizard_element == "ice" else "ice"

	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT:
			handle_attack_click()
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			handle_move_click()

func handle_attack_click() -> void:
	if not floor_layer or is_moving or in_battle or is_attacking or not is_alive():
		return

	var target_cell = floor_layer.local_to_map(floor_layer.to_local(get_global_mouse_position()))
	if not is_tile_in_vision(target_cell):
		return

	var enemy = _get_enemy_at_cell(target_cell)
	if enemy != null and enemy.is_monster_alive():
		var dist = _get_grid_distance(grid_pos, target_cell)
		var current_range = get_effective_attack_range()
		
		# 1. Elérjük-e a célpontot az aktuálisan korlátozott hatótávunkkal?
		if dist <= current_range:
			path_queue.clear()
			is_moving = false

			var enemy_reach: int = 1
			if enemy.has_method("get_attack_range"):
				enemy_reach = enemy.get_attack_range()
			elif enemy.get("attack_range") != null:
				enemy_reach = enemy.get("attack_range")

			# 2. Ha az ellenfél is elér minket, indul a harci felület; ha nem, szabad távoli lövés:
			if dist <= enemy_reach:
				var battle_ui = get_tree().get_first_node_in_group("battle_ui") as BattleDialog
				if battle_ui != null:
					battle_ui.open_battle(self, enemy)
			else:
				perform_standalone_ranged_shot(enemy)
		else:
			print("[Harcrendszer] Túl messze van a lőtávtól! (Távolság: %d, Aktuális hatótáv: %d)" % [dist, current_range])

## Egyetlen távolsági lövés leadása a free roam térképen (BattleDialog nélkül)
func perform_standalone_ranged_shot(target_enemy: Node2D) -> void:
	is_attacking = true

	# Fordulás az ellenség irányába
	if sprite:
		if target_enemy.grid_pos.x > grid_pos.x:
			sprite.flip_h = false
		elif target_enemy.grid_pos.x < grid_pos.x:
			sprite.flip_h = true

	var dist = _get_grid_distance(grid_pos, target_enemy.grid_pos)
	var raw_damage = roll_attack_damage()

	# A) PAPNŐ (SZENT MÁGIA)
	if active_class and active_class.class_name_id == "Priest":
		if sprite and sprite.sprite_frames.has_animation("attack_1"):
			sprite.play("attack_1")
		if projectile_delay > 0.0:
			await get_tree().create_timer(projectile_delay).timeout

		if projectile_scene != null:
			var spell = projectile_scene.instantiate()
			get_parent().add_child(spell)
			if spell.has_method("spawn_at"):
				spell.spawn_at(target_enemy, raw_damage, self)
			await spell.tree_exited
		else:
			target_enemy.take_damage(raw_damage)
			gain_combat_xp(1)

	# B) VARÁZSLÓ (JÉG VAGY TŰZGOLYÓ)
	elif active_class and active_class.class_name_id == "Wizard":
		var anim_name = "attack_1" if wizard_element == "ice" else "attack_2"
		if sprite and sprite.sprite_frames.has_animation(anim_name):
			sprite.play(anim_name)
		if projectile_delay > 0.0:
			await get_tree().create_timer(projectile_delay).timeout

		if projectile_scene != null:
			var spell = projectile_scene.instantiate() as WizardSpell
			get_parent().add_child(spell)
			if wizard_element == "ice":
				spell.spawn_ice(target_enemy, raw_damage, self)
			else:
				spell.launch_fire(global_position, target_enemy, raw_damage, self)
			await spell.tree_exited
		else:
			target_enemy.take_damage(raw_damage)
			gain_combat_xp(1)

	# C) ÍJÁSZ VAGY KATONA TÁVOLI ÍJA
	else:
		var anim_name = "attack_3" if (active_class and active_class.class_name_id == "Soldier") else "attack_1"
		if sprite and sprite.sprite_frames.has_animation(anim_name):
			sprite.play(anim_name)
		if projectile_delay > 0.0:
			await get_tree().create_timer(projectile_delay).timeout

		if projectile_scene != null:
			var arrow = projectile_scene.instantiate()
			get_parent().add_child(arrow)
			if arrow.has_method("launch"):
				arrow.launch(global_position, target_enemy, raw_damage, self)
			await arrow.tree_exited
		else:
			target_enemy.take_damage(raw_damage)
			gain_combat_xp(1)

	if sprite and is_alive():
		sprite.play("idle")
	is_attacking = false

	# Találat feldolgozása a célponton
	if is_instance_valid(target_enemy):
		if not target_enemy.is_monster_alive():
			var title = target_enemy.get_title()
			if title != "":
				award_title(title)
			if target_enemy.has_method("play_overworld_death"):
				await target_enemy.play_overworld_death()
		else:
			target_enemy.play_hurt_reaction()
			# A megsebzett szörny köre következik (elindul a hős felé!):
			trigger_monsters_turn()

## Kör átadása az ellenségeknek távoli támadás vagy cselekvés után
func trigger_monsters_turn() -> void:
	var enemies = get_tree().get_nodes_in_group("enemies")
	for enemy in enemies:
		if is_instance_valid(enemy) and enemy.has_method("take_turn"):
			enemy.take_turn(self)

func handle_move_click() -> void:
	if not floor_layer or is_moving or in_battle or not astar or not is_alive(): return
	var target_cell = floor_layer.local_to_map(floor_layer.to_local(get_global_mouse_position()))
	if not is_tile_in_vision(target_cell) or is_cell_solid(target_cell) or _get_enemy_at_cell(target_cell) != null:
		return

	var start_cell = current_step_target if is_moving else grid_pos
	var new_path = astar.get_id_path(start_cell, target_cell)
	if new_path.is_empty(): return
	if new_path[0] == start_cell: new_path.remove_at(0)

	path_queue = new_path
	if not is_moving: _step_next_in_queue()

func _step_next_in_queue() -> void:
	if path_queue.is_empty() or in_battle:
		is_moving = false
		if sprite and is_alive(): sprite.play("idle")
		return

	is_moving = true
	current_step_target = path_queue.pop_front()
	var step_dir = current_step_target - grid_pos
	if sprite:
		if step_dir.x > 0: sprite.flip_h = false
		elif step_dir.x < 0: sprite.flip_h = true
		if sprite.animation != "walk": sprite.play("walk")

	var target_world_pos = floor_layer.map_to_local(current_step_target)
	var tween = create_tween()
	tween.tween_property(self, "position", target_world_pos, move_duration)
	tween.finished.connect(_on_step_finished)

func _on_step_finished() -> void:
	grid_pos = current_step_target
	update_fog_of_war()
	update_hud()
	_step_next_in_queue()

func _on_animation_finished() -> void:
	if sprite.animation in ["attack_1", "attack_2", "attack_3", "heal", "hurt"]:
		if sprite and is_alive() and not in_battle: sprite.play("idle")

func select_class_by_index(index: int) -> void:
	if is_moving or in_battle: return
	if index >= 0 and index < available_classes.size():
		var chosen = available_classes[index]
		if chosen != null and chosen != active_class: apply_character_class(chosen)

func apply_character_class(new_class: CharacterClass) -> void:
	if new_class == null: return
	active_class = new_class
	if sprite:
		if new_class.sprite_frames: sprite.sprite_frames = new_class.sprite_frames
		sprite.scale = new_class.sprite_scale
		sprite.offset = new_class.sprite_offset
		sprite.play("idle")

	max_hp = new_class.max_hp
	current_hp = max_hp
	attack_power = new_class.base_damage
	defense = new_class.base_defense
	initiative = new_class.initiative
	move_duration = new_class.move_duration
	is_ranged = new_class.is_ranged
	projectile_scene = new_class.projectile_scene

	# A Varázsló maximális lőtávolsága 5 csempe:
	if new_class.class_name_id == "Wizard":
		max_class_range = 5
	else:
		max_class_range = new_class.attack_range

	attack_range = get_effective_attack_range()

	if projectile_scene != null and new_class.attack_fps > 0.0:
		projectile_delay = float(new_class.release_frame) / float(new_class.attack_fps)
	else:
		projectile_delay = 0.0

	update_hud()

# --- RÁCS ÉS KÖD ---

func _get_enemy_at_cell(cell: Vector2i) -> Node2D:
	var enemies = get_tree().get_nodes_in_group("enemies")
	for enemy in enemies:
		if is_instance_valid(enemy) and enemy.get("grid_pos") == cell: return enemy
	return null

func _get_grid_distance(a: Vector2i, b: Vector2i) -> int:
	var diff = a - b
	return maxi(absi(diff.x), absi(diff.y))

func update_fog_of_war() -> void:
	if fog_of_war:
		fog_of_war.update_vision(grid_pos, vision_limit)
		get_tree().call_group("enemies", "update_fog_visibility")

func get_effective_attack_range() -> int:
	if not is_ranged and (active_class == null or active_class.attack_range <= 1):
		return 1 # Közelharcos mindig 1 csempére üt

	# Íjász: a támadási lehetőség pontosan megegyezik a látótávolsággal
	if active_class and active_class.class_name_id == "Archer":
		return vision_limit

	# Varázsló: alapból 5 csempe, de ha a látótávolság kisebb, akkor addig lő;
	# ha a látótávolság nagyobb lesz (pl. 9), megáll a maximális 5-nél!
	if active_class and active_class.class_name_id == "Wizard":
		return mini(5, vision_limit)

	# Bármely egyéb távolsági kaszt (pl. Soldier íjjal vagy Priest):
	var base_cap = max_class_range if max_class_range > 1 else vision_limit
	return mini(base_cap, vision_limit)

func is_tile_in_vision(cell: Vector2i) -> bool:
	if fog_of_war and fog_of_war.is_initialized: return cell in fog_of_war.current_visible_cells
	var diff = cell - grid_pos
	return (diff.x * diff.x + diff.y * diff.y) <= vision_limit

func _get_safe_tile_data(layer: TileMapLayer, cell: Vector2i) -> TileData:
	if layer == null or layer.tile_set == null: return null
	var source_id = layer.get_cell_source_id(cell)
	if source_id == -1 or not layer.tile_set.has_source(source_id): return null
	return layer.get_cell_tile_data(cell)

func setup_grid_astar() -> void:
	astar = AStarGrid2D.new()
	var full_region: Rect2i = floor_layer.get_used_rect()
	if wall_layer: full_region = full_region.merge(wall_layer.get_used_rect())
	if decoratives_layer: full_region = full_region.merge(decoratives_layer.get_used_rect())
	astar.region = full_region
	astar.cell_size = cell_size
	astar.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_NEVER
	astar.update()

	for x in range(astar.region.position.x, astar.region.end.x):
		for y in range(astar.region.position.y, astar.region.end.y):
			var cell = Vector2i(x, y)
			if is_cell_solid(cell): astar.set_point_solid(cell, true)

func is_cell_solid(cell: Vector2i) -> bool:
	if floor_layer == null: return true
	var floor_data = _get_safe_tile_data(floor_layer, cell)
	if floor_data == null: return true
	if is_tile_blocking(floor_data, floor_layer.tile_set, false): return true
	if wall_layer != null:
		var wall_data = _get_safe_tile_data(wall_layer, cell)
		if wall_data != null and is_tile_blocking(wall_data, wall_layer.tile_set, true): return true
	if decoratives_layer != null:
		var decor_data = _get_safe_tile_data(decoratives_layer, cell)
		if decor_data != null and is_tile_blocking(decor_data, decoratives_layer.tile_set, false): return true
	return false

func is_tile_blocking(tile_data: TileData, tile_set: TileSet, default_blocking: bool) -> bool:
	if tile_data == null: return false
	if tile_set != null:
		var idx_camel = tile_set.get_custom_data_layer_by_name("isWall")
		if idx_camel != -1 and tile_data.get_custom_data_by_layer_id(idx_camel) == true: return true
		var idx_snake = tile_set.get_custom_data_layer_by_name("is_wall")
		if idx_snake != -1 and tile_data.get_custom_data_by_layer_id(idx_snake) == true: return true
	if tile_data.get_collision_polygons_count(0) > 0: return true
	return default_blocking

func _process(_delta: float) -> void:
	if not floor_layer: return
	var current_cell = floor_layer.local_to_map(floor_layer.to_local(get_global_mouse_position()))
	if current_cell != hovered_cell:
		hovered_cell = current_cell
		queue_redraw()

func _draw() -> void:
	if not floor_layer or in_battle: return
	var target_global = floor_layer.to_global(floor_layer.map_to_local(hovered_cell))
	var draw_pos = to_local(target_global)
	var rect = Rect2(draw_pos - cell_size / 2.0, cell_size)
	var enemy_here = _get_enemy_at_cell(hovered_cell)
	var in_vision = is_tile_in_vision(hovered_cell)

	if enemy_here != null and in_vision and enemy_here.is_monster_alive():
		var dist = _get_grid_distance(grid_pos, hovered_cell)
		var current_range = get_effective_attack_range()
		var in_range = dist <= current_range
		var fill_color = Color(1.0, 0.1, 0.1, 0.45) if in_range else Color(0.5, 0.1, 0.1, 0.25)
		var border_color = Color(1.0, 0.2, 0.2, 1.0) if in_range else Color(0.6, 0.2, 0.2, 0.6)
		draw_rect(rect, fill_color, true)
		draw_rect(rect, border_color, false, 2.0)
	else:
		var blocked = is_cell_solid(hovered_cell) or not in_vision
		var fill_color = Color(0.9, 0.2, 0.2, 0.25) if blocked else Color(1.0, 1.0, 1.0, 0.15)
		var border_color = Color(0.9, 0.2, 0.2, 0.9) if blocked else Color(1.0, 0.9, 0.3, 0.9)
		draw_rect(rect, fill_color, true)
		draw_rect(rect, border_color, false, 1.5)
