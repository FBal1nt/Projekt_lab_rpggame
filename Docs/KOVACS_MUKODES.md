# Kovácsműhely – fejlesztői útmutató

A Kovács UI a teljes ablakot használja, a karakterkártya és a felszereléslista a bal oldalon, a műveletek és részletek a jobb oldalon vannak. A jobb oldali módválasztóban öt opció található: **Készítés**, **Fejlesztés**, **Élesítés**, **Védelem** és **Vérzés**. A tartalom görgethető, így a hosszabb receptek és fejlesztési listák alacsonyabb ablakmagasságnál is elérhetők.

- **Készítés**: a `Data/SmithingRecipes/` mappa `recipe_type = &"craft"` receptjeit sorolja fel, ellenőrzi a nyersanyagokat, az aranyat és a karakter Inventory-jában lévő szabad helyet, majd az elkészült tárgyat az aktív karakterhez adja.
- **Fejlesztés**: a bal oldali listában kiválasztott, fejleszthető tárgyat a következő szintre emeli +1-től legfeljebb +5-ig. Az ár és az összetevők az adott szint `upgrade_*.tres` receptjéből jönnek.
- **Élesítés**, **Védelem**, **Vérzés**: továbbra is adatvezérelt enchantokkal működő fizikai tárgyfejlesztések.

A fejlesztések `Data/Enchantments/` alatti `.tres` erőforrások. A `workshop_type = &"blacksmith"` és az `option_category` dönti el, hogy melyik Kovács-opcióban jelennek meg. A UI automatikusan szűri a fejlesztéseket a kiválasztott tárgy `item_type` értéke alapján. Az arany- és nyersanyagköltséget a rendszer a művelet végrehajtása előtt ellenőrzi; a nyersanyag a hátizsákból, majd a közös Stash-ből fogy.

A készítési receptek és a +1…+5 fejlesztési API-k a Kovács UI-jába is be vannak kötve. Az alábbiak szerint lehet a listákat tartalommal bővíteni.

> A tényleges karakterre szereléshez és a harci következményekhez a csapat felszerelés-/harci rendszerét kell bekötni. A Kovács jelenleg mentett tárgy-statokkal és fejlesztésazonosítókkal dolgozik.

## Új kovácsolási recept hozzáadása

1. Készíts vagy másolj egy `ItemData` erőforrást a `Data/Items/` mappába.
2. Adj neki egyedi `id` értéket. Felszerelésnél töltsd ki az `item_type` mezőt (`weapon`, `armor`, `ring`, `earring`), az `equipment_slot` mezőt, a `base_stats` értékeket és szükség esetén a `can_upgrade` / `upgrade_stat_bonuses` mezőket.
3. Másolj egy fájlt a `Data/SmithingRecipes/` mappába és módosítsd:
   - `id`: stabil, egyedi receptazonosító.
   - `display_name`, `description`: a Kovács UI-jában látható szöveg.
   - `recipe_type = &"craft"`.
   - `result_item_id`: a `Data/Items/` alatti tárgy `id` értéke.
   - `ingredient_item_ids` és `ingredient_amounts`: egyező hosszúságú listák.
   - `gold_cost`: aranyköltség.
4. A `GameState` indításkor automatikusan betölti a mappában lévő `.tres` fájlokat; a recept külön UI-kód módosítása nélkül megjelenik.

Példa egy recept erőforrás-tartalmára:

```ini
recipe_type = &"craft"
result_item_id = &"iron_ring"
ingredient_item_ids = PackedStringArray("iron_ingot", "leather_strip")
ingredient_amounts = PackedInt32Array(3, 1)
gold_cost = 55
```

## A +1…+5 fejlesztési árak módosítása

A `Data/SmithingRecipes/upgrade_1.tres` … `upgrade_5.tres` fájlok állítják a fokozatok anyag- és aranyköltségét. Ezeknél a `recipe_type` értéke `&"upgrade"`, a `target_upgrade_level` pedig 1 és 5 közötti érték. Minden fokozathoz pontosan egy aktív receptet használjatok.

Az adott tárgy csak akkor fejleszthető, ha az `ItemData.can_upgrade = true`, és a `max_upgrade_level` elég magas. A felső korlát jelenleg +5.

## Új enchant hozzáadása

1. Másolj egy `.tres` fájlt a `Data/Enchantments/` mappába.
2. Állíts be stabil `id`, `display_name`, `description`, `applicable_item_types`, `ingredient_item_ids`, `ingredient_amounts`, `gold_cost` és `stat_modifiers` mezőket.
3. A `stat_modifiers` a `GameState.get_item_stats(item)` által összesített, additív statbónusz. Például:

```ini
applicable_item_types = PackedStringArray("weapon")
ingredient_item_ids = PackedStringArray("arcane_dust")
ingredient_amounts = PackedInt32Array(2)
gold_cost = 75
stat_modifiers = {"damage": 3.0}
```

Az `applicable_item_types` a tárgy `ItemData.item_type` értékeit használja. Üres tömb esetén az enchant minden tárgytípushoz megjelenik, de ezt csak tudatosan használjátok.

**Fontos:** a `id` értékekre mentett tárgyak hivatkoznak. Egy már játékba került enchant ID-ját ne változtassátok meg, hacsak nem készítetek mentésmigrációt.

## Hasznos GameState API-k

- `GameState.get_smithing_recipes(&"craft")`
- `GameState.get_smithing_recipes(&"upgrade")`
- `GameState.get_enchantments()` / `GameState.get_enchantment(id)`
- `GameState.craft_recipe(recipe)`
- `GameState.can_upgrade_item(item)` / `GameState.upgrade_item(item)`
- `GameState.can_apply_enchantment(item, id)` / `GameState.apply_enchantment(item, id)`
- `GameState.get_item_stats(item)` – a tárgy alapstatjai, fejlesztési bónuszai és enchantjai összevonva.
- `GameState.get_item_count(id)` – az aktív karakter hátizsákja és a közös Stash összesített mennyisége.

A kovács a jelenlegi aktív karakter hátizsákjában lévő tárgyakat listázza. Az alapanyagokat közösen használja a hátizsákból és a Stash-ből, a létrehozott tárgyat viszont az aktív karakter kapja.

## Új UI: Kovács és Varázsló (adatvezérelt tárgyfejlesztések)

- A két menü közös `Scripts/UI/ItemAugmentationWindow.gd` felületalapot használ. A karakterkártya a bal oldali panel tetején, a karakter hátizsákjában lévő felszerelések listája alatta, a három műveleti opció és a részletek a jobb oldali panelen találhatók.
- A Kovács látható opciói: `craft` (készítés), `upgrade` (a kiválasztott tárgy +1…+5 fejlesztése), `sharpen` (élesítés), `defense` (fizikai védelem), `bleeding` (vérzés).
- A Varázsló látható opciói: `weapon_element` (tűz/jég/méreg/villám fegyverhatások), `resistance` (elemi ellenállások), `utility_boost` (életerő és harcon kívüli HP-regeneráció).
- Új vagy módosított fejlesztéshez adj/szerkessz `.tres` fájlt a `Data/Enchantments/` mappában. A fontos mezők: `id`, `workshop_type`, `option_category`, `element`, `applicable_item_types`, `ingredient_item_ids`, `ingredient_amounts`, `gold_cost` és `stat_modifiers`.
- `stat_modifiers` numerikus kulcsai összeadódnak a `GameState.get_item_stats(item)` eredményében. A kulcsokat a harcrendszer később a tényleges harci szabályokhoz kapcsolhatja. Példák: `damage`, `crit_chance`, `defense`, `bleed_chance`, `bleed_damage`, `max_bleed_stacks`, `fire_damage`, `fire_attack_bonus`, `fire_extra_attack_chance`, `ice_damage`, `ice_resistance`, `poison_damage`, `poison_resistance`, `max_health`, `out_of_combat_hp_regen`.
- A bónusz és az enchant az `InventoryItem.enchantment_ids` mezőn tárolódik, ezért a már meglévő mentési rendszer új indítás után is visszaállítja. A UI nem enged többször ugyanazt az enchantot ugyanarra a tárgypéldányra alkalmazni.
- A Kovács `KÉSZÍTÉS` és `FEJLESZTÉS` menüje közvetlenül a receptadatokat használja. Új recept hozzáadása automatikusan megjelenik a listában, külön UI-módosítás nélkül.

### Fontos a csapattársaknak

Az `out_of_combat_hp_regen`, `fire_extra_attack_chance`, `ice_slow_chance`, `poison_chance` és hasonló értékek jelenleg mentett, lekérdezhető tárgy-statok. A tényleges extra támadás, lassítás, DoT, ellenállás-számítás és harcon kívüli regeneráció triggerelését a Dungeon/harcrendszernek kell majd megvalósítania a statértékek alapján.
