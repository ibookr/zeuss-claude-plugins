---
name: "zeuss-ugyfellevel"
description: "Ügyféllevél-tervezet a Zeuss könyvelő rendszerben: hiányzó számlák és bankszámlakivonatok, díjbekérők, hibás feltöltések, számla nélküli banktételek, lejárt számlák, tisztázandók – tervezetként, kiküldés a Zeuss levelezőjével (email_jobs)."
---

# Ügyféllevél-tervezet (Zeuss)

Akkor használd, ha a felhasználó azt kéri, hogy nézd meg, mi hiányzik egy vagy több ügyféltől, és írj nekik levelet. Az eszközök a `zeuss` MCP szerver `zeuss_*` eszközei.

## Szabályok
- **Tervezetet írsz** (`zeuss_save_email_draft`). A könyvelő a **Claude agent → Ügyféllevelek** oldalon (`agent_api/collection_letters.php`, az összes cég egy helyen) vagy a cégenkénti `agent_api/email_drafts.php` oldalon nézi át, és a **„Küldés a Zeuss levelezőjével”** gombbal teszi az `email_jobs` sorba (az iroda fiókjából megy ki).
- Chatből kiküldeni csak a főszál küldhet, `zeuss_queue_email_draft`-tel, kétlépcsősen: előnézet (`confirm_code` nélkül) → a teljes levél megmutatása → a felhasználó kifejezett „küldd el” válasza → hívás a `confirm_code`-dal. Agentből soha.
- Címzett csak a `zeuss_client_contact` által visszaadott `emails` cím lehet.
- Ügyfelenként **egy** összefoglaló levél, tételes listával. Ha az `open_email_drafts` alapján már van nyitott tervezet ugyanerről, ne duplikáld, hanem jelezd a felhasználónak.
- Magyarul, tegezve vagy magázva aszerint, ahogy a megszólítás (`suggested_greeting`) sugallja; rövid, udvarias, konkrét: dátum, partner, összeg, számlaszám.
- Belső könyvelési zsargont (párosítás, főkönyv, kódszó) ne írj az ügyfélnek.
- **Minden levélben benne van** (a zeuss-anyagbekeres skill „Három kötelező szabálya” szerint): (1) a hónap **összes** kép nélküli számlája (`invoices_without_file`, könyvelt és könyveletlen, bejövő és kimenő) tételesen; (2) **minden** hiányzó bankszámlakivonat bankonként, akkor is, ha a hónapra még nincs banktétel (`bank_import_missing`).
- **Anyagot soha nem e-mailben kérünk.** Minden dokumentumot (számla, kivonat, végszámla, újra feltöltendő fájl) a **Zeuss Dokumentumok felületére** kérünk feltölteni, a `zeuss_collection_status` → `upload_targets` szerinti mappába (pl. „Dokumentumok → 2026-09 → Bejövő számlák”), blokkonként megnevezve. Tilos: „küldje el e-mailben / válaszlevélben”, „csatolja”. E-mailben csak kérdésre válaszolhat.

## Lépések
1. `zeuss_list_companies`, ha a cég azonosítója nem ismert.
2. `zeuss_open_issues` (ha a felhasználó dátumot ad, `as_of`), és a havi anyagokhoz **mindig** `zeuss_collection_status` (`month`): kép nélküli számlák, hiányzó bankszámlakivonatok, díjbekérők, hibás feltöltések, feltöltési mappák – ezek kiértékelése a zeuss-anyagbekeres skill 2–4. lépése szerint.
3. Ellenőrzés, mielőtt bármit számon kérsz:
   - lejárt vevői/szállítói számlánál, ha van `possible_unmatched_payment`, vagy a `zeuss_invoice_candidates` / `zeuss_invoice_combinations` alapján a pénz már befolyt → NE kérdezd az ügyfelet, hanem írd az `agent_note`-ba, hogy párosítani kell;
   - részfizetésnél add meg, mennyi érkezett és mennyi maradt nyitva.
4. `zeuss_client_contact` → megszólítás, címzettek, aláírás.
5. Levél felépítése: megszólítás → egy mondat a célról → számozott blokkok (hiányzó bankszámlakivonatok; hiányzó számla-PDF-ek; díjbekérők helyett végszámla; újra feltöltendő fájlok; számla nélküli terhelések; tisztázandó jóváírások; lejárt vevői számlák tájékoztatásul), a dokumentumot kérő blokkok végén a Zeuss Dokumentumok-mappa (`upload_targets`) → záró mondat: a dokumentumokat a Zeuss Dokumentumok felületén a fenti mappákba kérjük feltölteni, határidővel → köszönet → aláírás.
6. `zeuss_save_email_draft`: `reason_codes` (`missing_invoice_file`, `bank_without_invoice`, `missing_bank_statement`, `unmatched_invoice_file`, `faulty_upload`, `overdue_receivable`, `overdue_payable`, `clarification`, `other`), `related` (bank_item_ids, invoice_ids), és `agent_note` a könyvelőnek arról, mit hagytál ki szándékosan és miért.
7. A chatben röviden: kinek, mi került a levélbe, mit hagytál ki, és hol küldheti ki (`/app/agent_api/email_drafts.php` → „Küldés a Zeuss levelezőjével”). Ha a felhasználó a chatben kéri a kiküldést, a fenti kétlépcsős `zeuss_queue_email_draft` jön.

## Szakmai tippek
- Kapott előlegről előlegszámlát kell kiállítani; ilyenkor kérdezd meg, megtörtént-e.
- Külföldi online szolgáltatások (Google, Amazon, Meta) számlája nem jelenik meg a NAV-ban; jelezd, hogy a fiókból letölthető.