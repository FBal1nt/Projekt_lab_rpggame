extends Panel


@onready var backpack_grid: InventoryGrid = $MarginContainer/VBoxContainer/InventoryContainer/BackpackPanel/VBoxContainer/BackpackGrid

@onready var stash_grid: InventoryGrid = $MarginContainer/VBoxContainer/InventoryContainer/StashPanel/VBoxContainer/StashGrid

@onready var close_button: Button = $MarginContainer/VBoxContainer/CloseButton


func _ready() -> void:
	backpack_grid.set_inventory(GameState.backpack)
	stash_grid.set_inventory(GameState.stash)

	close_button.pressed.connect(_on_close_button_pressed)


func _on_close_button_pressed() -> void:
	hide()
