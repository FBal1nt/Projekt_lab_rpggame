# Karakterosztályok – fejlesztői útmutató

A Lobby karakterválasztója adatvezérelt. A 16 induló osztály mindegyike külön `CharacterClassData` erőforrásban szerepel a `Data/CharacterClasses/` mappában. A `GameState` induláskor rekurzívan betölti az ott található `.tres` és `.res` erőforrásokat, így új osztály felvételekor a karakterkódot és a mentéskezelést nem kell módosítani.

## A jelenlegi 16 osztály

| Azonosító | Megjelenített név | Fő szerep |
|---|---|---|
| `warrior` | Harcos | Kiegyensúlyozott frontvonal |
| `duelist` | Párbajhős | Gyors, kritikus sebzés |
| `guardian` | Védelmező | Tank és társ-védelem |
| `ranger` | Vadőr | Sokoldalú távolsági harcos |
| `marksman` | Mesterlövész | Pontos, nagy sebzésű lövések |
| `scout` | Felderítő | Mozgékonyság és utility |
| `mage` | Mágus | Sokoldalú mágikus támogató/sebző |
| `pyromancer` | Tűzmágus | Tűz és területsebzés |
| `stormcaller` | Viharmágus | Villám és kontroll |
| `cleric` | Pap | Gyógyítás és támogatás |
| `mender` | Gyógyító | Folyamatos gyógyítás |
| `occultist` | Átokmondó | Átkok és kockázatos mágia |
| `plague_doctor` | Járványorvos | Állapothatások és segédkezelés |
| `alchemist` | Alkimista | Főzetek és helyzetfüggő utility |
| `battlemage` | Harci mágus | Fizikai/mágikus hibrid |
| `beastmaster` | Fenevadidomár | Állati társra építő taktika |

Ezek induló, szerkeszthető koncepciók. A statok első körös prototípusértékek, nem végleges balansz.

## Egy osztály elemei

A `Scripts/Data/CharacterClassData.gd` kezeli az alábbiakat:

- `id`, `display_name`, `role`, `description`: stabil azonosító és UI-szövegek.
- `portrait`: karakterválasztóban megjelenő portré.
- `battle_sprite`: a Dungeon/csata jelenet számára szánt sprite vagy sprite sheet.
- `placeholder_color`: háttérszín, amíg nincs portré.
- Alapstatisztikák: életerő, sebzésminimum/maximum, védelem, sebesség, pontosság, kritikus esély, kitérés, gyógyító erő és stressztűrés.
- Szintenkénti növekedés: jelenleg életerő, sebzés és védelem.
- `skill_ids` és `skill_names`: stabil technikai azonosítók, valamint UI-nak szánt emberi nevek.
- `starting_equipment_ids`: későbbi kezdőfelszerelés-integrációhoz fenntartott ItemData-azonosítók. Ez a mező önmagában még nem ad tárgyat a karakternek.

## Új osztály hozzáadása

1. Godotban másold le egy meglévő erőforrást a `Data/CharacterClasses/` mappában, például `ranger.tres`-t, és adj neki új nevet, például `duelist.tres`.
2. Módosítsd az egyedi `id` mezőt, a nevet, a szerepet és a leírást. Az `id` minden osztálynál legyen egyedi, kisbetűs, ékezet nélküli technikai azonosító.
3. Állítsd be a statokat és a képességazonosítókat.
4. Importáld a sprite-okat a projektbe, majd a `.tres` Inspectorában rendeld a képet a `portrait` és/vagy `battle_sprite` mezőhöz. A két mező használhatja ugyanazt a képet, de külön is megadhatók.
5. Nyisd meg újra a játékot: a karakterosztály automatikusan bekerül a legördülő listába és megjelenik az előnézetben.

**Sprite-elrendezés:** a `portrait` egy karakterválasztóban használható kép. A `battle_sprite` jelenleg `Texture2D` referenciát fogad; a csatajelenetben a csapattársak dönthetik el, hogy ezt `Sprite2D`, `AnimatedSprite2D` vagy saját sprite-sheet kezelő használja. A sprite animációk működtetését ez a Lobby-rendszer még nem valósítja meg.

## API a játékmeneti rendszerhez

```gdscript
# Összes betöltött osztály, név szerint rendezve
var classes: Array[CharacterClassData] = GameState.get_character_classes()

# Osztályadat lekérése ID alapján
var class_data: CharacterClassData = GameState.get_character_class(&"ranger")

# Aktív karakter és az ő osztályából/szintjéből számolt statok
var character: CharacterProfile = GameState.get_active_character()
var stats: Dictionary = GameState.get_character_stats(character)
var max_health: int = int(stats.get("max_health", 0))

# Dungeon után az egyéni HP és stressz frissítése (automatikus mentéssel)
GameState.set_character_health(character.id, max_health - 5)
GameState.set_character_stress(character.id, 20)

# Például új karakter létrehozása
GameState.create_character("Artemis", &"ranger")
```

`CharacterProfile.class_id` az új kódban ajánlott név. A korábbi `archetype` mező kompatibilitási okból megmaradt, és ugyanazt az azonosítót tárolja. A mentés mindkét kulcsot írja, és a régi, csak `archetype` mezőt tartalmazó mentéseket is be tudja olvasni.

## Mit tárolunk a karakteren, és mit az osztályon?

- **Osztálydefiníció:** közös stat-alapértékek, szintenkénti növekedés, sprite referenciák, szerep, leírás, alap képességlista és tervezett kezdőfelszerelés.
- **Karakterprofil:** név, osztály ID, szint, XP, aktuális életerő, stressz, tulajdonság/quirk ID-k és egyéni hátizsák.
- **Közös fiók:** arany és a megosztott Stash.

Az osztályok `skill_ids` értékei jelenleg adatok; tényleges harci képességként való futtatásukhoz a Dungeon-mechanikának hozzá kell rendelnie őket a saját képességrendszeréhez. A 16 erőforrásban most még nincs egyedi portré vagy harci sprite beállítva, mert ezek a képi assetek nem voltak részei a projektnek.
