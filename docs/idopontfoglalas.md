# Időpontfoglalás

## Használat

1. Ügyfél → projekt megnyitása → Szerkesztés.
2. Jelöld be: **Találkozó szükséges – időpontfoglaló az adatbekérőben**, majd mentsd.
3. A projekt **Időpontfoglalás → Szabad időpontok kezelése** részében adj meg kezdést és befejezést.
4. Küldd el az **Ügyfél adatbekérő linket**. Az ügyfél a saját neve, emailje vagy telefonszáma egyikével azonosítja magát, és választ időpontot. A foglalás az adatbekérő elküldésekor végleges.
5. Ha egyik időpont sem megfelelő, kérhet telefonos egyeztetést, vagy közvetlenül hívhatja a **+36 70 634 9630** számot.
6. Telefonos egyeztetés után az **Egyeztetett időpont rögzítése** gombbal rögzíthető a találkozó. A foglalás módosítható és lemondható; az előzmények megmaradnak.

A szabad időpontok közös Árajánlat-naptárt alkotnak. A foglalt idővel átfedő másik időpont sem foglalható. A listák budapesti időt mutatnak; az időpont beírása az eszköz helyi időzónáját használja.

## Riasztás

Belépés után nyisd le az **Értesítések** részt, és válaszd a **Riasztás bekapcsolása ezen az eszközön** gombot. Engedélyezd a böngésző kérését. Ezt külön kell megtenni minden telefonon, tableten és PC-n. Az eszköz és a böngésző értesítési beállításai se tiltsák a riasztást. A riasztás kikapcsolható; kijelentkezéskor az adott eszköz feliratkozása megszűnik.

A Supabase szerver percenként dolgozza fel a foglalási értesítéseket, lemondásokat és telefonos egyeztetési kéréseket. A 3 órás emlékeztetőt a szerver küldi, bezárt app mellett is. A böngésző/operációs rendszer tényleges kézbesítése függ az internetkapcsolattól és az értesítési beállításoktól; a pontos jelzéshangot az eszköz kezeli. Három órán belül rögzített találkozónál az azonnali foglalási értesítés megy ki, külön visszamenőleges emlékeztető nem.

## Automatikus email – aktiválás szükséges

A címzett **info@diszkertek.hu**. Az emailküldés kódja és a szerveres ütemezés elkészült, de küldéshez még szükséges:

1. Resend-fiók létrehozása az ingyenes csomagban.
2. A `diszkertek.hu` küldő domain igazolása a Resend által megadott DNS-rekordokkal. A meglévő levelezés rekordjait nem szabad törölni.
3. Resend emailküldő API-kulcs létrehozása és elmentése a kizárólag Árajánlatot kiszolgáló Supabase projekt **Edge Functions → Secrets** részében, `RESEND_API_KEY` néven.
4. Ha másik igazolt feladó címet használtok, a `QUOTE_EMAIL_FROM` secretbe írd be. Alapértelmezés: `Díszkertek <ertesites@diszkertek.hu>`.
5. Jóváhagyott próbafoglalással ellenőrizni az emailt és a bekapcsolt eszköz riasztását.

Kulcsot és jelszót ne másolj a GitHubba vagy a beszélgetésbe. A Resend ingyenes kerete a 2026. október 5-én ellenőrzött díjazás szerint havi 3000, napi 100 email: https://resend.com/pricing.

## Fejlesztési ellenőrzés

- `supabase/tests/quote_appointments.sql`: tranzakcióban ellenőrzi az azonosítást, token egyszeri használatát, foglalást, átfedések elutasítását, telefonos alternatívát, módosítást, lemondást, 3 órás ütemezést és a jogosultságokat. Minden tesztadat visszagörgetésre kerül.
- A worker `self_check` módja csak helyben készít titkosított push üzenetet; nem foglal le eseményt, és nem küld emailt vagy push üzenetet.
- Az anonim publikus RPC-k szándékosan token + ügyfélazonosítás alapján férnek hozzá; a táblákhoz nincs anonim hozzáférés. A worker Vault- és küldési RPC-jei kizárólag a szerver szerepköréből hívhatók.
- A saját `quote-appointment-notifications` Cron-feladat nem módosít más ütemezést. A Munkalap/Kassza adatbázisai, belépései és fájljai változatlanok.

Új telepítésnél a SQL-fájlok sorrendje: `quote_appointments.sql`, `quote_appointment_notifications.sql`, a `quote-appointment-notify` Edge Function telepítése, végül `quote_notification_schedule.sql`. A worker saját 256 bites szerveres kulcsot ellenőriz a Vaultból; a frontend ezt nem ismeri.
