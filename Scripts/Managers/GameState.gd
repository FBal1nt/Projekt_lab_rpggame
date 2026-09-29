extends Node


signal state_changed


var gold: int = 500
var level: int = 1
var xp: int = 0


var backpack: Inventory
var stash: Inventory


func _ready() -> void:
	backpack = Inventory.new()
	backpack.width = 8
	backpack.height = 4

	stash = Inventory.new()
	stash.width = 10
	stash.height = 5
	
	setup_starting_inventory()


func setup_starting_inventory() -> void:
	var sword: ItemData = load("res://Data/Items/iron_sword.tres")
	var potion: ItemData = load("res://Data/Items/health_potion.tres")

	backpack.add_item(
		sword,
		Vector2i(0, 0)
	)

	backpack.add_item(
		potion,
		Vector2i(2, 0),
		3
	)
