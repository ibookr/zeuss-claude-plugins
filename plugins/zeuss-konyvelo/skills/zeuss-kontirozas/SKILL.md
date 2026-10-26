---
name: "zeuss-kontirozas"
description: "Kontírozási javaslat bejövő számlákhoz és tanuló banki szabályok a Zeussban, zeuss_* MCP eszközökkel; csak javaslat, véglegesítés kétlépcsősen."
---

# Kontírozás és tanuló szabályok (Zeuss)

Használd, ha a felhasználó könyveletlen bejövő számlák kontírozását kéri, vagy azt, hogy milyen könyvelési szabályokat érdemes felvenni egy cégnél.

## Kontírozás
1. `zeuss_list_companies` → a cég id-je.
2. `zeuss_booking_queue` – a könyveletlen bejövő tételek: a partner korábbi kontírozásai (`partner_history`), hasonló megnevezések, a meglévő statisztikai predikció.
3. `zeuss_ledger_accounts` – a főkönyvi szám id-jét innen vedd (ne a kódot add meg). Csak 1-es, 2-es, 5-ös vagy 8-as számlaosztály.
4. Tételenként dönts:
   - Ha a partnert eddig mindig ugyanarra könyvelték és a tétel jellege ugyanaz → az a szám, magas konfidencia.
   - Új partner, vegyes tétel, nagy értékű tartós eszköz (tárgyi eszköz lehet), külföldi szolgáltató (fordított adózás / uniós beszerzés) → jelölők (`needs_human`, `fixed_asset`, `reverse_charge`, `eu_acquisition`, `new_partner`), alacsonyabb konfidencia.
   - ÁFA: `deductible`, `non_deductible` (pl. reprezentáció, személygépkocsi), vagy `partial` + `reclaim_percentage`.
5. `zeuss_save_booking_suggestions` – magyar indoklással (miért ez a szám, mire támaszkodtál). Ez nem könyvel: a „Nem könyvelt tételek” oldalon lila előválasztásként jelenik meg.
6. Összefoglaló a felhasználónak: tételenként szám, ÁFA, konfidencia, és külön a bizonytalanok.

## Könyvelés a chatből (csak kifejezett kérésre)
1. `zeuss_accept_booking_suggestions` confirm_code NÉLKÜL → előnézet. Mutasd meg tételesen (számla, tétel, nettó, főkönyvi szám, ÁFA), és a blokkolt tételeket okkal.
2. Csak ha a felhasználó EZUTÁN kifejezetten azt mondja, hogy könyveld le: ugyanazokkal a paraméterekkel + a kapott `confirm_code`.
3. Soha ne könyvelj saját kezdeményezésből, és ne ugyanabban a lépésben, amelyben a javaslatot készítetted.

## Tanuló szabályok
1. `zeuss_rule_candidates` – ismétlődő közvetlen banki könyvelések (szöveg → főkönyvi szám, előfordulás, hónapok, következetesség).
2. Szűrd a zajt: általános szövegek (pl. „UTALÁS MAGÁNSZEMÉLY”), változó főkönyvi szám, kevés hónap → ne javasold.
3. `match_text`: rövid, jellemző, stabil szövegrész (dátum és sorszám nélkül), pl. „OTP KÁRTYADÍJ”.
4. `zeuss_save_rule_suggestions` magyar magyarázattal. A Zeuss visszateszteli; nézd meg az `would_conflict` értéket, és ha nem 0, írd meg.
5. Bekapcsolni csak a könyvelő tudja: Claude agent → Szabályjavaslatok.

## Mérés (lokális demó)
`docker compose -f docker-compose.local.yml exec app php agent_api/tools/evaluate_agents.php booking` (illetve `rules`).