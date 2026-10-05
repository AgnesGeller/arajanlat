# Ügyfelek és adatbekérő

- Az ügyfélkeresőben két karakter után a mező alatt megjelennek a találatok. A név mellett a munkavégzési címek is láthatók. Érintéssel vagy a nyílbillentyűkkel és Enterrel lehet választani.
- Új ügyfél mentésekor a közös Munkalap/Kassza-listába felvétel automatikus. Internet- vagy szolgáltatáshiba esetén a mentett ügyfél megmarad, a szinkronizálás a következő frissítéskor folytatódik.
- Az Árajánlat helyi rekordját a közös ügyfélhez automatikusan egyesítjük, ha a név és a teljes, nem üres munkacímkészlet egyezik, és pontosan egy közös jelölt van. A kis- és nagybetű, valamint a felesleges szóköz nem számít eltérésnek. Más címeket nem vonunk össze. Az eredeti rekord és az előzmények megmaradnak, a projektek átkerülnek a megtartott ügyfélhez.
- Projekt megnyitása → **Ügyfél adatbekérő link**: bármely státuszban új link készíthető. Másolás, email vagy az eszköz megosztási lehetősége használható. Az email gomb az emailprogramot nyitja meg; a levelet ott kell elküldeni.
- Minden új link 30 napig érvényes, a válasz egyszer küldhető be. További adatok kéréséhez új link készíthető. A token és az ügyfél azonosítása továbbra is szerveroldali ellenőrzést kap. A később érkező adatbekérő nem lépteti vissza az előrehaladott projektstátuszt.

## Telepítés és ellenőrzés

Az új SQL: `supabase/quote_customer_workflow.sql`. A meglévő közösügyfél- és időpontfoglalási SQL után kell alkalmazni. Más alkalmazás tábláját vagy jogosultságát nem módosítja.

A `supabase/tests/quote_customer_workflow.sql` visszagörgetett tranzakcióban ellenőrzi az automatikus közös felvételt, az egyesítést, a különböző címek megőrzését, a projekt- és adatelőzményeket, a 11 státuszban készíthető és beküldhető adatbekérőt, a token újrafelhasználásának tiltását és a jogosultságellenőrzést.
