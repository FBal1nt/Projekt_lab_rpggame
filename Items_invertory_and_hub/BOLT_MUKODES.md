# Bolt – vásárlás és eladás

## Vásárlás

- A Bolt bal oldalán az aktív karakter saját hátizsákja látható.
- A jobb oldali lista automatikusan beolvassa a `Data/Items/` könyvtár `.tres` és `.res` `ItemData` erőforrásait.
- Vásárláshoz húzd a kívánt tárgyat a hátizsák megfelelő cellájára.
- A zöld előnézet azt jelenti, hogy a tárgy a célcellára elhelyezhető és van elég arany. A piros előnézet helyhiányt, foglalt cellát, megtelt stacket vagy elégtelen aranyat jelez.
- A vásárlás csak elengedéskor történik meg, és csak akkor, ha mindkét feltétel teljesül. Sikertelen próbálkozás nem von le aranyat és nem módosítja az inventoryt.
- Ha ugyanazon tárgy stackjére ejted, és abban van hely, egy egységgel nő a stack, és a megfelelő ár levonásra kerül.

## Eladás

- Jelölj ki egy tárgyat a bal oldali hátizsákban.
- Az alsó eladási gomb megmutatja a teljes stackért járó összeget.
- Az eladás a teljes kijelölt stacket értékesíti, és hozzáadja az aranyat a közös egyenleghez.

## Inventory-tárgy mozgatása és visszavonása

- Ha egy kijelölt tárgyat a saját eredeti helyére ejtesz vissza, a művelet sikeres, de nem módosítja az inventory-adatokat.
- Ha egy már kijelölt tárgyra ismét rákattintasz, és nem húzod el, megszünteti a kijelölést. Ha a kattintás után elhúzod, a szokásos drag-and-drop mozgatás indul.
- A kijelölés törlése a Bolt eladási paneljét is frissíti, így nem marad aktív egy már nem kijelölt tárgy eladása.

## Új termék felvétele

Adj hozzá egy `ItemData` erőforrást a `Data/Items/` könyvtárhoz, töltsd ki az egyedi `id`, `display_name`, `description`, `icon`, `size`, `max_stack`, `buy_price` és `sell_price` mezőket. A termék a Bolt listájába automatikusan bekerül; nincs szükség a `ShopWindow.gd` módosítására.

## Technikai megjegyzés

A célcellás tranzakciót a `GameState.buy_item_at()` kezeli. A fizetés és az inventory-módosítás előtt ellenőrzi az egyenleget és az elhelyezést, így az érvénytelen drop nem változtatja meg az adatokat. A meglévő `buy_item()` API kompatibilitásból továbbra is megmaradt.
