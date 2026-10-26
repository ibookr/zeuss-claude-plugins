---
name: "zeuss-kimutatas"
description: "Tetszőleges kimutatás/riport egy cégnek a Zeuss könyvelő rendszer adataiból (árbevétel, beszerzés, cashflow, kintlévőség, főkönyvi kivonat) zeuss_* MCP eszközökkel."
---

# Kimutatás készítése (Zeuss)

Akkor használd, ha a felhasználó egy cégről kimutatást, riportot, elemzést, összehasonlítást kér. Az adatot mindig a `zeuss_*` eszközökből veszed, soha nem becsülsz.

## Adatforrások
- `zeuss_analytics_invoices`: számlák, forintban. `group_by` legfeljebb 2 dimenzió: month, quarter, year, partner, direction, vat_rate, category, currency, status; `date_basis`: fulfillment (alap), issue, due.
- `zeuss_analytics_cashflow`: banki befolyó/kifolyó/nettó (month, week, day, partner, code).
- `zeuss_analytics_aging`: korosítás partnerenként (outgoing = vevők, incoming = szállítók).
- `zeuss_analytics_ledger_balances`: főkönyvi kivonat (level account/1/2/3, `with_opening`).
- Részletekhez: `zeuss_list_invoices`, `zeuss_get_invoice`, `zeuss_partner_history`.

## Lépések
1. Tisztázd a céget és az időszakot. Ha nincs megadva, az idei év eddigi részét vedd, és mondd ki.
2. Kérd le a szükséges aggregációkat; ellenőrizd az összegeket egymással (pl. havi összeg = időszaki összeg; főkönyvben tartozik = követel).
3. Megállapítások: 3–6 konkrét pont számokkal (trend, csúcs, koncentráció, lejárt követelés). Jelezd a torzító tényezőket, pl. párosítatlan banktételek (`unprocessed_count`) miatt a kintlévőség túlbecsült lehet.
4. Riport a chatben: táblázatok, és ahol segít, egyszerű grafikon. Magyar számformátum: ezres tagolás szóközzel, tizedesvessző, „M Ft”.
5. Ha a felhasználó kéri, vagy a riport ügyfélnek szól: `zeuss_save_report` önálló HTML-lel (inline CSS és SVG, **szkript nélkül**), `title`, `request_text`, `period_from/to`, `summary`. Megtekintés: `/app/agent_api/reports.php`.

## Korlátok, amiket ki kell mondani
- Az `open_huf` és a korosítás a mai nyitott állapotot mutatja.
- Ez vezetői kimutatás, nem beszámoló; bérköltség, értékcsökkenés, elhatárolások csak akkor szerepelhetnek, ha a főkönyvből le is kérdezted őket.