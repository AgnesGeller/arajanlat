# Felmérés, részletező és mellékletek

Az Árajánlat 37. verziójának négy kiegészítése. Más alkalmazás fájlja, adatbázisa és belépése nem változott.

## Hol található?

1. **Ügyfél → projekt → Helyszíni felmérés:** méret, terület, növény, munka és megjegyzés rögzítése; két mennyiség és mértékegység; szerkesztés és eltávolítás. Az eltávolítás archivál, nem töröl véglegesen.
2. **Árajánlat → Belső árlista és költségrészletező:** kereshető 163 eredeti katalógustétel, mértékegységek, anyagár, munkadíj, megjegyzés és a három importált tételösszetevő. A Részletező 185 eredeti sora külön kereshető és lapozható; a szöveges fejléceket is megőrzi.
3. **Ügyfél adatbekérő → A tervezett munka:** a kiválasztott munkához tartozó méretmezők jelennek meg. Öntözésnél a meglévő körök, mágnesszelepek és szórófejek száma is megadható. Más munkatípusnál a rejtett mezők nem kerülnek a válaszba.
4. **Belső árlista → Kiegészítő árforrások:** öntözési költségbontás és a robotfűnyírós PDF négy változata. Az „Új ajánlatváltozat ebből” új piszkozatot készít, meglévő változatot nem ír át.

## Képek

A felmérésnél kiválasztott képek helyi előnézete megjelenik. A képek letölthetők, és támogatott eszközön megoszthatók. A Supabase csak a fájlnevet, típust és a projekthez tartozást tárolja, külön gombbal. A kép nem kerül Supabase Storage-ba, adatbázisba vagy böngészős üzleti adattárba. Az oldal bezárásakor a helyi előnézet elvész; a képeket külön kell megtartani az eszközön. Ez még nem képes látványtervezés.

## Öntözős Excel

Eredeti fájl: `ontozorendszer_teljes_bontas.xlsx`, „Öntözés bontás” munkalap. Mind a 12 alap-költségsor, a hat levonási sor, a megjegyzések és az összes nem üres cella, képlet és tárolt eredmény bekerült az árforrásba. Az import nem módosította a fájlt.

- Alapköltség: **1 405 000 Ft**.
- Minden eredeti levonást alkalmazva: **1 045 000–1 111 000 Ft**.
- Levonás nélkül: **1 405 000 Ft**.
- A költségek sorösszegek. Például az 5 mágnesszelep 90 000 Ft anyagköltsége együtt az öt darabra vonatkozik.

A melléklet saját felirata szerint belső, alvállalkozói kalkuláció. Ezért az importált költséget nem minősítjük automatikusan eladási árnak. Másoláskor az ismeretlen eladási egységár **1 Ft**, piros jelzéssel; minden sor árellenőrzést kér. A levonások választása a belső becslési sávot módosítja, nem igazol helyszíni állapotot és nem készít automatikusan új eladási árat.

## Robotfűnyíró PDF

Eredeti fájl: `Fűnyíró árajánlat 4 verzio.pdf`. Mind a négy változat anyagsorai, darabszámai, bruttó egységárai, nettó/bruttó összesítése és eredeti szövege megmaradt.

| Változat | Nettó | Eredeti bruttó |
| --- | ---: | ---: |
| Vezetékes, két robot | 1 043 780 Ft | 1 325 600 Ft |
| Vezetékes, egy robot | 1 440 780 Ft | 1 829 790 Ft |
| WiFi | 965 976 Ft | 1 226 790 Ft |
| GPS | 1 082 031 Ft | 1 374 180 Ft |

A PDF már kerekített nettó összegeiből számolt 27% ÁFA néhány tized forintos eltérést ad. Az eredeti bruttó összeg és az eltérés látható a belső nézetben. Másoláskor három összesítő tétel készül: anyag, telepítés, tereprendezés. Kiküldés előtt az árakat soronként ellenőrizni kell; a meglévő ajánlati számítás nem változott.

## Adatbázis és újraimportálás

- Új saját táblák: `quote_survey_entries`, `quote_source_packages`.
- Új RPC: `quote_source_package_apply`, a hívó jogosultságával fut. Csak Árajánlat-staff hívhatja, és csak a saját cége ajánlatához készíthet változatot.
- A felmérések saját céghez és projekthez kötött RLS-védelmet kaptak. Publikus ügyfél nem olvashat belső felmérést vagy árforrást.
- A forráscsomagokat belső felhasználó csak olvashatja; a seed tölti fel. A forrásfájl SHA-256 lenyomata is tárolódik.
- Friss adatbázisnál a meglévő alapmigrációk után egyszer alkalmazandó: `supabase/quote_survey_sources.sql`, majd `supabase/quote_source_seed.sql`.
- A seed újra előállítható az `import_supplemental.py` Python programmal, az eredeti mellékletekből. Azonos forráskulcsra frissít, nem hoz létre újabb másolatot.

## Ellenőrzések

- Mellékletimport: 12 öntözési sor, 6 levonás, 4 PDF-változat; a sorszámítások és végösszegek egyeznek.
- Új böngészős teszt: **16 sikeres, 0 hibás**.
- Meglévő kalkulációs teszt: **33 sikeres, 0 hibás**.
- Adatbázis-próba visszagörgetéssel: felmérés mentése/szerkesztése/archiválása; mind az öt forrásból új változat; tételszám, árjelölés és robot nettó végösszegek; jogosulatlan és anonim hozzáférés tiltása.
- Geller Ágnes megőrzött bemutatóprojektjén a felmérési űrlap tényleges mentése sikeres. Egy egyértelműen bemutatónak jelölt 4 × 3 m-es adat maradt meg.
- Belső UI: árlista-keresés, műanyag szegély összetevői, részletező keresése/lapozása, öntözési levonások és PDF-összesítések ellenőrizve.
- Helyi képelőnézet: a saját ikonfájl kiválasztásával működött, helyi `blob:` címmel; képet vagy fájlnevet nem küldtünk a Supabase-ba. A mobilteszt keretében a képválasztó automatizálása elakadt, a normál böngészőnézetben sikeres volt.
- Telefonos nézet: 390 px széles keretben az árforrásnézet nem lóg ki (375 px hasznos szélesség és ugyanekkora teljes oldalszélesség); a széles táblázatok saját területükön görgethetők.
- A biztonsági advisor nem jelzett az új objektumokra vonatkozó problémát. A korábbi, szándékosan szerveroldali szinkronállapot-táblákat és tokenvédett publikus RPC-ket nem módosítottuk.

Ebben a körben nem küldtünk emailt, nem készítettünk valódi foglalást, és nem írtunk a Munkalap/Kassza adatbázisába.
