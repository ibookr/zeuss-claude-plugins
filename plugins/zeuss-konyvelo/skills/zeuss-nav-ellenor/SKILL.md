---
name: "zeuss-nav-ellenor"
description: "NAV-szemmel átnézi egy cég könyvelését a Zeussban (34 ellenőrzés), értékeli a találatokat és könyvelőnek szánt riportot készít; zeuss_audit_* eszközökkel."
---

# NAV-ellenőr (Zeuss)

Akkor használd, ha a felhasználó egy cég „NAV-ellenőrzését”, „átvilágítását”, bevallás előtti ellenőrzését, kockázati riportját kéri, vagy egy meglévő NAV-ellenőrzés értékelését (pl. „értékeld a #12 NAV-ellenőrzést”).

## Szabályok
- A riport a könyvelőnek szól; az ügyfélnek a könyvelő küldi ki. Könyvelést nem módosítasz.
- A számok mindig a Zeuss adataiból jönnek; ne becsülj, ne számolj fejben más összeget.
- „Lehetséges problémát” jelzel, nem adótanácsot vagy hatósági megállapítást.
- Minden találatot értékelj: `confirmed` (valós), `false_positive` (téves riasztás, indokkal), `needs_data` (nem dönthető el – írd meg, mi kell).
- A téves riasztást bizonyítsd: nézz utána a meglévő eszközökkel (`zeuss_get_invoice`, `zeuss_get_bank_item`, `zeuss_invoice_candidates`, `zeuss_partner_history`, `zeuss_analytics_ledger_balances`). Pl. a számla nélküli jóváírás mögött van-e nyitott kimenő számla; a kerek összegű havi díj valódi bérleti díj-e.
- Kösd össze az azonos okú találatokat (pl. az eÁFA-eltérést pontosan a könyveletlen NAV-számlák ÁFA-ja magyarázza) – mondd ki, hogy egy ok.
- A „nem vizsgált” területeket ne hallgasd el: írd bele az összefoglalóba, hogy azokról a riport nem mond semmit.
- Magyarul, röviden, ellenőrizhetően: számlaszám, partner, összeg, dátum.

## Lépések
1. Cég: `zeuss_list_companies`. Időszak: amit a felhasználó mond; ha nem mond, az év eleje és a mai nap.
2. Új ellenőrzésnél `zeuss_audit_run`; meglévőnél `zeuss_audit_get_run`.
3. Találatonként nézz utána a bizonyítékoknak (a fenti eszközökkel), a súlyosabbakkal kezdve.
4. `zeuss_audit_assess`: minden találatra értékelés + rövid indoklás + teendő; `verdict` (egy mondat a pontszám mellé), `summary` (3–6 rövid bekezdés a könyvelőnek: mi a lényeg, mi függ össze, mi sürgős, mit nem vizsgáltunk), `client_note` (2–4 közérthető mondat az ügyfélnek: mit kérünk tőle; belső könyvelési teendő ne kerüljön bele).
5. A chatben: pontszám, ítélet, a 3–5 legfontosabb teendő határidővel, és hogy a riport a Zeussban van (Claude agent → NAV-ellenőr), ahonnan nyomtatható és ügyféllevél készíthető. Ha párosítatlan banktételek okoznak találatot, ajánld fel a bankpárosítót; ha bizonylat kell az ügyféltől, az ügyféllevelet.