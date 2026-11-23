extends Control

const UI_THEME = preload("res://Scripts/UI/ui_theme.gd")
const CLASS_VISUAL_HELPER = preload("res://Scripts/Utils/ClassVisualHelper.gd")
const BACKGROUND_PATH := "res://Assets/UI/lobby_background.png"
const GOLD_ICON_PATH := "res://Assets/Items/Currency/gold_coins.png"

@onready var background: TextureRect = $Background
@onready var buildings: Control = $Buildings
@onready var top_bar: PanelContainer = $UI/TopBar
@onready var top_bar_container: HBoxContainer = $UI/TopBar/Container
@onready var gold_label: Label = $UI/TopBar/Container/GoldLabel
@onready var level_label: Label = $UI/TopBar/Container/LevelLabel

@onready var character_window: Panel = $UI/WindowLayer/CharacterWindow
@onready var blacksmith_window: Panel = $UI/WindowLayer/BlacksmithWindow
@onready var shop_window: Panel = $UI/WindowLayer/ShopWindow
@onready var wizard_window: Panel = $UI/WindowLayer/WizardWindow
@onready var dungeon_window: Panel = $UI/WindowLayer/DungeonWindow
@onready var inventory_window: Panel = $UI/WindowLayer/InventoryWindow

var windows: Array[Panel] = []
var main_menu_button: Button
var main_menu_confirm_dialog: CanvasLayer
var _main_menu_error_label: Label
var heading_label: Label
var _hero_pill_portrait: TextureRect
var _hero_pill_name: Label
var _hero_pill_sub: Label
var _window_backdrop: ColorRect
var _is_changing_scene: bool = false

const BUILDINGS := [
	{
		"node": "ShopBuilding",
		"label": "BOLT",
		"icon": "res://Assets/UI/Icons/shop.png",
		"tooltip": "Áruk, felszerelés és fogyóeszközök vásárlása vagy eladása.",
		"anchor": Vector2(0.16, 0.49),
		"accent": Color(0.88, 0.67, 0.32, 1.0)
	},
	{
		"node": "WizardBuilding",
		"label": "VARÁZSLÓ",
		"icon": "res://Assets/UI/Icons/wizard.png",
		"tooltip": "Enchantok, mágikus fejlesztések és ellenállások kezelése.",
		"anchor": Vector2(0.30, 0.37),
		"accent": Color(0.64, 0.55, 0.90, 1.0)
	},
	{
		"node": "CharacterBuilding",
		"label": "KARAKTER",
		"icon": "res://Assets/UI/Icons/character.png",
		"tooltip": "Karakteradatok, felszerelés és számított tulajdonságok.",
		"anchor": Vector2(0.44, 0.43),
		"accent": Color(0.51, 0.75, 0.88, 1.0)
	},
	{
		"node": "BlacksmithBuilding",
		"label": "KOVÁCS",
		"icon": "res://Assets/UI/Icons/blacksmith.png",
		"tooltip": "Fegyverek és felszerelések fejlesztése, illetve készítése.",
		"anchor": Vector2(0.61, 0.49),
		"accent": Color(0.91, 0.54, 0.31, 1.0)
	},
	{
		"node": "DungeonBuilding",
		"label": "DUNGEON",
		"icon": "res://Assets/UI/Icons/dungeon.png",
		"tooltip": "Dungeon kiválasztása és a nehézségi fokozat beállítása.",
		"anchor": Vector2(0.77, 0.65),
		"accent": Color(0.69, 0.44, 0.42, 1.0)
	},
	{
		"node": "InventoryBuilding",
		"label": "TÁRGYAK",
		"icon": "res://Assets/UI/Icons/inventory.png",
		"tooltip": "Hátizsák és raktár kezelése.",
		"anchor": Vector2(0.49, 0.80),
		"accent": Color(0.48, 0.75, 0.59, 1.0)
	}
]


func _ready() -> void:
	background.texture = load(BACKGROUND_PATH)
	background.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	background.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE

	_add_background_tint()
	_setup_hud()
	_setup_building_buttons()
	_setup_windows()

	windows = [
		character_window,
		blacksmith_window,
		shop_window,
		wizard_window,
		dungeon_window,
		inventory_window
	]
	close_all_windows()

	if not GameState.state_changed.is_connected(refresh_ui):
		GameState.state_changed.connect(refresh_ui)
	refresh_ui()

	if not get_viewport().size_changed.is_connected(_layout_building_buttons):
		get_viewport().size_changed.connect(_layout_building_buttons)
	_layout_building_buttons()
	if GameState.characters.is_empty():
		call_deferred("_open_initial_character_prompt")


func _add_background_tint() -> void:
	var tint := ColorRect.new()
	tint.name = "BackgroundTint"
	tint.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	tint.color = Color(0.015, 0.025, 0.045, 0.16)
	tint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(tint)
	move_child(tint, 1)


func _setup_hud() -> void:
	top_bar.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	top_bar.offset_left = 0.0
	top_bar.offset_top = 0.0
	top_bar.offset_right = 0.0
	top_bar.offset_bottom = 66.0
	top_bar.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR

	var bar_style := StyleBoxFlat.new()
	bar_style.bg_color = Color(0.016, 0.026, 0.046, 0.94)
	bar_style.border_color = Color(0.76, 0.58, 0.30, 0.85)
	bar_style.border_width_bottom = 2
	bar_style.content_margin_left = 20.0
	bar_style.content_margin_right = 20.0
	bar_style.content_margin_top = 8.0
	bar_style.content_margin_bottom = 8.0
	bar_style.shadow_color = Color(0.0, 0.0, 0.0, 0.45)
	bar_style.shadow_size = 8
	top_bar.add_theme_stylebox_override("panel", bar_style)
	top_bar_container.add_theme_constant_override("separation", 16)

	# Keep scene labels hidden and present upgraded gilded pills instead
	gold_label.visible = false
	level_label.visible = false

	var brand_box := HBoxContainer.new()
	brand_box.add_theme_constant_override("separation", 10)
	brand_box.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	top_bar_container.add_child(brand_box)
	top_bar_container.move_child(brand_box, 0)

	brand_box.add_child(UiIcons.make_icon_rect(UiIcons.HOME, Vector2(22, 22)))

	var brand_text := VBoxContainer.new()
	brand_text.add_theme_constant_override("separation", 0)
	brand_box.add_child(brand_text)

	heading_label = Label.new()
	heading_label.text = "VÁROSKÖZPONT"
	heading_label.add_theme_color_override("font_color", UI_THEME.GOLD)
	heading_label.add_theme_font_size_override("font_size", 17)
	brand_text.add_child(heading_label)

	var sub_heading := Label.new()
	sub_heading.text = "TÁBOR ÉS FELKÉSZÜLÉS"
	sub_heading.add_theme_color_override("font_color", UI_THEME.MUTED)
	sub_heading.add_theme_font_size_override("font_size", 10)
	brand_text.add_child(sub_heading)

	var vsep := VSeparator.new()
	vsep.modulate = Color(0.65, 0.52, 0.30, 0.45)
	top_bar_container.add_child(vsep)
	top_bar_container.move_child(vsep, 1)

	# Clickable active hero summary pill
	var hero_pill := Button.new()
	hero_pill.text = ""
	hero_pill.custom_minimum_size = Vector2(260, 46)
	hero_pill.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	hero_pill.focus_mode = Control.FOCUS_NONE
	hero_pill.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	hero_pill.tooltip_text = "Kattints a Karakter menü megnyitásához."
	hero_pill.add_theme_stylebox_override("normal", UI_THEME.make_card_box(Color(0.036, 0.058, 0.094, 0.94), Color(0.42, 0.56, 0.72, 0.72), 1, 9, 10.0, 4.0))
	hero_pill.add_theme_stylebox_override("hover", UI_THEME.make_card_box(Color(0.062, 0.094, 0.145, 0.98), UI_THEME.GOLD, 1, 9, 10.0, 4.0))
	hero_pill.add_theme_stylebox_override("pressed", UI_THEME.make_card_box(Color(0.025, 0.040, 0.068, 1.0), UI_THEME.GOLD, 1, 9, 10.0, 4.0))
	hero_pill.pressed.connect(_on_character_building_pressed)
	top_bar_container.add_child(hero_pill)
	top_bar_container.move_child(hero_pill, 2)

	var hero_row := HBoxContainer.new()
	hero_row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	hero_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hero_row.add_theme_constant_override("separation", 10)
	hero_pill.add_child(hero_row)

	var hero_pad := MarginContainer.new()
	hero_pad.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hero_pad.size_flags_vertical = Control.SIZE_EXPAND_FILL
	hero_pad.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hero_pad.add_theme_constant_override("margin_left", 8)
	hero_pad.add_theme_constant_override("margin_right", 10)
	hero_pad.add_theme_constant_override("margin_top", 4)
	hero_pad.add_theme_constant_override("margin_bottom", 4)
	hero_row.add_child(hero_pad)

	var hero_inner := HBoxContainer.new()
	hero_inner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hero_inner.add_theme_constant_override("separation", 9)
	hero_pad.add_child(hero_inner)

	var portrait_badge := PanelContainer.new()
	portrait_badge.custom_minimum_size = Vector2(36, 36)
	portrait_badge.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	portrait_badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	portrait_badge.add_theme_stylebox_override("panel", UI_THEME.make_badge_box(Color(0.02, 0.032, 0.055, 1.0), Color(0.72, 0.56, 0.28, 0.85), 6))
	var pb_sb: StyleBox = portrait_badge.get_theme_stylebox("panel")
	if pb_sb is StyleBoxFlat:
		var flat_pb := pb_sb as StyleBoxFlat
		flat_pb.content_margin_left = 2.0
		flat_pb.content_margin_right = 2.0
		flat_pb.content_margin_top = 2.0
		flat_pb.content_margin_bottom = 2.0
	hero_inner.add_child(portrait_badge)

	_hero_pill_portrait = TextureRect.new()
	_hero_pill_portrait.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_hero_pill_portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_hero_pill_portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_hero_pill_portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
	portrait_badge.add_child(_hero_pill_portrait)

	var hero_text_col := VBoxContainer.new()
	hero_text_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hero_text_col.alignment = BoxContainer.ALIGNMENT_CENTER
	hero_text_col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hero_text_col.add_theme_constant_override("separation", 0)
	hero_inner.add_child(hero_text_col)

	_hero_pill_name = Label.new()
	_hero_pill_name.text = "Nincs aktív hős"
	_hero_pill_name.clip_text = true
	_hero_pill_name.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_hero_pill_name.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hero_pill_name.add_theme_color_override("font_color", UI_THEME.IVORY)
	_hero_pill_name.add_theme_font_size_override("font_size", 13)
	hero_text_col.add_child(_hero_pill_name)

	_hero_pill_sub = Label.new()
	_hero_pill_sub.text = "SZINT -"
	_hero_pill_sub.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hero_pill_sub.add_theme_color_override("font_color", UI_THEME.GOLD)
	_hero_pill_sub.add_theme_font_size_override("font_size", 11)
	hero_text_col.add_child(_hero_pill_sub)

	var spacer := Control.new()
	spacer.name = "HudSpacer"
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top_bar_container.add_child(spacer)

	# Gold pill
	var gold_pill := PanelContainer.new()
	gold_pill.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	gold_pill.add_theme_stylebox_override("panel", UI_THEME.make_badge_box(Color(0.14, 0.10, 0.038, 0.96), UI_THEME.GOLD, 8))
	top_bar_container.add_child(gold_pill)

	var gold_row := HBoxContainer.new()
	gold_row.add_theme_constant_override("separation", 7)
	gold_pill.add_child(gold_row)

	var coin_icon := TextureRect.new()
	coin_icon.custom_minimum_size = Vector2(20, 20)
	coin_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	coin_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	if ResourceLoader.exists(GOLD_ICON_PATH):
		coin_icon.texture = load(GOLD_ICON_PATH) as Texture2D
	gold_row.add_child(coin_icon)

	gold_label.reparent(gold_row)
	gold_label.visible = true
	gold_label.add_theme_color_override("font_color", Color(1.0, 0.86, 0.48, 1.0))
	gold_label.add_theme_font_size_override("font_size", 15)
	gold_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER

	main_menu_button = Button.new()
	main_menu_button.text = "FŐMENÜ"
	main_menu_button.custom_minimum_size = Vector2(126, 40)
	main_menu_button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	UI_THEME.style_compact_button(main_menu_button, Color(0.60, 0.70, 0.82, 1.0), false, 40.0, 13)
	UiIcons.apply_button_icon(main_menu_button, "res://Assets/UI/Icons/exit.png", 16)
	main_menu_button.pressed.connect(_on_main_menu_pressed)
	top_bar_container.add_child(main_menu_button)


func _setup_building_buttons() -> void:
	for config in BUILDINGS:
		var button := buildings.get_node_or_null(config["node"]) as Button
		if button == null:
			push_warning("Hiányzó lobby gomb: " + str(config["node"]))
			continue

		var accent: Color = config["accent"]
		button.text = ""
		button.tooltip_text = config["tooltip"]
		button.custom_minimum_size = Vector2(114, 96)
		button.focus_mode = Control.FOCUS_NONE
		button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		button.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
		button.add_theme_stylebox_override("normal", UI_THEME.make_box(Color(0.018, 0.030, 0.052, 0.86), accent, 2, 12))
		button.add_theme_stylebox_override("hover", UI_THEME.make_box(Color(0.052, 0.084, 0.128, 0.96), accent.lightened(0.24), 2, 12))
		button.add_theme_stylebox_override("pressed", UI_THEME.make_box(Color(0.015, 0.025, 0.044, 0.99), accent.darkened(0.08), 2, 12))
		button.add_theme_stylebox_override("focus", UI_THEME.make_box(Color(0.0, 0.0, 0.0, 0.0), accent.lightened(0.24), 2, 12))

		var layout := VBoxContainer.new()
		layout.name = "GraphicContent"
		layout.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		layout.add_theme_constant_override("separation", 4)
		layout.alignment = BoxContainer.ALIGNMENT_CENTER
		layout.mouse_filter = Control.MOUSE_FILTER_IGNORE
		button.add_child(layout)

		var icon := TextureRect.new()
		icon.texture = load(config["icon"])
		icon.custom_minimum_size = Vector2(40, 40)
		icon.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		layout.add_child(icon)

		var label := Label.new()
		label.text = config["label"]
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		label.add_theme_color_override("font_color", UI_THEME.IVORY)
		label.add_theme_font_size_override("font_size", 13)
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		layout.add_child(label)


func _layout_building_buttons() -> void:
	if not is_inside_tree():
		return
	var viewport_size := get_viewport_rect().size
	if viewport_size.x <= 0.0 or viewport_size.y <= 0.0:
		return

	var card_size := Vector2(
		clampf(viewport_size.x * 0.075, 108.0, 140.0),
		clampf(viewport_size.y * 0.112, 88.0, 108.0)
	)
	for config in BUILDINGS:
		var button := buildings.get_node_or_null(config["node"]) as Button
		if button == null:
			continue
		button.size = card_size
		button.position = Vector2(
			viewport_size.x * config["anchor"].x - card_size.x * 0.5,
			viewport_size.y * config["anchor"].y - card_size.y * 0.5
		)


func _setup_windows() -> void:
	var window_layer := $UI/WindowLayer as Control
	if window_layer != null:
		_window_backdrop = ColorRect.new()
		_window_backdrop.name = "WindowBackdrop"
		_window_backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		_window_backdrop.color = Color(0.005, 0.010, 0.022, 0.72)
		_window_backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
		_window_backdrop.visible = false
		_window_backdrop.gui_input.connect(_on_window_backdrop_gui_input)
		window_layer.add_child(_window_backdrop)
		window_layer.move_child(_window_backdrop, 0)

	var accent_by_window := {
		"CharacterWindow": Color(0.51, 0.75, 0.88, 1.0),
		"BlacksmithWindow": UI_THEME.FORGE_EMBER,
		"ShopWindow": UI_THEME.GOLD,
		"WizardWindow": UI_THEME.ARCANE_VIOLET,
		"DungeonWindow": Color(0.78, 0.44, 0.40, 1.0),
		"InventoryWindow": Color(0.58, 0.74, 0.58, 1.0)
	}
	for window_name in accent_by_window.keys():
		var window := $UI/WindowLayer.get_node_or_null(String(window_name)) as Panel
		if window == null:
			continue
		var window_accent: Color = accent_by_window[window_name]
		UI_THEME.style_window_shell(window, window_accent)
		if not window.visibility_changed.is_connected(_sync_window_backdrop):
			window.visibility_changed.connect(_sync_window_backdrop)


func _on_window_backdrop_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
			if _has_open_window():
				_on_close_button_pressed()


func _has_open_window() -> bool:
	for window in windows:
		if is_instance_valid(window) and window.visible:
			return true
	return false


func _sync_window_backdrop() -> void:
	if is_instance_valid(_window_backdrop):
		_window_backdrop.visible = _has_open_window()


func close_all_windows() -> void:
	for window in windows:
		if is_instance_valid(window):
			window.hide()
	_sync_window_backdrop()


func _open_initial_character_prompt() -> void:
	if GameState.characters.is_empty() and character_window != null:
		open_window(character_window)


func refresh_ui() -> void:
	gold_label.text = "%d ARANY" % GameState.gold
	level_label.text = "SZINT  -" if GameState.characters.is_empty() else "SZINT  " + str(GameState.level)

	var active := GameState.get_active_character()
	if _hero_pill_name != null and _hero_pill_sub != null and _hero_pill_portrait != null:
		if active == null:
			_hero_pill_name.text = "Nincs aktív hős"
			_hero_pill_sub.text = "Kattints új karakterhez"
			_hero_pill_portrait.texture = null
		else:
			var cls := GameState.get_character_class(active.class_id)
			var cls_name := cls.display_name if cls != null else String(active.class_id)
			var stats := GameState.get_character_stats(active)
			var max_hp := int(round(float(stats.get("max_health", 100))))
			var cur_hp := active.current_health if active.current_health >= 0 else max_hp
			_hero_pill_name.text = active.character_name
			_hero_pill_sub.text = "%s · Szint %d · %d/%d HP" % [cls_name, active.level, cur_hp, max_hp]
			_hero_pill_portrait.texture = CLASS_VISUAL_HELPER.get_portrait_texture(active.class_id, cls)


func open_window(window: Panel) -> void:
	close_all_windows()
	if window == character_window:
		character_window.refresh()
	elif window == shop_window:
		shop_window.refresh()
	elif window == dungeon_window:
		dungeon_window.call("refresh")
	elif window == inventory_window and inventory_window.has_method("refresh_window"):
		inventory_window.refresh_window()
	elif (window == blacksmith_window or window == wizard_window) and window.has_method("refresh"):
		window.call("refresh")
	window.show()
	window.move_to_front()
	_sync_window_backdrop()
	AudioManager.sfx(&"ui_window_open", 0.97, 1.04)


func _on_close_button_pressed() -> void:
	AudioManager.sfx(&"ui_window_close", 0.96, 1.04)
	close_all_windows()


func _on_shop_building_pressed() -> void:
	open_window(shop_window)


func _on_character_building_pressed() -> void:
	open_window(character_window)


func _on_blacksmith_building_pressed() -> void:
	open_window(blacksmith_window)


func _on_wizard_building_pressed() -> void:
	open_window(wizard_window)


func _on_dungeon_building_pressed() -> void:
	open_window(dungeon_window)


func _on_inventory_building_pressed() -> void:
	open_window(inventory_window)


func _unhandled_input(event: InputEvent) -> void:
	if not is_inside_tree():
		return
	var sm := get_node_or_null("/root/SettingsManager")
	if sm != null and sm.has_method("is_open") and bool(sm.is_open()):
		return
	if event.is_action_pressed("ui_cancel"):
		if main_menu_confirm_dialog != null and is_instance_valid(main_menu_confirm_dialog):
			_dismiss_main_menu_modal()
			var vp := get_viewport()
			if vp != null and vp.is_inside_tree():
				vp.set_input_as_handled()
		elif _has_open_window():
			_on_close_button_pressed()
			var vp := get_viewport()
			if vp != null and vp.is_inside_tree():
				vp.set_input_as_handled()


func _dismiss_main_menu_modal() -> void:
	if main_menu_confirm_dialog != null and is_instance_valid(main_menu_confirm_dialog):
		main_menu_confirm_dialog.queue_free()
	main_menu_confirm_dialog = null
	_main_menu_error_label = null


func _on_main_menu_pressed() -> void:
	_dismiss_main_menu_modal()

	var accent := UI_THEME.GOLD
	var danger := Color(0.88, 0.36, 0.34, 1.0)

	var modal_layer := CanvasLayer.new()
	modal_layer.name = "MainMenuConfirmLayer"
	modal_layer.layer = 120
	add_child(modal_layer)
	main_menu_confirm_dialog = modal_layer

	var backdrop := ColorRect.new()
	backdrop.name = "MainMenuConfirmBackdrop"
	backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	backdrop.color = Color(0.015, 0.025, 0.045, 0.80)
	backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	modal_layer.add_child(backdrop)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_PASS
	backdrop.add_child(center)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(560, 0)
	panel.add_theme_stylebox_override("panel", UI_THEME.make_box(UI_THEME.PANEL, accent, 2, 14))
	center.add_child(panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 26)
	margin.add_theme_constant_override("margin_right", 26)
	margin.add_theme_constant_override("margin_top", 22)
	margin.add_theme_constant_override("margin_bottom", 22)
	panel.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 14)
	margin.add_child(vbox)

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 10)
	vbox.add_child(header)

	var title_label := Label.new()
	title_label.text = "VISSZA A FŐMENÜBE?"
	title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_label.add_theme_color_override("font_color", accent.lightened(0.18))
	title_label.add_theme_font_size_override("font_size", 21)
	header.add_child(title_label)

	var close_btn := _make_modal_button("", Vector2(36, 36), UI_THEME.MUTED, false, _dismiss_main_menu_modal)
	UiIcons.apply_button_icon(close_btn, UiIcons.CLOSE, 18)
	header.add_child(close_btn)

	var sep := HSeparator.new()
	sep.modulate = Color(accent.r, accent.g, accent.b, 0.45)
	vbox.add_child(sep)

	var lead_label := Label.new()
	lead_label.text = "Szeretnéd menteni az aktuális előrehaladást, mielőtt visszatérsz a főmenübe?"
	lead_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lead_label.add_theme_color_override("font_color", UI_THEME.IVORY)
	lead_label.add_theme_font_size_override("font_size", 15)
	vbox.add_child(lead_label)

	var detail_card := PanelContainer.new()
	detail_card.add_theme_stylebox_override(
		"panel",
		UI_THEME.make_box(Color(0.025, 0.042, 0.068, 0.96), Color(accent.r, accent.g, accent.b, 0.50), 1, 10)
	)
	vbox.add_child(detail_card)

	var detail_margin := MarginContainer.new()
	detail_margin.add_theme_constant_override("margin_left", 14)
	detail_margin.add_theme_constant_override("margin_right", 14)
	detail_margin.add_theme_constant_override("margin_top", 10)
	detail_margin.add_theme_constant_override("margin_bottom", 10)
	detail_card.add_child(detail_margin)

	var detail_label := Label.new()
	detail_label.text = "Jelenlegi állapot: %d arany  •  %s\nA „Mentés nélkül” gombra kattintva az utolsó mentés óta történt változások elvesznek." % [
		GameState.gold,
		"Nincs aktív hős" if GameState.characters.is_empty() else "%d. szint" % GameState.level
	]
	detail_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	detail_label.add_theme_color_override("font_color", Color("f7e4b4"))
	detail_label.add_theme_font_size_override("font_size", 14)
	detail_margin.add_child(detail_label)

	_main_menu_error_label = Label.new()
	_main_menu_error_label.visible = false
	_main_menu_error_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_main_menu_error_label.add_theme_color_override("font_color", danger.lightened(0.22))
	_main_menu_error_label.add_theme_font_size_override("font_size", 14)
	vbox.add_child(_main_menu_error_label)

	var button_row := HBoxContainer.new()
	button_row.alignment = BoxContainer.ALIGNMENT_END
	button_row.add_theme_constant_override("separation", 10)
	vbox.add_child(button_row)

	var discard_btn := _make_modal_button("Mentés nélkül", Vector2(150, 44), danger, false, _return_to_main_menu_without_save)
	button_row.add_child(discard_btn)

	var cancel_btn := _make_modal_button("Mégse", Vector2(115, 44), UI_THEME.MUTED, false, _dismiss_main_menu_modal)
	button_row.add_child(cancel_btn)

	var save_exit_btn := _make_modal_button("Mentés és kilépés", Vector2(175, 44), accent, true, _return_to_main_menu_after_save)
	button_row.add_child(save_exit_btn)
	save_exit_btn.grab_focus()


func _make_modal_button(
	label_text: String,
	min_size: Vector2,
	btn_accent: Color,
	is_primary: bool,
	on_press: Callable
) -> Button:
	var btn := Button.new()
	btn.text = label_text
	UI_THEME.style_button(btn, btn_accent, is_primary)
	btn.custom_minimum_size = min_size
	btn.alignment = HORIZONTAL_ALIGNMENT_CENTER
	btn.add_theme_font_size_override("font_size", 15)
	if on_press.is_valid():
		btn.pressed.connect(on_press)
	return btn


func _return_to_main_menu_after_save() -> void:
	if not GameState.save_game():
		push_warning("A mentés nem sikerült; a főmenübe lépés megszakadt.")
		if _main_menu_error_label != null and is_instance_valid(_main_menu_error_label):
			_main_menu_error_label.text = "A mentés nem sikerült! Próbáld újra, vagy válaszd a „Mentés nélkül” lehetőséget."
			_main_menu_error_label.visible = true
		return
	_dismiss_main_menu_modal()
	_change_to_main_menu()


func _return_to_main_menu_without_save() -> void:
	_dismiss_main_menu_modal()
	_change_to_main_menu()


func _change_to_main_menu() -> void:
	if _is_changing_scene:
		return
	_is_changing_scene = true
	call_deferred("_perform_change_to_main_menu")


func _perform_change_to_main_menu() -> void:
	if not is_inside_tree():
		_is_changing_scene = false
		return
	var main_menu_path := "res://Scenes/Menu/MainMenu.tscn"
	if SceneTransition != null:
		if not SceneTransition.transition_failed.is_connected(_on_scene_transition_failed):
			SceneTransition.transition_failed.connect(_on_scene_transition_failed)
		if SceneTransition.request_scene_change(main_menu_path):
			return
	var result := get_tree().change_scene_to_file(main_menu_path)
	if result != OK:
		_is_changing_scene = false
		push_error("Nem sikerült visszalépni a főmenübe.")


func _on_scene_transition_failed(_scene_path: String, _reason: String) -> void:
	if is_inside_tree():
		_is_changing_scene = false
