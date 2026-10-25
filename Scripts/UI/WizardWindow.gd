extends "res://Scripts/UI/ItemAugmentationWindow.gd"


func _configure_workshop() -> void:
	workshop_type = &"wizard"
	workshop_title = "VARÁZSLÓ TORNYA"
	accent_color = Color(0.58, 0.48, 0.88, 1.0)
	option_configs = [
		{
			"id": &"weapon_element",
			"label": "ELEMENTÁL",
			"description": "Tűz-, jég- és méregvarázs fegyverekre: elemi sebzés és támadási bónusz."
		},
		{
			"id": &"resistance",
			"label": "ELLENÁLLÁS",
			"description": "Felszerelésre rakható elemi ellenállások, szükség szerint életerő- vagy regenerációs bónusszal."
		},
		{
			"id": &"utility_boost",
			"label": "ÁLDÁSOK",
			"description": "Életerő, regeneráció és más támogató bónuszok felszerelésekre."
		}
	]
