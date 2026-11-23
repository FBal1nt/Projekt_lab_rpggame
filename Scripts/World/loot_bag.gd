extends Area2D
class_name LootBag

const UI_THEME = preload("res://Scripts/UI/ui_theme.gd")
const SUPPLIES_TEX: Texture2D = preload("res://Assets/Tilesets/Dungeon/supplies_objects.png")

## Méretben és bőségben skálázódó zsák-régiók a supplies_objects.png-ből
const TIER_VISUALS := {
	1: {
		"name": "Kisebb zsák",
		"region": Rect2(114, 295, 12, 13),
		"offset": Vector2(0, -1),
		"glow_color": Color(0.88, 0.78, 0.56, 0.20),
		"glow_radius": 7.5
	},
	2: {
		"name": "Közepes zsákmányzsák",
		"region": Rect2(96, 229, 16, 20),
		"offset": Vector2(0, -3),
		"glow_color": Color(0.95, 0.78, 0.36, 0.28),
		"glow_radius": 9.5
	},
	3: {
		"name": "Nehéz zsákmánycsomag",
		"region": Rect2(148, 337, 23, 24),
		"offset": Vector2(0, -4),
		"glow_color": Color(0.98, 0.72, 0.28, 0.34),
		"glow_radius": 11.5
	},
	4: {
		"name": "Főellenség kincseszsákja",
		"region": Rect2(82, 334, 29, 30),
		"offset": Vector2(0, -5),
		"glow_color": Color(1.0, 0.84, 0.32, 0.48),
		"glow_radius": 14.5
	}
}

@onready var bag_sprite: Sprite2D = $BagSprite
@onready var interaction_hitbox: CollisionShape2D = $InteractionHitbox

var grid_pos: Vector2i = Vector2i.ZERO
var bag_tier: int = 1
var source_enemy_name: String = "Ellenség"
var gold_amount: int = 0
var material_drops: Array[Dictionary] = []
var fog_of_war: FogOfWar = null

var _player_in_range: bool = false
var _is_closest_active: bool = false
var _collected: bool = false
var _cached_player: HeroController = null
var _pulse_time: float = 0.0

var _prompt_layer: CanvasLayer
var _prompt_panel: PanelContainer
var _prompt_key_badge: Label
var _prompt_text_label: Label


func _ready() -> void:
	add_to_group("loot_bags")
	z_index = 4
	monitoring = false
	monitorable = false
	_apply_tier_visuals()
	_build_prompt_ui()
	_play_drop_bounce()
	update_fog_visibility()


func _exit_tree() -> void:
	if is_instance_valid(_prompt_layer):
		_prompt_layer.queue_free()


func setup_loot(
	p_grid_pos: Vector2i,
	p_tier: int,
	p_enemy_name: String,
	p_gold: int,
	p_materials: Array[Dictionary],
	p_fow: FogOfWar = null
) -> void:
	grid_pos = p_grid_pos
	bag_tier = clampi(p_tier, 1, 4)
	source_enemy_name = p_enemy_name if not p_enemy_name.strip_edges().is_empty() else "Ellenség"
	gold_amount = maxi(0, p_gold)
	material_drops.clear()
	for entry in p_materials:
		if entry is Dictionary and int(entry.get("amount", 0)) > 0:
			material_drops.append(entry.duplicate(true))
	if p_fow != null:
		fog_of_war = p_fow

	if is_inside_tree():
		_apply_tier_visuals()
		update_fog_visibility()
		queue_redraw()


func merge_loot(
	p_tier: int,
	p_enemy_name: String,
	p_gold: int,
	p_materials: Array[Dictionary]
) -> void:
	if _collected:
		return
	bag_tier = maxi(bag_tier, clampi(p_tier, 1, 4))
	if not p_enemy_name.strip_edges().is_empty() and not (p_enemy_name in source_enemy_name):
		source_enemy_name = "%s, %s" % [source_enemy_name, p_enemy_name]
	gold_amount += maxi(0, p_gold)
	for entry in p_materials:
		if not (entry is Dictionary):
			continue
		var add_id: StringName = StringName(String(entry.get("item_id", "")))
		var add_amt: int = int(entry.get("amount", 0))
		if String(add_id).is_empty() or add_amt <= 0:
			continue
		var merged := false
		for existing in material_drops:
			if StringName(String(existing.get("item_id", ""))) == add_id:
				existing["amount"] = int(existing.get("amount", 0)) + add_amt
				merged = true
				break
		if not merged:
			material_drops.append({"item_id": add_id, "amount": add_amt})

	if is_inside_tree():
		_apply_tier_visuals()
		_play_drop_bounce()
		_refresh_prompt()
		queue_redraw()


static func get_tier_visual_meta(tier_val: int) -> Dictionary:
	var clamped: int = clampi(tier_val, 1, 4)
	return (TIER_VISUALS.get(clamped, TIER_VISUALS[1]) as Dictionary)


static func make_tier_icon_texture(tier_val: int) -> AtlasTexture:
	var meta: Dictionary = get_tier_visual_meta(tier_val)
	var atlas := AtlasTexture.new()
	atlas.atlas = SUPPLIES_TEX
	atlas.region = meta["region"] as Rect2
	return atlas


static func generate_loot_for_enemy(
	enemy_data: EnemyData,
	is_summoned_minion: bool = false,
	is_split_child: bool = false,
	difficulty_id: String = "normal"
) -> Dictionary:
	var raw_tier: int = int(enemy_data.tier) if enemy_data != null else 1
	var tier_val: int = clampi(raw_tier, 1, 4)
	var enemy_level: int = maxi(1, int(enemy_data.enemy_level)) if enemy_data != null else 1
	var enemy_name: String = enemy_data.monster_name if (enemy_data != null and not enemy_data.monster_name.strip_edges().is_empty()) else "Ellenség"

	var diff_clean: String = difficulty_id.strip_edges().to_lower()
	var diff_mult: float = 1.0
	if "easy" in diff_clean:
		diff_mult = 0.85
	elif "hard" in diff_clean:
		diff_mult = 1.30

	var minion_mult: float = 1.0
	if is_summoned_minion:
		minion_mult = 0.55
	elif is_split_child:
		minion_mult = 0.50

	var base_gold: int = 0
	var gold_per_level: float = 1.0
	var mat_rolls: int = 1
	var mat_qty_min: int = 1
	var mat_qty_max: int = 1

	match tier_val:
		EnemyData.EnemyTier.BASIC:
			base_gold = randi_range(4, 9)
			gold_per_level = 1.0
			mat_rolls = 1 if randf() < 0.72 else 2
			mat_qty_min = 1
			mat_qty_max = 1
		EnemyData.EnemyTier.ARMORED:
			base_gold = randi_range(12, 20)
			gold_per_level = 1.8
			mat_rolls = 2 if randf() < 0.70 else 3
			mat_qty_min = 1
			mat_qty_max = 2
		EnemyData.EnemyTier.ELITE:
			base_gold = randi_range(24, 38)
			gold_per_level = 2.5
			mat_rolls = 2 if randf() < 0.45 else 3
			mat_qty_min = 1
			mat_qty_max = 2
		EnemyData.EnemyTier.BOSS:
			base_gold = randi_range(75, 110)
			gold_per_level = 4.0
			mat_rolls = 4
			mat_qty_min = 2
			mat_qty_max = 4

	var level_bonus_gold: int = roundi(float(maxi(0, enemy_level - 1)) * gold_per_level)
	var final_gold: int = maxi(2, roundi(float(base_gold + level_bonus_gold) * diff_mult * minion_mult))

	# Alapanyag-táblázat (kovácsolás + varázsló tornya nyersanyagok)
	var pool: Array[Dictionary] = []
	match tier_val:
		EnemyData.EnemyTier.BASIC:
			pool = [
				{"id": &"leather_strip", "w": 42},
				{"id": &"iron_ingot", "w": 40},
				{"id": &"silver_ingot", "w": 10},
				{"id": &"arcane_dust", "w": 8}
			]
		EnemyData.EnemyTier.ARMORED:
			pool = [
				{"id": &"iron_ingot", "w": 44},
				{"id": &"leather_strip", "w": 26},
				{"id": &"silver_ingot", "w": 16},
				{"id": &"arcane_dust", "w": 14}
			]
		EnemyData.EnemyTier.ELITE:
			pool = [
				{"id": &"iron_ingot", "w": 30},
				{"id": &"silver_ingot", "w": 26},
				{"id": &"arcane_dust", "w": 26},
				{"id": &"leather_strip", "w": 18}
			]
		EnemyData.EnemyTier.BOSS:
			# Főellenség minden nyersanyagból bőségesen ejt
			pool = [
				{"id": &"arcane_dust", "w": 30},
				{"id": &"silver_ingot", "w": 30},
				{"id": &"iron_ingot", "w": 25},
				{"id": &"leather_strip", "w": 15}
			]

	var counts_by_id: Dictionary = {}
	if tier_val == EnemyData.EnemyTier.BOSS:
		for mat_id in [&"iron_ingot", &"silver_ingot", &"arcane_dust", &"leather_strip"]:
			var amt: int = maxi(2, roundi(float(randi_range(mat_qty_min, mat_qty_max)) * diff_mult))
			counts_by_id[mat_id] = amt
	else:
		var effective_rolls: int = maxi(1, roundi(float(mat_rolls) * minion_mult)) if not (is_split_child and randf() < 0.35) else 1
		for _i in range(effective_rolls):
			var picked_id: StringName = _pick_weighted_material(pool)
			var qty: int = randi_range(mat_qty_min, mat_qty_max)
			if is_summoned_minion or is_split_child:
				qty = 1
			counts_by_id[picked_id] = int(counts_by_id.get(picked_id, 0)) + qty
		# Elit szörnynél legalább 1 ritkább (ezüstrúd / arkán por) garantált, ha még nincs
		if tier_val == EnemyData.EnemyTier.ELITE and not counts_by_id.has(&"silver_ingot") and not counts_by_id.has(&"arcane_dust"):
			var rare_id: StringName = &"silver_ingot" if randf() < 0.5 else &"arcane_dust"
			counts_by_id[rare_id] = 1

	var mats: Array[Dictionary] = []
	for key in [&"iron_ingot", &"leather_strip", &"silver_ingot", &"arcane_dust"]:
		if counts_by_id.has(key) and int(counts_by_id[key]) > 0:
			mats.append({"item_id": key, "amount": int(counts_by_id[key])})

	return {
		"tier": tier_val,
		"enemy_name": enemy_name,
		"gold": final_gold,
		"materials": mats
	}


static func _pick_weighted_material(pool: Array[Dictionary]) -> StringName:
	var total_w: int = 0
	for entry in pool:
		total_w += int(entry.get("w", 1))
	if total_w <= 0:
		return &"iron_ingot"
	var roll: int = randi_range(1, total_w)
	var acc: int = 0
	for entry in pool:
		acc += int(entry.get("w", 1))
		if roll <= acc:
			return entry.get("id", &"iron_ingot") as StringName
	return &"iron_ingot"


func _apply_tier_visuals() -> void:
	var meta: Dictionary = get_tier_visual_meta(bag_tier)
	if is_instance_valid(bag_sprite):
		bag_sprite.texture = SUPPLIES_TEX
		bag_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		bag_sprite.region_enabled = true
		bag_sprite.region_rect = meta["region"] as Rect2
		bag_sprite.offset = meta["offset"] as Vector2


func _play_drop_bounce() -> void:
	if not is_instance_valid(bag_sprite):
		return
	var meta: Dictionary = get_tier_visual_meta(bag_tier)
	var rest_offset: Vector2 = meta["offset"] as Vector2
	bag_sprite.offset = rest_offset + Vector2(0, -8)
	bag_sprite.scale = Vector2(0.7, 0.7)
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(bag_sprite, "offset", rest_offset, 0.24).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
	tw.tween_property(bag_sprite, "scale", Vector2.ONE, 0.20).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _draw() -> void:
	if _collected or not visible:
		return
	var meta: Dictionary = get_tier_visual_meta(bag_tier)
	var glow_col: Color = meta["glow_color"] as Color
	var radius: float = float(meta["glow_radius"])
	var pulse: float = 0.75 + 0.25 * sin(_pulse_time * 3.2)
	var col := Color(glow_col.r, glow_col.g, glow_col.b, glow_col.a * pulse)
	draw_circle(Vector2(0, 2), radius, col)
	if bag_tier >= 3 or _is_closest_active:
		var ring_alpha: float = 0.78 if _is_closest_active else 0.40 * pulse
		draw_arc(Vector2(0, 2), radius + 1.0, 0.0, TAU, 24, Color(UI_THEME.GOLD.r, UI_THEME.GOLD.g, UI_THEME.GOLD.b, ring_alpha), 1.0)


func _process(delta: float) -> void:
	if _collected or _is_dungeon_generating():
		return

	_pulse_time += delta
	if visible and (bag_tier >= 2 or _is_closest_active):
		queue_redraw()

	var in_range_now: bool = _is_player_inside_hitbox()
	var closest_now: bool = in_range_now and _is_closest_loot_bag_in_range()
	if in_range_now != _player_in_range or closest_now != _is_closest_active:
		_player_in_range = in_range_now
		_is_closest_active = closest_now
		_refresh_prompt()
		queue_redraw()
	elif _is_closest_active and is_instance_valid(_prompt_layer):
		var should_show: bool = not _is_interaction_blocked()
		if _prompt_layer.visible != should_show:
			if should_show:
				_refresh_prompt()
			else:
				_prompt_layer.visible = false
		if should_show:
			_update_prompt_vertical_offset()


func _unhandled_input(event: InputEvent) -> void:
	if _collected or not _is_closest_active or _is_interaction_blocked():
		return
	if not (event is InputEventKey):
		return
	var key_event := event as InputEventKey
	if not key_event.pressed or key_event.echo:
		return
	if not _matches_interact_key(key_event):
		return

	var vp := get_viewport()
	if vp != null:
		vp.set_input_as_handled()
	_collect_loot()


func _collect_loot() -> void:
	if _collected:
		return
	_collected = true
	if is_instance_valid(_prompt_layer):
		_prompt_layer.visible = false

	var gs := get_node_or_null("/root/GameState")
	var grant_summary: Dictionary = {}
	if gs != null and gs.has_method("grant_dungeon_loot"):
		grant_summary = gs.grant_dungeon_loot(gold_amount, material_drops)
	else:
		if gs != null and gs.has_method("add_gold"):
			gs.add_gold(gold_amount, true)
		grant_summary = {
			"gold": gold_amount,
			"items": []
		}

	var meta: Dictionary = get_tier_visual_meta(bag_tier)
	var window_payload := {
		"tier": bag_tier,
		"bag_name": String(meta.get("name", "Zsákmányzsák")),
		"enemy_name": source_enemy_name,
		"gold": int(grant_summary.get("gold", gold_amount)),
		"items": grant_summary.get("items", []),
		"bag_icon": make_tier_icon_texture(bag_tier)
	}

	AudioManager.sfx(&"gold_coins", 0.94, 1.06, -1.0)

	var hud := get_tree().get_first_node_in_group("hud")
	if hud != null and hud.has_method("show_loot_window"):
		hud.show_loot_window(window_payload)

	remove_from_group("loot_bags")
	queue_free()


func update_fog_visibility() -> void:
	if _collected:
		return
	if fog_of_war == null:
		fog_of_war = get_tree().root.find_child("FogOfWar", true, false) as FogOfWar
	if fog_of_war != null and fog_of_war.is_initialized:
		var state: int = int(fog_of_war.cell_states.get(grid_pos, FogOfWar.CellState.UNEXPLORED))
		if state == FogOfWar.CellState.VISIBLE:
			visible = true
			modulate = Color.WHITE
		elif state == FogOfWar.CellState.IN_FOG or fog_of_war.is_cell_map_discovered(grid_pos):
			visible = true
			modulate = Color(0.66, 0.70, 0.80, 0.95)
		else:
			visible = false
	else:
		var hero: HeroController = _get_player()
		visible = hero != null and hero.is_tile_in_vision(grid_pos)
		modulate = Color.WHITE


func _build_prompt_ui() -> void:
	_prompt_layer = CanvasLayer.new()
	_prompt_layer.name = "LootBagPromptLayer"
	_prompt_layer.layer = 46
	_prompt_layer.visible = false
	add_child(_prompt_layer)

	var anchor := Control.new()
	anchor.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	anchor.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_prompt_layer.add_child(anchor)

	_prompt_panel = PanelContainer.new()
	_prompt_panel.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	_prompt_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_prompt_panel.anchor_left = 0.5
	_prompt_panel.anchor_top = 1.0
	_prompt_panel.anchor_right = 0.5
	_prompt_panel.anchor_bottom = 1.0
	_prompt_panel.offset_left = -210.0
	_prompt_panel.offset_right = 210.0
	_prompt_panel.offset_top = -94.0
	_prompt_panel.offset_bottom = -48.0
	_prompt_panel.add_theme_stylebox_override(
		"panel",
		UI_THEME.make_box(Color(0.024, 0.042, 0.074, 0.94), UI_THEME.GOLD, 2, 10)
	)
	anchor.add_child(_prompt_panel)

	var margin := MarginContainer.new()
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_theme_constant_override("margin_left", 14)
	margin.add_theme_constant_override("margin_top", 6)
	margin.add_theme_constant_override("margin_right", 14)
	margin.add_theme_constant_override("margin_bottom", 6)
	_prompt_panel.add_child(margin)

	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", 10)
	margin.add_child(row)

	var badge_box := PanelContainer.new()
	badge_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	badge_box.add_theme_stylebox_override(
		"panel",
		UI_THEME.make_box(Color(0.24, 0.16, 0.065, 0.98), UI_THEME.GOLD, 1, 6)
	)
	var badge_sb: StyleBox = badge_box.get_theme_stylebox("panel")
	if badge_sb is StyleBoxFlat:
		var flat_sb := badge_sb as StyleBoxFlat
		flat_sb.content_margin_left = 8.0
		flat_sb.content_margin_right = 8.0
		flat_sb.content_margin_top = 2.0
		flat_sb.content_margin_bottom = 2.0
	row.add_child(badge_box)

	_prompt_key_badge = Label.new()
	_prompt_key_badge.text = "E"
	_prompt_key_badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_prompt_key_badge.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_prompt_key_badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_prompt_key_badge.add_theme_font_size_override("font_size", 14)
	_prompt_key_badge.add_theme_color_override("font_color", UI_THEME.GOLD)
	badge_box.add_child(_prompt_key_badge)

	_prompt_text_label = Label.new()
	_prompt_text_label.text = "ZSÁKMÁNY ÁTVIZSGÁLÁSA"
	_prompt_text_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_prompt_text_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_prompt_text_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_prompt_text_label.add_theme_font_size_override("font_size", 14)
	_prompt_text_label.add_theme_color_override("font_color", UI_THEME.IVORY)
	row.add_child(_prompt_text_label)


func _refresh_prompt() -> void:
	if not is_instance_valid(_prompt_layer):
		return
	var should_show: bool = _is_closest_active and not _is_interaction_blocked()
	_prompt_layer.visible = should_show
	if not should_show:
		return

	if is_instance_valid(_prompt_key_badge):
		_prompt_key_badge.text = _get_interact_key_label()
	if is_instance_valid(_prompt_text_label):
		var meta: Dictionary = get_tier_visual_meta(bag_tier)
		var bag_title: String = String(meta.get("name", "Zsákmányzsák")).to_upper()
		_prompt_text_label.text = "%s — FELVÉTEL" % bag_title
	_update_prompt_vertical_offset()


func _update_prompt_vertical_offset() -> void:
	if not is_instance_valid(_prompt_panel):
		return
	var exit_prompt_visible := false
	for gate in get_tree().get_nodes_in_group("exit_gates"):
		if is_instance_valid(gate) and bool(gate.get("_player_in_range")):
			exit_prompt_visible = true
			break
	if exit_prompt_visible:
		_prompt_panel.offset_top = -148.0
		_prompt_panel.offset_bottom = -102.0
	else:
		_prompt_panel.offset_top = -94.0
		_prompt_panel.offset_bottom = -48.0


func _get_player() -> HeroController:
	if is_instance_valid(_cached_player):
		return _cached_player
	if not is_inside_tree():
		return null
	_cached_player = get_tree().get_first_node_in_group("player") as HeroController
	return _cached_player


func _is_player_inside_hitbox() -> bool:
	var hero: HeroController = _get_player()
	if not is_instance_valid(hero) or not hero.is_alive():
		return false
	var cheb_dist: int = maxi(absi(grid_pos.x - hero.grid_pos.x), absi(grid_pos.y - hero.grid_pos.y))
	if cheb_dist <= 1:
		return true
	if is_instance_valid(interaction_hitbox) and interaction_hitbox.shape != null:
		var local_pt: Vector2 = interaction_hitbox.to_local(hero.global_position)
		if interaction_hitbox.shape is CircleShape2D:
			return local_pt.length() <= (interaction_hitbox.shape as CircleShape2D).radius
		if interaction_hitbox.shape is RectangleShape2D:
			var half: Vector2 = (interaction_hitbox.shape as RectangleShape2D).size * 0.5
			return absf(local_pt.x) <= half.x and absf(local_pt.y) <= half.y
	return global_position.distance_to(hero.global_position) <= 24.0


func _is_closest_loot_bag_in_range() -> bool:
	var hero: HeroController = _get_player()
	if not is_instance_valid(hero):
		return false
	var my_dist: float = global_position.distance_squared_to(hero.global_position)
	var my_id: int = get_instance_id()
	for node in get_tree().get_nodes_in_group("loot_bags"):
		var bag := node as LootBag
		if bag == null or bag == self or not is_instance_valid(bag) or bag._collected:
			continue
		if not bag._is_player_inside_hitbox():
			continue
		var d: float = bag.global_position.distance_squared_to(hero.global_position)
		if d < my_dist - 0.1:
			return false
		if absf(d - my_dist) <= 0.1 and bag.get_instance_id() < my_id:
			return false
	return true


func _matches_interact_key(key_event: InputEventKey) -> bool:
	var sm := get_node_or_null("/root/SettingsManager")
	if sm != null and sm.has_method("matches_keybind"):
		return bool(sm.matches_keybind(key_event, "interact"))
	return key_event.keycode == KEY_E or key_event.physical_keycode == KEY_E


func _get_interact_key_label() -> String:
	var sm := get_node_or_null("/root/SettingsManager")
	if sm != null and sm.has_method("get_keybind_label"):
		return String(sm.get_keybind_label("interact")).to_upper()
	return "E"


func _is_dungeon_generating() -> bool:
	var dm := get_node_or_null("/root/DungeonManager")
	if dm != null and dm.has_method("is_loading_dungeon") and bool(dm.is_loading_dungeon()):
		return true
	var scene: Node = get_tree().current_scene if is_inside_tree() else null
	if scene != null:
		var gen := scene.get_node_or_null("MapGenerator")
		if gen != null and bool(gen.get("is_generating")):
			return true
	return false


func _is_interaction_blocked() -> bool:
	if not is_inside_tree() or get_tree().paused:
		return true
	var hero: HeroController = _get_player()
	if not is_instance_valid(hero) or not hero.is_alive() or hero.in_battle:
		return true
	var dm := get_node_or_null("/root/DungeonManager")
	if dm != null and dm.has_method("is_loading_dungeon") and bool(dm.is_loading_dungeon()):
		return true
	var sm := get_node_or_null("/root/SettingsManager")
	if sm != null and sm.has_method("is_open") and bool(sm.is_open()):
		return true
	var hud := get_tree().get_first_node_in_group("hud")
	if hud != null:
		if hud.has_method("is_fullscreen_map_open") and bool(hud.is_fullscreen_map_open()):
			return true
		if hud.has_method("is_backpack_open") and bool(hud.is_backpack_open()):
			return true
	var loot_ui := get_tree().get_first_node_in_group("dungeon_loot") as CanvasLayer
	if loot_ui != null and loot_ui.visible:
		return true
	var victory := get_tree().get_first_node_in_group("dungeon_victory") as CanvasLayer
	if victory != null and victory.visible:
		return true
	var battle_ui := get_tree().get_first_node_in_group("battle_ui")
	if battle_ui != null and bool(battle_ui.get("combat_active")):
		return true
	return false
