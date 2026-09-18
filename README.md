# Díszkertek árajánlatkészítő

Statikus HTML/CSS/vanilla JS alkalmazás a meglévő KAP Supabase projekttel. A Munkalap fájljai és táblái változatlanok; az ügyfeleket a meglévő `public.clients` táblából olvassa és ott kezeli a meglévő RLS szerint. A projekt és az ajánlat adatai kizárólag `quote_` táblákban vannak.

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

Az Árajánlat két saját Supabase Auth-fiókot használ. A `js/config.js` csak a belső fiókazonosító email címeket és a publikus projektkulcsot tartalmazza; a PIN-ek nincsenek a frontend kódjában. A belépés `signInWithPassword` hívással történik, a session az eszközön megmarad, és a felületen csak a név és PIN látható. Az Auth-fiókokhoz nem tartozik `public.profiles` sor. Jogosultságukat a `quote_staff` adja, így a nem `quote_` KAP-táblák RLS-szabályai nem engednek hozzáférést. A közös `clients` tábla meglévő szabályai változatlanok; az Árajánlat a `quote_clients_list` és `quote_clients_upsert` függvényen át használja. A bevezetés sorrendje: `supabase/quote_auth_isolation.sql`, a két Auth-fiók létrehozása, `supabase/quote_auth_provision.sql`, belépési és RLS-teszt, majd `supabase/quote_auth_cutover.sql`.

A GC.hu növényárlista 9 oldaláról 519 egyedi cikkszám és nettó beszerzési ár került a `quote_plants` táblába (forrásdátum: 2024. 03. 04.). A növények az ajánlatszerkesztőben kereshetők. A beszerzési ár belső adat; az ismeretlen eladási ár piros 1 Ft-os ellenőrzési jelzés, amelyből nem készíthető végleges ajánlat. A valódi eladási egységárat külön kell megadni, mert a forrás nem tartalmaz felárat. Az ügyfélfájlok csak a böngészőben maradnak: megoszthatók, menthetők vagy emailben külön csatolhatók; az adatbázisban csak a fájlmetaadat marad. Az email küldés `mailto:` átadással történik. A böngésző Nyomtatás / Mentés PDF-ként funkciója A4 nézetet használ. A Supabase Auth munkamenet és az utoljára választott név helyben megmarad; üzleti adat nem kerül `localStorage`-ba. Az ügyféloldal a token után a projekthez tartozó ügyfél neve, emailje vagy telefonszáma közül egyet Supabase oldalon is ellenőriz.
