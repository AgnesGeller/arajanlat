# Adatbekérő emailes megosztása

## Feltárt hiányosság

A korábbi belső megosztóablak egyetlen `mailto:` gombbal próbálta elindítani a gép levelezőjét, `window.location.href` átállításával. Nem adott külön böngészős levelezési lehetőséget, címzettszerkesztést vagy teljes levélszöveget. Beállított protokollkezelő nélkül a kattintás nem biztosít használható levélírást. A felhasználó konkrét Windows-beállítását nem változtattuk meg és nem ellenőriztük.

## Javítás

- Az adatbekérő és az ajánlati link belső küldőablakában látható, szerkeszthető címzett, tárgy és levélszöveg.
- Külön hivatkozás az emailprogramhoz, Gmailhez, Outlook.com-hoz és Microsoft 365-höz.
- A Gmail fiókválasztás a teljes levélhivatkozást továbbviszi a bejelentkezés utánra is.
- A tárgy és a levélszöveg külön másolható; így más levelezővel is használható. Tiltott vágólap esetén kijelöli a tartalmat a kézi másoláshoz.
- Hibás emailcímnél a megnyitást megállítja. Hiányzó címzettnél jelzi, hogy a levélben meg kell adni.
- Nem jelzi kiküldöttnek a levelet: a felhasználó a saját levelezőjében ellenőrzi és küldi el.
- Az új modul PWA-cache-be került. Publikált verzió: 39.

Az adatbekérő mentése, tokenvédelme, adatbázisa és foglalási értesítése nem változott. Más appot nem módosítottunk. Nem vezettünk be emailküldő szolgáltatást, új jogosultságot vagy költséget.

## Ellenőrzés és határai

- 10 böngészős ellenőrzés: eredeti link, címzett, magyar ékezetek, sortörések, Gmail/Microsoft átadási paraméterek, szerkesztett tárgy, ajánlati levél, hibás emailcím.
- A Geller Ágnes bemutatóprojektjén a valódi adatbekérő megosztóablaka megjelent, előtöltött címzettel és a hozzá tartozó levéllel. Próbaemailt nem küldtünk.
- A Gmail bejelentkezési oldala megnyílt, és a folytatási cím tartalmazta a tesztlevelet. A tesztböngésző nincs bejelentkezve a levelezőfiókokba; a bejelentkezés utáni teljes levélírást és kézbesítést ezért nem igazoltuk.
- Az Outlook.com kijelentkezve termékoldalra irányított, a levél `deeplink` paraméterének megtartásával. Bejelentkezett Outlook-fiókban külön ellenőrizendő.
- A tesztböngésző biztonsági szabálya blokkolta a külső emailprogram indítását. Ezt nem kerültük meg; a hagyományos emailprogram Windows alatti tényleges elindítása nem igazolt.
- A másolás gomb sikeres visszajelzést adott; az automatizáló böngésző külön vágólap-olvasó felülete nem tudta visszaolvasni a tartalmat. Kézi másoláshoz a teljes levélszöveg akkor is elérhető.

Források: [Google: Gmail protokollkezelés](https://developer.chrome.com/blog/getting-gmail-to-handle-all-mailto-links-with-registerprotocolhandler/), [Microsoft: email protokollkezelők](https://learn.microsoft.com/en-us/deployedge/microsoft-edge-browser-policies/registeredprotocolhandlers).
