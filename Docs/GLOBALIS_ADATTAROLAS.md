# Globális beállítások és játékadatok

## Mit használ a projekt?

- `SettingsManager` egy Autoload (`project.godot` → `[autoload]`). Minden jelenetből elérhető, és az F10 billentyűvel vagy a jobb felső fogaskerék-gombbal nyitható meg. A beállítások a `user://settings.cfg` fájlba kerülnek.
- `GameState` a játék egyetlen központi állapotkezelője. A karakterek, az aktív karakter, az inventoryk, a felszerelések, a közös Stash, az arany és a dungeon-futás adatai a `user://savegame.json` fájlba kerülnek.
- A `savegame.json` verziózott JSON-mentés, nem szerveres vagy SQL-adatbázis. Egyjátékos Godot-projekthez ez a helyi közös mentési pont; ha később hálózatos, több gép által közösen elért adatbázis kell, ahhoz külön backend vagy adatbázisréteg szükséges.

## Dungeon/harcrendszer használata

```gdscript
# Minden jelenetből ugyanaz az Autoload érhető el.
var character: CharacterProfile = GameState.get_active_character()
var inventory: Inventory = GameState.get_active_inventory()
var stats: Dictionary = GameState.get_character_stats(character)

# A named attribútum a karakter mentésébe kerül.
GameState.set_character_attribute(character.id, &"strength", 12.0)

# A hatékony statok tartalmazzák az osztály fejlődését,
# a karakter tartós statmódosítóit és a felszerelés/enchant bónuszait.
var max_hp: int = int(stats.get("max_health", 1))
var attack: float = float(stats.get("damage", 0.0))

# A centralizált API frissít és ment is.
GameState.damage_character(character.id, 7)
GameState.heal_character(character.id, 4)
GameState.spend_character_mana(character.id, 3)
GameState.restore_character_mana(character.id, 2)

# Tartós státuszhatások és cooldownok.
GameState.set_character_status_effects(character.id, [
    {"id": "poison", "turns_left": 2, "damage_per_turn": 3}
])
GameState.set_character_ability_cooldowns(character.id, {"heavy_attack": 1})

# Példa aktív dungeon-futás adatainak mentésére.
GameState.set_run_state({"dungeon_id": "crypt_01", "floor": 2, "turn": 8})
GameState.update_run_state(&"turn", 9)

# Ha a mechanika több karaktermezőt közvetlenül módosított egy körben,
# a kör végén ezzel egyszerre biztosítható a clamp + mentés.
GameState.commit_character_state(character.id)
```

## Felszerelés API

A felszerelés a karakter `equipment` szótárában található, slotazonosító szerint. A tárgy példánya megőrzi a fejlesztési szintjét és enchantjait.

```gdscript
var character := GameState.get_active_character()
var sword: InventoryItem = character.inventory.items[0]
GameState.equip_item(character.id, sword) # Csak inventoryban lévő felszerelhető item
var equipped: InventoryItem = GameState.get_equipped_item(character.id, &"weapon")
GameState.unequip_item(character.id, &"weapon")
```

Ha a slot foglalt, az `equip_item` csak akkor cserél, ha a korábbi tárgy visszafér a hátizsákba. Ha nincs hely, a művelet sikertelen, és nem veszít el tárgyat. Az `unequip_item` ugyancsak csak akkor sikerül, ha van elég hely.

## Mit tárol karakterenként a `CharacterProfile`?

- ID, név, osztály, szint, XP
- aktuális HP és opcionális MP (a `CharacterClassData.base_mana` és `mana_per_level` adja meg, lesz-e mana)
- stressz, quirkek
- osztályból örökölt és karakterenként felülírható attribútumok (`attributes`), például strength/agility/intellect
- karakterre rakott tartós statmódosítók (`stat_modifiers`)
- minden felszerelési slot, az item fejlesztési szintjével és enchantjaival
- tartós státuszhatások, képesség-cooldownok
- `persistent_data`: későbbi küldetés-, karakter- vagy mechanikaadatok bővítéséhez
- a saját hátizsák

A közös Stash és arany account-/csapat-szintű adat. A `run_state` a futó dungeon által meghatározott, JSON-kompatibilis adatokat őrzi.

## Fontos együttműködési szabály

A csapattársak lehetőleg a `GameState` API-t használják, ne tartsanak külön, saját `current_hp`, inventory vagy felszerelés példányt. Ha egy dungeon körben közvetlenül írják a `CharacterProfile` mezőit, a kör végén hívják meg a `GameState.commit_character_state(character.id)` metódust. A módosítás csak JSON-ban tárolható értékeket használjon (`String`, számok, bool, tömb és szótár); node-ot, scene-t vagy Resource-példányt ne tegyenek a `persistent_data` vagy `run_state` mezőkbe.
