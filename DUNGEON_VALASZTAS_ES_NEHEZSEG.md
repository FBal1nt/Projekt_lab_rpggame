# Dungeonválasztás és nehézségpanel – Lobby-integráció

A Lobby ebben a projektben kizárólag a dungeon és a nehézségi fokozat kiválasztását biztosítja. Nincs benne pályagenerálás, jelenetváltás, enemy spawn, harcrendszer vagy dungeon-játékmenet.

## Kiválasztófelület

A `Scenes/Lobby/Lobby.tscn` jelenet `DungeonWindow` panelje a `Scripts/UI/DungeonWindow.gd` scriptet használja. A lista adatvezérelt: a dungeont a `Data/Dungeons`, a hozzá tartozó fokozatokat a `Data/DungeonDifficulties` mappából tölti be.

## Integráció a generátorral

A `DungeonSelection` autoload felel a definíciók beolvasásáért és a kiválasztás átadásáért. A generátoroldal csatlakozzon ehhez:

```gdscript
func _ready() -> void:
    DungeonSelection.dungeon_launch_requested.connect(_on_dungeon_launch_requested)

func _on_dungeon_launch_requested(configuration: Dictionary) -> void:
    # A kapott konfiguráció alapján a saját generátor indítható.
    print(configuration.get("dungeon_id"), configuration.get("difficulty_id"))
```

A teljes Dictionary mezőinek leírását a `README_LOBBY_MODUL.md` tartalmazza. A Lobby csak kiválasztási adatokat ad át; a generátor oldalának kell a seedet, a map paramétereit, a pályát és az indulást kezelnie.

## Fontos

A `Data/Dungeons/forgotten_crypt.tres` `scene_path` mezője szándékosan üres. Nincs jelenetútvonal vagy pályageneráló kód a Lobby-modulban.
