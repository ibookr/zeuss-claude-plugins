---
name: "zeuss-nyitas"
description: "Nyitás a Zeussban egy cégnél: a nyitott vevő–szállító számlák (egy vagy több fájl) és a nyitó napló importja a cég Nyitas mappájából (uploads/<cég>/Nyitas). Formátum-felismerés (RLB, könyvelőprogramok importformátumai), szükség esetén átalakítás Zeuss formátumra; egyeztetés főkönyvi számonként (31x vevő, 454x szállító: vevő–szállító nyitott összeg = bruttó − rendezett ↔ nyitó napló egyenleg); csak hibátlan egyezés után importál – előbb a vevő–szállító számlákat (NAV szinkron, partnerek, könyvelés), majd a nyitó naplót (partnerválasztás / -létrehozás). Jóváhagyást nem kér; devizás vevő–szállító számla is mehet (forintértékkel egyeztetve)."
---

# Nyitás – nyitott vevő–szállító számlák + nyitó napló (Zeuss)

Akkor használd, ha a felhasználó egy vagy több cégnél a nyitást kéri. Eszközök: a `zeuss` MCP szerver `zeuss_opening_*` eszközei. Közös elvek: `${CLAUDE_PLUGIN_ROOT}/skills/zeuss-iroda/references/alapelvek.md` – ez a skill az ott leírt „nem könyvelünk” elv **kifejezett kivétele**: a felhasználó döntése szerint a nyitáshoz nem kell jóváhagyás, a kapu a Zeuss beépített egyeztetése.

## Alapszabály: egyezés nélkül semmi nem kerül be
- A Zeuss (`zeuss_opening_import`) csak akkor ír, ha **minden ellenőrzés `ok`**, és főkönyvi számonként a vevő–szállító fájlok nyitott összege egyezik a nyitó napló egyenlegével:
  - vevő (31x, pl. 311, 312, 313): Σ(bruttó − rendezett) = a napló T − K egyenlege az adott főkönyvi számon;
  - szállító (454x, pl. 4541): Σ(bruttó − rendezett) = a napló K − T egyenlege; jóváíró számla negatív.
  - A főkönyvi szám a fájlból jön; ha a fájlban nincs, vevőnél 311, szállítónál 4541 (vagy amit a `ledger_code` megad).
- Ha nem egyezik: **nem importálsz**, nem igazítod az adatot. Leírod főkönyvi számonként az eltérést, és ha látszik az oka (hiányzó fájl, rendezett oszlop, más főkönyvi szám, eltérő dátum), azt is.
- Devizás vevő–szállító számla is importálható: a kimenőket a Zeuss a NAV-ból tölti le, a bejövőket létrehozza (deviza, devizaösszeg, árfolyam). Az egyeztetésben a devizás számla a **forintértékével** (bruttó Ft − rendezett Ft) szerepel; a nyitó napló forintos.
- `zeuss_accept_*`, `zeuss_queue_email_draft` – soha.

## 0. Cég, futás
- Cég: amit a felhasználó mond; ha semmi, `zeuss_list_companies`, és azok a cégek, ahol a Nyitas mappában van fájl (`zeuss_opening_status` → `files`). Cégenként külön, egymástól függetlenül (párhuzamosítható).
- Cégenként `zeuss_start_run` (`task: opening_import`), a végén `zeuss_finish_run` darabszámokkal; a `run_id`-t add át a check / import hívásnak.

## 1. Helyzetkép – `zeuss_opening_status`
- `files` – a Nyitas mappa fájljai (`file_comment_id`), a könyvelő vegyesen, válogatás nélkül tölti fel őket: **Nyitás → MI nyitás – fájlok feltöltése**. Hogy melyik mi (vevő, szállító, nyitó napló, kiegészítő fájl), azt neked kell eldöntened a 2. lépésben. Ha üres: jelezd, hogy a fájlokat ott kell feltölteni (vagy ha a felhasználó megadja őket, `zeuss_opening_upload_file`-lal feltöltöd).
- `existing_opening_journal` – ha a nyitás évére már van nyitó tétel, a Zeuss csak akkor engedi tovább, ha főkönyvi számonként egyezik a fájllal (`already_loaded`); eltérőnél megáll (nem duplikál).
- `formats` – a választható importformátumok (`vevo_szallito` / `nyito_naplo`), több fájlos formátumnál a fájlmezőkkel (`files.key`).

## 2. Formátum – fájlonként `zeuss_opening_file_preview`
- `detected` – mely importálók olvassák be (type + format, tételszám; vevő–szállítónál `open_by_ledger`). Döntsd el fájlonként, hogy **vevő–szállító** vagy **nyitó napló**, és melyik formátum:
  - egy fájlt több formátum is felismerhet – azt válaszd, amelyik a tartalomhoz illik (`raw` első sorai), és a tételszám a fájl sorainak felel meg;
  - több fájlos program-formátumnál (Kulcs .CSV + .001 + .002, Forintsoft DBF-ek, SmartBooks vevő + szállító XLSX, TenSoft FELADAS + UGYFEL) a fájlokat a `files` térképpel adod meg (`{"main": [id], "items": [id], "clients": [id]}`).
- **Ha egyik importáló sem ismeri fel** (`detected` üres), vagy a felismert formátum hibás eredményt ad: **alakítsd át Zeuss formátumra**, a `raw` tartalma alapján, minden sort változatlan értékkel átvéve:
  - vevő–szállító (pontosvesszős CSV, UTF-8, első sor fejléc): `vszfsz;bizszam;partnev;adoszam;telj;bruttossz;rendezve`
    - `vszfsz`: a fájl főkönyvi száma (31x / 454x); ha nincs, vevő 311, szállító 4541;
    - `telj`: teljesítés `ÉÉÉÉ-HH-NN`; `bruttossz`: bruttó Ft (jóváíró negatív); `rendezve`: a fordulónapig kiegyenlített rész (üres = 0), **nem** a nyitott összeg – ha a forrásban csak nyitott / hátralék van, `rendezve = bruttó − nyitott`;
    - opcionális: `kelt`, `fizhat`, `megjegyzes`.
    - devizás számlánál még: `devnem` (pl. EUR), `ertek` (bruttó devizában, kötelező), `arfolyam`, `devrend` (rendezett rész devizában); `bruttossz` és `rendezve` ilyenkor is forintban (a forrás forintértéke, vagy devizaösszeg × árfolyam, ha a forrás csak devizát ad – ezt jelezd).
  - nyitó napló (pontosvesszős CSV, UTF-8): `Dátum;Főkönyvi szám;Ellenszámla;Tartozik;Követel;Partner neve;Megjegyzés` – soronként a főkönyvi szám az ellenszámlával szemben (jellemzően 491), az összeg a Tartozik vagy a Követel oszlopban; egyenleglistából: T-egyenleg → Tartozik, K-egyenleg → Követel, ellenszámla 491.
  - Fájlnév: `<eredeti név>_zeuss.csv`; `zeuss_opening_upload_file` (base64), majd ezzel a `file_comment_id`-val és `format: zeuss` dolgozol. Az eredeti fájl marad. A visszatérésben jelezd, melyik fájlt alakítottad át és hogyan.
  - Átalakítás után futtasd újra a `zeuss_opening_file_preview`-t az új fájlra: a tételszám és az `open_by_ledger` egyezzen a forrással.

## 3. Ellenőrzés – `zeuss_opening_check` (írás nélkül)
Paraméterek: `customer_supplier_files` (egy vagy több `{file_comment_id | files, format, direction?, ledger_code?}`), `journal_file` (`{file_comment_id, format}`), `opening_date` (alap: a nyitó tételek dátuma), szükség szerint `create_missing_accounts`, `account_names`, `journal_partners`, `run_id`.
Nézd végig a `checks`-et (mind `ok` kell):
- `reconciliation` – a lényeg; a `reconciliation` táblában főkönyvi számonként a két oldal és az eltérés. Eltérésnél: nincs import.
  - Gyakori ok: hiányzik egy vevő–szállító fájl (pl. csak a vevők jöttek), más főkönyvi számon van a fájl (`ledger_code`-dal adható meg, ha a forrásban egyértelmű), a rendezett összeg nem a fordulónapig szól. Csak akkor módosítasz paramétert, ha a forrásból egyértelmű; egyébként könyvelőnek szóló hiba.
- `customer_supplier_parsed`, `journal_parsed` – olvasási hiba / hibás sor (hiányzó dátum, főkönyvi szám). Hibás forrásnál nincs import.
- `opening_date` – a nyitó tételek dátuma egységes legyen.
- `currency` – tájékoztató: a devizás számlák darabszáma és összege pénznemenként (devizában és forintban). Nem állít meg; a visszatérésben említsd meg.
- `ledger_accounts` – a nyitó naplóban (vagy a vevő–szállító fájlban) olyan főkönyvi szám van, ami a cég számlatükrében még nincs. Ilyenkor **létre kell hozni**, ahogy a Zeuss Számlatükör oldalán (`ledger_manage.php`) is:
  - `create_missing_accounts: true` – a Zeuss a cég **számlatükör sablonjában** hozza létre, a hiányzó **szülő szintekkel együtt** (pl. 46611-hez a 4661-et is, ha az sincs), az első meglévő ős alá. Ha a cégnek még **nincs sablonja**, előbb létrehoz egyet a cég nevével („<cég> – számlatükör”), és a céghez rendeli. A check kiírja: mi hiányzik (`missing_accounts`), mely szülők jönnek létre (`parent_accounts`), mely meglévő szám válik gyűjtőszámlává (`new_summary_accounts`), és melyik sablonba.
  - `account_names` – az új számok neve a forrásfájl szerint, ha ott van (egyenleglista, főkönyvi kivonat, számlatükör a fájlban): `{"4661": "…", "46611": "…"}`. Ne találj ki nevet: ha a forrásban nincs, hagyd ki – akkor a napló megjegyzése, különben „Nyitó import <szám>” lesz, és a visszatérésben jelezd, hogy a könyvelő nevezze át.
  - Nem hozható létre (könyvelőnek szóló hiba, nem kerülöd meg): ha az ős „nem bontható” vagy banki számla (pl. 466, 311, 4541 alá nem nyitható alszámla); ha az ős most válna gyűjtőszámlává, de a sablont használó valamelyik cégnél már van rajta könyvelés vagy beállítás (ezt a Számlatükör oldalon, átvezetéssel kell megcsinálni); ha a nyitó napló maga is a gyűjtővé váló számra könyvel. Ilyenkor ne írd át a főkönyvi számot a fájlban – a könyvelő dönt.
- `postable` – gyűjtőszámlára (aminek alszámlái vannak) nem lehet nyitni: a forrás egy alszámláját kell használni, ezt a könyvelőnek jelezd.
- `journal_not_loaded_yet` – az évre már eltérő nyitó tételek vannak → megállsz.
- `journal_partners` – a nyitó napló partnerdöntései (`journal.partner_plan`):
  - a Zeuss magától dönt: adószám (a vevő–szállító fájlból) → meglévő partner; pontos névegyezés → meglévő; a vevő–szállító import által létrehozott partner; 31x / 454x soron, ha nincs hasonló partner → **új partner**;
  - ha csak **hasonló** partner van (`candidates`), neked kell döntened: `journal_partners: [{"row": 12, "partner_id": 345}]`, vagy `{"row": 12, "action": "new"}`, vagy `{"partner_name": "…", …}` az összes ilyen nevű sorra. Meglévőt akkor válassz, ha a név lényegében azonos (rövidítés, cégforma, ékezet, elírás) és az adószám nem mond ellent; különben új partner. Partner nélkül (`action: none`) vevő / szállító soron csak akkor, ha a forrásban sincs partner.
  - A döntéseidet indokold a visszatérésben.
- `customer_supplier.partner_groups` – a vevő–szállító számlák partnerei (meglévő / új). Ha egy javaslat nyilvánvalóan rossz (más cég), `customer_supplier_partners: [{"partner_name": "…", "partner_id": …}]` vagy `{"action": "new"}`.

## 4. Import – `zeuss_opening_import` (ugyanazokkal a paraméterekkel)
Csak ha a check `status = ready`. A Zeuss az elején újra ellenőriz (ha közben bármi változott, nem ír).
- `status = nav_in_progress` → a vevő–szállító számlák NAV szinkronja folyik (a könyvelésbe még semmi nem került): hívd **újra ugyanígy**, amíg el nem fogy (`nav.remaining`).
- Sorrend: NAV szinkron → vevő–szállító import (egy tranzakcióban: hiányzó főkönyvi számok, partnerek, NAV-ban nem talált számlák kézi létrehozása, fordulónap előtti könyvelés, rendezett rész) → nyitó napló (egy tranzakcióban, főkönyvi visszaellenőrzéssel).
- `imported` → kész; a `verification` szerint a főkönyv nyitó tételei főkönyvi számonként egyeznek a fájllal és a vevő–szállító összegekkel.
- `journal_failed` → a vevő–szállító import **bent van**, a nyitó napló technikai hiba miatt 3 próbálkozás után sem. Egyszer később ugyanezzel a kéréssel próbáld újra (nem duplikál); ha megint nem megy, írd meg: „technikai okok miatt a nyitó napló nem importálható”, a hibaüzenettel.
- `imported_with_differences` → bent van, de a visszaellenőrzés eltérést mutat: tételesen a könyvelőnek.
- `failed` → semmi nem került be; a hibás ellenőrzések / a hibaüzenet a könyvelőnek.

## 5. Visszatérés
Az agent leírásában lévő formátum szerint: egyeztetés főkönyvi számonként, import darabszámok, partnerdöntések, átalakított fájlok, legfeljebb 5 teendő a könyvelőnek (hol a Zeussban: Nyitás → Nyitó tételek, Vevő–szállító import, Partnerek, Számlatükör).
Betöltöttnek csak azt mondod, amire a Zeuss `imported` / `already_loaded` állapotot adott.
