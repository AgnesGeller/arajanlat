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

A Supabase szerver percenként dolgozza fel a foglalási értesítéseket, lemondásokat és telefonos egyeztetési kéréseket. A 2 órás push emlékeztetőt a szerver küldi, bezárt app mellett is. A böngésző/operációs rendszer tényleges kézbesítése függ az internetkapcsolattól és az értesítési beállításoktól; a pontos jelzéshangot az eszköz kezeli. Két órán belül rögzített találkozónál az azonnali foglalási értesítés megy ki, külön visszamenőleges emlékeztető nem.

## Foglalási email

Email csak új foglaláskor megy az **info@diszkertek.hu** címre, a Munkalapban használt FormSubmit szolgáltatáson keresztül. Az emlékeztető, lemondás és telefonos egyeztetési kérés csak appos értesítés. Resend-fiók, saját küldő domain és DNS-beállítás nem szükséges.

A FormSubmit szerveres próbája sikeres: a kérésben az Árajánlat saját webcíme szerepel, és a szolgáltató visszaigazolta a technikai tesztlevél elfogadását. A címzett az ellenőrzéskor még nem látta a levelet; a tényleges postafiókba érkezés nyitott ellenőrzés. További próbalevél csak új jóváhagyással indítható. A hibás email nem akadályozza a push értesítést. Sikeres HTTP-válasz önmagában nem elegendő: a szolgáltató JSON-visszaigazolását is ellenőrizzük. Az email elfogadása nem bizonyítja a postafiókba érkezést; azt a címzett ellenőrzi.

FormSubmit nem biztosít itt idempotenciakulcsot: megszakadt hálózati válasz után újrapróbálva előfordulhat ismételt email. Minden levélben szerepel a foglalási esemény azonosítója. A push kézbesítés eszközönként nyilvántartott, a sikeresen elküldött értesítést nem küldjük újra emailhiba miatt.

## Fejlesztési ellenőrzés

- `supabase/tests/quote_appointments.sql`: tranzakcióban ellenőrzi az azonosítást, token egyszeri használatát, foglalást, átfedések elutasítását, telefonos alternatívát, módosítást, lemondást, 2 órás ütemezést és a jogosultságokat. Minden tesztadat visszagörgetésre kerül.
- A worker `self_check` módja csak helyben készít titkosított push üzenetet; nem foglal le eseményt, és nem küld emailt vagy push üzenetet.
- Az anonim publikus RPC-k szándékosan token + ügyfélazonosítás alapján férnek hozzá; a táblákhoz nincs anonim hozzáférés. A worker Vault- és küldési RPC-jei kizárólag a szerver szerepköréből hívhatók.
- A saját `quote-appointment-notifications` Cron-feladat nem módosít más ütemezést. A Munkalap/Kassza adatbázisai, belépései és fájljai változatlanok.

Új telepítésnél a SQL-fájlok sorrendje: `quote_appointments.sql`, `quote_appointment_notifications.sql`, a `quote-appointment-notify` Edge Function telepítése, végül `quote_notification_schedule.sql`. A worker saját 256 bites szerveres kulcsot ellenőriz a Vaultból; a frontend ezt nem ismeri.

## Kétórás értesítési frissítés ellenőrzése

- A foglalási adatbázisteszt sikeres: ügyfélazonosítás, foglalás, átfedés tiltása, módosítás, lemondás, kétórás emlékeztető és hozzáférési korlátok. Minden tesztadat visszagörgetve.
- Külön adatbázisteszt igazolta: a már elküldött push-emlékeztető nem kerül újra sorra hiányzó email miatt, a foglalási email viszont külön újrapróbálható.
- A worker szállítás nélküli push-ellenőrzése 200-as választ adott; titkosítás és hitelesítés sikeres. Ez nem helyettesíti a fizikai eszközre érkező értesítés próbáját.
- Jelenleg nincs bekapcsolt eszközfeliratkozás. Minden használni kívánt eszközön az Értesítések → Riasztás bekapcsolása ezen az eszközön gombbal kell engedélyezni.
- Hét helyi emailkezelési próba sikeres: csak foglalás, ismétlés kizárása sikeres küldés után, címzett és saját webcím, HTTP-hiba, aktiválási válasz, hibás JSON.
- Meglévő telepítés frissítése: `quote_booking_notifications_update.sql`, majd a saját `quote-appointment-notify` function frissítése. Más app és más ütemezés változatlan.
