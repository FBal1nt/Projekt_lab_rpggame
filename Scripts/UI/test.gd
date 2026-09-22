extends Control


func _ready() -> void:
	var sword: ItemData = load("res://data/items/iron_sword.tres")

	var potion: ItemData = load("res://data/items/health_potion.tres")

	print("=== INVENTORY TEST ===")

	var sword_instance = GameState.backpack.add_item(
		sword,
		Vector2i(0, 0)
	)

	if sword_instance != null:
		print("Sword added successfully.")
	else:
		print("Sword could not be added.")


	var potion_instance = GameState.backpack.add_item(
		potion,
		Vector2i(2, 0),
		3
	)

	if potion_instance != null:
		print("Potion added successfully.")
	else:
		print("Potion could not be added.")


	print("Sword position: ", sword_instance.position)
	print("Potion position: ", potion_instance.position)

	var second_sword = GameState.backpack.add_item(
		sword,
		Vector2i(1, 1)
	)
	
	if second_sword != null:
		print("ERROR: Sword should NOT fit here!")
	else:
		print("Collision test passed.")
