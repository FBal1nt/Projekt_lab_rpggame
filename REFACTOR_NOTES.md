# Refaktorálási jegyzetek – 1. kör

## Mi változott?

- A rekurzív `.tres` / `.res` fájlkeresés közös helyre került: `Scripts/Utils/ResourceCatalog.gd`.
- A `GameState`, `DungeonManager` és `ShopWindow` most ugyanazt a segédosztályt használja adatfájlok keresésére.
- A `GameSaveSerializer.gd` külön felelősségként kezeli a mentési pillanatkép létrehozását, az inventory/tárgy/felszerelés szerializálását és a JSON fájlba írását; a betöltés és migráció változatlanul a `GameState`-ben maradt.
- A nagyobb scriptekbe logikai fejezetcímek kerültek. Ezek csak olvashatóságot szolgálnak, a futási logikát nem módosítják.
- Elkészült a `CODEBASE_GUIDE.md`, amely leírja a fő felelősségi köröket, a globális API-k használatát és a csapat kódolási konvencióit.

## Miért nem lett még szétbontva a GameState és az InventoryGrid?

Ezek jelenleg sok UI- és gameplay-összeköttetés központjai. Egy lépésben történő teljes szétszedés könnyen megtörheti a jelenlegi kompatibilitási API-kat, különösen úgy, hogy ebben a környezetben a Godot futtatókörnyezet nem elérhető. Ezért ez a kör az ismétlődő kód megszüntetésére és a könnyebb navigációra koncentrál.

A `CODEBASE_GUIDE.md` javaslatot ad a következő, külön tesztelhető bontási lépésekre.

## Ellenőrzés

- Ellenőrizendő: projektbeli resource-hivatkozások, adat-ID-k, receptmezők és a közös erőforrás-kereső használata.
- Nem állítható: a projekt Godotban sikeresen lefutott. Ebben a környezetben nincs Godot futtatható állomány, ezért a változtatás után szerkesztőben és játékindítással is tesztelni kell.
