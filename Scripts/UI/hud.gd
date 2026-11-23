extends CanvasLayer
class_name PlayerHUD

@onready var hero_portrait_badge: PanelContainer = find_child("IconBadge", true, false) as PanelContainer
@onready var hero_portrait_icon: TextureRect = find_child("IconTexture", true, false) as TextureRect
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
@onready var class_ability_icon: TextureRect = find_child("ClassAbilityIcon", true, false) as TextureRect
@onready var class_ability_label: Label = find_child("ClassAbilityLabel", true, false) as Label

@onready var tile_info_label: Label = find_child("TileInfoLabel", true, false) as Label

# Mini-térkép komponensek
@onready var minimap_margin: Control = find_child("MinimapMargin", true, false) as Control
@onready var minimap_canvas: Control = find_child("MinimapCanvas", true, false) as Control
@onready var pause_margin: Control = find_child("PauseMargin", true, false) as Control
@onready var backpack_margin: Control = find_child("BackpackMargin", true, false) as Control
@onready var potion_margin: Control = find_child("PotionMargin", true, false) as Control

# Teljes képernyős térkép komponensek
@onready var fullscreen_map_overlay: Control = find_child("FullscreenMapOverlay", true, false) as Control
@onready var big_map_canvas: Control = find_child("BigMapCanvas", true, false) as Control
@onready var big_map_coords: Label = find_child("BigMapCoords", true, false) as Label
@onready var close_map_button: Button = find_child("CloseMapButton", true, false) as Button
@onready var pause_button: Button = find_child("PauseButton", true, false) as Button
@onready var backpack_button: Button = find_child("BackpackButton", true, false) as Button
@onready var potion_button: Button = find_child("PotionButton", true, false) as Button
@onready var hud_toast_panel: PanelContainer = find_child("HudToastPanel", true, false) as PanelContainer
@onready var hud_toast_label: Label = find_child("HudToastLabel", true, false) as Label

const DUNGEON_BACKPACK_OVERLAY_SCRIPT := preload("res://Scripts/UI/dungeon_backpack_overlay.gd")
const DUNGEON_VICTORY_OVERLAY_SCRIPT := preload("res://Scripts/UI/dungeon_victory_overlay.gd")
const DUNGEON_LOOT_OVERLAY_SCRIPT := preload("res://Scripts/UI/dungeon_loot_overlay.gd")
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
var _backpack_overlay: DungeonBackpackOverlay = null
var _victory_overlay: DungeonVictoryOverlay = null
var _loot_overlay: DungeonLootOverlay = null
var _toast_timer: float = 0.0

func _exit_tree() -> void:
	var gs := get_node_or_null("/root/GameState")
	if gs != null and gs.has_signal("state_changed") and gs.state_changed.is_connected(_on_game_state_changed):
		gs.state_changed.disconnect(_on_game_state_changed)
	var sm := get_node_or_null("/root/SettingsManager")
	if sm != null and sm.has_signal("settings_changed") and sm.settings_changed.is_connected(_apply_hud_settings):
		sm.settings_changed.disconnect(_apply_hud_settings)

func _ready() -> void:
	add_to_group("hud")
	# Ensure HUD is visible at runtime even if hidden in the Godot editor while editing scenes.
	visible = not _battle_lock

	if hero_portrait_badge:
		var base_badge := hero_portrait_badge.get_theme_stylebox("panel") as StyleBoxFlat
		if base_badge != null:
			var portrait_style := base_badge.duplicate() as StyleBoxFlat
			portrait_style.content_margin_left = 3.0
			portrait_style.content_margin_top = 3.0
			portrait_style.content_margin_right = 3.0
			portrait_style.content_margin_bottom = 3.0
			hero_portrait_badge.add_theme_stylebox_override("panel", portrait_style)
	if hero_portrait_icon:
		hero_portrait_icon.custom_minimum_size = Vector2(32, 32)
		hero_portrait_icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST

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
		AudioManager.mark_custom_button_sfx(close_map_button)

	if pause_button and not pause_button.pressed.is_connected(_on_pause_pressed):
		pause_button.pressed.connect(_on_pause_pressed)
		pause_button.focus_mode = Control.FOCUS_NONE
		AudioManager.mark_custom_button_sfx(pause_button)

	if backpack_button and not backpack_button.pressed.is_connected(_on_backpack_pressed):
		backpack_button.pressed.connect(_on_backpack_pressed)
		backpack_button.focus_mode = Control.FOCUS_NONE
		AudioManager.mark_custom_button_sfx(backpack_button)

	if potion_button and not potion_button.pressed.is_connected(_on_potion_pressed):
		potion_button.pressed.connect(_on_potion_pressed)
		potion_button.focus_mode = Control.FOCUS_NONE
		AudioManager.mark_custom_button_sfx(potion_button)

	if hud_toast_panel:
		hud_toast_panel.visible = false

	if fullscreen_map_overlay:
		fullscreen_map_overlay.visible = false

	var gs := get_node_or_null("/root/GameState")
	if gs != null and gs.has_signal("state_changed") and not gs.state_changed.is_connected(_on_game_state_changed):
		gs.state_changed.connect(_on_game_state_changed)

	var sm := get_node_or_null("/root/SettingsManager")
	if sm != null and sm.has_signal("settings_changed") and not sm.settings_changed.is_connected(_apply_hud_settings):
		sm.settings_changed.connect(_apply_hud_settings)

	_apply_hud_settings()
	_refresh_potion_button()

## Harc vagy halálképernyő közben elrejti a teljes HUD-ot és letiltja a térkép nyitást
func set_battle_mode(in_battle: bool) -> void:
	_battle_lock = in_battle
	if in_battle:
		if is_fullscreen_map_open():
			fullscreen_map_overlay.visible = false
		if is_backpack_open():
			toggle_backpack(false)
		if hud_toast_panel:
			hud_toast_panel.visible = false
			_toast_timer = 0.0
		visible = false
	else:
		visible = true
		if is_instance_valid(cached_hero):
			refresh_stats(cached_hero)
		_refresh_potion_button()

func _is_map_blocked() -> bool:
	var tree := get_tree()
	if _battle_lock or not visible or tree == null or tree.paused:
		return true
	if is_backpack_open():
		return true
	var dm := get_node_or_null("/root/DungeonManager")
	if dm != null and dm.has_method("is_loading_dungeon") and dm.is_loading_dungeon():
		return true
	var pause_ui := tree.get_first_node_in_group("pause_menu")
	if pause_ui != null and pause_ui.visible:
		return true
	var victory_ui := tree.get_first_node_in_group("dungeon_victory")
	if victory_ui != null and victory_ui.visible:
		return true
	var loot_ui := tree.get_first_node_in_group("dungeon_loot")
	if loot_ui != null and loot_ui.visible:
		return true
	var battle_ui := tree.get_first_node_in_group("battle_ui")
	if battle_ui != null and bool(battle_ui.get("combat_active")):
		return true
	if is_instance_valid(cached_hero) and (not cached_hero.is_alive() or cached_hero.in_battle):
		return true
	return false

func _on_backpack_pressed() -> void:
	toggle_backpack()

func _on_potion_pressed() -> void:
	use_quick_health_potion()

func _on_game_state_changed() -> void:
	_refresh_potion_button()

func _on_backpack_closed() -> void:
	_refresh_potion_button()
	if is_instance_valid(cached_hero):
		refresh_stats(cached_hero)

func ensure_backpack_overlay() -> DungeonBackpackOverlay:
	if is_instance_valid(_backpack_overlay):
		return _backpack_overlay
	var existing := get_tree().get_first_node_in_group("dungeon_backpack") as DungeonBackpackOverlay
	if is_instance_valid(existing):
		_backpack_overlay = existing
	else:
		_backpack_overlay = DUNGEON_BACKPACK_OVERLAY_SCRIPT.new() as DungeonBackpackOverlay
		var host: Node = get_tree().current_scene
		if host == null:
			host = get_parent()
		if host == null:
			host = self
		host.add_child(_backpack_overlay)
	if is_instance_valid(_backpack_overlay) and not _backpack_overlay.backpack_closed.is_connected(_on_backpack_closed):
		_backpack_overlay.backpack_closed.connect(_on_backpack_closed)
	return _backpack_overlay

func is_backpack_open() -> bool:
	return is_instance_valid(_backpack_overlay) and _backpack_overlay.is_open()

func toggle_backpack(force_state: Variant = null) -> void:
	var currently_open := is_backpack_open()
	var want_open := not currently_open if force_state == null else bool(force_state)
	if want_open:
		if _is_map_blocked() or is_fullscreen_map_open():
			return
		if is_instance_valid(cached_hero) and cached_hero.progression != null and cached_hero.progression.has_method("sync_health_to_game_state"):
			cached_hero.progression.sync_health_to_game_state(false)
		var overlay := ensure_backpack_overlay()
		if is_instance_valid(overlay):
			overlay.open_backpack()
	else:
		if currently_open:
			_backpack_overlay.close_backpack()

func use_quick_health_potion() -> void:
	if _is_map_blocked() or is_fullscreen_map_open():
		return
	if is_instance_valid(cached_hero) and cached_hero.progression != null and cached_hero.progression.has_method("sync_health_to_game_state"):
		cached_hero.progression.sync_health_to_game_state(false)
	var gs := get_node_or_null("/root/GameState")
	if gs == null or not gs.has_method("use_consumable_by_id"):
		return
	var result: Dictionary = gs.use_consumable_by_id(&"health_potion")
	if bool(result.get("ok", false)):
		AudioManager.sfx(&"potion_drink", 0.96, 1.06)
		var healed := int(result.get("healed", 0))
		var item_name := String(result.get("item_name", "Gyógyital"))
		_show_hud_toast("+%d HP (%s)" % [healed, item_name], true)
		if is_instance_valid(cached_hero):
			refresh_stats(cached_hero)
	else:
		AudioManager.sfx(&"ui_error", 0.96, 1.04)
		_show_hud_toast(String(result.get("message", "A gyógyital most nem használható.")), false)
	_refresh_potion_button()

func _get_keybind_text(action_id: String, fallback: String) -> String:
	var sm := get_node_or_null("/root/SettingsManager")
	if sm != null and sm.has_method("get_keybind_label"):
		return String(sm.get_keybind_label(action_id))
	return fallback

func _apply_hud_settings() -> void:
	var show_map := true
	var sm := get_node_or_null("/root/SettingsManager")
	if sm != null:
		show_map = bool(sm.get("show_minimap"))
	if is_instance_valid(minimap_margin):
		minimap_margin.visible = show_map
	var base_top: float = 226.0 if show_map else 16.0
	if is_instance_valid(pause_margin):
		pause_margin.offset_top = base_top
		pause_margin.offset_bottom = base_top + 36.0
	if is_instance_valid(backpack_margin):
		backpack_margin.offset_top = base_top + 42.0
		backpack_margin.offset_bottom = base_top + 78.0
	if is_instance_valid(potion_margin):
		potion_margin.offset_top = base_top + 84.0
		potion_margin.offset_bottom = base_top + 120.0

	if is_instance_valid(pause_button):
		pause_button.text = "SZÜNET  [%s / ESC]" % _get_keybind_text("pause_game", "P").to_upper()
	if is_instance_valid(backpack_button):
		var bp_key := _get_keybind_text("toggle_backpack", "Tab").to_upper()
		backpack_button.text = "HÁTIZSÁK  [%s]" % bp_key
	_refresh_potion_button()
	_update_class_ability_indicator()

func _refresh_potion_button() -> void:
	if not is_instance_valid(potion_button):
		return
	var potion_count: int = 0
	var gs := get_node_or_null("/root/GameState")
	if gs != null and gs.has_method("get_item_count"):
		potion_count = int(gs.get_item_count(&"health_potion", false))
	var potion_key := _get_keybind_text("quick_potion", "Q").to_upper()
	potion_button.text = "GYÓGYITAL (%d)  [%s]" % [potion_count, potion_key]
	potion_button.disabled = potion_count <= 0
	if potion_count > 0:
		potion_button.tooltip_text = "Gyógyital gyors használata (+40 HP) [%s]" % potion_key
	else:
		potion_button.tooltip_text = "Nincs gyógyital a hátizsákban."

func show_title_collected_toast(title_text: String) -> void:
	if title_text.strip_edges().is_empty():
		return
	AudioManager.sfx(&"title_unlock")
	_show_hud_toast("Titulus összegyűjtve: %s (lépj ki a kijárati kapun!)" % title_text, true)

func show_boss_defeated_toast() -> void:
	var interact_key := _get_keybind_text("interact", "E").to_upper()
	AudioManager.sfx(&"victory_fanfare", 1.0, 1.0)
	_show_hud_toast("Főellenség legyőzve! A kijárati kapu megnyílt — nyomj [%s]-t a kapunál!" % interact_key, true)

func show_exit_locked_toast() -> void:
	_show_hud_toast("A kijárati kapu zárva van — előbb győzd le a főellenséget!", false)

func show_dungeon_victory(newly_unlocked: PackedStringArray, run_titles: PackedStringArray) -> void:
	if is_fullscreen_map_open():
		toggle_fullscreen_map(false)
	if is_backpack_open():
		toggle_backpack(false)
	if not is_instance_valid(_victory_overlay):
		var existing := get_tree().get_first_node_in_group("dungeon_victory") as DungeonVictoryOverlay
		if is_instance_valid(existing):
			_victory_overlay = existing
		else:
			_victory_overlay = DUNGEON_VICTORY_OVERLAY_SCRIPT.new() as DungeonVictoryOverlay
			var host: Node = get_tree().current_scene
			if host == null:
				host = get_parent()
			if host == null:
				host = self
			host.add_child(_victory_overlay)
	if is_instance_valid(_victory_overlay):
		_victory_overlay.show_victory(cached_hero, newly_unlocked, run_titles)

func show_loot_window(loot_payload: Dictionary) -> void:
	if is_fullscreen_map_open():
		toggle_fullscreen_map(false)
	if is_backpack_open():
		toggle_backpack(false)
	if not is_instance_valid(_loot_overlay):
		var existing := get_tree().get_first_node_in_group("dungeon_loot") as DungeonLootOverlay
		if is_instance_valid(existing):
			_loot_overlay = existing
		else:
			_loot_overlay = DUNGEON_LOOT_OVERLAY_SCRIPT.new() as DungeonLootOverlay
			var host: Node = get_tree().current_scene
			if host == null:
				host = get_parent()
			if host == null:
				host = self
			host.add_child(_loot_overlay)
	if is_instance_valid(_loot_overlay):
		_loot_overlay.show_loot(loot_payload)

func _show_hud_toast(message: String, is_positive: bool) -> void:
	if not is_instance_valid(hud_toast_panel) or not is_instance_valid(hud_toast_label):
		return
	hud_toast_label.text = message
	hud_toast_label.add_theme_color_override(
		"font_color",
		Color(0.62, 0.96, 0.68, 1.0) if is_positive else Color(1.0, 0.72, 0.45, 1.0)
	)
	hud_toast_panel.visible = true
	_toast_timer = 2.0

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

func _input(event: InputEvent) -> void:
	# Handle TAB (or rebound backpack key) in _input so Godot's ui_focus_next never swallows TAB.
	if not is_inside_tree() or _is_map_blocked():
		return
	var sm := get_node_or_null("/root/SettingsManager")
	if sm != null and sm.has_method("is_open") and bool(sm.is_open()):
		return
	if event is InputEventKey and event.pressed and not event.echo:
		var kc := (event as InputEventKey).keycode
		var pkc := (event as InputEventKey).physical_keycode
		var is_backpack_key: bool = (
			bool(sm.matches_keybind(event, "toggle_backpack"))
			if (sm != null and sm.has_method("matches_keybind"))
			else (kc == KEY_TAB or pkc == KEY_TAB)
		)
		if is_backpack_key:
			if not is_fullscreen_map_open():
				toggle_backpack()
			_mark_input_handled()

func _unhandled_input(event: InputEvent) -> void:
	if not is_inside_tree() or _is_map_blocked():
		return
	if event is InputEventKey and event.pressed and not event.echo:
		var kc := (event as InputEventKey).keycode
		var pkc := (event as InputEventKey).physical_keycode
		var sm := get_node_or_null("/root/SettingsManager")
		var has_sm_binds := sm != null and sm.has_method("matches_keybind")
		var is_map_key: bool = bool(sm.matches_keybind(event, "toggle_map")) if has_sm_binds else (kc == KEY_M or pkc == KEY_M)
		var is_potion_key: bool = bool(sm.matches_keybind(event, "quick_potion")) if has_sm_binds else (kc == KEY_Q or pkc == KEY_Q)

		if is_map_key:
			toggle_fullscreen_map()
			_mark_input_handled()
		elif is_potion_key and not is_fullscreen_map_open():
			use_quick_health_potion()
			_mark_input_handled()
		elif (kc == KEY_ESCAPE or pkc == KEY_ESCAPE) and is_fullscreen_map_open():
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
	AudioManager.sfx(&"ui_map_open" if want_open else &"ui_window_close", 0.97, 1.04)

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

	var cur_scene := get_tree().current_scene
	if cur_scene != null:
		var by_name := cur_scene.get_node_or_null("PauseMenu")
		if is_instance_valid(by_name):
			return by_name

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

func _process(delta: float) -> void:
	if not _pause_menu_ensured:
		_pause_menu_ensured = true
		ensure_pause_menu()
		if is_instance_valid(pause_button):
			pause_button.focus_mode = Control.FOCUS_NONE

	if _toast_timer > 0.0:
		_toast_timer = maxf(0.0, _toast_timer - delta)
		if _toast_timer <= 0.0 and is_instance_valid(hud_toast_panel):
			hud_toast_panel.visible = false

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

	# 1. Hős portré és neve (+ összevont titulusok)
	_update_hero_portrait(hero)
	if hero_title_label:
		hero_title_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		hero_title_label.text = hero.hero_name
		hero_title_label.tooltip_text = hero.hero_name
		var title_font_size: int = 15
		if hero.hero_name.length() > 65:
			title_font_size = 11
		elif hero.hero_name.length() > 36:
			title_font_size = 13
		hero_title_label.add_theme_font_size_override("font_size", title_font_size)

	# 2. Kaszt (magyarul) és Aktuális szint
	if class_level_label:
		var c_name: String = _get_localized_hero_class_name(hero)
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
		atk_label.text = "Támadás: %d" % hero.attack_power
	if def_label:
		def_label.text = "Védelem: %d" % hero.get_defense()
	if init_label:
		init_label.text = "Kezdeményezés: %.1f" % hero.get_initiative()
	if vision_label:
		var grid_span: int = 2 * hero.vision_limit + 1
		vision_label.text = "Látótáv: %d (%dx%d)" % [hero.vision_limit, grid_span, grid_span]

	# 6. Aktuális mező információ
	_update_coords()
	_update_class_ability_indicator()
	_refresh_potion_button()

	if minimap_canvas:
		minimap_canvas.queue_redraw()
	if is_fullscreen_map_open() and big_map_canvas:
		big_map_canvas.queue_redraw()

func _resolve_hero_class_id(hero: HeroController) -> StringName:
	if is_instance_valid(hero) and hero.active_class != null:
		var raw_id: String = hero.active_class.class_name_id.strip_edges().to_lower().replace(" ", "_")
		if raw_id == "templar":
			return &"knight_templar"
		if not raw_id.is_empty():
			return StringName(raw_id)
	var gs := get_node_or_null("/root/GameState")
	if gs != null and gs.has_method("get_active_character"):
		var active_char = gs.get_active_character()
		if active_char != null and not String(active_char.class_id).strip_edges().is_empty():
			return StringName(String(active_char.class_id).strip_edges().to_lower())
	return &""

func _get_localized_hero_class_name(hero: HeroController) -> String:
	var class_id: StringName = _resolve_hero_class_id(hero)
	var gs := get_node_or_null("/root/GameState")
	if gs != null and gs.has_method("get_character_class") and class_id != &"":
		var cls_data = gs.get_character_class(class_id)
		if cls_data != null and not String(cls_data.display_name).strip_edges().is_empty():
			return String(cls_data.display_name)
	match String(class_id):
		"archer":
			return "Íjász"
		"knight":
			return "Lovag"
		"knight_templar":
			return "Templomos lovag"
		"priest":
			return "Papnő"
		"soldier":
			return "Katona"
		"swordsman":
			return "Kardforgató"
		"wizard":
			return "Varázsló"
	if is_instance_valid(hero) and hero.active_class != null and not hero.active_class.class_name_id.strip_edges().is_empty():
		return hero.active_class.class_name_id
	return "Kalandor"

func _update_hero_portrait(hero: HeroController) -> void:
	if hero_portrait_icon == null or not is_instance_valid(hero):
		return
	var class_id: StringName = _resolve_hero_class_id(hero)
	var cls_data: CharacterClassData = null
	var gs := get_node_or_null("/root/GameState")
	if gs != null and gs.has_method("get_character_class") and class_id != &"":
		cls_data = gs.get_character_class(class_id) as CharacterClassData
	var portrait: Texture2D = ClassVisualHelper.get_portrait_texture(class_id, cls_data)
	if portrait == null and hero.sprite != null and hero.sprite.sprite_frames != null:
		var frames: SpriteFrames = hero.sprite.sprite_frames
		if frames.has_animation(&"idle") and frames.get_frame_count(&"idle") > 0:
			portrait = ClassVisualHelper.crop_transparent_texture(frames.get_frame_texture(&"idle", 0))
	if portrait != null and hero_portrait_icon.texture != portrait:
		hero_portrait_icon.texture = portrait
		hero_portrait_icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST

func _apply_ability_bar_colors(style_key: String, fill_col: Color, border_col: Color, label_col: Color) -> void:
	if _last_ability_style_key == style_key:
		return
	_last_ability_style_key = style_key
	if _ability_fill_style:
		_ability_fill_style.bg_color = fill_col
		_ability_fill_style.border_color = border_col
	if class_ability_label:
		class_ability_label.add_theme_color_override("font_color", label_col)

func _set_ability_icon(icon_path: String) -> void:
	if class_ability_icon == null:
		return
	if ResourceLoader.exists(icon_path):
		class_ability_icon.texture = load(icon_path) as Texture2D

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
		var wiz_key := _get_keybind_text("wizard_element", "F")
		if class_ability_bar:
			class_ability_bar.max_value = 1.0
			class_ability_bar.value = 1.0
		if is_ice:
			_apply_ability_bar_colors("wizard_ice", Color(0.18, 0.56, 0.85, 0.88), Color(0.55, 0.90, 1.0, 1.0), Color(0.86, 0.97, 1.0, 1.0))
			_set_ability_icon(UiIcons.FROST)
			if class_ability_label:
				class_ability_label.text = "Elem: Jég  [%s]" % wiz_key
		else:
			_apply_ability_bar_colors("wizard_fire", Color(0.85, 0.30, 0.12, 0.90), Color(1.0, 0.62, 0.25, 1.0), Color(1.0, 0.93, 0.82, 1.0))
			_set_ability_icon(UiIcons.FIRE)
			if class_ability_label:
				class_ability_label.text = "Elem: Tűz  [%s]" % wiz_key
	elif c_name == "Priest" and hero_combat:
		class_ability_container.visible = true
		var cd: float = hero_combat.get_priest_heal_cooldown_remaining()
		var dur: float = hero_combat.get_priest_heal_cooldown_duration()
		var heal_key := _get_keybind_text("priest_heal", "H")
		if class_ability_bar:
			class_ability_bar.max_value = maxf(0.1, dur)
			class_ability_bar.value = clampf(dur - cd, 0.0, dur)
		if cd > 0.01:
			_apply_ability_bar_colors("priest_cd", Color(0.75, 0.55, 0.16, 0.88), Color(0.95, 0.78, 0.35, 1.0), Color(1.0, 0.94, 0.75, 1.0))
			_set_ability_icon(UiIcons.HOURGLASS)
			if class_ability_label:
				class_ability_label.text = "Gyógyítás: %.1f mp  [%s]" % [cd, heal_key]
		else:
			_apply_ability_bar_colors("priest_ready", Color(0.16, 0.62, 0.36, 0.88), Color(0.45, 0.92, 0.62, 1.0), Color(0.86, 1.0, 0.90, 1.0))
			_set_ability_icon(UiIcons.HEAL)
			if class_ability_label:
				class_ability_label.text = "Gyógyítás kész  [%s]" % heal_key
	else:
		class_ability_container.visible = false
		_last_ability_style_key = ""

func _update_coords() -> void:
	if not is_instance_valid(cached_hero):
		return
	if tile_info_label:
		var tile_desc = _get_current_tile_description(cached_hero)
		tile_info_label.text = "Mező: (%d, %d) - %s" % [cached_hero.grid_pos.x, cached_hero.grid_pos.y, tile_desc]
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
