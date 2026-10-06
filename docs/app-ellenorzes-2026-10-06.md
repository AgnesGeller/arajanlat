# Árajánlat ellenőrzése – 2026. október 6.

## Javítások

- Az ügyféloldal logója megőrzi a tokenes linket.
- A még ki nem választott azonosítási mód rejtett mezője nem akadályozza az űrlapot.
- Hibás mezőnél az összecsukott rész megnyílik, és magyar visszajelzés jelenik meg.
- A projekt ismert munkavégzési címe előre bekerül az adatbekérőbe.
- Felhasznált vagy lejárt link állapotát csak a linkhez tartozó ügyfél sikeres azonosítása után jelzi a szerver. Hibás azonosítás nem fed fel állapotot vagy ügyféladatot.
- A linket létrehozó ablakból közvetlenül megnyitható az adatbekérő. A „Kész” gomb és az „Emailprogram megnyitása” felirat pontosan jelzi a működést; az emailt a megnyíló emailprogramban kell elküldeni.
- A már használt Supabase SDK azonos, rögzített 2.58.0 változata helyi fájlból töltődik, és bekerül az Árajánlat saját PWA-gyorsítótárába. Új függőség nincs.
- A foglalási email a Munkalap meglévő mintájának megfelelő `_captcha: false` paramétert is elküldi. Új tesztlevél engedély nélkül nem indul.

## Eredmények

- Az éles Geller Ágnes bemutatóprojekt új adatbekérője azonosítás után kitölthető és sikeresen menthető. A visszaérkezett adatok a belső projektoldalon is megjelennek. A lezárt projekt állapota megmaradt.
- Helyi böngészős ellenőrzés: hiányzó token, felhasznált token, cím előtöltése és összecsukott hibás emailmező kezelése megfelelő.
- Foglalási email egységellenőrzése: 8 sikeres eset, tényleges emailküldés nélkül.
- Számítások: 33 sikeres eset. Projektmegjelenítés: 5 sikeres eset. A korábbi Munkalap-kiegészítés saját tesztmásolata: 7 sikeres eset. Más app fájlja nem változott.
- A tokenállapot RPC szerveres tranzakciós próbája: aktív, lejárt, visszavont, hibás azonosítás; visszavont token nem olvasható. A próbák visszagörgetve.
- Ági és Tamás saját jogosultságaival a 163 katalógustétel és a saját projektek elérhetők. A publikus felület nem kap közvetlen táblahozzáférést.
- Mobilnézet 390 px szélességen: az ellenőrzött ügyfél/projekt nézet nem lóg túl vízszintesen.

## Még igazolandó

- A FormSubmit korábban elfogadta a technikai levelet, de a címzett nem kapta meg. A mostani paraméterjavítás utáni kézbesítést új, külön engedélyezett tesztlevéllel és postafiók-visszajelzéssel kell igazolni. Szolgáltatói elfogadás nem jelent bizonyított kézbesítést.
- A push szerveres titkosítási próbája sikeres, a 2 órás szerveres ütemezés működik. Jelenleg nincs aktív eszközfeliratkozás; telefonos/PC-s tényleges riasztáspróbához az adott eszközön be kell kapcsolni az értesítéseket.
- Az engedélyezett éles domainen működő ügyfél- és munkalapszinkront a localhost eredetéről a CORS-védelem szándékosan nem engedi. Emiatt helyi böngészőben a mentett másolat látható; ez önmagában nem éles szinkronhiba.

Csak az Árajánlat saját kódja és `quote_` szerveroldali kiegészítése változott. Más alkalmazás kódja, Auth-fiókja és jogosultsága nem módosult.
