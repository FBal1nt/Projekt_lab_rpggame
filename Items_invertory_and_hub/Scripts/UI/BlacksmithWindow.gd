extends "res://Scripts/UI/ItemAugmentationWindow.gd"


func _configure_workshop() -> void:
	workshop_type = &"blacksmith"
	workshop_title = "KOVÁCSMŰHELY"
	accent_color = Color(0.84, 0.54, 0.26, 1.0)
	option_configs = [
		{
			"id": &"craft",
			"label": "KÉSZÍTÉS",
			"description": "Új fegyverek és felszerelések kovácsolása nyersanyagokból."
		},
		{
			"id": &"upgrade",
			"label": "FEJLESZTÉS",
			"description": "A kiválasztott felszerelés fejlesztése +1-től +5-ig."
		},
		{
			"id": &"sharpen",
			"label": "ÉLESÍTÉS",
			"description": "Fegyverek fizikai sebzésének és kritikus esélyének növelése."
		},
		{
			"id": &"defense",
			"label": "VÉDELEM",
			"description": "Páncél és ékszerek fizikai védelmének megerősítése."
		},
		{
			"id": &"bleeding",
			"label": "VÉRZÉS",
			"description": "Fegyverekre kerülő vérző hatás, nagyobb vérzéssebzéssel és további vérzésréteggel."
		}
	]
