# RPG projekt – jelenlegi állapot és fejlesztési terv

## Jelenlegi alap

A projekt már tartalmazza a Lobby/főmenü felületet, a karakterosztály-választást, a karakterenkénti hátizsákokat, a közös Stash-t, a vásárlás/eladás alapfunkciókat, a Kovács és Varázsló adatvezérelt fejlesztéseit, a globális beállításokat, valamint a Dungeon és nehézség kiválasztását.

A tartalmi definíciók nagyrészt a `Data/` alatti `.tres` erőforrásokban vannak. A karakterek és a közös raktár a `user://savegame.json` fájlba, a játékbeállítások a `user://settings.cfg` fájlba kerülnek.

## Könyvtárak röviden

- `Scenes/` – Godot-jelenetek.
- `Scripts/Data/` – adatmodellek (`Resource`-ok).
- `Scripts/Managers/` – globális állapot és játék-szolgáltatások.
- `Scripts/UI/` – a felhasználói felületek.
- `Scripts/Utils/` – általános, több rendszer által használt segédfunkciók.
- `Data/` – osztályok, tárgyak, receptek, enchantok és dungeon-konfigurációk.
- `Arts/` – UI-ikonok, hátterek és tárgyképek.

A részletes felelősségi körök és kódolási szabályok a [`CODEBASE_GUIDE.md`](CODEBASE_GUIDE.md) fájlban találhatók. A legutóbbi alacsony kockázatú refaktorálás rövid összefoglalója: [`REFACTOR_NOTES.md`](REFACTOR_NOTES.md).

## Javasolt fejlesztési sorrend

### 1. Dungeon-jelenet és harci alapciklus

A kiválasztott Dungeon-konfigurációt át kell kötni a valódi pályajelenetbe. Az első játszható verzióban elég egy rövid pálya, egy-két ellenféltípus, körönkénti támadás, HP/MP-kezelés, győzelem/vereség, XP és aranyjutalom, valamint a Lobbyba visszatérés.

### 2. Karakterfelszerelés és harcrendszer integrációja

A már létrehozott equipment-slotokat, az osztálystatisztikákat, a +1–+5 fejlesztést és az enchantok statkulcsait a harci számításokban is alkalmazni kell. A tényleges extra támadás, vérzés, méreg, lassítás és harcon kívüli regeneráció a Dungeon/harcrendszer feladata marad.

### 3. Integrációs és regressziós tesztek

A teljes csapat közös ága előtt érdemes végigtesztelni: karakterlétrehozás és váltás, hátizsák–Stash mozgatás, bolt vásárlás/eladás, craft/fejlesztés/enchant, mentés és visszatöltés, beállítások minden jelenetből, Dungeon-konfiguráció átadása a pályának.

### 4. Nagyobb architekturális refaktorálás

A jelenlegi `GameState.gd` több felelősséget fog össze. A harcrendszer első integrációja után külön, tesztelhető lépésekben érdemes kiválasztani belőle a mentést/betöltést, a karakterkezelést és a tárgygazdaságot. Ez ne egyetlen nagy átnevezési kör legyen, mert több csapattársi rendszer is a jelenlegi API-ra építhet.

## Tesztelési megjegyzés

A fejlesztési ZIP statikus fájl- és hivatkozásellenőrzésen esett át. A Godot Editor/engine nem volt elérhető ebben a környezetben, ezért a tényleges jelenetindítás és a kattintásos tesztelés a csapat gépén továbbra is szükséges.
