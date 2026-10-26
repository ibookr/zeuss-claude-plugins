---
name: "zeuss-anyagbekeres"
description: "Könyvelési anyagok beszedése a Zeussban (zeuss_collection_status): a számlával nem párosított feltöltött számlaképek vizsgálata (valós/külföldi számla, díjbekérő, hibás feltöltés), a bankszámlakivonatok ellenőrzése a banktételes főkönyvi bankszámlák alapján, és ügyféllevél a hiányokról a Zeuss levelezőjén (email_jobs) át."
---

# Anyagbekérés – könyvelési anyagok beszedése (Zeuss)

Akkor használd, ha a felhasználó azt kéri, hogy nézd meg, megjött-e minden anyag a hónapra, mi hiányzik vagy hibás a feltöltések közül, vagy kérd be a hiányzó anyagokat (bankszámlakivonat, számla, díjbekérő helyett végszámla).
Eszközök: a `zeuss` MCP szerver `zeuss_*` eszközei. Közös elvek: `${CLAUDE_PLUGIN_ROOT}/skills/zeuss-iroda/references/alapelvek.md`.

## 0. Cégek és hónap
- **Mindig azokat a cégeket vizsgáld, amelyekhez a felhasználónak hozzáférése van**: `zeuss_list_companies`. Ha a felhasználó egy céget nevez meg, csak azt; különben az összeset, cégenként külön (a cégek függetlenek, párhuzamosíthatók).
- Hónap: amit a felhasználó mond; alapból az **előző naptári hónap** (`month` paraméter nélkül a Zeuss is ezt adja). Mondd ki, melyiket vetted.
- Cégenként: `zeuss_start_run` (`task: document_collection`, `company_id`), a végén `zeuss_finish_run` darabszámokkal.
- A cég saját adószáma és neve: `zeuss_company_overview` – a számlák irányának ellenőrzéséhez kell.

## 1. Helyzetkép
`zeuss_collection_status` (`company_id`, `month`). Négy blokkot ad:
- `invoices_without_file` – a hónap (teljesítés, ennek híján kelte szerint) könyvelt számlái a NAV-szinkronból (vagy kézi rögzítésből), **amelyekhez nincs számlakép**; `totals` irányonként (összes / van kép / nincs kép), `items` tételesen. **Ez a hiányzó számlák fő forrása** – a feltöltött fájlokból ez nem látszik.
- `invoice_files` – a Dokumentumok közé (`file_comments`) feltöltött bejövő/kimenő számlaképek közül **csak a számlával nem párosítottak** (`unpaired`); a párosítottak csak darabszámként (`paired`). **A párosított fájlokkal nem foglalkozunk – azok rendben vannak.**
- `banks` – mely főkönyvi bankszámlákon (`ledger_number.bank = 1`) van banktétel (`bank_ledgers_with_items`), és a feltöltött banki fájlok (`bank_files`, valamint a rossz mappába tett, kivonatnak látszó `bank_like_files_elsewhere`).
- `previous_agent_emails`, `open_email_drafts` – ne kérjünk kétszer ugyanazt.

## Három kötelező szabály (minden levélben)
1. **Minden kép nélküli számla benne van a levélben**, tételesen – bejövő és kimenő, könyvelt és még nem könyvelt (`booked = false`, csak NAV-szinkronizált) egyaránt. Nem rövidítesz, nem válogatsz „a legnagyobbakra”.
2. **Minden hiányzó bankszámlakivonat benne van a levélben** – bankonként, akkor is, ha a hónapra még nincs banktétel a rendszerben (`bank_import_missing`).
3. **A hiányzó anyagot soha nem e-mailben kérjük**: nincs „küldje el válaszlevélben / e-mailben / csatolja”. Mindig azt kérjük, hogy töltse fel a **Zeuss Dokumentumok felületén** (Dokumentumok varázsló) a megfelelő mappába – a mappát az `upload_targets` adja, blokkonként megnevezve.

## 2. Számlák, amelyekhez nincs kép
`invoices_without_file.items` – bejövő **és** kimenő, **könyvelt és könyveletlen** (`booked`) is:
- Mind ügyfélnek szóló tétel: tételesen kérd be (partner, számlaszám, kelte, teljesítés, bruttó összeg, pénznem), irányonként külön blokkban („Bejövő (szállítói) számlák”, „Kimenő (vevői) számlák”). **Mindig az összeset** – darabszámtól függetlenül.
- Az egyetlen kivétel: ha az `invoice_files.unpaired` között (vagy a szomszédos hónap mappájában) már ott van ugyanannak a számlának a képe (számlaszám / partner + összeg egyezik), az nem hiányzik – a könyvelőnek csatolnia kell (`agent_note`), az ügyféltől nem kérjük. Ezt az `agent_note`-ban tételesen indokold.
- Ha `invoices_without_file.truncated = true`, a lista nem teljes: jelezd a könyvelőnek az `agent_note`-ban és az összefoglalóban (a levélbe az összes kapott tétel bekerül).
- A levél elején mindig legyen ott irányonként: „{hónap}: N számla, ebből K-hoz megvan a kép, M hiányzik”.
- Külföldi online szolgáltatónál (Google, Meta, Amazon, Microsoft stb.) írd mellé, hogy a számla a szolgáltató fiókjából tölthető le.

## 3. Nem párosított számlaképek
Fájlonként (`invoice_files.unpaired`):
1. `fresh = true` → valószínűleg csak a NAV-letöltésre vár: **ne vizsgáld, ne kérd számon**, csak darabszámként jelezd.
2. Van `last_check` ugyanerre a fájlra → használd az ítéletét, ne olvasd újra (kivéve, ha `unreadable` volt és azóta nem változott – akkor sem).
3. Első lépésben az `ocr_excerpt`, az `extracted` mezők, a fájlnév és a `uploader_comment` alapján döntsd el, mi a dokumentum. Ha bármi kétséges, vagy valódi számlának látszik: `zeuss_get_document` (`document_id`) – képként kapod –, majd `zeuss_save_document_extraction` (a Zeuss megkeresi a NAV-számlát és összeveti). `document_id` nélkül csak az OCR-ből dönts, és jelöld a bizonytalanságot.
4. Besorolás (`document_type` + jelölők):
   | Mit látsz | `document_type` | Jelölő | Kinek szól |
   |---|---|---|---|
   | Magyar számla, a NAV-ban van párja (`match` / `mismatch`) | `invoice` | – | könyvelő: csatolni kell (Claude agent → Számlaképek); `mismatch`-nél az eltérés |
   | Magyar ÁFÁ-s számla, NAV-ban nincs (`not_in_nav`, `domestic_not_reported`) | `invoice` | – | könyvelő **és** ügyfél: kérdezze meg a kiállítót, valóban számla-e, jelentette-e |
   | Külföldi számla (EU/harmadik ország, pl. Google, Meta, AWS) | `foreign_invoice` | – | könyvelő: kézzel rögzítendő; ügyfélnek nem kell írni |
   | Díjbekérő, előlegbekérő, proforma, „nem számla” felirat | `proforma` | – | ügyfél: ha kifizette, kérjük a végszámlát (előlegnél az előlegszámlát) – **kivéve**, ha a mentés után a Zeuss ugyanattól az eladótól, egyező összeggel NAV-számlát talált (`matched_invoice`, `in_nav`): akkor a végszámla megvan, a díjbekérő csak fölösleges feltöltés (könyvelőnek jelezni, ügyfélnek nem) |
   | Nyugta, blokk | `receipt` | – | könyvelő; ügyfélnek csak ha olvashatatlan |
   | Jóváíró / sztornó számla | `credit_note` | – | könyvelő |
   | Szerződés, ajánlat, szállítólevél, fotó, egyéb | `other` | `wrong_folder` | ügyfél: rossz helyre került, a számlát kérjük |
   | Olvashatatlan, üres, sérült | `unreadable` | `poor_quality` / `blank_or_corrupt` | ügyfél: töltse fel újra |
   | Csak egy oldal / levágott számla | `invoice` | `partial_document` | ügyfél: a teljes számlát kérjük |
   | Nem a cég a vevő (bejövőnél) / nem a cég az eladó (kimenőnél) | a típusa | `not_our_document` | ügyfél: tévesen feltöltött? |
   | Bejövő számla a Kimenő mappában vagy fordítva; bankkivonat a számlák között | a típusa | `wrong_folder` | könyvelő (átsorolás); ügyfélnek csak tájékoztatás |
   | Ugyanaz a számla kétszer | a típusa | `duplicate_suspect` | könyvelő |
5. Csak azt rögzítsd, amit a képen biztosan látsz; NAV-adatból semmit ne tölts ki.

## 4. Bankszámlakivonatok
1. **Szükséges kivonatok:** minden `bank_ledgers_with_items` sor, ahol `statement_required = true`. Ahány ilyen főkönyvi bankszámla, annyi bankszámlája van a cégnek, és **mindegyikhez kell a hónapra PDF bankszámlakivonat**.
   - `items_in_month > 0` → biztosan kell.
   - `bank_import_missing = true` (a hónapban nincs tétel, de az elmúlt fél évben volt) → **ugyanúgy kell kivonat, és bekerül a levélbe** (lehet, hogy forgalom nélküli hónap, vagy csak a banki import maradt el). Soha ne hagyd ki azzal, hogy „nincs szeptemberi tétel”. A levélben kérd, hogy ha nem volt mozgás, azt jelezze.
   - Ha a főkönyvben egyáltalán nincs banktételes bankszámla, de a `previous_month_bank_files` szerint az előző hónapban jöttek kivonatok → azoknak a hónapra eső párját is kérd be, és jelezd a könyvelőnek, hogy a banki import hiányzik.
   - **Melyik kivonat kell:** a `previous_month_bank_files` (és a `company_bank_accounts`) mutatja, milyen kivonatok szoktak jönni (bank, számlaszám, pénznem a fájlnévből). Minden ott szereplő kivonatfajtának kell a vizsgált hónapra eső párja – a levélben így nevezd meg: „{bank} {számlaszám / pénznem} – {hónap} havi kivonat (az előző hónapban „{fájlnév}” néven érkezett)”. Figyelj: van, aki a hónap kivonatát a következő havi mappába tölti (ott a fájlnév dátuma dönt).
   - **Ne kérd, ami megvan, csak rossz helyen:** ha a `next_month_bank_files` (vagy `bank_like_files_elsewhere`) között ott a hónap kivonata, az nem hiányzik – a könyvelőnek jelezd (`agent_note`).
   - Megszűnt számlát (pl. „…_zaro”, „zarasig” fájlnév, régóta nincs tétel) ne kérj; írd az `agent_note`-ba.
   - `ledger_missing` sor (banktétel főkönyvi bankszámla nélkül) vagy `not_flagged_as_bank` → könyvelőnek szóló jelzés, nem ügyfélnek.
   - A bank nevét és pénznemét a `bank_name_hint` / `currency_hint` / `currencies_in_items` adja; ha a név semleges (pl. „Elszámolási betétszámla HUF1”), a `company_bank_accounts` (a feltöltő varázsló bankjai) és a kivonatok tartalma alapján azonosítsd.
2. **Feltöltött banki fájlok** (`bank_files`, `bank_like_files_elsewhere`), amelyeknek még nincs `agent_link`-je:
   - fajta: `folder_kind` és kiterjesztés alapján – PDF a `Bankszamlakivonatok` mappában (vagy közvetlenül a `Bankok` alatt) ≈ `statement`; CSV/XLS(X) ≈ `transaction_list`; ami nem banki, az `not_bank_document`.
   - **számlatulajdonos**: a kivonaton szereplő név / adószám a cégé-e. Más cég kivonata → `not_our_statement` (tévesen feltöltött – az ügyfélnek jelezni, és ellenőrizni, nem került-e a mi kivonatunk a másik céghez).
   - főkönyvi szám: (a) `usual_bank_folder_ids` – ha a bankmappát korábban már hozzárendeltük, az a minta; (b) a mappa / `company_bank_accounts` banknév ↔ `bank_name_hint`; (c) pénznem az OCR-ben ↔ `currency_hint` / `currencies_in_items`; (d) bankszámlaszám az OCR-ben. Ha így sem egyértelmű (pl. két forintszámla ugyanannál a banknál): `zeuss_get_document` és a kivonat fejlécéből (számlaszám, pénznem, időszak) dönts.
   - időszak: nézd meg, hogy a kivonat a vizsgált hónapot fedi-e (`period_from` / `period_to`). Másik hónap kivonata → jelöld a `note`-ban, és ne számítsd a hónap kivonatának.
   - mentés: `zeuss_save_bank_statement_link` (`file_comment_id`, `kind` – `statement` / `transaction_list` / `not_our_statement` / `other` / `not_bank_document`, `ledger_number_id`, `period_from/to`, `account_number`, `currency`, `confidence`, `note`). Bizonytalan hozzárendelésnél `confidence < 0,5` és a `note`-ban, mi a kétség.
3. Mentés után hívd újra a `zeuss_collection_status`-t: minden szükséges főkönyvi bankszámla `covered` vagy hiányzik.
4. **Hiány:** amelyik szükséges főkönyvi bankszámlához nincs a hónapra `statement` → hiányzó kivonat (bank, pénznem, főkönyvi szám, időszak). A tranzakciós lista egymagában nem pótolja a PDF kivonatot.

## 5. Kell-e levél?
Ügyfélnek szóló tétel: **kép nélküli számla (`invoices_without_file`)**; hiányzó bankszámlakivonat; más cég tévesen feltöltött kivonata; díjbekérő végszámla nélkül; hibás/olvashatatlan/hiányos/rossz helyre tett feltöltés; nem a céghez tartozó dokumentum; NAV-ban nem szereplő magyar számla (a kiállítónál tisztázandó).
Csak a könyvelőnek szól (a levélbe NEM kerül, az `agent_note`-ba igen): csatolandó, NAV-ban meglévő számla; külföldi számla rögzítése; duplikátum; főkönyvi bankszámla nélküli banktétel; bizonytalan hozzárendelés.

Ha nincs ügyfélnek szóló tétel → nincs levél; az összefoglalóban írd, hogy a hónap anyaga rendben.
Ha a `previous_agent_emails` / `open_email_drafts` szerint 7 napon belül már kértük ugyanezt → ne írj újat; jelezd, hogy emlékeztető kell-e.
**Teljes havi kör részeként** (zeuss-iroda) ne ments tervezetet: add vissza a tételeket a főszálnak, és a kör végi ügyféllevél tartalmazza őket (ügyfelenként egy levél).

## 6. Levéltervezet
1. `zeuss_client_contact` → címzettek (csak az `emails` címek), megszólítás, aláírás.
2. Felépítés: megszólítás → egy mondat: „a(z) {hónap} havi könyveléshez az alábbiakra van még szükségünk” → számozott blokkok, **mindegyik végén a feltöltési hely** (`upload_targets`):
   - **Hiányzó bejövő számlák** – az összes, tételesen: partner, számlaszám, kelte, teljesítés, bruttó összeg → „Kérjük, töltse fel a számlák PDF-jét / képét a Zeuss Dokumentumok felületén: Dokumentumok → {hónap} → Bejövő számlák.”
   - **Hiányzó kimenő számlák** – ugyanígy → „… Dokumentumok → {hónap} → Kimenő számlák.”
   - **Bankszámlakivonatok** – mindegyik hiányzó, bankonként: „{bank} {számlaszám / pénznem} – {hónap} havi PDF kivonat” (ha a bank nem ismert: a pénznem és az előző havi fájlnév) → „… Dokumentumok → {hónap} → Bankok → {bank} → Bankszámlakivonatok (a Dokumentumok varázslóban a bank kiválasztásával).”
   - **Díjbekérők**: fájlnév, partner, összeg → „ha kifizette, kérjük, töltse fel a végszámlát a Bejövő számlák mappába”;
   - **Újra feltöltendő fájlok**: fájlnév + ok (olvashatatlan, csak az első oldal, nem a cég nevére szól…) → ugyanabba a mappába, ahová eredetileg feltöltötte;
   - **Tisztázandó számlák**: partner, számlaszám, összeg – „a NAV-ban nem látjuk, kérjük, egyeztessen a kiállítóval”;
   → záró mondat: „A dokumentumokat a Zeuss Dokumentumok felületén ({upload_targets.page}) a fenti mappákba kérjük feltölteni, legkésőbb {határidő}-ig.” → köszönet → aláírás.
   **Tilos:** „küldje el e-mailben”, „válaszoljon erre a levélre a csatolmánnyal”, „csatolja” – anyagot e-mailben soha nem kérünk. Kérdésre (pl. „volt-e mozgás a számlán”, „céges költség-e”) válaszolhat e-mailben, de a dokumentumot akkor is a Zeussba töltse fel.
   Határidő: egységesen a hónap ÁFA-/zárási határideje előtti munkanap, vagy amit a felhasználó mond; minden levélben ugyanaz a formátum (ÉÉÉÉ.HH.NN.).
   Ügyfélnek nincs belső zsargon (párosítás, főkönyvi szám, OCR, import).
3. `zeuss_save_email_draft`: `reason_codes` (`missing_invoice_file`, `missing_bank_statement`, `unmatched_invoice_file`, `faulty_upload`, `clarification`), `agent_note` a könyvelőnek (a csak neki szóló tételek, és mit hagytál ki szándékosan).

## 7. Kiküldés a Zeuss levelezőjével (email_jobs)
- A tervezetet a könyvelő a **Claude agent → Ügyféllevelek** oldalon (`/app/agent_api/collection_letters.php`, minden cég egy helyen) a **„Küldés a Zeuss levelezőjével”** gombbal teszi az `email_jobs` sorba – ez az alapút, ütemezett vagy agentből indított futásnál mindig ez.
- A chatből (csak főszálból, a felhasználóval szemtől szemben, ha a környezetben van `zeuss_queue_email_draft`):
  1. `zeuss_queue_email_draft` `confirm_code` nélkül → előnézet (feladó, címzett, másolat, tárgy, teljes szöveg);
  2. mutasd meg a felhasználónak szó szerint;
  3. csak a kifejezett „küldd el” / „mehet” válaszára hívd újra ugyanazzal a `draft_id`-vel és a `confirm_code`-dal.
  Subagent soha nem küld. Ha az eszköz nem érhető el (a felhasználó Zeuss-jogosultsága nem engedi a küldést), mondd meg, és add meg a tervezet linkjét.

## 7/b. Eredmény a Havi irányítópultra (minden cégnél, minden futásban)
Cégenként a végén `zeuss_save_collection_result` (`month`, `missing_count`, `breakdown`, `draft_id`, rövid `note`) – ez adja a Varázsló → Havi irányítópult „Könyvelési anyagok” oszlopát:
- `missing_count` = az ügyféltől még hiányzó / hibás tételek száma: kép nélküli számlák + hiányzó kivonatok + hibás / újra feltöltendő fájlok + végszámla nélküli díjbekérők + tisztázandó tételek (a levél tételei). A csak könyvelőnek szóló teendő (csatolandó NAV-számla, külföldi számla rögzítése, duplikátum) **nem** hiány.
- `breakdown`: `missing_invoice_files`, `missing_bank_statements`, `faulty_uploads`, `proformas_without_final`, `clarifications`.
- `missing_count = 0` (zöld pipa) csak akkor menthető, ha minden kivonatköteles főkönyvi bankszámlához hozzárendelted a hónap PDF kivonatát (`zeuss_save_bank_statement_link`, `kind: statement`) – különben a Zeuss visszadobja. Ez után futtatható a `zeuss-anyagbetolto` agent (kivonatok betöltése, külföldi számlák rögzítése).
- „Teljes havi kör” része, ütemezett futás, csak helyzetkép – mindig mentsd.

## 8. Összefoglaló
Cégenként egy blokk:
- **Cég / hónap**
- **Számlák**: bejövő N / kép nélkül M · kimenő N / kép nélkül M
- **Számlaképek**: párosított N (rendben) · nem párosított M → ebből NAV-ra vár x, külföldi y, díjbekérő z, hibás w, NAV-ban nincs v, csatolandó u
- **Bank**: szükséges kivonat N főkönyvi bankszámlára · megvan K · hiányzik: tételesen (bank, pénznem, főkönyvi szám)
- **Ügyféllevél**: tervezet #id (mi van benne) / sorba állítva #email_job / nem kellett
- **Könyvelőnek**: legfeljebb 5 teendő, hol a Zeussban
Több cégnél elöl egy rövid táblázat: cég · kép nélküli számla (be/ki) · hiányzó kivonat · ügyfélnek szóló tétel · levél állapota.

## 9. Ütemezett (felügyelet nélküli) futás
Ha ütemezett feladatként futsz (a feladat szövege ezt mondja), senki nem ül a gépnél:
1. `zeuss_list_companies` → **minden** elérhető cég. A hónap az előző naptári hónap, hacsak a feladat mást nem mond.
2. Cégenként: `zeuss_start_run` **`task: scheduled_document_collection`** (ettől lesz a levél csak a felületről kiküldhető), majd az 1–6. lépés. Levéltervezetet mentesz, ha van ügyfélnek szóló tétel (ilyenkor nincs „teljes havi kör” kivétel). `zeuss_save_collection_result` (7/b), `zeuss_finish_run`.
3. **Soha nem hívsz `zeuss_queue_email_draft`-et**, és semmilyen `zeuss_accept_*` eszközt. Kérdést nem teszel fel – ami bizonytalan, az a tervezet `agent_note`-jába és az összefoglalóba kerül.
4. Egy cég hibája ne állítsa meg a többit: jegyezd fel, és menj tovább.
5. A végén **egyszer** `zeuss_collection_done`: `month`, `companies_checked`, `draft_ids` (az összes mentett tervezet), `summary_markdown` (táblázat: cég · hiányzó kivonat · ügyfélnek szóló tétel · tervezet id; alatta a könyvelőnek szóló teendők és a hibás cégek). Ez értesíti a könyvelőt, hogy a levelek a **Claude agent → Ügyféllevelek** oldalon jóváhagyásra várnak.
6. A záró üzeneted ugyanez röviden.

