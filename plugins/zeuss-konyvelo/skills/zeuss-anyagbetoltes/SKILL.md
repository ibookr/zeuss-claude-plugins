---
name: "zeuss-anyagbetoltes"
description: "A beérkezett havi könyvelési anyag betöltése a Zeussba bankonként (ami megjött, az most, a többi a következő futáskor, duplikálás nélkül): bankszámlakivonatok tételei a megfelelő főkönyvi bankszámlára (PDF a Bank PDF átalakító parserével, vagy tranzakciós CSV), külföldi (NAV-ban nem szereplő) számlák rögzítése a számlaképből, majd ellenőrzés – kivonat nyitó / záró ↔ főkönyvi bankszámla nyitó / záró (Banknyilvántartás), külföldi számlák ↔ számlakép, MNB-árfolyam, közösségi adószám. Csak sikeres ellenőrzés után ír, jóváhagyást nem kér."
---

# Anyagbetöltés – kivonatok és külföldi számlák a könyvelésbe (Zeuss)

Akkor használd, ha a felhasználó azt kéri, hogy a beérkezett havi anyagot töltsd be: bankszámlakivonatok a főkönyvbe, külföldi számlák rögzítése, utána bankegyeztetés. A `zeuss-anyagbekeres` utáni lépés, de **nem vár a hónap zöld pipájára**: bankonként azt tölti be, ami már megjött. Egy kivonat akkor tölthető, ha az anyagbekérő az adott főkönyvi bankszámlához rendelte; külföldi számla akkor, ha az anyagbekérő már futott a hónapra – ezt a Zeuss is ellenőrzi. Ha 8 bankból 2 kivonata hiányzik, a 6-ot most betöltöd, a 2-t egy későbbi futás – a már betöltött 6-hoz nem nyúl (a Zeuss `already_loaded`-ként csak ellenőrzi, eltérő meglévő tételnél megáll).
Eszközök: a `zeuss` MCP szerver `zeuss_*` eszközei. Közös elvek: `${CLAUDE_PLUGIN_ROOT}/skills/zeuss-iroda/references/alapelvek.md` – ez a skill az ott leírt „nem könyvelünk” elv **kifejezett kivétele**: a felhasználó döntése szerint a betöltéshez nem kell jóváhagyás, a kapu a Zeuss beépített ellenőrzése.

## Alapszabály: ellenőrzés nélkül semmi nem kerül be
- `zeuss_load_bank_statement` és `zeuss_create_foreign_invoice` **csak akkor ír, ha minden ellenőrzés `ok`**; különben semmi nem változik, és a `checks` listában ott a hiba oka.
- Ha egy ellenőrzés nem megy át: **nem kerülöd meg**. Nem írsz át egyenleget, időszakot, összeget azért, hogy egyezzen a főkönyvvel; egy kivonatból nem töltesz be csak néhány tételt. Bemenetet csak akkor adsz meg vagy javítasz, ha az valóban hiányzott vagy a parser félreolvasta – és azt a kivonat / számla képén saját szemeddel ellenőrizted (`zeuss_get_document`).
- A hibát tételesen leírod a könyvelőnek (mi nem egyezik, mennyivel, hol kell rendbe tenni). A Havi irányítópulton ez piros X. A még hiányzó anyag nem hiba: az sárga „részben” állapot.
- `zeuss_accept_*`, `zeuss_queue_email_draft` – soha.

## 0. Cég, hónap, futás
- Cég: amit a felhasználó mond; ha semmi, `zeuss_list_companies` és mind, cégenként külön (párhuzamosítható). Hónap: amit mond, alapból az előző naptári hónap – mondd ki.
- Cégenként `zeuss_start_run` (`task: material_loading`), a végén `zeuss_finish_run` darabszámokkal.

## 1. Helyzetkép
`zeuss_processing_status` (`company_id`, `month`):
- `collection.checked = false` → **állj meg ennél a cégnél**: az anyagbekérő még nem futott (ő rendeli a kivonatokat a bankszámlákhoz). Javasold a `zeuss-anyagbekero` futtatását.
- `can_load = false`, de az anyagbekérő futott → most nincs új betölthető anyag; a 2–3. lépés kimarad, de a 4. lépést (lezárás) akkor is futtasd, hogy az irányítópult friss legyen.
- `bank_ledgers` – kivonatköteles főkönyvi bankszámlánként a hozzárendelt PDF kivonat(ok) (`statement_files`), tranzakciós listák (`transaction_list_files`), a korábbi betöltések (`loads`), a még betöltendő kivonatok (`pending_statement_file_ids`), a hónap le nem fedett napjai (`coverage_gaps`) és az állapot:
  - `ready` → a `pending_statement_file_ids` kivonatait töltsd be (2. lépés);
  - `done` → kész, **ne nyúlj hozzá**;
  - `partial` → a betöltött rész rendben, a hónap többi kivonata még nem jött meg – nincs teendő, a levél / következő futás dolga;
  - `waiting` → nincs hozzárendelt kivonat – nincs teendő;
  - `failed` → egy korábbi betöltés ellenőrzése elbukott; csak akkor próbáld újra, ha a hiba oka azóta megszűnhetett (pl. betöltöttük az előző időszakot), különben könyvelőnek szóló hiba.
- `foreign_invoice_documents` – a külföldinek kiolvasott számlaképek (`todo` / `recorded` / `failed`); csak a `todo`-val foglalkozol.
- `summary` – darabszámok (bankok és külföldi számlák állapot szerint).

## 2. Bankszámlakivonatok (csak a `ready` bankszámlák `pending_statement_file_ids` kivonatai; több kivonatnál időrendben)
A `done` / `partial` / `waiting` bankszámlához nem nyúlsz. Ha egy bankszámla elbukik, a többit ettől függetlenül betöltöd.
1. `zeuss_bank_file_preview` a PDF-re: felismerte-e a parser (`statements`: számlaszám, pénznem, tételszám, összeg), olvasható-e a nyitó / záró egyenleg (`balance_candidates`), mi az időszak.
2. Bemenetek:
   - **Egyenleg**: ha a jelöltekből nem egyértelmű (üres, vagy több van és egyik pár sem egyezik a tételekkel), nyisd meg a kivonatot (`zeuss_get_document` a `document_id`-val), és add meg az `opening_balance` / `closing_balance`-t pontosan úgy, ahogy a kivonaton áll (előjel: tartozás / folyószámlahitel negatív).
   - **Több alszámla egy PDF-ben**: `account_number` – amelyik ehhez a főkönyvi bankszámlához tartozik (pénznem, számlaszám).
   - **Időszak**: ha a fejlécből nem derül ki és nem a teljes hónap, `period_from` / `period_to` a kivonatról.
   - **A parser nem ismeri a PDF-et** (`parse_error`): ha van `transaction_list_files` CSV, `zeuss_bank_file_preview` a CSV-re → `csv_file_comment_id` + `csv_mapping` (a javasolt hozzárendelés, ha jó) + `csv_start_row`; az egyenleg ilyenkor is a PDF-ről jön. Más fájltípusra nincs megoldás: jelezd a könyvelőnek.
3. `zeuss_bank_statement_check` – próba, semmi nem marad bent. Nézd végig a `checks`-et:
   - `statement_consistent` (nyitó + tételek = záró) hibája → hiányzó / félreolvasott tétel vagy rossz egyenleg: nézd meg a képet; ha a kép szerint a bemenet jó, ez könyvelőnek szóló hiba.
   - `ledger_opening` hibája → a főkönyvi bankszámla nyitója az időszak elején nem egyezik a kivonattal: hiányzik az előző hónap (vagy a nyitó tétel), vagy kézi tétel került be. Könyvelőnek szóló hiba, nem töltöd be.
   - `not_loaded_yet` hibája → az időszakban már van eltérő tétel a bankszámlán (részleges / kézi import) – könyvelőnek szóló hiba.
   - `ledger_currency` / `account_consistent` / `collection_link` → valószínűleg rossz főkönyvi bankszámla; nézd meg a `zeuss_processing_status` többi bankszámláját, és ha a kivonat egyértelműen egy másikhoz tartozik, azzal próbáld; különben könyvelőnek szóló hiba.
4. Ha a próba `status = would_load` (vagy `already_loaded`): `zeuss_load_bank_statement` **ugyanazokkal a paraméterekkel**. Devizás számlánál nézd meg az `fx.items_without_huf`-ot (hiányzó MNB-árfolyam → könyvelőnek).
5. `status = failed` → nem töltesz be; a hibás ellenőrzések üzenete megy a könyvelőnek.

## 3. Külföldi számlák
`zeuss_list_foreign_invoices` (`month`) – `todo` és `failed` dokumentumonként:
1. Ha a kiolvasott adat (`extracted`) hiányos, nyisd meg a képet (`zeuss_get_document`), és mentsd az olvasatot: `zeuss_save_document_extraction` (`document_type: foreign_invoice`, a képen látott mezők).
2. **Mindig bejövő (költség) számla.** Nem rögzítesz, csak jelzed a könyvelőnek, ha:
   - az eladó magyar vagy magyar adószámos (akkor a NAV-ban kell lennie);
   - a számlán külföldi ÁFA van (pl. 20% osztrák ÁFA) – ez kézi rögzítés;
   - díjbekérő / proforma, nem számla;
   - nem tudod egyértelműen eldönteni az ÁFA-kódot.
3. Partner: `zeuss_list_partners` (`search` a névre / adószámra) → ha megvan, `partner_id`; különben `partner` = `name`, `country_code`, `vat_number` (EU-s eladónál a számlán szereplő közösségi adószám, pl. `IE6388047V`), cím.
4. Tételek: a számla tételei nettó egységárral a számla pénznemében; `tax_rate: 0`; `tax_code` a `vat_codes` közül – EU-s szolgáltatásnál a fordított adózású / közösségi szolgáltatás kódja, harmadik országnál a harmadik országbeli szolgáltatásé, termékbeszerzésnél a közösségi termékbeszerzésé (a leírás alapján). Ha a tételsor bonyolult, egy összesítő tétel a számla nettó összegével is jó.
5. `zeuss_create_foreign_invoice` `dry_run: true` → nézd a `checks`-et; ha minden `ok`, ugyanaz `dry_run` nélkül. Az árfolyamot a Zeuss adja (MNB, a teljesítés napjára, ha arra nincs, az előtte utolsó) – nem adsz meg árfolyamot.
6. A rögzítés után az `invoice_check` a rögzített számla ellenőrzése; `payment` hiánya csak figyelmeztetés (kártyás / gyűjtött terhelés), az a Bank párosítás lépés dolga.

## 4. Ellenőrzés és lezárás
1. `zeuss_bank_reconciliation` (`month`) – bankszámlánként: `ok` = a kivonatok lefedik a hónapot, és nyitójuk / zárójuk = a főkönyvi bankszámla nyitója / zárója a Banknyilvántartás szerint; `partial` = a betöltött rész egyezik, de a hónapból még hiányzik kivonat (`coverage_gaps`); `no_statement` = még nincs kivonat; `mismatch` = eltérés (könyvelőnek).
2. `zeuss_processing_finish` (`month`, rövid `note`) – **minden futás végén**, a hiányos hónapnál is. A Zeuss maga dönti el az eredményt a Varázsló → Havi irányítópult „Anyagok betöltése” oszlopába: `ok` → zöld pipa (minden bank kész, minden külföldi számla rögzítve); `partial` → sárga „6/8 bank” (ami megjött, rendben bent van, a többi anyagra vár – `waiting` lista); `waiting` → még semmi nem volt tölthető; `failed` → piros X a `problems` listával.
3. `zeuss_finish_run`.

## 5. Összefoglaló
Cégenként:
- **Cég / hónap** – `ok` / `partial` / `waiting` / `failed`, a `counts` szerint (pl. bank 6/8, külföldi 3/4)
- **Bank**: főkönyvi bankszámlánként egy sor – kivonat (fájlnév), tétel db, nyitó → záró, most betöltve / korábban már kész / anyagra vár (melyik időszak) / nem sikerült (miért)
- **Külföldi számlák**: rögzítve (számlaszám, partner, bruttó, pénznem, árfolyam) / kihagyva (miért)
- **Egyeztetés**: bankszámlánként ok / eltérés összeggel
- **Könyvelőnek**: legfeljebb 5 teendő, hol a Zeussban (Banktételek, Banknyilvántartás, Dokumentumok)
Több cégnél elöl táblázat: cég · bankszámlák (kész / összes) · külföldi számlák (rögzítve / összes) · most betöltve · eredmény.

## 6. Ütemezett (felügyelet nélküli) futás
Senki nem ül a gépnél: kérdést nem teszel fel; ami bizonytalan, azt nem töltöd be, hanem a `zeuss_processing_finish` `note`-jába és az összefoglalóba írod. Egy cég hibája nem állítja meg a többit.
