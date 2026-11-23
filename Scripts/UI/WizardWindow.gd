extends "res://Scripts/UI/ItemAugmentationWindow.gd"


func _configure_workshop() -> void:
	workshop_type = &"wizard"
	workshop_title = "VARÁZSLÓ TORNYA"
	workshop_subtitle = "Elemi rúnák, ellenállások és védőáldások bűvölése"
	workshop_icon_path = "res://Assets/UI/Icons/wizard.png"
	accent_color = UI_THEME.ARCANE_VIOLET
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
