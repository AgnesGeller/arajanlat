# Munkalap árlista az Árajánlatban

Az import forrása a Munkalap mezőlistája és a `Költségvetés 2026 (3).xlsx` fájlból kinyert, ellenőrzött számítási szabályok. A Munkalap és a Kassza alkalmazása, adatbázisa és jogosultságai nem változnak.

## Importálási szabály

- A meglévő Árajánlat-árlista az **1. árforrás**.
- Az azonos nevű, mértékegységű és árú Munkalap-tétel nem kerül be másodszor.
- Azonos tétel eltérő áránál a Munkalap ára **2. Munkalap ár** jelölést kap.
- A hiányzó Munkalap-tétel új tételként kerül az Árajánlat saját `quote_price_catalog` táblájába.
- A forrásban ár nélküli tételek 1 Ft-os, ellenőrzendő jelzőárat kapnak.

## Megőrzött képletek

- Munkadíj: létszám × tényleges óraszám × 8 500 Ft.
- Növényvédelem és talajpermet: 1. tartály 25 000 Ft; 2–4. tartály 17 000 Ft/db; az 5. tartálytól 12 000 Ft/db.
- Lemosó permetezés: 1. tartály 20 000 Ft; 2–4. tartály 12 000 Ft/db; az 5. tartálytól 7 000 Ft/db.
- Földelszállítás: mennyiség × 8 000 Ft/m³ + egyszeri 10 000 Ft szállítási díj.

Az importáló SQL: `supabase/quote_worksheet_prices.sql`. Az elkülönített adatbázis-ellenőrzés: `supabase/tests/quote_worksheet_prices.sql`.
