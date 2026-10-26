---
name: "zeuss-anyagbetoltes"
description: "Hiánytalan havi könyvelési anyag betöltése a Zeussba: bankszámlakivonatok tételei a megfelelő főkönyvi bankszámlára (PDF a Bank PDF átalakító parserével, vagy tranzakciós CSV), külföldi (NAV-ban nem szereplő) számlák rögzítése a számlaképből, majd ellenőrzés – kivonat nyitó / záró ↔ főkönyvi bankszámla nyitó / záró (Banknyilvántartás), külföldi számlák ↔ számlakép, MNB-árfolyam, közösségi adószám. Csak sikeres ellenőrzés után ír, jóváhagyást nem kér."
---

# Anyagbetöltés – kivonatok és külföldi számlák a könyvelésbe (Zeuss)

Akkor használd, ha a felhasználó azt kéri, hogy a beérkezett havi anyagot töltsd be: bankszámlakivonatok a főkönyvbe, külföldi számlák rögzítése, utána bankegyeztetés. A `zeuss-anyagbekeres` utáni lépés: **csak az a hónap tölthető be, amelyre az anyagbekérő zöld pipát adott** (`missing_count = 0`), ezt a Zeuss is ellenőrzi.
Eszközök: a `zeuss` MCP szerver `zeuss_*` eszközei. Közös elvek: `${CLAUDE_PLUGIN_ROOT}/skills/zeuss-iroda/references/alapelvek.md` – ez a skill az ott leírt „nem könyvelünk” elv **kifejezett kivétele**: a felhasználó döntése szerint a betöltéshez nem kell jóváhagyás, a kapu a Zeuss beépített ellenőrzése.

## Alapszabály: ellenőrzés nélkül semmi nem kerül be
- `zeuss_load_bank_statement` és `zeuss_create_foreign_invoice` **csak akkor ír, ha minden ellenőrzés `ok`**; különben semmi nem változik, és a `checks` listában ott a hiba oka.
- Ha egy ellenőrzés nem megy át: **nem kerülöd meg**. Nem írsz át egyenleget, időszakot, összeget azért, hogy egyezzen a főkönyvvel; nem töltesz be „részben”. Bemenetet csak akkor adsz meg vagy javítasz, ha az valóban hiányzott vagy a parser félreolvasta – és azt a kivonat / számla képén saját szemeddel ellenőrizted (`zeuss_get_document`).
- A hibát tételesen leírod a könyvelőnek (mi nem egyezik, mennyivel, hol kell rendbe tenni). A Havi irányítópulton ez piros X.
- `zeuss_accept_*`, `zeuss_queue_email_draft` – soha.

## 0. Cég, hónap, futás
- Cég: amit a felhasználó mond; ha semmi, `zeuss_list_companies` és mind, cégenként külön (párhuzamosítható). Hónap: amit mond, alapból az előző naptári hónap – mondd ki.
- Cégenként `zeuss_start_run` (`task: material_loading`), a végén `zeuss_finish_run` darabszámokkal.

## 1. Helyzetkép
`zeuss_processing_status` (`company_id`, `month`):
- `can_load = false` → **állj meg ennél a cégnél**: az anyag még nem hiánytalan (vagy az anyagbekérő még nem futott). Írd meg, és javasold a `zeuss-anyagbekero` futtatását.
- `bank_ledgers` – kivonatköteles főkönyvi bankszámlánként a hozzárendelt PDF kivonat(ok) (`statement_files`), tranzakciós listák (`transaction_list_files`), a korábbi betöltések (`loads`) és az állapot (`todo` / `done` / `failed`).
- `foreign_invoice_documents` – a külföldinek kiolvasott számlaképek (`todo` / `recorded` / `failed`).

## 2. Bankszámlakivonatok (főkönyvi bankszámlánként; több kivonatnál időrendben)
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
1. `zeuss_bank_reconciliation` (`month`) – minden kivonatköteles bankszámlán `ok` kell: a kivonat nyitója és zárója = a főkönyvi bankszámla nyitója és zárója a Banknyilvántartás szerint.
2. `zeuss_processing_finish` (`month`, rövid `note`) – a Zeuss maga dönti el az eredményt (ok → zöld pipa a Varázsló → Havi irányítópult „Anyagok betöltése” oszlopában; failed → X a problémák listájával). Akkor is hívd, ha valami nem sikerült – így látszik a könyvelőnek.
3. `zeuss_finish_run`.

## 5. Összefoglaló
Cégenként:
- **Cég / hónap** – `ok` vagy `failed`
- **Bank**: főkönyvi bankszámlánként egy sor – kivonat (fájlnév), tétel db, nyitó → záró, betöltve / már bent volt / nem sikerült (miért)
- **Külföldi számlák**: rögzítve (számlaszám, partner, bruttó, pénznem, árfolyam) / kihagyva (miért)
- **Egyeztetés**: bankszámlánként ok / eltérés összeggel
- **Könyvelőnek**: legfeljebb 5 teendő, hol a Zeussban (Banktételek, Banknyilvántartás, Dokumentumok)
Több cégnél elöl táblázat: cég · bankszámlák (ok / összes) · külföldi számlák (rögzítve / összes) · eredmény.

## 6. Ütemezett (felügyelet nélküli) futás
Senki nem ül a gépnél: kérdést nem teszel fel; ami bizonytalan, azt nem töltöd be, hanem a `zeuss_processing_finish` `note`-jába és az összefoglalóba írod. Egy cég hibája nem állítja meg a többit.
