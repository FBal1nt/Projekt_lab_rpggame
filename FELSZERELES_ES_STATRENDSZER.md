FELSZERELÉS ÉS KARAKTERSTATISZTIKÁK

Áttekintés
A karakter felszerelése karakterenként külön tárolódik. A felszerelési helyek az ItemData.equipment_slot mező értékével azonosíthatók. A jelenlegi felületen a fegyver, páncél, gyűrű és fülbevaló hely érhető el.

Karakteradatok
A CharacterProfile három fontos mezőt tartalmaz:
- equipment: a felszerelt InventoryItem példányok, felszerelési hely szerint tárolva.
- base_stats: az osztályból és a karakter szintjéből számolt alapstatisztikák.
- derived_stats: a végleges statisztikák, amelyek az alapértékek és a felszerelt tárgyak módosítóinak összegei.

A GameState.recalculate_character_stats(character) újraszámolja és eltárolja az adott karakter alap- és végleges statjait. A GameState.get_character_stats(character) a végleges statisztikákat adja vissza. Ha a paraméter nincs megadva, az aktív karakter statjait adja vissza. A harcrendszernek ezt a lekérdezést kell használnia a tényleges sebzés, védelem, sebesség, pontosság és egyéb jellemzők meghatározásához.

Tárgymódosítók
Az ItemData.base_stats tartalmazza a tárgy alapbónuszait. Az ItemData.upgrade_stat_bonuses a fejlesztési szintenként hozzáadott értékeket tartalmazza. Az InventoryItem.upgrade_level jelöli a tárgy aktuális fejlesztési szintjét. Az InventoryItem.enchantment_ids az alkalmazott varázslatok azonosítóit tárolja.

A GameState.get_item_stats(item) egyesíti a tárgy alapértékeit, a fejlesztési bónuszokat és az enchantok módosítóit. A karakter végleges statjainál a damage kulcs a damage_min és damage_max értékhez egyaránt hozzáadódik. A többi statkulcs a megfelelő alapértékhez adódik hozzá. Új statkulcs felvehető az ItemData vagy EnchantmentData erőforrásban, a karakter végleges statisztikái pedig automatikusan eltárolják.

Példa
A Harcos 1. szinten 4–8 alapsebzéssel rendelkezik. A jelenlegi vas kard +10 damage bónuszt ad. A kard felszerelése után a karakter végleges sebzése 14–18 lesz. Az alapérték továbbra is 4–8 marad a base_stats mezőben, míg a 14–18 érték a derived_stats mezőben tárolódik.

Felszerelés műveletek
A GameState.can_equip_item(item, character) előzetesen ellenőrzi, hogy a tárgy a karakter hátizsákjában van-e, egyedi tárgy-e, és rendelkezik-e érvényes felszerelési hellyel. Ha a hely foglalt, a rendszer ellenőrzi, hogy a korábbi tárgy visszatehető-e a hátizsákba. A GameState.equip_item(item, character) csak sikeres ellenőrzés után cseréli le a felszerelést.

A GameState.can_unequip_item(slot, character) ellenőrzi, hogy van-e elegendő szabad hely a tárgy visszahelyezéséhez. A GameState.unequip_item(slot, character) sikertelen, ha a tárgy nem fér vissza. A sikertelen felszerelés- és levételművelet nem módosítja az inventoryt.

A lobby Tárgyak ablakában először a hátizsák tárgyát kell kiválasztani, majd a FELSZEREL gombbal lehet felvenni. A felszerelt tárgy helyét kiválasztva a LEVÉTEL gombbal lehet visszatenni a hátizsákba. A karakterváltáskor a felület az új aktív karakter saját hátizsákját, felszerelését és végleges statjait mutatja.

Kovács és Varázsló
A műhelyek tárgylistája a hátizsák tárgyai mellett a karakter már felszerelt tárgyait is tartalmazza. Emiatt a felszerelt fegyver vagy páncél közvetlenül fejleszthető, illetve enchantolható. A műveletek után a GameState újraszámolja a karakter statjait.

Mentés
A mentési adat tartalmazza a karakter alap- és végleges statjait, az egyéni inventoryját, valamint a felszerelési helyeken tárolt tárgypéldányokat is. Betöltéskor a rendszer először visszaállítja a tárgyakat és a felszerelést, utána újraszámolja a végleges statokat, így a karakter statisztikái nem vesznek el mentésváltáskor.

Felület – karakter és felszerelési helyek
Az inventory felszerelési paneljén a karakter középen jelenik meg, körülötte a fegyver, páncél, gyűrű és fülbevaló helyével. A felszerelési helyeken ikonok láthatók szöveges tárgynevek helyett. Ha a tárgy saját ikonja elérhető, azt használja a felület; egyébként a felszerelési helyhez tartozó alapértelmezett ikon jelenik meg. Az ikon fölé vitt egérmutató megjeleníti a tárgy nevét, leírását és statmódosítóit. A karakter osztályportréját használja, ha az adott osztályhoz van beállítva kép, ellenkező esetben az általános karakterikon jelenik meg.

A kovács- és varázslóablak közös, viewporthoz igazodó keretet használ. A Bezárás gomb a jobb felső sarokhoz rögzített, az aranymennyiség pedig a fejlécben fenntartott szélességű, sortörés nélküli mezőben jelenik meg, így kisebb ablakméretnél sem szorul egyetlen betűs oszlopba.
