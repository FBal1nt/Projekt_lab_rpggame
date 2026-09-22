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
