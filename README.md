# Díszkertek árajánlatkészítő

Statikus HTML/CSS/vanilla JS alkalmazás a meglévő KAP Supabase projekttel. Az ügyfeleket a saját `quote_clients` táblában kezeli. A Kassza/Munkalap jóváhagyott ügyféllistájának másolata és a korábbi Árajánlat-ügyfelek itt szerepelnek; a másik két alkalmazás kódja, sémája, belépése és jogosultságai változatlanok. A projekt és az ajánlat adatai kizárólag `quote_` táblákban vannak.

## Az Excel jelenlegi működése (15 sor)

1. A `Kalkulátor` lap sorai a főkategóriát és alkategóriát választják ki.
2. Az `Adatbázis` lapból az alkategória alapján VLOOKUP tölti be a leírást.
3. Ugyanez tölti be a megjegyzést, két mértékegységet és két egységárat.
4. Az első mennyiség a fő szorzó.
5. Ha van második mértékegység, a második mennyiség is szorzó.
6. Anyagösszeg = anyag egységár × mennyiség 1 × opcionális mennyiség 2.
7. Munkadíj = munkadíj egységár × ugyanezek a mennyiségek.
8. A nettó sorérték az anyag és a munkadíj összege.
9. Az ÁFA a nettó és a sor ÁFA arányának szorzata; a példasorokban 0.
10. A bruttó a nettó és az ÁFA összege.
11. Az Excel hibás vagy üres szorzókat az IFERROR ágon nullaként kezeli.
12. A 40 kalkulátorsorban azonos képletminta van; eltérő sorformula nem fordult elő.
13. Az `Adatbázis` 163 kitöltött, árazható sort tartalmaz 22 kategóriában.
14. A `Részletező` költségelemeket, részösszegeket és megjegyzéseket tartalmaz.
15. A `Minták` három munkacsomagot ír le; a járda minta öt sora nem egyezik pontosan az árlistával.

## Telepítés és ellenőrzés

A `supabase/schema.sql` és `supabase/seed.sql` a KAP projektben már lefutott. A seed 163 árlistatételt, 3 árösszetevőt, 185 részletező sort, 3 sablont és 19 sablonsort tartalmaz. Az új árak előtt a régi Excel-árakat kereskedelmileg ellenőrizni kell.

Az Árajánlat két saját Supabase Auth-fiókot használ. A `js/config.js` csak a belső fiókazonosító email címeket és a publikus projektkulcsot tartalmazza; a PIN-ek nincsenek a frontend kódjában. A belépés `signInWithPassword` hívással történik, a session az eszközön megmarad, és a felületen csak a név és PIN látható. Az Auth-fiókokhoz nem tartozik `public.profiles` sor. Jogosultságukat a `quote_staff` adja, így a nem `quote_` KAP-táblák RLS-szabályai nem engednek hozzáférést. A korábbi `public.clients` tábla változatlan. A `quote_clients_list` és `quote_clients_upsert` már kizárólag a saját `quote_clients` táblát használja, a `quote_staff.company_id` alapján ellenőrzött hozzáféréssel. A bevezetés sorrendje: `supabase/quote_auth_isolation.sql`, a két Auth-fiók létrehozása, `supabase/quote_auth_provision.sql`, belépési és RLS-teszt, majd `supabase/quote_auth_cutover.sql`.

A GC.hu növényárlista 9 oldaláról 519 egyedi cikkszám és nettó beszerzési ár került a `quote_plants` táblába (forrásdátum: 2024. 03. 04.). A növények az ajánlatszerkesztőben kereshetők. A beszerzési ár belső adat; az ismeretlen eladási ár piros 1 Ft-os ellenőrzési jelzés, amelyből nem készíthető végleges ajánlat. A valódi eladási egységárat külön kell megadni, mert a forrás nem tartalmaz felárat. Az ügyfélfájlok csak a böngészőben maradnak: megoszthatók, menthetők vagy emailben külön csatolhatók; az adatbázisban csak a fájlmetaadat marad. Az email küldés `mailto:` átadással történik. A böngésző Nyomtatás / Mentés PDF-ként funkciója A4 nézetet használ. A Supabase Auth munkamenet és az utoljára választott név helyben megmarad; üzleti adat nem kerül `localStorage`-ba. Az ügyféloldal a token után a projekthez tartozó ügyfél neve, emailje vagy telefonszáma közül egyet Supabase oldalon is ellenőriz.

## Saját ügyféllista és közös névjegyzék

A `supabase/quote_own_clients.sql` az eredeti ügyfelek összes mezőjét és azonosítóját átmásolja. Az ajánlatok ügyfélkapcsolata és a tokenes ügyfélazonosítás is az új táblát használja. Az egyszeri adminisztrátori import `quote_private.import_customers(company_id, customers_json)` formában történik; a JSON a Kassza projekt `munkalap.customers` aktív, jóváhagyott soraiból, a kapcsolódó `customer_details` és aktív/jóváhagyott `customer_locations` adatokból készül. Ügyféladat nem kerül a nyilvános repositoryba. Egyezés csak egyetlen, szóközökre és kis/nagybetűkre normalizált teljes név alapján történik; bizonytalan egyezést nem von össze. A régi elérhetőségek megmaradnak, a hiányzó mezők kiegészülnek, a teljes importadat a `source_payload` mezőben is megmarad.

2026. október 1.: 107 eredeti ügyfél megőrizve; 108 közös ügyfél beolvasva; 64 pontos névegyezés; összesen 151 saját ügyfél, ebből 43 csak a korábbi listában szerepelt. Mindkét saját fiók 151 ügyfelet és 163 katalógustételt lát. A PIN-ek kizárólag Supabase Authban vannak, a frontendbe nem kerülnek.

A `supabase/quote_customer_sync.sql` az ezután létrehozott saját ügyfeleket tartós adatbázisos átadási sorba teszi. A `supabase/functions/quote-customer-sync/index.ts` kizárólag az Árajánlatot kiszolgáló projektben fut. Érvényes Auth sessiont és `quote_staff` tagságot ellenőriz. A közös forrásba csak új nevet ír (aktív, jóváhagyott ügyfélként), név szerint előbb ellenőrzi a meglévő rekordot. A forrásban csak GET és INSERT kéréseket végez; meglévő rekordot, elérhetőséget, címet vagy megjegyzést nem ír át. Az Árajánlatban végzett szerkesztés nem módosítja a közös ügyfelet. Sikertelen átadás esetén az ügyfél itt megmarad, a függőben lévő átadást következő belépéskor/ügyfélmentéskor újra megpróbálja. A meglévő inaktív vagy jóváhagyásra váró nevet nem aktiválja automatikusan.

Az Edge Function telepítve, JWT-ellenőrzéssel. Az éles közös átadáshoz még a `KASSZA_SERVICE_ROLE_KEY` titkos beállítás szükséges az Árajánlatot kiszolgáló projekt Edge Functions → Secrets oldalán. Értéke a Kassza projekt service_role kulcsa; nem kerülhet frontendbe, Gitbe, ügyfélfájlba vagy naplóba. A titok nélkül az átadás 503 választ ad, és a mentett ügyfél a saját listában marad. A tényleges közös adatbeírás és ismételt átadás ellenőrzése a titok beállítása után végezhető el.

Új telepítésnél a saját ügyféllista migrációját az eredeti séma és a `quote_auth_isolation.sql` után kell alkalmazni, majd importálni a közös listát, végül alkalmazni a `quote_customer_sync.sql` fájlt. A régi migrációk történeti fájlok; azokat működő környezetben nem szabad újrafuttatni az új ügyfélforrás felülírására.
