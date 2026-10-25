# Karakterek, inventory és mentés – fejlesztői jegyzet

## Mit csinál a rendszer?

- Minden karakternek külön `CharacterProfile` adata van, külön hátizsákkal, szinttel és XP-vel.
- Az aktív karakter neve és inventoryja a Karakter ablakban váltható.
- A Stash egyetlen közös inventory, amely minden karakter számára ugyanaz.
- Az arany közös fiókadat.
- A játék automatikusan ment a `user://savegame.json` fájlba, többek között tárgymozgatáskor, karakterváltáskor, vásárláskor és eladáskor.
- A karaktereket egyéni nevük alapján lehet létrehozni. Az üres vagy duplikált nevet a rendszer elutasítja.

## API a többi játékrendszerhez

```gdscript
# Aktív karakter adatainak elérése
var character: CharacterProfile = GameState.get_active_character()

# A jelenlegi karakter inventoryja
var inventory: Inventory = GameState.get_active_inventory()
# Kompatibilitás miatt a régi forma is működik:
var same_inventory: Inventory = GameState.backpack

# A csapat összes karaktere és a közös stash
var roster: Array[CharacterProfile] = GameState.characters
var shared_stash: Inventory = GameState.stash

# Karakter létrehozása, illetve aktiválása
GameState.create_character("Artemis", &"scout")
GameState.select_character(character.id)

# Osztály és aktuális, szintre számolt statok
var class_data: CharacterClassData = GameState.get_character_class(character.class_id)
var stats: Dictionary = GameState.get_character_stats(character)

# A dungeonben elszenvedett sérülés/stressz automatikusan mentődik
GameState.set_character_health(character.id, int(stats.get("max_health", 30)) - 5)
GameState.set_character_stress(character.id, 20)

# Aktív karakter fejlődése; a változás automatikusan mentődik
GameState.xp += 25
GameState.level += 1
```

Az `Inventory` saját `inventory_changed` jelét a `GameState` figyeli, ezért a meglévő `add_item`, `move_item`, `remove_item`, `try_add_item` és a Stash-áthelyezés automatikusan mentődik.

## Karakterosztályok hozzáadása és módosítása

A projekt 16 induló osztálya külön `CharacterClassData` erőforrásban van a `Data/CharacterClasses/` mappában. A `GameState` rekurzívan megkeresi az ott található `.tres`/`.res` fájlokat, ezért új osztály felvételéhez nem kell UI-kódot módosítani: másolj le egy meglévő osztály-erőforrást, adj neki egyedi ID-t, és töltsd ki az adatokat.

Az osztály neve, szerepe, leírása, portréja, harci sprite-ja, alapstatisztikái, szintenkénti növekedése és képesség-ID-listája az osztályerőforrásba tartozik. A karakter saját szintje, XP-je, aktuális életereje, stressze, trait/quirk ID-i és inventoryja a `CharacterProfile`-ban marad.

Részletes mezőlista, a 16 osztály felsorolása és csapattársi integrációs példa: **`KARAKTEROSZTALYOK.md`**.

A 16 osztály egyelőre prototípus statértékeket használ. A `portrait` és `battle_sprite` mezők elő vannak készítve, de a projektben jelenleg még nincsenek egyedi osztályképek hozzárendelve. A `skill_ids`/`skill_names` adatok a jövőbeli harci rendszer számára vannak előkészítve; a képességek tényleges működését a Dungeon-mechanikához kell kötni.

## Új tárgy hozzáadása

Az új `ItemData` erőforrást tedd a `res://Data/Items/` mappába. A mentés eltárolja az erőforrás útvonalát és a tárgy `id` mezőjét; ha az útvonal megváltozik, a rendszer az ID alapján is megpróbálja megkeresni az erőforrást.
