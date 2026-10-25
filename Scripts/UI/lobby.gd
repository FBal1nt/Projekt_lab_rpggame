extends Control

const UI_THEME = preload("res://Scripts/UI/ui_theme.gd")
const BACKGROUND_PATH := "res://Arts/UI/lobby_background.png"

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
var main_menu_confirm_dialog: ConfirmationDialog
var heading_label: Label

const BUILDINGS := [
	{
		"node": "ShopBuilding",
		"label": "BOLT",
		"icon": "res://Arts/UI/Icons/shop.png",
		"tooltip": "Áruk, felszerelés és fogyóeszközök vásárlása vagy eladása.",
		"anchor": Vector2(0.16, 0.49),
		"accent": Color(0.88, 0.67, 0.32, 1.0)
	},
	{
		"node": "WizardBuilding",
		"label": "VARÁZSLÓ",
		"icon": "res://Arts/UI/Icons/wizard.png",
		"tooltip": "Mágia, képességek és fejlesztések. (Későbbi fejlesztés)",
		"anchor": Vector2(0.30, 0.37),
		"accent": Color(0.64, 0.55, 0.90, 1.0)
	},
	{
		"node": "CharacterBuilding",
		"label": "KARAKTER",
		"icon": "res://Arts/UI/Icons/character.png",
		"tooltip": "Karakteradatok és fejlődés. (Későbbi fejlesztés)",
		"anchor": Vector2(0.44, 0.43),
		"accent": Color(0.51, 0.75, 0.88, 1.0)
	},
	{
		"node": "BlacksmithBuilding",
		"label": "KOVÁCS",
		"icon": "res://Arts/UI/Icons/blacksmith.png",
		"tooltip": "Fegyverek és felszerelések fejlesztése. (Későbbi fejlesztés)",
		"anchor": Vector2(0.61, 0.49),
		"accent": Color(0.91, 0.54, 0.31, 1.0)
	},
	{
		"node": "DungeonBuilding",
		"label": "DUNGEON",
		"icon": "res://Arts/UI/Icons/dungeon.png",
		"tooltip": "A kalandok és harcok helyszíne. (Következő nagy fejlesztési lépés)",
		"anchor": Vector2(0.77, 0.65),
		"accent": Color(0.69, 0.44, 0.42, 1.0)
	},
	{
		"node": "InventoryBuilding",
		"label": "TÁRGYAK",
		"icon": "res://Arts/UI/Icons/inventory.png",
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
	top_bar.offset_bottom = 70.0
	UI_THEME.style_panel(top_bar, Color(0.78, 0.60, 0.32, 0.9), Color(0.025, 0.045, 0.07, 0.94))
	top_bar_container.add_theme_constant_override("separation", 24)

	heading_label = Label.new()
	heading_label.text = "VÁROSKÖZPONT"
	heading_label.add_theme_color_override("font_color", UI_THEME.GOLD)
	heading_label.add_theme_font_size_override("font_size", 18)
	heading_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	top_bar_container.add_child(heading_label)
	top_bar_container.move_child(heading_label, 0)

	for label in [gold_label, level_label]:
		label.add_theme_color_override("font_color", UI_THEME.IVORY)
		label.add_theme_font_size_override("font_size", 16)
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER

	var spacer := Control.new()
	spacer.name = "HudSpacer"
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top_bar_container.add_child(spacer)

	main_menu_button = Button.new()
	main_menu_button.text = "FŐMENÜ"
	main_menu_button.custom_minimum_size = Vector2(124, 44)
	main_menu_button.icon = load("res://Arts/UI/Icons/exit.png")
	UI_THEME.style_button(main_menu_button, Color(0.62, 0.69, 0.76, 1.0))
	main_menu_button.add_theme_font_size_override("font_size", 15)
	main_menu_button.pressed.connect(_on_main_menu_pressed)
	top_bar_container.add_child(main_menu_button)


func _setup_building_buttons() -> void:
	for config in BUILDINGS:
		var button := buildings.get_node_or_null(config["node"]) as Button
		if button == null:
			push_warning("Hiányzó lobby gomb: " + str(config["node"]))
			continue

		button.text = ""
		button.tooltip_text = config["tooltip"]
		button.custom_minimum_size = Vector2(112, 96)
		button.focus_mode = Control.FOCUS_ALL
		UI_THEME.style_button(button, config["accent"])
		button.add_theme_stylebox_override("normal", UI_THEME.make_box(Color(0.025, 0.045, 0.07, 0.82), config["accent"], 2, 12))
		button.add_theme_stylebox_override("hover", UI_THEME.make_box(Color(0.06, 0.10, 0.14, 0.96), config["accent"].lightened(0.18), 3, 12))
		button.add_theme_stylebox_override("pressed", UI_THEME.make_box(Color(0.02, 0.035, 0.055, 0.98), config["accent"], 2, 12))

		var layout := VBoxContainer.new()
		layout.name = "GraphicContent"
		layout.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		layout.add_theme_constant_override("separation", 3)
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
		label.add_theme_font_size_override("font_size", 14)
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
	# The Dungeon window now has its own data-driven selector; keep only true placeholders here.
	var placeholder_descriptions := {}

	for window_name in ["CharacterWindow", "BlacksmithWindow", "ShopWindow", "WizardWindow", "DungeonWindow", "InventoryWindow"]:
		var window := $UI/WindowLayer.get_node_or_null(window_name) as Panel
		if window == null:
			continue
		var window_accent := Color(0.78, 0.60, 0.32, 1.0)
		if window_name == "BlacksmithWindow":
			window_accent = Color(0.84, 0.54, 0.26, 1.0)
		elif window_name == "WizardWindow":
			window_accent = Color(0.58, 0.48, 0.88, 1.0)
		UI_THEME.style_panel(window, window_accent, Color(0.025, 0.045, 0.07, 0.98))
		var title := window.find_child("Title", true, false) as Label
		if title != null:
			title.add_theme_color_override("font_color", UI_THEME.IVORY)
			title.add_theme_font_size_override("font_size", 28)
		var close_button := window.find_child("CloseButton", true, false) as Button
		if close_button != null:
			UI_THEME.style_button(close_button, window_accent, true)
			close_button.alignment = HORIZONTAL_ALIGNMENT_CENTER

		if placeholder_descriptions.has(window_name):
			_polish_placeholder_window(window, title, close_button, placeholder_descriptions[window_name])


func _polish_placeholder_window(window: Panel, title: Label, close_button: Button, description_text: String) -> void:
	if title != null:
		title.position = Vector2(24, 38)
		title.size = Vector2(552, 48)
		title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER

	var description := window.get_node_or_null("PlaceholderDescription") as Label
	if description == null:
		description = Label.new()
		description.name = "PlaceholderDescription"
		description.position = Vector2(55, 135)
		description.size = Vector2(490, 100)
		description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		description.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		description.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		description.add_theme_color_override("font_color", UI_THEME.MUTED)
		description.add_theme_font_size_override("font_size", 17)
		description.mouse_filter = Control.MOUSE_FILTER_IGNORE
		window.add_child(description)
	description.text = description_text

	if close_button != null:
		close_button.position = Vector2(220, 320)
		close_button.size = Vector2(160, 48)
		close_button.text = "BEZÁRÁS"


func close_all_windows() -> void:
	for window in windows:
		if is_instance_valid(window):
			window.hide()


func refresh_ui() -> void:
	gold_label.text = "ARANY  " + str(GameState.gold)
	level_label.text = "SZINT  " + str(GameState.level)


func open_window(window: Panel) -> void:
	close_all_windows()
	if window == shop_window:
		shop_window.refresh()
	elif window == dungeon_window:
		dungeon_window.call("refresh")
	window.show()
	window.move_to_front()


func _on_close_button_pressed() -> void:
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


func _on_main_menu_pressed() -> void:
	if main_menu_confirm_dialog == null:
		main_menu_confirm_dialog = ConfirmationDialog.new()
		main_menu_confirm_dialog.title = "Vissza a főmenübe?"
		main_menu_confirm_dialog.dialog_text = "Szeretnéd menteni a játékot, mielőtt visszatérsz a főmenübe?"
		main_menu_confirm_dialog.ok_button_text = "Mentés és kilépés"
		main_menu_confirm_dialog.cancel_button_text = "Mégse"
		main_menu_confirm_dialog.add_button("Mentés nélkül", true, "discard")
		main_menu_confirm_dialog.confirmed.connect(_return_to_main_menu_after_save)
		main_menu_confirm_dialog.custom_action.connect(_on_main_menu_save_choice)
		add_child(main_menu_confirm_dialog)
	main_menu_confirm_dialog.popup_centered()


func _on_main_menu_save_choice(action: StringName) -> void:
	if action == &"discard":
		_return_to_main_menu_without_save()


func _return_to_main_menu_after_save() -> void:
	if not GameState.save_game():
		push_warning("A mentés nem sikerült; a főmenübe lépés megszakadt.")
		return
	_change_to_main_menu()


func _return_to_main_menu_without_save() -> void:
	_change_to_main_menu()


func _change_to_main_menu() -> void:
	var result := get_tree().change_scene_to_file("res://Scenes/Menu/MainMenu.tscn")
	if result != OK:
		push_error("Nem sikerült visszalépni a főmenübe.")
