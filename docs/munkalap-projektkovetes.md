# Munkalap és projektkövetés – 2026. október 5.

## Működés

- Főóra: csapatonként a létszám × tényleges érkezés/távozás közötti idő; nincs szünetlevonás.
- Munkadíj: 8 500 Ft/főóra. Órakeret: az egyetlen elfogadott ajánlat munkadíja / 8 500.
- Föld: mennyiség × 8 000 Ft + egyszeri 10 000 Ft szállítás. Nulla mennyiségnél nincs szállítási díj.
- A szöveges feladatleírásból nem számolunk árat vagy készültséget.
- Javított munkalap azonos forrás-UUID-val lecseréli a régi eredményt, nem duplázódik.
- Készültség: azonosított mennyiség / ajánlati mennyiség, munkadíjjal súlyozva.
  Ági/Tamás tételenként felülírhatja az elkészült mennyiséget; üres mező visszaállítja az automatikus számítást.
- Hiányzó mennyiség, ár vagy nem egyértelmű projekt esetén figyelmeztetés jelenik meg; nem találunk ki adatot.
- A két sáv csak kezdési dátummal rendelkező projektnél jelenik meg.

## Elkészült

Az Árajánlat saját quote_ táblái és jogosultságai élesítve. A quote-work-sync
szerveroldali funkció csak olvassa a Munkalap forrását, és saját quote_ másolatot
frissít. Ügyfél-UUID, normalizált cím, kezdési dátum és szükség esetén explicit
projektazonosító kapcsolja össze az adatokat. Részleges vagy sikertelen lekérés
nem törli a korábban szinkronizált adatot.

A Munkalap kiegészítése kizárólag opcionális projektválasztás és két sáv.
A saját, meglévő Munkalap-belépést használja a szerveroldali ellenőrzéshez;
az Árajánlat belépése továbbra is külön van. A dolgozói válasz nem tartalmaz
ajánlati egységárakat, ügyfél-elérhetőséget vagy nyers munkalapadatokat.
A projektlekérés hibája nem akadályozza a beküldést.

A Kassza kódja, meglévő forrásadatok, Auth-fiókok, jelszavak és forrásoldali
jogosultságok változatlanok. Kizárólag négy külön jóváhagyott, új bemutató
munkalap került a forrásba. A Munkalap korábbi, más feladathoz tartozó emailes
változtatásai elkülönítve maradtak, nem részei ennek a commitnak.

## Ellenőrzések

- 30 böngészős számítási ellenőrzés: főóra, árak, sávos képletek, földszállítás,
  javított adatok, hiányzó adat, súlyozott készültség és kézi felülírás.
- 5 projektkövetési és 5 Munkalap-kiegészítési ellenőrzés.
- SQL tranzakciós próbák ROLLBACK-kel: RLS, anon/idegen fiók kizárása,
  frontendes forrásadatírás tiltása, javítás és elavult párhuzamos frissítés.
- Éles Árajánlat staff belépéssel szinkron és összesítés; érvénytelen és idegen
  projekthez tartozó belépés elutasítva.
- Valódi Munkalap-sessionnel is ellenőrizve: PR-2026-0003 kiválasztva, mindkét sáv
  egyezik az Árajánlat összesítésével. Beküldés nélkül.
- Az éles böngészős próba két hibát tárt fel: hiányzó x-client-info CORS-fejléc
  és a service_role összesítő ágban feleslegesen kiértékelt felhasználói ellenőrzés.
  Mindkettő javítva, a szerveroldali ág külön SQL regressziós tesztet kapott.
- A fizikai telefon/tablet ellenőrzése még hátravan; a böngészős méretállító
  ebben a környezetben nem alkalmazta a kért 390 px-es szélességet.

## Megőrzött bemutató

PR-2026-0003 – Grill terasz nyárikerttel, Geller Ágnes.
Az adatbekérő, a nem valódi megrendelést jelentő elfogadás, négy tesztmunkalap,
a készültségi adatok és a bemutató lezárása rögzítve. Email nem ment ki.

Ajánlat 628 400 Ft; munkadíjkeret 414 000 Ft = 48,71 főóra.
Tényleges tesztadat 48 főóra = 408 000 Ft, 98,55% időkeret, 100% készültség.
Hátralévő 0,71 főóra. A 100% a geotextília automatikus mennyiségéből és a
külön nem mérhető munkák jóváhagyott kézi bemutató mennyiségeiből adódik.

A bemutató javítási előnézete 50 főórával mutatja a túllépést, adatírás nélkül.
Részletek: [grill-terasz-bemutato.md](grill-terasz-bemutato.md).

## Hátralévő döntések és fejlesztések

1. Hiányzó egységárak és mértékegységek egyeztetése: big bag, ömlesztett anyagok,
   bérlés, alvállalkozó, egyedi tételek. Több szállítás egyszeri díjának pontosítása.
2. Több elfogadott ajánlat esetén a keret szabálya; jelenleg a rendszer jelzi,
   hogy nem egyértelmű, és nem összegez önkényesen.
3. Kasszakiadások, tényleges bérkifizetések és anyagköltségek projektkapcsolata,
   kettős elszámolás nélkül. A 8 500 Ft nem kifizetett dolgozói bérként szerepel.
4. Email és egyórás foglalási emlékeztető aktiválása/valós próbája, appértesítés ellenőrzése.
5. Strukturált helyszíni felmérés; ingyenes képes látványtervezés egyeztetése,
   Supabase-képtárolás nélkül.
6. A korábbi teljes Excel/PDF/PWA/RLS/mobil ellenőrzés fennmaradó részeinek lezárása.

Ezek külön egyeztetendő feladatok; a jelenlegi változtatás nem módosítja a
Munkalap beküldési működését vagy más appok adatstruktúráját.
