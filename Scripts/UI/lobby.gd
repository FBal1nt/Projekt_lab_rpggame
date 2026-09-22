extends Control


@onready var gold_label: Label = $UI/TopBar/Container/GoldLabel
@onready var level_label: Label = $UI/TopBar/Container/LevelLabel

@onready var character_window: Panel = $UI/WindowLayer/CharacterWindow
@onready var blacksmith_window: Panel = $UI/WindowLayer/BlacksmithWindow
@onready var shop_window: Panel = $UI/WindowLayer/ShopWindow
@onready var wizard_window: Panel = $UI/WindowLayer/WizardWindow
@onready var dungeon_window: Panel = $UI/WindowLayer/DungeonWindow

var windows: Array[Panel] = []

func _ready() -> void:
	windows = [
		character_window,
		blacksmith_window,
		shop_window,
		wizard_window,
		dungeon_window
	]

	close_all_windows()
	refresh_ui()

func close_all_windows() -> void:
	for window in windows:
		window.hide()

func refresh_ui() -> void:
	gold_label.text = "Gold: " + str(GameState.gold)
	level_label.text = "Level: " + str(GameState.level)

func _on_close_button_pressed() -> void:
	close_all_windows()

func open_window(window: Panel) -> void:
	close_all_windows()
	window.show()

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
