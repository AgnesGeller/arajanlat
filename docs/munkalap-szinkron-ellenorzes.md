# Munkalap-szinkron és megőrzött bemutató ellenőrzése

## Aktuális állapot

A négy Grill terasz nyárikerttel tesztmunkalapot a felhasználó törölte a Munkalap appból. Az Árajánlat négy másolata inaktív. Az aktuális projektösszesítő nulla aktív munkalapot ad vissza, az elfogadott munkadíjkeret 414 000 Ft maradt.

A megőrzött bemutató az inaktív másolatokat kizárólag olvasási előnézethez használja. A lezárásnál külön jelenik meg az aktuális elszámolás és a korábbi bemutató eredménye. Az inaktív másolatok nem kerülnek vissza az aktív elszámolásba vagy a Munkalap rendszerébe.

## Ellenőrzések

- 33 számítási próba: munkaidő, 8 500 Ft/főóra, földelszállítás, Excel-tételárak, javítás, mennyiségi készültség, kézi felülírás, törölt munkalapok kizárása.
- 5 projektmegjelenítési próba és 7 Munkalap-kiegészítési próba az Árajánlat saját helyi tesztoldalain.
- Adatbázispróba egy visszagörgetett tranzakcióban: azonos forrásazonosító javítása egy rekordot hagy; hiányzó munkalap inaktív lesz; régebbi lekérés nem állítja vissza.
- A kézi készültségi mennyiség munkalaptörléskor megmarad: az Ági/Tamás által megadott adat önálló adat, nem a törölt munkalap része.

A Munkalap app kódjához és forrásadataihoz ebben a körben nem nyúltunk. Új tesztmunkalap és email nem készült. A fizikai telefon/tablet ellenőrzése továbbra is külön felhasználói próba.

## Következő fejlesztési területek

1. Foglalási email, egyórás emlékeztető és eszközön megjelenő appértesítés működésének ellenőrzése, a hiányzó szolgáltatási beállítások azonosítása.
2. Projektazonosító mentén a tényleges kasszakiadások, anyagfelhasználás és bérkifizetések olvasási összerendelése; a hiányzó kapcsolati adatok előzetes egyeztetésével.
3. Képes látványtervezés megtervezése: a képeket a Supabase nem tárolja; szolgáltatás vagy új technológia bevezetése előtt külön egyeztetés szükséges.
