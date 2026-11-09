# Varázslótorony – fejlesztői útmutató

A Varázsló ugyanazt a teljes ablakot kitöltő, nagyobb felületet használja, mint a Kovács. Bal oldalon a karakterkártya és a felszereléslista, jobb oldalon a három mágikus kategória és az elérhető fejlesztések jelennek meg. Három opciója van:

- `weapon_element`: fegyverek elemi hatásai (tűz, jég, méreg, villám), extra elemi sebzéssel, támadási bónusszal és opcionális proc/extra-támadás eséllyel.
- `resistance`: páncélra és ékszerekre alkalmazható elemi ellenállások, néha életerő- vagy regenerációs bónusszal.
- `utility_boost`: életerő- és harcon kívüli HP-regenerációs bónuszok.

## Új varázslat/enchant hozzáadása

1. Másolj egy `.tres` fájlt a `Data/Enchantments/` mappában.
2. Állíts be egyedi `id`, olvasható `display_name`, `description`, `workshop_type = &"wizard"`, `option_category`, opcionálisan `element`, valamint `applicable_item_types` értéket.
3. Az `ingredient_item_ids` és `ingredient_amounts` hossza legyen azonos; az anyagazonosítók a `Data/Items/` alatti tárgyak `id` mezőjére hivatkoznak.
4. Állítsd be a `gold_cost` költséget és a `stat_modifiers` numerikus dictionary-t.

Például egy fegyverre tehető jégenchant:

```ini
workshop_type = &"wizard"
option_category = &"weapon_element"
element = &"ice"
applicable_item_types = PackedStringArray("weapon")
ingredient_item_ids = PackedStringArray("arcane_dust", "silver_ingot")
ingredient_amounts = PackedInt32Array(2, 1)
gold_cost = 90
stat_modifiers = {"ice_damage": 2.0, "ice_attack_bonus": 1.0, "ice_slow_chance": 15.0}
```

## Javasolt statkulcsok

| Hatás | Statkulcsok |
|---|---|
| Fizikai sebzés és kritikus találat | `damage`, `crit_chance` |
| Vérzés | `bleed_chance`, `bleed_damage`, `max_bleed_stacks` |
| Elemi fegyverhatás | `fire_damage`, `ice_damage`, `poison_damage`, `lightning_damage` |
| Elemi támadási bónusz / extra támadás | `fire_attack_bonus`, `ice_attack_bonus`, `poison_attack_bonus`, `lightning_attack_bonus`, illetve a megfelelő `*_extra_attack_chance` |
| Elemi ellenállás | `fire_resistance`, `ice_resistance`, `poison_resistance` |
| Támogató bónusz | `max_health`, `out_of_combat_hp_regen`, `defense`, `speed` |

A `GameState.get_item_stats(item)` összeadja az alapstatokat, a +szintek bónuszait és a tárgy `enchantment_ids` mezőjében tárolt enchantbónuszokat. Az alkalmazott enchant az Inventory mentésébe bekerül, ezért karakterváltás és újraindítás után is megmarad.

**Fontos:** ezek a numerikus értékek már tárolódnak és lekérdezhetők; a tényleges extra támadás, DoT, lassítás, ellenállás-számítás és harcon kívüli regeneráció viselkedését a Dungeon/harcrendszernek kell a megfelelő statkulcsok alapján megvalósítania.
