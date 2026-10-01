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

## Saját ügyféllista és közös ügyféltörzs

A közös forrás a Kassza projekt `munkalap.customers` táblája, a kapcsolódó `customer_details` és `customer_locations` adatokkal. Ezt a forrást használja a Munkalap is. Az Árajánlat saját `quote_clients` táblával dolgozik; a közös ügyfél azonosítója a `source_customer_id`. A másik két alkalmazás kódja, sémája, belépése és jogosultságai változatlanok. Kizárólag a felhasználó által engedélyezett ügyféladatok olvasása, felvétele és frissítése történik.

2026. október 1.: 108 közös ügyfél és 43 korábbi saját ügyfél, összesen 151 rekord. A korábbi ügyfelek és ajánlatkapcsolataik megmaradtak. A korábbi saját ügyfelek külön szűrhetők; csak kifejezett választással kerülnek a közös törzsbe vagy kapcsolhatók meglévő közös ügyfélhez. Az összekapcsolás megtartja az eredeti rekordot, és csak az Árajánlat projektjeinek ügyfélkapcsolatát vezeti át.

A `quote-customer-sync` Edge Function érvényes saját Auth sessiont és `quote_staff` tagságot ellenőriz. A közös nevet, ügyféltípust, kapcsolattartót, emailt, telefonszámot, adószámot, megjegyzést és munkavégzési címeket szinkronizálja. A közös forrás pénzügyi mezőit nem írja. A számlázási cím kizárólag az Árajánlatban marad, mert a jelenlegi közös forrásban nincs hozzá külön mező.

Frissítés történik belépéskor, ügyfélmentéskor, az alkalmazás újbóli előtérbe kerülésekor, látható ablakban kétpercenként, illetve az Ügyféllista frissítése gombbal. A többi alkalmazás új ügyfelei is átkerülnek az Árajánlatba, ha aktívak és jóváhagyottak. Inaktív vagy függőben lévő ügyfelet nem aktivál automatikusan.

A mezőnkénti összevetés megőrzi az eredeti adatot és az utolsó közös állapotot. Egymástól független új változtatások összeolvadnak. A felhasználó döntése alapján adateltérés esetén a Munkalap aktuális közös törzse az elsődleges: a teljes közös címjegyzék és a többi közös mező kerül az Árajánlatba. A régi 42 eltérés a frissen lekért közös adatokkal rendezve; ezek nem írhatják felül a közös törzset. Az előzményeket a `quote_customer_history` és a `legacy_payload` őrzi.

A szerver tartós adatbázisos sorral, párhuzamos futást kizáró foglalással, valamint a közös rekord módosítási időpontját ellenőrző írásokkal dolgozik. Sikertelen szinkronnál a saját mentés megmarad és később újrapróbálható. Ügyféladat nem kerül localStorage-ba, nyilvános repositoryba vagy naplóba.

A `KASSZA_SERVICE_ROLE_KEY` kizárólag az Árajánlatot kiszolgáló projekt Edge Functions → Secrets beállításában szerepel. A függvény telepítve, JWT-ellenőrzéssel. Az éles ellenőrzés során öt ügyfélnél hiányzó közös megjegyzést egészített ki; ismételt futtatás nem írt újra adatot. Mindkét saját fiók hozzáférése, a szerveroldali műveletek tiltása a kliens számára és az anonim hozzáférés tiltása ellenőrizve.

Új telepítésnél: eredeti séma és Auth-elkülönítés, `quote_own_clients.sql`, kezdeti közös import, `quote_customer_sync.sql`, végül `quote_common_customers.sql`. A régi migrációkat működő környezetben nem szabad újrafuttatni. A tranzakcióban futó `supabase/tests/quote_common_customers.sql` visszagörgethető tesztekkel ellenőrzi az összeolvasztást, formátumegyezéseket, eltérések megőrzését és feloldását, a mentési sort, előzményeket, elavult mentések elutasítását és a párhuzamos futás kizárását. A teszt nem ír a Kassza projektbe.

Többcímű ügyfelek: minden munkavégzési cím külön sorban marad. Címeltérésnél az „Összes cím megtartása” választás összeilleszti a két listát; kizárólag azonos, kis/nagybetűre és fölösleges szóközre normalizált címeket egyesít. Ügyfélbejegyzések kézi összekapcsolásakor mindkét bejegyzés címei megmaradnak. A kiegészítő migráció: `quote_customer_addresses.sql`.

Forráselsőbbség: `quote_customer_source_priority.sql`. A módosítás csak az Árajánlat összevetési függvényét érinti; a közös forrásba a korábbi eltérések rendezése nem ír adatot.

## Telepítés és ügyféldokumentumok

Az App letöltése gomb Androidon, Android-tableten és asztali Chrome/Edge böngészőben a böngésző telepítési ajánlatakor jelenik meg. Telepített módban és igazolt telepítés után rejtve marad; a helyi telepítési jelző csak felületi beállítás. Új telepítési ajánlat esetén az eltávolított app újra telepíthető. A telepített app élő üzleti adataihoz továbbra is internetkapcsolat szükséges.

Az assets/diszkertek-logo.png a felhasználó saját logója. Az ügyféloldal és az adminból nyomtatott/PDF-be mentett ajánlat ezt használja; a belső app ikonja változatlan. Minden későbbi, ügyfélnek küldendő dokumentumon ezt a logót kell használni.
