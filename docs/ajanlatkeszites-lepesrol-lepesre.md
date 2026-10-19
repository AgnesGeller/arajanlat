# Árajánlat készítése – egyszerűsített felület

## Hogyan kezdj?

Belépés után a **Kezdés** oldal jelenik meg. Az **Új ajánlat indítása** gomb az ügyfélkeresőhöz vezet.

1. **Ügyfél:** írj be legalább két betűt, válassz a találatok közül. Ha még nincs ügyfél, kattints az **Új ügyfél** gombra.
2. **Projekt és felmérés:** az ügyfél adatlapján nyiss meg egy meglévő projektet, vagy válaszd az **Új projekt** gombot. A projekt a konkrét munkát és címet jelenti. Szükség esetén készíts adatbekérő linket, rögzíts felmérési adatokat vagy állíts be időpontokat. Ezek később is elérhetők.
3. **Ajánlat:** a projektben kattints az **Árajánlat készítése ehhez a projekthez** gombra, vagy nyisd meg a már meglévő ajánlatot. Adj hozzá árlistatételeket, növényeket vagy sablont, és ellenőrizd a mennyiségeket, anyagárakat és munkadíjakat.
4. **Ellenőrzés és megosztás:** az ajánlat alján ellenőrizd az érvényességet, a feltételeket és a végösszeget. Rendezd a piros árjelzéseket. A véglegesítés elkészíti az ügyféllinket és rögzíti a változatot. Ezután a PDF / Nyomtatás is elérhető. A link létrehozása önmagában nem küld emailt; a meglévő emailes átadás a levelezőben fejezhető be.

## Meglévő munka folytatása

- **Kezdés:** a legutóbb létrehozott öt projekt közvetlenül megnyitható.
- **Ügyfelek:** keresés, ügyféladatok, az adott ügyfél projektjei.
- **Projektek:** minden projekt; saját oldalon az adatok, felmérés, ajánlatok, haladás és előzmények.
- **Árajánlatok:** meglévő ajánlatok listája. Az ajánlatból vissza lehet lépni a projekthez.

A lépéssor az aktuális felületet jelzi, nem kötelező adatkitöltési ellenőrzőlista. A felmérés és adatbekérés szükség szerint használható.

## Fejlesztői ellenőrzés – 2026. október 19.

A változás a felületet és a navigációt érinti. Nincs új függőség, technológia, adatbázisséma, Auth-beállítás vagy más alkalmazásban végzett módosítás. A számítási modul változatlan. A projekt részletei a saját Projektek nézetbe kerültek. A ritkábban használt projektmezők, dokumentumok és időpontkezelés lenyithatók.

A `tests/workflow.html` az eredeti alkalmazásmodult futtatja elkülönített, memóriában működő adatforrással. Nem jelentkezik be valódi fiókba, nem ír éles adatot, és nem küld emailt. Huszonöt ellenőrzés sikeres asztali (1344 px), mobil (390 px) és tablet (768 px) szélességen. A keskeny nézeteket a `tests/workflow-responsive.html?width=390` és `?width=768` oldalak valódi szélességű keretben ellenőrzik.

Ellenőrizve: kezdőoldal, kétbetűs ügyfélkeresés, projektválasztás, több cím megőrzése, adatbekérő elérése, árlistamezők, eredeti tételszámítás, ajánlat létrehozása a megfelelő projekthez, navigálás előtti mentés és mentési hiba, véglegesítés, megosztható link újrakészítése, PDF-gomb elérhetősége, vízszintes kilógás. A tényleges emailkézbesítés és fizikai nyomtatás nem része ennek a felületmódosításnak és tesztnek.

Az alkalmazás gyorsítótár-verziója: 40.
