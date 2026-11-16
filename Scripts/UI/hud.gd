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
@onready var class_ability_container: Control = find_child("ClassAbilityContainer", true, false) as Control
@onready var class_ability_bar: ProgressBar = find_child("ClassAbilityBar", true, false) as ProgressBar
@onready var class_ability_label: Label = find_child("ClassAbilityLabel", true, false) as Label

@onready var tile_info_label: Label = find_child("TileInfoLabel", true, false) as Label

# Mini-térkép komponensek
@onready var minimap_canvas: Control = find_child("MinimapCanvas", true, false) as Control

# Teljes képernyős térkép komponensek
@onready var fullscreen_map_overlay: Control = find_child("FullscreenMapOverlay", true, false) as Control
@onready var big_map_canvas: Control = find_child("BigMapCanvas", true, false) as Control
@onready var big_map_coords: Label = find_child("BigMapCoords", true, false) as Label
@onready var close_map_button: Button = find_child("CloseMapButton", true, false) as Button
@onready var pause_button: Button = find_child("PauseButton", true, false) as Button

const BIG_MAP_DEFAULT_TILE_SIZE: float = 12.0
const BIG_MAP_MIN_TILE_SIZE: float = 8.0
const BIG_MAP_MAX_TILE_SIZE: float = 20.0
const BIG_MAP_ZOOM_STEP: float = 2.0
const BIG_MAP_MAX_PAN_PIXELS: float = 700.0

var cached_hero: HeroController = null
var last_minimap_pos: Vector2i = Vector2i(-99999, -99999)
var _battle_lock: bool = false

# Pixel-art térkép méretek
var minimap_tile_size: float = 7.0
var minimap_view_radius: int = 12
var big_map_tile_size: float = BIG_MAP_DEFAULT_TILE_SIZE
var big_map_pan: Vector2 = Vector2.ZERO
var _big_map_dragging: bool = false
var _ability_fill_style: StyleBoxFlat = null
var _last_ability_style_key: String = ""

func _ready() -> void:
	add_to_group("hud")
	# Ensure HUD is visible at runtime even if hidden in the Godot editor while editing scenes.
	visible = not _battle_lock

	if class_ability_bar:
		var base_fill := class_ability_bar.get_theme_stylebox("fill") as StyleBoxFlat
		if base_fill:
			_ability_fill_style = base_fill.duplicate() as StyleBoxFlat
			class_ability_bar.add_theme_stylebox_override("fill", _ability_fill_style)

	if minimap_canvas and not minimap_canvas.draw.is_connected(_on_minimap_draw):
		minimap_canvas.draw.connect(_on_minimap_draw)

	if big_map_canvas:
		big_map_canvas.mouse_filter = Control.MOUSE_FILTER_STOP
		if not big_map_canvas.draw.is_connected(_on_big_map_draw):
			big_map_canvas.draw.connect(_on_big_map_draw)
		if not big_map_canvas.gui_input.is_connected(_on_big_map_gui_input):
			big_map_canvas.gui_input.connect(_on_big_map_gui_input)

	if fullscreen_map_overlay:
		fullscreen_map_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
		if not fullscreen_map_overlay.gui_input.is_connected(_on_fullscreen_map_overlay_gui_input):
			fullscreen_map_overlay.gui_input.connect(_on_fullscreen_map_overlay_gui_input)
		var big_map_panel := fullscreen_map_overlay.find_child("BigMapPanel", true, false) as Control
		if big_map_panel and not big_map_panel.gui_input.is_connected(_on_fullscreen_map_overlay_gui_input):
			big_map_panel.gui_input.connect(_on_fullscreen_map_overlay_gui_input)

	if close_map_button and not close_map_button.pressed.is_connected(_on_close_map_pressed):
		close_map_button.pressed.connect(_on_close_map_pressed)

	if pause_button and not pause_button.pressed.is_connected(_on_pause_pressed):
		pause_button.pressed.connect(_on_pause_pressed)

	if fullscreen_map_overlay:
		fullscreen_map_overlay.visible = false

## Harc vagy halálképernyő közben elrejti a teljes HUD-ot és letiltja a térkép nyitást
func set_battle_mode(in_battle: bool) -> void:
	_battle_lock = in_battle
	if in_battle:
		if is_fullscreen_map_open():
			fullscreen_map_overlay.visible = false
		visible = false
	else:
		visible = true
		if is_instance_valid(cached_hero):
			refresh_stats(cached_hero)

func _is_map_blocked() -> bool:
	var tree := get_tree()
	if _battle_lock or not visible or tree == null or tree.paused:
		return true
	var dm := get_node_or_null("/root/DungeonManager")
	if dm != null and dm.has_method("is_loading_dungeon") and dm.is_loading_dungeon():
		return true
	var pause_ui := tree.get_first_node_in_group("pause_menu")
	if pause_ui != null and pause_ui.visible:
		return true
	var battle_ui := tree.get_first_node_in_group("battle_ui")
	if battle_ui != null and bool(battle_ui.get("combat_active")):
		return true
	if is_instance_valid(cached_hero) and (not cached_hero.is_alive() or cached_hero.in_battle):
		return true
	return false

func _on_pause_pressed() -> void:
	var dm := get_node_or_null("/root/DungeonManager")
	if dm != null and dm.has_method("is_loading_dungeon") and dm.is_loading_dungeon():
		return
	var pause_ui := get_tree().get_first_node_in_group("pause_menu")
	if pause_ui == null and ResourceLoader.exists("res://Scenes/UI/pause_menu.tscn"):
		var packed := load("res://Scenes/UI/pause_menu.tscn") as PackedScene
		if packed != null:
			pause_ui = packed.instantiate()
			get_tree().current_scene.add_child(pause_ui)
	if pause_ui != null and pause_ui.has_method("open_pause"):
		pause_ui.open_pause()

func _mark_input_handled() -> void:
	if not is_inside_tree():
		return
	var vp := get_viewport()
	if vp != null and vp.is_inside_tree():
		vp.set_input_as_handled()

func _unhandled_input(event: InputEvent) -> void:
	if not is_inside_tree() or _is_map_blocked():
		return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_M:
			toggle_fullscreen_map()
			_mark_input_handled()
		elif event.keycode == KEY_ESCAPE and is_fullscreen_map_open():
			toggle_fullscreen_map(false)
			_mark_input_handled()
	elif is_fullscreen_map_open() and (event is InputEventMouseButton or event is InputEventMouseMotion):
		_mark_input_handled()

func toggle_fullscreen_map(force_state: Variant = null) -> void:
	if not is_instance_valid(fullscreen_map_overlay):
		return

	var want_open := not fullscreen_map_overlay.visible if force_state == null else bool(force_state)
	if want_open and _is_map_blocked():
		return

	fullscreen_map_overlay.visible = want_open
	_big_map_dragging = false

	if fullscreen_map_overlay.visible:
		big_map_pan = Vector2.ZERO
		_update_coords()
		if big_map_canvas:
			big_map_canvas.queue_redraw()

var _pause_menu_ensured: bool = false

func ensure_pause_menu() -> Node:
	var existing := get_tree().get_first_node_in_group("pause_menu")
	if is_instance_valid(existing):
		return existing

	var packed := load("res://Scenes/UI/pause_menu.tscn") as PackedScene
	if packed == null:
		return null

	var pause_ui := packed.instantiate()
	var host: Node = get_tree().current_scene
	if host == null:
		host = get_parent()
	if host == null:
		host = self
	host.add_child(pause_ui)
	return pause_ui

func is_fullscreen_map_open() -> bool:
	return is_instance_valid(fullscreen_map_overlay) and fullscreen_map_overlay.visible

func _on_close_map_pressed() -> void:
	toggle_fullscreen_map(false)

func _process(_delta: float) -> void:
	if not _pause_menu_ensured:
		_pause_menu_ensured = true
		ensure_pause_menu()
		if is_instance_valid(pause_button):
			pause_button.focus_mode = Control.FOCUS_NONE

	if not is_instance_valid(cached_hero):
		_find_player()

	if is_instance_valid(cached_hero):
		if cached_hero.grid_pos != last_minimap_pos:
			last_minimap_pos = cached_hero.grid_pos
			_update_coords()
			if minimap_canvas:
				minimap_canvas.queue_redraw()
			if is_fullscreen_map_open() and big_map_canvas:
				big_map_canvas.queue_redraw()
		_update_class_ability_indicator()

func _find_player() -> void:
	var player = get_tree().get_first_node_in_group("player") as HeroController
	if is_instance_valid(player):
		cached_hero = player
		refresh_stats(player)

## A hős állapotának kirajzolása a felületre
func refresh_stats(hero: HeroController) -> void:
	if not is_instance_valid(hero):
		return

	cached_hero = hero

	# 1. Hős Neve
	if hero_title_label:
		hero_title_label.text = hero.hero_name

	# 2. Kaszt és Aktuális szint
	if class_level_label:
		var c_name = hero.active_class.class_name_id if hero.active_class else "Kalandor"
		class_level_label.text = "%s  •  Szint %d" % [c_name, hero.level]

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
		atk_label.text = "⚔️ Támadás: %d" % hero.attack_power
	if def_label:
		def_label.text = "🛡️ Védelem: %d" % hero.get_defense()
	if init_label:
		init_label.text = "⚡ Kezdeményezés: %.1f" % hero.get_initiative()
	if vision_label:
		vision_label.text = "👁️ Látótáv: %d (5x5)" % hero.vision_limit

	# 6. Aktuális mező információ
	_update_coords()
	_update_class_ability_indicator()

	if minimap_canvas:
		minimap_canvas.queue_redraw()
	if is_fullscreen_map_open() and big_map_canvas:
		big_map_canvas.queue_redraw()

func _apply_ability_bar_colors(style_key: String, fill_col: Color, border_col: Color, label_col: Color) -> void:
	if _last_ability_style_key == style_key:
		return
	_last_ability_style_key = style_key
	if _ability_fill_style:
		_ability_fill_style.bg_color = fill_col
		_ability_fill_style.border_color = border_col
	if class_ability_label:
		class_ability_label.add_theme_color_override("font_color", label_col)

func _update_class_ability_indicator() -> void:
	if not is_instance_valid(class_ability_container) or not is_instance_valid(cached_hero):
		if is_instance_valid(class_ability_container):
			class_ability_container.visible = false
		return

	var c_name: String = cached_hero.active_class.class_name_id if cached_hero.active_class else ""
	var hero_combat := cached_hero.combat

	if c_name == "Wizard" and hero_combat:
		class_ability_container.visible = true
		var is_ice: bool = hero_combat.wizard_element == "ice"
		if class_ability_bar:
			class_ability_bar.max_value = 1.0
			class_ability_bar.value = 1.0
		if is_ice:
			_apply_ability_bar_colors("wizard_ice", Color(0.18, 0.56, 0.85, 0.88), Color(0.55, 0.90, 1.0, 1.0), Color(0.86, 0.97, 1.0, 1.0))
			if class_ability_label:
				class_ability_label.text = "❄️ Elem: Jég  [F]"
		else:
			_apply_ability_bar_colors("wizard_fire", Color(0.85, 0.30, 0.12, 0.90), Color(1.0, 0.62, 0.25, 1.0), Color(1.0, 0.93, 0.82, 1.0))
			if class_ability_label:
				class_ability_label.text = "🔥 Elem: Tűz  [F]"
	elif c_name == "Priest" and hero_combat:
		class_ability_container.visible = true
		var cd: float = hero_combat.get_priest_heal_cooldown_remaining()
		var dur: float = hero_combat.get_priest_heal_cooldown_duration()
		if class_ability_bar:
			class_ability_bar.max_value = maxf(0.1, dur)
			class_ability_bar.value = clampf(dur - cd, 0.0, dur)
		if cd > 0.01:
			_apply_ability_bar_colors("priest_cd", Color(0.75, 0.55, 0.16, 0.88), Color(0.95, 0.78, 0.35, 1.0), Color(1.0, 0.94, 0.75, 1.0))
			if class_ability_label:
				class_ability_label.text = "⏳ Gyógyítás: %.1f mp  [H]" % cd
		else:
			_apply_ability_bar_colors("priest_ready", Color(0.16, 0.62, 0.36, 0.88), Color(0.45, 0.92, 0.62, 1.0), Color(0.86, 1.0, 0.90, 1.0))
			if class_ability_label:
				class_ability_label.text = "💚 Gyógyítás kész  [H]"
	else:
		class_ability_container.visible = false
		_last_ability_style_key = ""

func _update_coords() -> void:
	if not is_instance_valid(cached_hero):
		return
	if tile_info_label:
		var tile_desc = _get_current_tile_description(cached_hero)
		tile_info_label.text = "📍 Mező: (%d, %d) - %s" % [cached_hero.grid_pos.x, cached_hero.grid_pos.y, tile_desc]
	if big_map_coords:
		big_map_coords.text = "Pozíció: [%d, %d]" % [cached_hero.grid_pos.x, cached_hero.grid_pos.y]

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

## Négyzetes mini-térkép kirajzolása (Pixel-Art stílusban, simítás nélkül)
func _on_minimap_draw() -> void:
	if not is_instance_valid(minimap_canvas):
		return

	var canvas_size: Vector2 = minimap_canvas.size
	var center: Vector2 = Vector2(floor(canvas_size.x / 2.0), floor(canvas_size.y / 2.0))

	# 1. Háttér kitöltése (sötét pixel háttér)
	minimap_canvas.draw_rect(Rect2(Vector2.ZERO, canvas_size), Color(0.04, 0.05, 0.08, 0.96), true)

	if not is_instance_valid(cached_hero):
		return

	var hero_pos: Vector2i = cached_hero.grid_pos
	var fow = cached_hero.fog_of_war
	var fl = cached_hero.floor_layer
	var wl = cached_hero.wall_layer
	var dl = cached_hero.decoratives_layer

	var half_tile: Vector2 = Vector2(floor(minimap_tile_size / 2.0), floor(minimap_tile_size / 2.0))

	# 2. Rácscellák kirajzolása (pixel-art blokkok)
	for dy in range(-minimap_view_radius, minimap_view_radius + 1):
		for dx in range(-minimap_view_radius, minimap_view_radius + 1):
			var cell = hero_pos + Vector2i(dx, dy)
			var draw_pos = Vector2(floor(center.x + dx * minimap_tile_size - half_tile.x), floor(center.y + dy * minimap_tile_size - half_tile.y))
			var tile_rect = Rect2(draw_pos, Vector2(minimap_tile_size, minimap_tile_size))

			var is_floor_tile = (fl and fl.get_cell_source_id(cell) != -1) or (dl and dl.get_cell_source_id(cell) != -1)
			var is_wall_tile = (wl and wl.get_cell_source_id(cell) != -1)

			if not is_floor_tile and not is_wall_tile:
				continue

			if fow and fow.is_initialized:
				if not fow.is_cell_map_discovered(cell):
					continue
				var state = fow.cell_states.get(cell, FogOfWar.CellState.UNEXPLORED)
				if state == FogOfWar.CellState.UNEXPLORED:
					continue
				elif state == FogOfWar.CellState.VISIBLE:
					if is_floor_tile:
						minimap_canvas.draw_rect(tile_rect, Color(0.55, 0.63, 0.77, 0.98), true)
					elif is_wall_tile:
						minimap_canvas.draw_rect(tile_rect, Color(0.20, 0.23, 0.32, 0.98), true)
				elif state == FogOfWar.CellState.IN_FOG:
					if is_floor_tile:
						minimap_canvas.draw_rect(tile_rect, Color(0.24, 0.28, 0.38, 0.85), true)
					elif is_wall_tile:
						minimap_canvas.draw_rect(tile_rect, Color(0.12, 0.14, 0.20, 0.90), true)
			else:
				if is_floor_tile:
					minimap_canvas.draw_rect(tile_rect, Color(0.42, 0.50, 0.65, 0.90), true)
				elif is_wall_tile:
					minimap_canvas.draw_rect(tile_rect, Color(0.16, 0.18, 0.25, 0.95), true)

			# Fáklyák jelölése (3x3 pixel aranysárga négyzet)
			if fow and fow.is_torch_discovered(cell):
				var torch_rect = Rect2(floor(draw_pos.x + 2), floor(draw_pos.y + 2), 3, 3)
				minimap_canvas.draw_rect(torch_rect, Color(1.0, 0.85, 0.25, 1.0), true)

	# 3. Élő, látható szörnyek jelölése (4x4 pixel vörös négyzet)
	for enemy in get_tree().get_nodes_in_group("enemies"):
		if is_instance_valid(enemy) and enemy.has_method("is_monster_alive") and enemy.is_monster_alive():
			var edx = enemy.grid_pos.x - hero_pos.x
			var edy = enemy.grid_pos.y - hero_pos.y
			if absi(edx) <= minimap_view_radius and absi(edy) <= minimap_view_radius:
				if fow == null or not fow.is_initialized or (fow.is_cell_map_discovered(enemy.grid_pos) and fow.current_visible_cells.has(enemy.grid_pos)):
					var ex = floor(center.x + edx * minimap_tile_size)
					var ey = floor(center.y + edy * minimap_tile_size)
					minimap_canvas.draw_rect(Rect2(ex - 2, ey - 2, 4, 4), Color(0.95, 0.15, 0.22, 1.0), true)
					minimap_canvas.draw_rect(Rect2(ex - 1, ey - 1, 2, 2), Color(1.0, 0.8, 0.8, 1.0), true)

	# 4. Hős jelölése a térkép középpontjában (pixel-art retro marker)
	var hx = center.x
	var hy = center.y
	minimap_canvas.draw_rect(Rect2(hx - 3, hy - 3, 6, 6), Color(0.10, 0.90, 1.0, 1.0), true)
	minimap_canvas.draw_rect(Rect2(hx - 1, hy - 1, 2, 2), Color(1.0, 1.0, 1.0, 1.0), true)
	minimap_canvas.draw_rect(Rect2(hx - 4, hy - 4, 8, 8), Color(0.05, 0.35, 0.50, 0.8), false, 1.0)

	# 5. Négyzetes finom pixel keret
	var border_col = Color(0.45, 0.52, 0.68, 0.6)
	minimap_canvas.draw_rect(Rect2(Vector2.ZERO, canvas_size), border_col, false, 2.0)
	minimap_canvas.draw_line(Vector2(hx, 0), Vector2(hx, 6), border_col, 1.0)
	minimap_canvas.draw_line(Vector2(hx, canvas_size.y - 6), Vector2(hx, canvas_size.y), border_col, 1.0)
	minimap_canvas.draw_line(Vector2(0, hy), Vector2(6, hy), border_col, 1.0)
	minimap_canvas.draw_line(Vector2(canvas_size.x - 6, hy), Vector2(canvas_size.x, hy), border_col, 1.0)

func _on_fullscreen_map_overlay_gui_input(event: InputEvent) -> void:
	if not is_fullscreen_map_open() or not is_instance_valid(big_map_canvas):
		return
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_zoom_big_map(BIG_MAP_ZOOM_STEP, big_map_canvas.size * 0.5)
			fullscreen_map_overlay.accept_event()
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_zoom_big_map(-BIG_MAP_ZOOM_STEP, big_map_canvas.size * 0.5)
			fullscreen_map_overlay.accept_event()
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
		_big_map_dragging = false

func _on_big_map_gui_input(event: InputEvent) -> void:
	if not is_fullscreen_map_open() or not is_instance_valid(big_map_canvas):
		return
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			_big_map_dragging = event.pressed
			big_map_canvas.accept_event()
		elif event.pressed and event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_zoom_big_map(BIG_MAP_ZOOM_STEP, event.position)
			big_map_canvas.accept_event()
		elif event.pressed and event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_zoom_big_map(-BIG_MAP_ZOOM_STEP, event.position)
			big_map_canvas.accept_event()
	elif event is InputEventMouseMotion and _big_map_dragging:
		if not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
			_big_map_dragging = false
			return
		big_map_pan = (big_map_pan + event.relative).clamp(
			Vector2(-BIG_MAP_MAX_PAN_PIXELS, -BIG_MAP_MAX_PAN_PIXELS),
			Vector2(BIG_MAP_MAX_PAN_PIXELS, BIG_MAP_MAX_PAN_PIXELS)
		)
		big_map_canvas.queue_redraw()
		big_map_canvas.accept_event()

func _zoom_big_map(delta_tile: float, anchor_local: Vector2) -> void:
	if not is_instance_valid(big_map_canvas):
		return
	var old_tile := big_map_tile_size
	var new_tile := clampf(old_tile + delta_tile, BIG_MAP_MIN_TILE_SIZE, BIG_MAP_MAX_TILE_SIZE)
	if is_equal_approx(new_tile, old_tile):
		return
	var center := Vector2(floor(big_map_canvas.size.x / 2.0), floor(big_map_canvas.size.y / 2.0))
	var scale_ratio := new_tile / old_tile
	big_map_pan = (anchor_local - center - (anchor_local - center - big_map_pan) * scale_ratio).clamp(
		Vector2(-BIG_MAP_MAX_PAN_PIXELS, -BIG_MAP_MAX_PAN_PIXELS),
		Vector2(BIG_MAP_MAX_PAN_PIXELS, BIG_MAP_MAX_PAN_PIXELS)
	)
	big_map_tile_size = new_tile
	big_map_canvas.queue_redraw()

## Teljes képernyős nagy négyzet térkép kirajzolása (M gomb)
func _on_big_map_draw() -> void:
	if not is_instance_valid(big_map_canvas):
		return

	var canvas_size: Vector2 = big_map_canvas.size
	var center: Vector2 = Vector2(floor(canvas_size.x / 2.0), floor(canvas_size.y / 2.0))
	var map_origin: Vector2 = Vector2(floor(center.x + big_map_pan.x), floor(center.y + big_map_pan.y))

	# 1. Háttér kitöltése
	big_map_canvas.draw_rect(Rect2(Vector2.ZERO, canvas_size), Color(0.04, 0.05, 0.08, 1.0), true)

	if not is_instance_valid(cached_hero):
		return

	var hero_pos: Vector2i = cached_hero.grid_pos
	var fow = cached_hero.fog_of_war
	var fl = cached_hero.floor_layer
	var wl = cached_hero.wall_layer
	var dl = cached_hero.decoratives_layer

	var min_dx: int = floori((-map_origin.x) / big_map_tile_size) - 1
	var max_dx: int = ceili((canvas_size.x - map_origin.x) / big_map_tile_size) + 1
	var min_dy: int = floori((-map_origin.y) / big_map_tile_size) - 1
	var max_dy: int = ceili((canvas_size.y - map_origin.y) / big_map_tile_size) + 1
	var half_tile: Vector2 = Vector2(floor(big_map_tile_size / 2.0), floor(big_map_tile_size / 2.0))
	var torch_size: float = clampf(floor(big_map_tile_size * 0.35), 3.0, 7.0)

	# 2. Rácscellák kirajzolása (pixel-art blokkok nagy méretben)
	for dy in range(min_dy, max_dy + 1):
		for dx in range(min_dx, max_dx + 1):
			var cell = hero_pos + Vector2i(dx, dy)
			var draw_pos = Vector2(floor(map_origin.x + dx * big_map_tile_size - half_tile.x), floor(map_origin.y + dy * big_map_tile_size - half_tile.y))
			var tile_rect = Rect2(draw_pos, Vector2(big_map_tile_size, big_map_tile_size))

			var is_floor_tile = (fl and fl.get_cell_source_id(cell) != -1) or (dl and dl.get_cell_source_id(cell) != -1)
			var is_wall_tile = (wl and wl.get_cell_source_id(cell) != -1)

			if not is_floor_tile and not is_wall_tile:
				continue

			if fow and fow.is_initialized:
				if not fow.is_cell_map_discovered(cell):
					continue
				var state = fow.cell_states.get(cell, FogOfWar.CellState.UNEXPLORED)
				if state == FogOfWar.CellState.UNEXPLORED:
					continue
				elif state == FogOfWar.CellState.VISIBLE:
					if is_floor_tile:
						big_map_canvas.draw_rect(tile_rect, Color(0.55, 0.63, 0.77, 0.98), true)
						big_map_canvas.draw_rect(tile_rect, Color(0.42, 0.48, 0.60, 0.35), false, 1.0)
					elif is_wall_tile:
						big_map_canvas.draw_rect(tile_rect, Color(0.20, 0.23, 0.32, 0.98), true)
				elif state == FogOfWar.CellState.IN_FOG:
					if is_floor_tile:
						big_map_canvas.draw_rect(tile_rect, Color(0.24, 0.28, 0.38, 0.85), true)
					elif is_wall_tile:
						big_map_canvas.draw_rect(tile_rect, Color(0.12, 0.14, 0.20, 0.90), true)
			else:
				if is_floor_tile:
					big_map_canvas.draw_rect(tile_rect, Color(0.42, 0.50, 0.65, 0.90), true)
				elif is_wall_tile:
					big_map_canvas.draw_rect(tile_rect, Color(0.16, 0.18, 0.25, 0.95), true)

			# Fáklyák jelölése (aranysárga négyzet)
			if fow and fow.is_torch_discovered(cell):
				var torch_rect = Rect2(floor(draw_pos.x + (big_map_tile_size - torch_size) / 2.0), floor(draw_pos.y + (big_map_tile_size - torch_size) / 2.0), torch_size, torch_size)
				big_map_canvas.draw_rect(torch_rect, Color(1.0, 0.85, 0.25, 1.0), true)

	# 3. Élő, látható szörnyek jelölése (vörös pixel négyzet)
	for enemy in get_tree().get_nodes_in_group("enemies"):
		if is_instance_valid(enemy) and enemy.has_method("is_monster_alive") and enemy.is_monster_alive():
			var edx = enemy.grid_pos.x - hero_pos.x
			var edy = enemy.grid_pos.y - hero_pos.y
			if edx >= min_dx and edx <= max_dx and edy >= min_dy and edy <= max_dy:
				if fow == null or not fow.is_initialized or (fow.is_cell_map_discovered(enemy.grid_pos) and fow.current_visible_cells.has(enemy.grid_pos)):
					var ex = floor(map_origin.x + edx * big_map_tile_size)
					var ey = floor(map_origin.y + edy * big_map_tile_size)
					big_map_canvas.draw_rect(Rect2(ex - 3, ey - 3, 6, 6), Color(0.95, 0.15, 0.22, 1.0), true)
					big_map_canvas.draw_rect(Rect2(ex - 1, ey - 1, 2, 2), Color(1.0, 0.8, 0.8, 1.0), true)

	# 4. Hős jelölése a térképen (retro pixel marker)
	var hx = map_origin.x
	var hy = map_origin.y
	big_map_canvas.draw_rect(Rect2(hx - 5, hy - 5, 10, 10), Color(0.10, 0.90, 1.0, 1.0), true)
	big_map_canvas.draw_rect(Rect2(hx - 3, hy - 3, 6, 6), Color(1.0, 1.0, 1.0, 1.0), true)
	big_map_canvas.draw_rect(Rect2(hx - 1, hy - 1, 2, 2), Color(0.10, 0.90, 1.0, 1.0), true)
	big_map_canvas.draw_rect(Rect2(hx - 7, hy - 7, 14, 14), Color(0.05, 0.35, 0.50, 0.8), false, 1.0)

	# 5. Célkereszt vonalak (pixel-art)
	var border_col = Color(0.50, 0.58, 0.72, 0.40)
	big_map_canvas.draw_line(Vector2(hx, 0), Vector2(hx, canvas_size.y), border_col, 1.0)
	big_map_canvas.draw_line(Vector2(0, hy), Vector2(canvas_size.x, hy), border_col, 1.0)
	big_map_canvas.draw_rect(Rect2(Vector2.ZERO, canvas_size), border_col, false, 2.0)
