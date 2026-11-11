# RPG – Lobby modul

Ez a csomag kizárólag a játék Lobby-részét és a dungeonválasztó / nehézségválasztó felületet tartalmazza. A projekt önállóan megnyitható Godot-projektként, így a csapat a saját projektjébe történő átemelés előtt külön is ellenőrizheti a Lobbyt.

## Tartalom

- Főmenü, új játék és három kézi mentési hely + külön automatikus mentés.
- Lobby épületei és ablakai.
- Karakterválasztás és karakteralkotás, 16 Lobby-karakterosztály.
- Inventory, Stash és karakterenkénti equipment.
- Karakterstatisztikák, felszerelési bónuszok.
- Bolt, kovácsműhely és varázslótorony.
- Globális játékállapot és a Lobbyhoz szükséges mentési rendszer.
- Dungeonválasztó és nehézségi panel.

## Szándékosan nincs benne

- Tényleges pályagenerátor vagy pályajelenet.
- Player controller, harcrendszer, ellenfél-AI, lövedékek és boss.
- Dungeon HUD, szobák, spawnrendszer és játékmenet.

Ezeket a csapat többi tagja a saját moduljában valósítja meg.

## Indítás

1. Nyisd meg a `project.godot` fájlt Godot 4.7-ben.
2. Várd meg az erőforrások importálását.
3. F5: a főmenü indul.
4. Indíts új játékot vagy válassz mentést, majd a Lobbyban nyisd meg a DUNGEON épületet.

## Dungeon-integrációs szerződés

A dungeonablak nem indít jelenetet és nem futtat generálást. A játékos választását a `DungeonSelection` autoload adja át a generátorcsapatnak.

A fogadó kód a következő jelet figyelje:

```gdscript
func _ready() -> void:
    DungeonSelection.dungeon_launch_requested.connect(_on_dungeon_launch_requested)

func _on_dungeon_launch_requested(configuration: Dictionary) -> void:
    var dungeon_id := String(configuration.get("dungeon_id", ""))
    var difficulty_id := String(configuration.get("difficulty_id", ""))
    # Innen a generátorcsapat saját kódja veszi át a folyamatot.
```

A kiválasztás lekérdezhető az eseményen kívül is:

```gdscript
var configuration: Dictionary = DungeonSelection.get_selected_configuration()
```

A konfiguráció kulcsai:

| Kulcs | Jelentés |
|---|---|
| `dungeon_id`, `dungeon_name` | Kiválasztott dungeon stabil azonosítója és neve |
| `difficulty_id`, `difficulty_name` | Kiválasztott nehézség azonosítója és neve |
| `scene_path` | Opcionális jelenetútvonal; jelenleg üres, a generátorcsapat töltheti ki |
| `recommended_level_min`, `recommended_level_max` | Ajánlott csapatszint |
| `base_spawn_rate_multiplier` | A dungeon alap spawn-szorzója |
| `spawn_rate_multiplier` | Dungeon- és nehézségszorzó együtt |
| `encounter_count_multiplier` | Találkozások mennyiségének szorzója |
| `enemy_level_min`, `enemy_level_max` | Beállított ellenfélszint-tartomány |
| `enemy_type_ids`, `enemy_type_names` | A nehézséghez rendelt típusazonosítók és megjelenített nevek |
| `elite_spawn_chance` | Elit megjelenési esély 0–1 tartományban |

A jel minden érvényes **VÁLASZTÁS ÁTADÁSA** gombnyomáskor egyszer lefut. Az eseményben átadott Dictionary mély másolat; a fogadó rendszer módosíthatja anélkül, hogy a Lobby belső választását felülírná.

## Új dungeon és nehézség hozzáadása

- Dungeon: hozz létre új `DungeonDefinition` erőforrást a `Data/Dungeons` mappában.
- Nehézség: hozz létre `DungeonDifficultyData` erőforrást a `Data/DungeonDifficulties` mappában, és állítsd be benne a `dungeon_id` mezőt.
- A `DungeonSelection` automatikusan beolvassa az erőforrásokat induláskor. A játék közbeni frissítéshez meghívható a `DungeonSelection.reload_catalog()`.

## Fő integrációs fájlok

- `Scenes/Lobby/Lobby.tscn`
- `Scripts/UI/lobby.gd`
- `Scripts/UI/DungeonWindow.gd`
- `Scripts/Integration/DungeonSelectionBridge.gd`
- `Scripts/Data/DungeonDefinition.gd`
- `Scripts/Data/DungeonDifficultyData.gd`
- `Data/Dungeons/`
- `Data/DungeonDifficulties/`
