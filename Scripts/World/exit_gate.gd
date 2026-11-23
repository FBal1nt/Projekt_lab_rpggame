extends Area2D
class_name ExitGate

const UI_THEME = preload("res://Scripts/UI/ui_theme.gd")

const DOOR_FRAME_SIZE := Vector2i(32, 32)
const DOOR_ROW_Y: int = 96 # Row 3 in doors_lever_chest_animation.png (wooden arched door into dark passage)
const DOOR_FRAME_COUNT: int = 5
const OPEN_FRAME_DURATION: float = 0.11

@onready var door_sprite: Sprite2D = $DoorSprite
@onready var interaction_hitbox: CollisionShape2D = $InteractionHitbox

var _player_in_range: bool = false
var _is_unlocked: bool = false
var _is_opening: bool = false
var _initial_state_synced: bool = false
var _open_anim_elapsed: float = 0.0
var _current_frame: int = 0
var _cached_player: HeroController = null

var _prompt_layer: CanvasLayer
var _prompt_panel: PanelContainer
var _prompt_key_badge: Label
var _prompt_text_label: Label


func _ready() -> void:
	add_to_group("exit_gates")
	z_index = 3
	monitoring = false
	monitorable = false
	_apply_door_frame(0)
	_build_prompt_ui()
	call_deferred("_sync_initial_unlock_state")


func _exit_tree() -> void:
	if is_instance_valid(_prompt_layer):
		_prompt_layer.queue_free()


func _build_prompt_ui() -> void:
	_prompt_layer = CanvasLayer.new()
	_prompt_layer.name = "ExitGatePromptLayer"
	_prompt_layer.layer = 45
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
	_prompt_panel.offset_left = -190.0
	_prompt_panel.offset_right = 190.0
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
	_prompt_text_label.text = "KILÉPÉS A TÁBORBA"
	_prompt_text_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_prompt_text_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_prompt_text_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_prompt_text_label.add_theme_font_size_override("font_size", 14)
	_prompt_text_label.add_theme_color_override("font_color", UI_THEME.IVORY)
	row.add_child(_prompt_text_label)


func _sync_initial_unlock_state() -> void:
	if not is_inside_tree() or _is_dungeon_generating():
		return
	_initial_state_synced = true
	var unlocked_now: bool = _check_can_unlock()
	_is_unlocked = unlocked_now
	_apply_door_frame(DOOR_FRAME_COUNT - 1 if _is_unlocked else 0)


func on_boss_defeated() -> void:
	_initial_state_synced = true
	if _is_unlocked:
		return
	_is_unlocked = true
	_is_opening = true
	_open_anim_elapsed = 0.0
	_refresh_prompt()


func _process(delta: float) -> void:
	if _is_dungeon_generating():
		return
	if not _initial_state_synced:
		_sync_initial_unlock_state()
	elif not _is_unlocked and _check_can_unlock():
		on_boss_defeated()

	if _is_opening:
		_open_anim_elapsed += delta
		var target_frame: int = mini(
			int(floor(_open_anim_elapsed / OPEN_FRAME_DURATION)),
			DOOR_FRAME_COUNT - 1
		)
		if target_frame != _current_frame:
			_apply_door_frame(target_frame)
		if target_frame >= DOOR_FRAME_COUNT - 1:
			_is_opening = false

	var in_range_now: bool = _is_player_inside_hitbox()
	if in_range_now != _player_in_range:
		_player_in_range = in_range_now
		_refresh_prompt()
	elif _player_in_range and is_instance_valid(_prompt_layer):
		var should_show: bool = not _is_interaction_blocked()
		if _prompt_layer.visible != should_show:
			_prompt_layer.visible = should_show


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


func _unhandled_input(event: InputEvent) -> void:
	if not _player_in_range or _is_interaction_blocked():
		return
	if not (event is InputEventKey):
		return
	var key_event := event as InputEventKey
	if not key_event.pressed or key_event.echo:
		return

	if not _matches_interact_key(key_event):
		return
	for bag in get_tree().get_nodes_in_group("loot_bags"):
		if is_instance_valid(bag) and bool(bag.get("_is_closest_active")):
			return

	var vp := get_viewport()
	if vp != null:
		vp.set_input_as_handled()
	_trigger_interact()


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


func _trigger_interact() -> void:
	var hud := get_tree().get_first_node_in_group("hud")
	if not _is_unlocked and not _check_can_unlock():
		AudioManager.sfx(&"ui_error", 0.96, 1.04)
		if hud != null and hud.has_method("show_exit_locked_toast"):
			hud.show_exit_locked_toast()
		return

	if not _is_unlocked:
		on_boss_defeated()

	var gs := get_node_or_null("/root/GameState")
	var newly_unlocked := PackedStringArray()
	var run_titles := PackedStringArray()
	if gs != null:
		if not bool(gs.get("current_run_completed")) and gs.has_method("complete_dungeon_run"):
			var result: Dictionary = gs.complete_dungeon_run()
			newly_unlocked = result.get("newly_unlocked", PackedStringArray())
			run_titles = result.get("run_titles", PackedStringArray())
		elif gs.has_method("get_completed_run_title_summary"):
			var summary: Dictionary = gs.get_completed_run_title_summary()
			newly_unlocked = summary.get("newly_unlocked", PackedStringArray())
			run_titles = summary.get("run_titles", PackedStringArray())

	if is_instance_valid(_prompt_layer):
		_prompt_layer.visible = false

	if hud != null and hud.has_method("show_dungeon_victory"):
		hud.show_dungeon_victory(newly_unlocked, run_titles)


func _refresh_prompt() -> void:
	if not is_instance_valid(_prompt_layer):
		return
	var should_show: bool = _player_in_range and not _is_interaction_blocked()
	_prompt_layer.visible = should_show
	if not should_show:
		return

	if is_instance_valid(_prompt_key_badge):
		_prompt_key_badge.text = _get_interact_key_label()

	if is_instance_valid(_prompt_text_label):
		if _is_unlocked:
			_prompt_text_label.text = "KILÉPÉS A TÁBORBA"
			_prompt_text_label.add_theme_color_override("font_color", UI_THEME.IVORY)
		else:
			_prompt_text_label.text = "ZÁRVA — Győzd le a főellenséget!"
			_prompt_text_label.add_theme_color_override("font_color", Color(0.95, 0.68, 0.56, 1.0))

	if is_instance_valid(_prompt_panel):
		var border_col: Color = UI_THEME.GOLD if _is_unlocked else Color(0.75, 0.36, 0.30, 0.92)
		_prompt_panel.add_theme_stylebox_override(
			"panel",
			UI_THEME.make_box(Color(0.024, 0.042, 0.074, 0.94), border_col, 2, 10)
		)


func _apply_door_frame(frame_idx: int) -> void:
	_current_frame = clampi(frame_idx, 0, DOOR_FRAME_COUNT - 1)
	if is_instance_valid(door_sprite):
		door_sprite.region_enabled = true
		door_sprite.region_rect = Rect2(
			float(_current_frame * DOOR_FRAME_SIZE.x),
			float(DOOR_ROW_Y),
			float(DOOR_FRAME_SIZE.x),
			float(DOOR_FRAME_SIZE.y)
		)


func _check_can_unlock() -> bool:
	var gs := get_node_or_null("/root/GameState")
	if gs != null and bool(gs.get("current_run_completed")):
		return true
	var map_gen: Node = get_tree().get_first_node_in_group("map_generator") if is_inside_tree() else null
	if map_gen != null and map_gen.has_method("is_boss_defeated"):
		if bool(map_gen.is_boss_defeated()):
			return true
		if map_gen.get("boss_room_node") != null and _has_living_boss():
			return false
	return not _has_living_boss()


func _has_living_boss() -> bool:
	if not is_inside_tree():
		return false
	var candidates: Array[Node] = []
	for enemy in get_tree().get_nodes_in_group("enemies"):
		if is_instance_valid(enemy):
			candidates.append(enemy)
	# Az eltűnt (vanished) Nekromanta átmenetileg kikerül az "enemies" csoportból,
	# ezért az Enemies tároló összes gyermekét is megvizsgáljuk.
	var scene := get_tree().current_scene
	if scene != null:
		var enemies_node := scene.get_node_or_null("Enemies")
		if enemies_node != null:
			for child in enemies_node.get_children():
				if is_instance_valid(child) and not candidates.has(child):
					candidates.append(child)
	for enemy in candidates:
		if not is_instance_valid(enemy) or enemy.is_queued_for_deletion():
			continue
		var alive: bool = true
		if enemy.has_method("is_monster_alive"):
			alive = bool(enemy.is_monster_alive())
		if not alive:
			continue
		var data := enemy.get("enemy_data") as EnemyData
		if data != null and (int(data.tier) == EnemyData.EnemyTier.BOSS or int(data.special_profile) == 4):
			return true
	return false


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
	if not is_instance_valid(interaction_hitbox) or interaction_hitbox.shape == null:
		return global_position.distance_to(hero.global_position) <= 36.0

	var local_pt: Vector2 = interaction_hitbox.to_local(hero.global_position)
	if interaction_hitbox.shape is RectangleShape2D:
		var rect_shape := interaction_hitbox.shape as RectangleShape2D
		var half: Vector2 = rect_shape.size * 0.5
		return absf(local_pt.x) <= half.x and absf(local_pt.y) <= half.y
	if interaction_hitbox.shape is CircleShape2D:
		var circle_shape := interaction_hitbox.shape as CircleShape2D
		return local_pt.length() <= circle_shape.radius
	return local_pt.length() <= 32.0


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
	return false
