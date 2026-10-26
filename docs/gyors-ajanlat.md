# Gyors ajánlat

A belső menü feltűnő, indigókék **⚡ Gyors ajánlat** gombja nyitja meg. A többi alkalmazás nem változik.

## Használat

1. **Ügyfél és helyszín:** kereshetsz a közös ügyféllistában, vagy megadhatsz nevet regisztráció nélkül. Az „Ügyfél felvétele a közös listába” gomb a már meglévő ügyfélfelvételt használja. Az ügyfél, cím és munkanév a gyors kalkulációhoz és PDF-hez kihagyható.
2. **Tételek és felmérés:** ugyanaz a 163 tételes Excel-árlista, a meglévő sablonok és a növényárlista használható, mint a teljes ajánlatkészítőben. A főtétel/csoport opcionális. Egyszerre egy tétel szerkeszthető. Az árak és a többi tétel lenyitható.
3. **Feltételek:** dátum, érvényesség, megjegyzés és a fejléc/lábléc adatai; minden mező kihagyható.
4. **PDF és megosztás:** valódi PDF-fájl, magyar ékezetekkel, logóval, fejléccel, lábléccel és oldalszámokkal. Androidon a fájlmegosztás akkor jelenik meg, ha a böngésző támogatja. Minden eszközön használható a PDF letöltése. Az emailhez a fájl a saját levelezőben csatolható; nincs automatikus emailküldés.

A korábbi lépések egyetlen sorra csukódnak össze, visszalépéskor az adatok megmaradnak. Lépésváltáskor mentés történik a saját `quote_quick_drafts` táblába. A mentett gyors ajánlatok a felület tetején nyithatók meg. A legutóbbi 50 bejegyzést listázzuk.

## Választható mennyiségszámítás

- Kézi mennyiség: bármelyik tételnél használható.
- m/fm: hosszúság méterben.
- m²/m2: hosszúság × szélesség, mindkettő méterben.
- m³/m3: hosszúság × szélesség × magasság/mélység, méterben.
- Sövény: hosszúság méterben, tőtávolság centiméterben. `ceil(hossz / tőtávolság)`; a mindkét végpontot bekapcsoló pipa további egy növényt ad. 10 m / 50 cm esetén 20 vagy 21 db. Nem egész osztásnál az egyenletesen elosztott tőtávolság legfeljebb a megadott érték.
- Talajtakaró: `ceil(terület × 6 × sűrűség / 100)`. A sűrűség 0–200%, alapértéke 100%; 100% = 6 db/m². A terület kézzel vagy hosszúság × szélességből adható meg. A 0% szándékosan 0 db-ot eredményez.

A hiányos mérési segéd a kézi mennyiséget használja. A beírt hibás negatív értékek, a nullás tőtávolság és a 200% feletti sűrűség érthető hibaüzenetet adnak. Sem a méretmezők, sem a segédek használata nem kötelező. A kiválasztott árlistatétel eredeti mértékegysége és egységára megmarad. Ha a felhasználó más dimenziójú mértékegységre vált, a korábbi egységár nem értelmezhető automatikusan: az eladási ár ilyenkor piros 1 Ft-os, ellenőrizendő jelzést kap. A növények ismeretlen eladási ára ugyanilyen jelzés; nem feltételezünk felárat.

## Átvétel a teljes ajánlatkezelésbe

A negyedik lépés pipája megjeleníti az átvétel gombját. Választható új projekt vagy a kiválasztott ügyfél azonos című meglévő projektje. A teljes rendszer ügyfélkapcsolatot igényel, ezért az átvételhez ügyfelet kell kiválasztani vagy nevet megadni. Ha csak név szerepel, az átvétel gomb automatikusan felveszi az ügyfelet a már meglévő közös felvételi folyamattal; a gyors PDF ettől függetlenül elkészíthető. Az átvétel piszkozatot készít, nem jelent ügyfél általi elfogadást vagy automatikus kiküldést.

A szerver egyetlen tranzakcióban hozza létre a projektet, ajánlatot, változatot és tételeket. A gyors ajánlat száma megmarad; a csoport a teljes tétel nevében, a mérési adatok a belső megjegyzésben is szerepelnek. Az ismételt kérés ugyanazt az ajánlatot adja vissza. A gyors másolat az átvétel után rögzített állapot marad; későbbi módosítás a teljes ajánlatban végezhető.

## Technika és biztonság

- Új, kizárólag `quote_` táblákhoz tartozó mentés és két `SECURITY INVOKER` RPC: `quote_quick_save`, `quote_quick_promote`.
- RLS a meglévő `quote_staff.company_id` szerint. Nincs anonim hozzáférés és új Auth/PIN rendszer.
- Verziószám védi a párhuzamos szerkesztéseket. Hiba esetén nincs automatikus továbblépés. A mentett változat újratöltése külön megerősítéssel elvetheti a nem mentett helyi módosításokat.
- Üzleti adat és PDF nem kerül localStorage-ba vagy Supabase Storage-ba. A PDF az eszközön készül, a külső szolgáltatónak nincs továbbítva.
- Az alkalmazás HTML/CSS/vanilla JavaScript maradt. Nincs Node/npm a futó appban, nincs új keretrendszer vagy előfizetés.
- A saját statikus tárhelyről, PDF-készítéskor töltődik be a [jsPDF 4.2.1](https://github.com/parallax/jsPDF/releases/tag/v4.2.1) és a [Lato](https://github.com/google/fonts/tree/main/ofl/lato) betűtípus. A licencek az `assets/vendor` könyvtárban vannak. A PWA a fájlokat gyorsítótárazza.

## Ellenőrzés – 2026. október 26.

- `tests/quick-quote.html`: 32 sikeres elkülönített felületi és számítási ellenőrzés asztali, 390 px mobil- és 768 px tabletszélességen.
- A teljes ajánlatkészítő meglévő tesztje 26 sikeres ellenőrzéssel fut, beleértve az új belső menüpontot.
- A `supabase/tests/quote_quick_quotes.sql` hitelesített szereppel teszteli a mentést, az elavult verzió elutasítását, a teljes átvétel tételösszegeit, az ismételt kérés egyszeri hatását és a jogosulatlan olvasás/átvétel tiltását. Minden adatírás visszagörgetve, éles tesztrekord nem maradt.
- Egyoldalas és ötlapos PDF készült; ékezetek, oldalszámok, logó, fejléc és lábléc ellenőrizve. Valós címzettnek nem küldtünk levelet vagy fájlt. A fizikai Android/PC megosztási célokat a felhasználó saját eszköze biztosítja.
- Gyorsítótár-verzió: 41. Adatbázisszkript: `supabase/quote_quick_quotes.sql`; az Árajánlatot kiszolgáló projektben már alkalmazva. Más Supabase-projektben nem futott változtatás.
