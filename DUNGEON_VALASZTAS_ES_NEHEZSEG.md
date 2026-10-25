# Dungeonválasztás és nehézségi beállítások

## Játékos felület

A Dungeon ablak egyetlen, a képernyőn belül maradó dialógus. Két legördülő lista van benne:

1. **Dungeon** – a `Data/Dungeons/` mappából automatikusan betöltött helyszínek.
2. **Nehézség** – az adott dungeonhoz tartozó, `Data/DungeonDifficulties/` mappában lévő konfigurációk.

A kiválasztás alatt azonnal frissül a dungeon leírása, az ajánlott csapatszint és a nehézség részletes összefoglalója. A nehézség részletei között szerepel a spawn-szorzó, a találkozások mennyisége, az ellenfelek szinttartománya, az elit spawn esélye és a lehetséges ellenfelek neve.

A hosszabb részletek egy belső görgethető területen jelennek meg, így kisebb ablakméretnél sem lógnak ki a dialógusból.

## Új dungeon hozzáadása

1. Hozz létre egy `DungeonDefinition` erőforrást a `Data/Dungeons/` mappában.
2. Adj neki egyedi `id`-t, `display_name`-t, `description`-t, ajánlott szinttartományt és (ha elkészül) `scene_path` értéket.
3. Adj hozzá legalább egy `DungeonDifficultyData` erőforrást a `Data/DungeonDifficulties/` mappában, és állítsd be a `dungeon_id` mezőt.
4. A Dungeon-választó automatikusan felismeri a definíciókat; a UI-kódot nem kell módosítani.

## Nehézség hangolása

A `DungeonDifficultyData` mezők jelentése:

- `spawn_rate_multiplier`: az adott dungeon alap spawnrátáját szorozza.
- `encounter_count_multiplier`: a találkozások számának skálázója.
- `enemy_level_min`, `enemy_level_max`: az ellenfelek véletlenszerű szinttartománya.
- `enemy_type_ids`: a spawnrendszer által feloldandó ellenfél-azonosítók.
- `enemy_type_names`: a menüben látható nevek, az ID-listával azonos sorrendben.
- `elite_spawn_chance`: elit találkozás esélye 0.0–1.0 tartományban.
- `sort_order`: a nehézségi szintek megjelenítési sorrendje.

## Dungeon-mechanika integráció

A „Kaland előkészítése” művelet a `DungeonManager.start_dungeon(dungeon_id, difficulty_id)` függvényt hívja. A kiválasztott teljes konfiguráció a `GameState.run_state` mezőbe kerül, többek között `spawn_rate_multiplier`, `encounter_count_multiplier`, `enemy_level_min`, `enemy_level_max`, `enemy_type_ids`, `elite_spawn_chance`, `seed`, `floor` és `room_index` értékekkel.

A csapattársak a `DungeonManager.get_run_configuration()`, `get_spawn_rate_multiplier()`, `roll_enemy_level()` és `roll_enemy_type_id()` metódusokat használhatják. A tényleges pályajelenetet a Dungeon erőforrás `scene_path` mezőjében kell majd megadni.
