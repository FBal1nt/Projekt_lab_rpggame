extends "res://Scripts/UI/ItemAugmentationWindow.gd"


func _configure_workshop() -> void:
	workshop_type = &"blacksmith"
	workshop_title = "KOVÁCSMŰHELY"
	workshop_subtitle = "Fegyverek és páncélok kovácsolása, fejlesztése és edzése"
	workshop_icon_path = "res://Assets/UI/Icons/blacksmith.png"
	accent_color = UI_THEME.FORGE_EMBER
	option_configs = [
		{
			"id": &"craft",
			"label": "KÉSZÍTÉS",
			"description": "Új fegyverek és felszerelések kovácsolása nyersanyagokból (a közös tár alapanyagai is felhasználhatók)."
		},
		{
			"id": &"upgrade",
			"label": "FEJLESZTÉS",
			"description": "A kiválasztott felszerelés megerősítése +1-től +5-ig."
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
