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

@onready var tile_info_label: Label = find_child("TileInfoLabel", true, false) as Label

# Mini-térkép komponensek
@onready var minimap_canvas: Control = find_child("MinimapCanvas", true, false) as Control
@onready var minimap_coords_label: Label = find_child("MinimapCoordsLabel", true, false) as Label

# Teljes képernyős térkép komponensek
@onready var fullscreen_map_overlay: Control = find_child("FullscreenMapOverlay", true, false) as Control
@onready var big_map_canvas: Control = find_child("BigMapCanvas", true, false) as Control
@onready var big_map_coords: Label = find_child("BigMapCoords", true, false) as Label
@onready var close_map_button: Button = find_child("CloseMapButton", true, false) as Button

var cached_hero: HeroController = null
var last_minimap_pos: Vector2i = Vector2i(-99999, -99999)

# Pixel-art térkép méretek
var minimap_tile_size: float = 7.0
var minimap_view_radius: int = 12
var big_map_tile_size: float = 12.0

func _ready() -> void:
	add_to_group("hud")

	if minimap_canvas and not minimap_canvas.draw.is_connected(_on_minimap_draw):
		minimap_canvas.draw.connect(_on_minimap_draw)

	if big_map_canvas and not big_map_canvas.draw.is_connected(_on_big_map_draw):
		big_map_canvas.draw.connect(_on_big_map_draw)

	if close_map_button and not close_map_button.pressed.is_connected(_on_close_map_pressed):
		close_map_button.pressed.connect(_on_close_map_pressed)

	if fullscreen_map_overlay:
		fullscreen_map_overlay.visible = false

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_M:
			toggle_fullscreen_map()
			get_viewport().set_input_as_handled()
		elif event.keycode == KEY_ESCAPE and is_fullscreen_map_open():
			toggle_fullscreen_map(false)
			get_viewport().set_input_as_handled()

func toggle_fullscreen_map(force_state: Variant = null) -> void:
	if not is_instance_valid(fullscreen_map_overlay):
		return

	if force_state != null:
		fullscreen_map_overlay.visible = bool(force_state)
	else:
		fullscreen_map_overlay.visible = not fullscreen_map_overlay.visible

	if fullscreen_map_overlay.visible:
		_update_coords()
		if big_map_canvas:
			big_map_canvas.queue_redraw()

func is_fullscreen_map_open() -> bool:
	return is_instance_valid(fullscreen_map_overlay) and fullscreen_map_overlay.visible

func _on_close_map_pressed() -> void:
	toggle_fullscreen_map(false)

func _process(_delta: float) -> void:
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
		var c_name = hero.active_class.class_name_id if hero.active_class else "Kardforgató"
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

	if minimap_canvas:
		minimap_canvas.queue_redraw()
	if is_fullscreen_map_open() and big_map_canvas:
		big_map_canvas.queue_redraw()

func _update_coords() -> void:
	if not is_instance_valid(cached_hero):
		return
	if tile_info_label:
		var tile_desc = _get_current_tile_description(cached_hero)
		tile_info_label.text = "📍 Mező: (%d, %d) - %s" % [cached_hero.grid_pos.x, cached_hero.grid_pos.y, tile_desc]
	if minimap_coords_label:
		minimap_coords_label.text = "[%d, %d]" % [cached_hero.grid_pos.x, cached_hero.grid_pos.y]
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
			if fow and fow.torch_cells.has(cell):
				var torch_rect = Rect2(floor(draw_pos.x + 2), floor(draw_pos.y + 2), 3, 3)
				minimap_canvas.draw_rect(torch_rect, Color(1.0, 0.85, 0.25, 1.0), true)

	# 3. Élő, látható szörnyek jelölése (4x4 pixel vörös négyzet)
	for enemy in get_tree().get_nodes_in_group("enemies"):
		if is_instance_valid(enemy) and enemy.has_method("is_monster_alive") and enemy.is_monster_alive():
			var edx = enemy.grid_pos.x - hero_pos.x
			var edy = enemy.grid_pos.y - hero_pos.y
			if absi(edx) <= minimap_view_radius and absi(edy) <= minimap_view_radius:
				if fow == null or not fow.is_initialized or fow.current_visible_cells.has(enemy.grid_pos):
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

## Teljes képernyős nagy négyzet térkép kirajzolása (M gomb)
func _on_big_map_draw() -> void:
	if not is_instance_valid(big_map_canvas):
		return

	var canvas_size: Vector2 = big_map_canvas.size
	var center: Vector2 = Vector2(floor(canvas_size.x / 2.0), floor(canvas_size.y / 2.0))

	# 1. Háttér kitöltése
	big_map_canvas.draw_rect(Rect2(Vector2.ZERO, canvas_size), Color(0.04, 0.05, 0.08, 1.0), true)

	if not is_instance_valid(cached_hero):
		return

	var hero_pos: Vector2i = cached_hero.grid_pos
	var fow = cached_hero.fog_of_war
	var fl = cached_hero.floor_layer
	var wl = cached_hero.wall_layer
	var dl = cached_hero.decoratives_layer

	var view_r_x: int = int(canvas_size.x / (2.0 * big_map_tile_size)) + 1
	var view_r_y: int = int(canvas_size.y / (2.0 * big_map_tile_size)) + 1
	var half_tile: Vector2 = Vector2(floor(big_map_tile_size / 2.0), floor(big_map_tile_size / 2.0))

	# 2. Rácscellák kirajzolása (pixel-art blokkok nagy méretben)
	for dy in range(-view_r_y, view_r_y + 1):
		for dx in range(-view_r_x, view_r_x + 1):
			var cell = hero_pos + Vector2i(dx, dy)
			var draw_pos = Vector2(floor(center.x + dx * big_map_tile_size - half_tile.x), floor(center.y + dy * big_map_tile_size - half_tile.y))
			var tile_rect = Rect2(draw_pos, Vector2(big_map_tile_size, big_map_tile_size))

			var is_floor_tile = (fl and fl.get_cell_source_id(cell) != -1) or (dl and dl.get_cell_source_id(cell) != -1)
			var is_wall_tile = (wl and wl.get_cell_source_id(cell) != -1)

			if not is_floor_tile and not is_wall_tile:
				continue

			if fow and fow.is_initialized:
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

			# Fáklyák jelölése (4x4 pixel aranysárga négyzet)
			if fow and fow.torch_cells.has(cell):
				var torch_rect = Rect2(floor(draw_pos.x + (big_map_tile_size - 4.0) / 2.0), floor(draw_pos.y + (big_map_tile_size - 4.0) / 2.0), 4.0, 4.0)
				big_map_canvas.draw_rect(torch_rect, Color(1.0, 0.85, 0.25, 1.0), true)

	# 3. Élő, látható szörnyek jelölése (6x6 vörös pixel négyzet)
	for enemy in get_tree().get_nodes_in_group("enemies"):
		if is_instance_valid(enemy) and enemy.has_method("is_monster_alive") and enemy.is_monster_alive():
			var edx = enemy.grid_pos.x - hero_pos.x
			var edy = enemy.grid_pos.y - hero_pos.y
			if absi(edx) <= view_r_x and absi(edy) <= view_r_y:
				if fow == null or not fow.is_initialized or fow.current_visible_cells.has(enemy.grid_pos):
					var ex = floor(center.x + edx * big_map_tile_size)
					var ey = floor(center.y + edy * big_map_tile_size)
					big_map_canvas.draw_rect(Rect2(ex - 3, ey - 3, 6, 6), Color(0.95, 0.15, 0.22, 1.0), true)
					big_map_canvas.draw_rect(Rect2(ex - 1, ey - 1, 2, 2), Color(1.0, 0.8, 0.8, 1.0), true)

	# 4. Hős jelölése a térkép középpontjában (retro pixel marker)
	var hx = center.x
	var hy = center.y
	big_map_canvas.draw_rect(Rect2(hx - 5, hy - 5, 10, 10), Color(0.10, 0.90, 1.0, 1.0), true)
	big_map_canvas.draw_rect(Rect2(hx - 3, hy - 3, 6, 6), Color(1.0, 1.0, 1.0, 1.0), true)
	big_map_canvas.draw_rect(Rect2(hx - 1, hy - 1, 2, 2), Color(0.10, 0.90, 1.0, 1.0), true)
	big_map_canvas.draw_rect(Rect2(hx - 7, hy - 7, 14, 14), Color(0.05, 0.35, 0.50, 0.8), false, 1.0)

	# 5. Célkereszt vonalak (pixel-art)
	var border_col = Color(0.50, 0.58, 0.72, 0.40)
	big_map_canvas.draw_line(Vector2(hx, 0), Vector2(hx, canvas_size.y), border_col, 1.0)
	big_map_canvas.draw_line(Vector2(0, hy), Vector2(canvas_size.x, hy), border_col, 1.0)
	big_map_canvas.draw_rect(Rect2(Vector2.ZERO, canvas_size), border_col, false, 2.0)
