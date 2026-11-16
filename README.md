# Projekt Lab — 2D Pixel-Art Dungeon RPG (Godot 4.7)

Csoportmunkában készült 2D-s, körökre osztott / rácsalapú (grid-based) pixel-art szerepjáték **Godot 4.7** motor alatt.

---

## Projekt felépítése

```text
Projekt_lab_rpggame/
├── Assets/                  # Grafikai elemek, sprite-ok, tilesetek és UI ikonok
│   ├── Characters/          # Hősök és ellenfelek animációs sprite-lapjai
│   ├── Items/               # Tárgyikonok (Consumables, Weapons)
│   ├── Projectiles/         # Lövedékek és varázslatok effektjei (Arrows, Magic)
│   ├── Source/              # Forrásfájlok (Aseprite, PSD)
│   ├── Tilesets/            # Pályaépítő elemek (Dungeon, Tiled)
│   └── UI/                  # Felhasználói felület hátterek és ikonok
├── Data/                    # Adatvezérelt Godot (.tres) erőforrások
│   ├── CharacterClasses/    # Lobby karakterosztály-definíciók
│   ├── DungeonDifficulties/ # Nehézségi szintek és ellenfél-konfigurációk
│   ├── Dungeons/            # Kazamata-definíciók
│   ├── Enchantments/        # Kovács és Varázsló fejlesztések / varázslatok
│   ├── Heroes/              # Harci hős-adatok és SpriteFrames erőforrások
│   ├── Items/               # Tárgydefiníciók
│   ├── Monsters/            # Ellenfél-adatok és SpriteFrames erőforrások
│   ├── Projectiles/         # Lövedék erőforrások
│   └── SmithingRecipes/     # Kovácsolási és tárgyfejlesztési receptek
├── Docs/                    # Rendszerdokumentációk, tervek és bemutatók
├── Scenes/                  # Godot jelenetek (.tscn)
│   ├── Enemy/               # Ellenfél jelenet
│   ├── Inventory/           # Hátizsák, Stash és felszerelés ablakok
│   ├── Lobby/               # Központi Hub / Lobby jelenet
│   ├── Menu/                # Főmenü és mentéskezelő
│   ├── Player/              # Játékos karakter jelenet
│   ├── Projectiles/         # Lövedék és idézési effekt jelenetek
│   ├── Rooms/               # Procedurális kazamataszobák (Normal, Kapu, Wall, Zsakutca)
│   ├── Shop/                # Bolt ablak és tételsorok
│   ├── UI/                  # HUD és harci dialógus
│   └── Main.tscn            # Fő kazamata / játékmenet jelenet
├── Scripts/                 # GDScript forráskódok modulok szerint csoportosítva
│   ├── Core/                # Harci motor (CombatEngine) és rácskalkuláció (GridManager)
│   ├── Data/                # Erőforrás-osztályok (Resource definíciók)
│   ├── Enemy/               # Ellenfél AI, mozgás és harci profilok
│   ├── Managers/            # Autoload singletonok (GameState, DungeonManager, SettingsManager)
│   ├── Player/              # Hős irányítás, fejlődés, harc és megjelenítés
│   ├── Projectiles/         # Lövedékek vezérlése
│   ├── UI/                  # Menü, Lobby, Inventory, Bolt, Kovács, Varázsló és HUD szkriptek
│   ├── Utils/               # Segédeszközök (ResourceCatalog)
│   └── World/               # Procedurális pályagenerátor (MapGenerator) és Fog of War
├── Tools/                   # Fejlesztői ellenőrző szkriptek
│   └── validate_project.py  # Statikus projekt- és erőforrás-ellenőrző
└── project.godot            # Godot 4 projektkonfiguráció
```

---

## Fejlesztői dokumentációk (`Docs/`)

- [Kódbázis útmutató](Docs/CODEBASE_GUIDE.md)
- [Globális adattárolás és mentés](Docs/GLOBALIS_ADATTAROLAS.md)
- [Karakterrendszer](Docs/KARAKTERRENDSZER.md) és [Karakterosztályok](Docs/KARAKTEROSZTALYOK.md)
- [Felszerelés és statisztikák](Docs/FELSZERELES_ES_STATRENDSZER.md)
- [Bolt működése](Docs/BOLT_MUKODES.md)
- [Kovácsműhely működése](Docs/KOVACS_MUKODES.md)
- [Varázslótorony működése](Docs/VARAZSLO_MUKODES.md)
- [Dungeonválasztás és nehézség](Docs/DUNGEON_VALASZTAS_ES_NEHEZSEG.md)

## Projekt ellenőrzése

A `res://` hivatkozások, erőforrás-azonosítók és jelenetfájlok konzisztenciájának ellenőrzéséhez futtasd:

```bash
python Tools/validate_project.py
```
