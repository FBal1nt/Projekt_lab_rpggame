# RPG projekt – fejlesztési terv és jelenlegi állapot

## Mi került be ebbe a változatba?

- Új, saját készítésű, középkori-fantasy hangulatú Lobby-háttér és hozzá illő épületikonok.
- Újratervezett, méretezéshez alkalmazkodó főmenü: **Játék indítása**, **Beállítások**, **Kilépés**.
- Működő alapbeállítások: fő hangerő és teljes képernyős mód, helyi mentés a `user://settings.cfg` fájlba.
- Grafikailag egységes épületgombok, hover/lenyomott állapotokkal és eszköztippekkel.
- A Lobby felső sávja most az aranyat és a szintet mutatja, és hozzáadódott a visszalépés a főmenübe.
- A karakter, kovács, varázsló és dungeon ablakok a mostani prototípusban már röviden jelzik, mi kerülhet majd beléjük.
- Javítva a `GameState` kezdőtárgyainak kis-/nagybetű-érzékeny erőforrásútvonala és a főmenü Lobby-jelenetváltása.
- Az inventory tárgyfelvétele a több új stack létrehozásakor egyetlen `inventory_changed` jelet küld, nem minden új stack után külön.
- A bolt a vásárlás/eladás utáni állapotváltozásra frissít, és megnyitáskor is újratölti az eladási listát.

## Javasolt fejlesztési sorrend

### 1. Egy teljesen végigjátszható alapciklus

A következő nagy lépés a dungeon prototípus. Legyen egy rövid, egyszerű küldetés, egy ellenfél, játékos- és ellenfél-életerő, győzelem/vereség állapot, majd a végén jutalom aranyban és XP-ben. A jutalom után vissza lehessen térni a Lobbyba. Ezzel a projekt már nemcsak menükből és rendszerekből áll, hanem van egy ismételhető játékmeneti köre.

### 2. Karakterfejlődés és felszerelés

- A karakterablak mutassa az életerőt, támadást, védelmet, szintet és XP-t.
- A felszerelés az inventoryból kerüljön a karakter megfelelő slotjaiba.
- A szintlépés adjon látható statnövekedést vagy választható fejlesztést.
- A boltban vásárolt tárgyak hassanak ténylegesen a karakterre.

### 3. Mentés és folytatás

Érdemes csak azután bevezetni a főmenü **Folytatás** gombját, amikor már van mit menteni. A mentés első körben JSON-fájlba kerülhet (`user://savegame.json`): arany, szint, XP, hátizsák, raktár és a tárgyak pozíciói/mennyiségei. A betöltésnél ellenőrizni kell a fájl érvényességét, a tárgyazonosítókat és a verziót. Később több mentési hely is támogatható.

### 4. Inventory minőségjavítása

- Hátizsák és raktár közötti kétkattintásos áthelyezés.
- Egyértelmű visszajelzés, ha egy tárgy nem fér el vagy egy stack megtelt.
- Tárgyadatok külön `Resource` fájlokban, a játéklogika és a megjelenítés további szétválasztásával.
- A bolt és inventory UI-jának újraépítése csak akkor fusson le, amikor tényleg változott az adat.

### 5. Utolsó vizuális kör

- A főmenü és a Lobby ikon-, szín- és betűrendszere már közös `ui_theme.gd` segédfájlt használ.
- Következőnek érdemes közös stílust adni a bolt és inventory belső elemeinek is.
- Ezután animációk jöhetnek: finom hover-fény, panelnyitás, vásárlási visszajelzés és rövid hanghatások.

## Fontos megjegyzés

Ez a csomag a projektfájlok és útvonalak statikus ellenőrzésén esett át. Ebben a futtatókörnyezetben nem volt telepített Godot Editor/engine, ezért a jelenetek tényleges elindítását és kattintásos tesztelését itt nem tudtam lefuttatni. Első megnyitáskor Godotban kérlek futtasd a projektet, és ha a parser vagy az import bármilyen hibát jelez, a pontos hibaüzenet alapján lehet tovább javítani.
