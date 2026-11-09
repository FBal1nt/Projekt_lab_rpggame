# Kódbázis-útmutató

Ez a dokumentum a csapat számára foglalja össze a projekt fő felelősségi köreit, a bővítés menetét és a kódolási szabályokat. A cél, hogy új funkció hozzáadásakor ne kelljen minden meglévő scriptet végigolvasni.

## 1. Rövid állapotkép

A projekt jelenleg **funkcióprototípus / integrációs alap**. Már létezik a Lobby, a karakterenkénti hátizsák, a közös Stash, a Bolt, a Kovács és Varázsló felülete, a karakterosztály-adatmodell, a globális beállítások és a Dungeon-választó konfigurációja. A tényleges Dungeon-jelenet és a teljes harcrendszer még csapatfeladat.

A játékot az aktuális fejlesztői környezetben nem sikerült Godotból futtatni, ezért ezt a csomagot kódstruktúra- és statikus ellenőrzésen átesett kiindulópontnak tekintsétek, ne végleges, futásidőben validált buildnek.

## 2. Hol mit kell keresni?

| Hely | Felelősség | Mikor kell módosítani? |
|---|---|---|
| `Scripts/Managers/GameState.gd` | Központi játékmeneti állapot, karakterek, arany, inventoryk, felszerelés, statok, craft/upgrade/enchant, mentésvezérlés | Ha tartós játékállapot vagy gazdasági tranzakció változik |
| `Scripts/Managers/GameSaveSerializer.gd` | Karakterek, tárgyak, felszerelés és közös Stash JSON-kompatibilis mentési alakra alakítása, fájlba írás | Ha a mentés exportformátuma változik |
| `Scripts/Managers/SettingsManager.gd` | Globális grafikai/hangbeállítások és a minden jelenetből elérhető overlay | Ha új, mentendő játékbeállítás érkezik |
| `Scripts/Managers/DungeonManager.gd` | Dungeon- és nehézségdefiníciók, futáskonfiguráció, spawn-segédadatok | Ha a dungeon indítási vagy konfigurációs logika változik |
| `Scripts/Utils/ResourceCatalog.gd` | `.tres` / `.res` adatfájlok rekurzív, rendezett felderítése | Ha egységesíteni kell az adatfájlok keresését |
| `Scripts/Data/*.gd` | Adatmodellek és `Resource`-definíciók | Ha új, adatvezérelt mező vagy definíciótípus kell |
| `Data/Items/` | Tárgydefiníciók | Új fegyver, páncél, nyersanyag, fogyóeszköz esetén |
| `Data/CharacterClasses/` | A 16 osztály statjai, sprite-hivatkozásai és képességazonosítói | Új osztály vagy osztálybalansz esetén |
| `Data/SmithingRecipes/` | Craft- és +1–+5 fejlesztési receptek | Új kovácsreceptnél vagy költségmódosításnál |
| `Data/Enchantments/` | Kovács- és Varázsló-fejlesztések | Új fizikai fejlesztés vagy mágikus enchant esetén |
| `Data/Dungeons/` | Dungeonválasztási adatok | Új dungeon hozzáadásakor |
| `Data/DungeonDifficulties/` | Spawn-, szint-, enemy-pool- és elitbeállítások | Új fokozat vagy nehézségbalansz esetén |
| `Scripts/UI/` | Csak felhasználói felület, megjelenítés és események | Ha ablak vagy interakció megjelenése változik |

## 3. Globális szolgáltatások

A `project.godot` három Autoloadot regisztrál:

- `GameState`: karakterek és a mentendő játékmeneti állapot.
- `DungeonManager`: dungeon-konfiguráció és indítás.
- `SettingsManager`: játékbeállítások és globális beállításablak.

Ezekhez a jelenetből közvetlenül hozzá lehet férni; **ne készítsetek párhuzamos, scene-local példányt ugyanebből az állapotból**.

### Állapotmódosítás

- Karakter HP/MP-módosításához a `GameState.damage_character()`, `heal_character()`, `set_character_health()`, `spend_character_mana()` vagy `restore_character_mana()` API-t használjátok.
- Egy körben végzett, több mezőt érintő karakterfrissítés után hívjátok meg a `GameState.commit_character_state(character.id)` metódust.
- Dungeon-konfiguráció módosításakor a `GameState.set_run_state()` vagy `GameState.update_run_state()` használatos.
- A `GameState.run_state` csak JSON-kompatibilis értékeket tartalmazzon: szám, szöveg, logikai érték, tömb vagy Dictionary. Ne mentsétek bele közvetlenül Node-ot, Resource-t vagy Objectet.
- A `GameState.backpack` a régi kód kompatibilitása miatt elérhető; új kódban a `GameState.get_active_inventory()` az ajánlott.

## 4. Új tartalom hozzáadásának szabályai

1. Adjatok minden tartalomnak stabil, egyedi `id`-t, lehetőleg kisbetűs `snake_case` formában.
2. A UI-kód ne tartalmazza beégetve a tárgyak vagy osztályok teljes listáját. Az adatokat a `Data/` könyvtár definícióiból olvassa be.
3. Erőforrásokat a `ResourceCatalog.collect_resource_paths()` metódussal keressetek, hogy a bejárás rekurzív és mindenhol azonos legyen.
4. A megjelenített név magyar szöveg lehet, de a technikai azonosító ne függjön a lokalizált névtől.
5. Módosítás után ellenőrizzétek, hogy nincs-e duplikált ID, hibás resource-útvonal, illetve hogy minden recept nyersanyag-ID-ja létezik-e.

## 5. A UI és a játékmenet szétválasztása

A UI felelőssége: adat megjelenítése, választás bekérése, a szolgáltatás meghívása, hiba/siker visszajelzése. A UI ne másolja le saját változókba a karakter tartós HP-ját, aranyát vagy inventoryját úgy, mintha az lenne az igazság forrása.

A játékmeneti szabályok helye a `GameState` vagy az adott szolgáltatás. A craft, vásárlás, fejlesztés és enchant legyen tranzakció: a feltételeket előbb ellenőrizzük, és csak siker esetén módosítsuk az aranyat, a nyersanyagokat vagy a tárgyat.

## 6. Mentési fájlok

- Karakter- és játékmeneti mentés: `user://savegame.json`.
- Beállítások: `user://settings.cfg`.

A mentés verziószámmal rendelkezik. A `GameSaveSerializer.gd` állítja elő és írja ki a JSON-adatot; a betöltés és a migráció továbbra is a `GameState.gd` feladata, mert annak szüksége van az aktuálisan betöltött osztály-, tárgy- és enchantdefiníciókra. Új kötelező mező bevezetésekor adjatok meg alapértelmezést a régi mentésekhez, és emeljétek a mentésverziót, ha valódi migráció szükséges. Ne töröljétek a régi mentési adatot csak azért, mert új mező érkezik.

## 7. Kódolási konvenciók

- Függvények neve: `snake_case`; változók: `snake_case`; konstansok: `UPPER_SNAKE_CASE`.
- Típusozzátok a publikus függvények paramétereit és visszatérési értékét, ahol ez egyértelmű.
- A publikus metódusok előtt írjatok rövid docstringet, ha a név önmagában nem mondja el a szerződését.
- A `UI` script ne legyen felelős egyszerre mentésért, adatbetöltésért és harci szabályokért.
- Új adatmezőnél dokumentáljátok az elvárt kulcsnevet, mértékegységet és a százalékos értékek tartományát. Például a `crit_chance` jelenleg 0–100 közötti százalékot jelent.
- Ne végezzetek nagyszabású átnevezést párhuzamos csapatmunka közben, amíg a Dungeon és a harcrendszer integrációja nincs stabilizálva.

## 8. Ajánlott következő refaktorálási kör

A következő, külön tesztelhető lépésként érdemes a `GameState.gd` nagy felelősségeit fokozatosan külön szolgáltatásokra bontani:

1. `SaveGameRepository`: csak mentés, visszatöltés és verziómigráció.
2. `CharacterService`: karakter-létrehozás, fejlődés, HP/MP és effektív statok.
3. `ItemEconomyService`: vásárlás/eladás, craft, fejlesztés és enchant.

A `GameState` maradjon vékony, kompatibilitást biztosító Autoload-felület. Ezt a bontást a harcrendszer első integrációja után javasolt megkezdeni, és minden lépés után tesztelni, hogy ne keletkezzen két külön állapotforrás.
