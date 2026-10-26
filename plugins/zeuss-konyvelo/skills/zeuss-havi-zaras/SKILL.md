---
name: "zeuss-havi-zaras"
description: "Havi zárás átnézése a Zeuss Varázsló lépései szerint és zárási jegyzőkönyv; reggeli irodavezetői összefoglaló az összes cégre (zeuss_closing_*, zeuss_office_*)."
---

# Havi zárás és reggeli összefoglaló (Zeuss)

## Havi zárás egy cégre
Használd, ha a felhasználó egy cég adott havi zárásának átnézését vagy zárási jegyzőkönyvet kér.
1. `zeuss_closing_status` (year, month) – a Varázsló lépései az adatokból: `ok` / `todo` / `warning` / `manual` / `not_examined`, tényszámokkal, a NAV-ellenőr kapcsolódó találataival, a könyvelő pipáival.
2. A `todo` és `warning` lépéseknek nézz utána a meglévő eszközökkel: `zeuss_work_queue`, `zeuss_list_bank_items`, `zeuss_open_issues`, `zeuss_list_match_suggestions`, `zeuss_booking_queue`, `zeuss_list_documents`.
3. `zeuss_closing_save`:
   - `steps`: lépésenként státusz és rövid, konkrét megjegyzés (mi hiányzik, hány tétel, mi a teendő). A `manual` lépéseknél írd le, mit kell kézzel ellenőrizni.
   - `summary`: zárási jegyzőkönyv a könyvelőnek (kész / hiányzik / teendő, sorrendben).
   - `accountant_note_draft` és `client_report_draft`: tervezetek; az ügyfélnek szóló közérthető, belső adat nélkül.
4. A lépéseket NEM pipálod ki – ezt a könyvelő teszi a Varázslóban. Ha anyag kell az ügyféltől, ajánld fel a zeuss-ugyfellevel skillt.

## Reggeli irodavezetői összefoglaló
Használd, ha a felhasználó a napi/reggeli összefoglalót kéri (ütemezett feladatból is).
1. `zeuss_office_overview` – az iroda összes cége egy hívásban.
2. Írj egy oldalas Markdown összefoglalót, fontossági sorrendben:
   1. Határidők 7 napon belül (ÁFA), és hogy van-e hozzá hiányzó anyag (könyveletlen számla, párosítatlan bank).
   2. NAV-jelzések: hiányzó bevallás, adótartozás, az utolsó NAV-ellenőrzés súlyos nyitott találatai.
   3. Elfogadásra váró agent-munka cégenként (párosítás, kontírozás, szabály, számlakép-eltérés, levéltervezet, ügyfélkérdés).
   4. Kitől kell anyag (hiányzó számlaképek; az előző hónap hiányzó bankszámlakivonatai a `zeuss_collection_status` szerint – csak cégenként egy hívás, részletes vizsgálat nélkül).
   5. Tegnap óta érkezett számlák és banktételek.
   Táblázat a cégekre, a végén 3–5 pontos „mai teendő”.
3. `zeuss_save_office_brief` (title, brief_date, summary, content_markdown). A Zeussban: Claude agent → Reggeli összefoglaló.