---
name: "zeuss-anyagbetoltes"
description: "A beérkezett havi könyvelési anyag betöltése a Zeussba bankonként (ami megjött, az most, a többi a következő futáskor, duplikálás nélkül): bankszámlakivonatok tételei a megfelelő főkönyvi bankszámlára – a PDF kivonat mindig kell; a tételek a kivonat melletti tranzakciós adatforrásból (CSV / XLS / XLSX / XML fájl, Számlázz.hu banki szinkron) vagy a PDF-ből (Bank PDF átalakító), külföldi (NAV-ban nem szereplő) számlák rögzítése a számlaképből, majd ellenőrzés mindig a kivonat alapján – kivonat nyitó / záró ↔ főkönyvi bankszámla nyitó / záró (főkönyv), külföldi számlák ↔ számlakép, MNB-árfolyam, közösségi adószám. Csak sikeres ellenőrzés után ír, jóváhagyást nem kér."
---

# Anyagbetöltés – kivonatok és külföldi számlák a könyvelésbe (Zeuss)

Akkor használd, ha a felhasználó azt kéri, hogy a beérkezett havi anyagot töltsd be: bankszámlakivonatok a főkönyvbe, külföldi számlák rögzítése, utána bankegyeztetés. **Nem vár az anyagbekérőre és nem kötődik egy hónaphoz**: az anyagbekérő az előző hónapra fut (5., 7., 10.), az adatbetöltő viszont minden friss anyagot betölt, bármelyik hónap mappájába került – bankonként azt, ami már megjött. Egy kivonat akkor tölthető, ha egy főkönyvi bankszámlához van rendelve: ezt az anyagbekérő vagy te magad (`zeuss_save_bank_statement_link`) teszed meg. Ha 8 bankból 2 kivonata hiányzik, a 6-ot most betöltöd, a 2-t egy későbbi futás – a már betöltött 6-hoz nem nyúl (a Zeuss `already_loaded`-ként csak ellenőrzi, eltérő meglévő tételnél megáll).
Eszközök: a `zeuss` MCP szerver `zeuss_*` eszközei. Közös elvek: `${CLAUDE_PLUGIN_ROOT}/skills/zeuss-iroda/references/alapelvek.md` – ez a skill az ott leírt „nem könyvelünk” elv **kifejezett kivétele**: a felhasználó döntése szerint a betöltéshez nem kell jóváhagyás, a kapu a Zeuss beépített ellenőrzése.

## Alapszabály: kivonat nélkül és ellenőrzés nélkül semmi nem kerül be
- **Bankszámlakivonat (PDF) nélkül nincs banktétel-import.** Tranzakciós fájl (CSV / XLS / XLSX / XML) vagy a Számlázz.hu banki szinkron egymagában soha nem tölthető be – a Zeuss sem engedi (a `file_comment_id` mindig a PDF kivonat).
- Ha a kivonat mellett van tranzakciós adatforrás, a tételeket abból is veheted (nem kell a PDF-ből kiolvasni), de **az ellenőrzés akkor is a kivonat alapján megy**: nyitó / záró egyenleg a PDF-ről, nyitó + tételek = záró, főkönyvi nyitó / záró = kivonat, és ha a parser a PDF tételeit is felismerte, az adatforrás tételszáma és összege egyezzen velük.
- `zeuss_load_bank_statement` és `zeuss_create_foreign_invoice` **csak akkor ír, ha minden ellenőrzés `ok`**; különben semmi nem változik, és a `checks` listában ott a hiba oka.
- Ha egy ellenőrzés nem megy át: **nem kerülöd meg**. Nem írsz át egyenleget, időszakot, összeget azért, hogy egyezzen a főkönyvvel; egy kivonatból nem töltesz be csak néhány tételt. Bemenetet csak akkor adsz meg vagy javítasz, ha az valóban hiányzott vagy a parser félreolvasta – és azt a kivonat / számla képén saját szemeddel ellenőrizted (`zeuss_get_document`).
- A hibát tételesen leírod a könyvelőnek (mi nem egyezik, mennyivel, hol kell rendbe tenni). A Havi irányítópulton ez piros X. A még hiányzó anyag nem hiba: az sárga „részben” állapot.
- `zeuss_accept_*`, `zeuss_queue_email_draft` – soha.

## 0. Cég, hónap, futás
- Ha a felhasználó céget és hónapot mond, azt csinálod. Egyébként **`zeuss_processing_queue`** (alap `days: 31`): cégenként és hónaponként (a feltöltés hónap-mappája szerint, bármelyik hónap) a friss, még fel nem dolgozott anyag – `bank_statements`, `foreign_invoices`, `images_to_classify`, `chat_answered`. **Csak a listában szereplő cég–hónap párokon dolgozol**, cégenként külön (párhuzamosítható); egy cégnél több hónap is lehet – időrendben haladj (a régebbi hónap kivonata kell a következő nyitó egyenlegéhez). Ha a queue eszköz nincs (régebbi Zeuss): cégenként az előző és a folyó hónap.
- Ha a felhasználó csak céget mond, hónapot nem: a queue sorai közül az ő cégéé; ha nincs ott, az előző naptári hónap – mondd ki.
- Cégenként `zeuss_start_run` (`task: material_loading`), a végén `zeuss_finish_run` darabszámokkal.

## 1. Helyzetkép
`zeuss_processing_status` (`company_id`, `month`):
- `collection` – csak tájékoztató (futott-e már az anyagbekérő a hónapra); **nem feltétel**, ha `checked = false`, attól még tölthetsz.
- `unlinked_bank_files` – a hónap banki fájljai (PDF kivonat, CSV / XLS / XLSX / XML tranzakciós lista), amelyeket még senki nem rendelt főkönyvi bankszámlához. **Te rendeled hozzá**, mielőtt betöltenél (lásd lent: „Kivonat hozzárendelése”).
- `can_load = false` → most nincs új betölthető vagy hozzárendelendő anyag; a 2–3. lépés kimarad, de a 4. lépést (lezárás) akkor is futtasd, hogy az irányítópult friss legyen.
- `bank_ledgers` – kivonatköteles főkönyvi bankszámlánként a hozzárendelt PDF kivonat(ok) (`statement_files`), tranzakciós adatfájlok (`transaction_list_files`: CSV / XLS / XLSX / XML), a Számlázz.hu banki szinkron tételei a hónapra (`szamlazzhu_sync`: számlaszám, tétel db, összeg, első / utolsó nap – a kivonat / korábbi betöltés számlaszáma alapján), a korábbi betöltések (`loads`, `transactions_source`-szal), a még betöltendő kivonatok (`pending_statement_file_ids`), a hónap le nem fedett napjai (`coverage_gaps`) és az állapot:
  - `ready` → a `pending_statement_file_ids` kivonatait töltsd be (2. lépés);
  - `done` → kész, **ne nyúlj hozzá**;
  - `partial` → a betöltött rész rendben, a hónap többi kivonata még nem jött meg – nincs teendő, a levél / következő futás dolga;
  - `waiting` → nincs hozzárendelt kivonat – nincs teendő;
  - `failed` → egy korábbi betöltés ellenőrzése elbukott; csak akkor próbáld újra, ha a hiba oka azóta megszűnhetett (pl. betöltöttük az előző időszakot), különben könyvelőnek szóló hiba.
- `szamlazzhu_accounts` – a cég összes Számlázz.hu-n szinkronizált számlája a hónapra; amelyiknél `ledger_number_id = null`, azt még egyik kivonat számlaszáma sem kötötte bankszámlához (ha a kivonat számlaszáma más alakú, `szamlazzhu_account`-tal megadhatod).
- `foreign_invoice_documents` – a külföldinek kiolvasott számlaképek (`todo` / `recorded` / `failed`); csak a `todo`-val foglalkozol.
- `summary` – darabszámok (bankok és külföldi számlák állapot szerint).
- `ai_notes` – **a könyvelő megjegyzései ennél a cégnél** (lásd lent: „A könyvelő megjegyzései”).
- `chat` – **a könyvelő válaszai a korábbi kérdéseidre** (`chat.answered`) és a még nyitott kérdéseid száma (`chat.open_count`) – lásd lent: „MI chat”. A megválaszolt szálakat **a 2–3. lépés előtt** dolgozd fel.

## A könyvelő megjegyzései (`ai_notes`)
A `zeuss_processing_status` → `ai_notes.items`: a könyvelő ennél a cégnél **ma érvényes** utasításai az adatbetöltőnek (Zeuss: MI asszisztens → Megjegyzések az MI-nek) – fix (a törlésig) vagy időszakos (`valid_from`–`valid_to`). Minden futásban olvasd el, és mindegyiket alkalmazd a 2–3. lépésben:
- **Tételforrás / bemenet** (pl. „a K&H kivonat tételeit mindig a CSV-ből töltsd”, „a Wise kivonat számlaszáma: …”) → azt használod; ha azzal az ellenőrzés elbukik, nem váltasz csendben forrást, hanem jelzed.
- **Kihagyás** (pl. „a Revolut kivonatot a könyvelő tölti be kézzel”, „ezt a külföldi számlát ne rögzítsd”) → nem töltöd be, és a `zeuss_processing_finish` `note`-jába és az összefoglalóba írod: „a könyvelő megjegyzése szerint kihagyva: …”.
- **Partner / ÁFA-kód / egyéb rögzítési tudnivaló** külföldi számlához → aszerint töltöd ki (a dry run ellenőrzése ugyanúgy kell).
- **Nem írja felül** az alapszabályt: kivonat és hibátlan ellenőrzés nélkül semmi nem kerül be; egyenleget, időszakot, összeget a megjegyzés kedvéért sem igazítasz; részleges betöltés nincs; `zeuss_accept_*` / `zeuss_queue_email_draft` soha. Ha egy megjegyzés ilyet kér, nem érthető, vagy ellentmond a kivonatnak, nem alkalmazod, és jelzed a könyvelőnek.
- Ha nincs `ai_notes` blokk (régebbi Zeuss), `zeuss_ai_notes` (`agent: anyagbetolto`) – ha az sincs, folytasd megjegyzések nélkül.

## MI chat – kérdés a cég könyvelőjének, és a válasz feldolgozása
Futás közben senkit nem kérdezel meg közvetlenül. Ami a te döntésed szerint bizonytalan, abból **kérdést teszel fel a cég könyvelőjének** a Zeuss MI chatjében (MI asszisztens → MI chat). A könyvelő választ egy opciót és / vagy megjegyzést ír, a következő futásod pedig ez alapján folytatja. **Az ügyfélnek innen semmi nem megy** – ügyfélnek szóló hiányt (pl. hiányzó kivonatoldal) nem itt, hanem az anyagbekérő levelében kell kérni; ezt legfeljebb a könyvelőnek jelzed.

**Kérdés feltevése** – `zeuss_chat_post`:
- `agent: anyagbetolto`, `period_month`, rövid `title` (cég nélkül, pl. „Google Ireland 2026-10 számla – ÁFA-kód?”), `body`: mit találtál (partner, összeg, pénznem, dátum, mi nem egyezik), és mi a kérdés.
- `suggestion`: amit tennél, ha a könyvelő jóváhagyja – konkrétan (pl. „rögzítés bejövőként: partner Google Ireland Ltd (IE6388047V), 5xx, ÁFA-kód: közösségi szolgáltatás fordított adózással, nettó 120,00 EUR, MNB 2026-10-31”).
- `topic_key` **kötelezően**, hogy ne kérdezz kétszer: `foreign_invoice:<file_comment_id>`, `bank_statement:<file_comment_id>`, `bank_ledger:<ledger_number_id>:<ÉÉÉÉ-HH>`. Ha a válasz `unchanged`, nem tettél fel újat; ha `updated`, a meglévő szálba került az új helyzet.
- `ref_type` / `ref_id` (pl. `file_comment` + id), `options` – csak ha az alapértelmezett („Jó a javaslat, csináld” / „Ezt én intézem”) nem elég (pl. két ÁFA-kód közül választás: két `accept_…` opció). `close: true` csak a „nincs teendőd” jellegű opció.

**Mikor kérdezel** (és nem töltöd be):
- külföldi számla, ami nem „ismert eset” (lásd 3. lépés), vagy ahol a 3.2 pont szerint nem rögzíthetsz;
- a kivonat ellenőrzése elbukik, és a hiba nem anyaghiány (pl. `ledger_opening` eltérés, `not_loaded_yet`, nem egyértelmű bankszámla) – a kérdés: hogyan folytassuk; a javaslatod lehet „a könyvelő rendezi a főkönyvet, utána újra próbálom”;
- egy könyvelői megjegyzés (`ai_notes`) nem érthető, vagy ellentmond a kivonatnak.
A még nyitott kérdést (`open`) **nem kérdezed újra**, és ugyanarra a tételre addig nem csinálsz semmit.

**Válasz feldolgozása** – `chat.answered` szálanként (vagy `zeuss_chat_list` `status: answered`, több cégnél `zeuss_office_chat`):
- A válasz a `messages` vége: `author: user`, `option_key` / `option_label` és / vagy `body` (megjegyzés). **A megjegyzés felülírja a javaslatodat** (pl. „nem 5291, hanem 5211”).
- `accept` (vagy más végrehajtó opció) → végrehajtod a javaslatot **ugyanazokkal az ellenőrzésekkel** (dry run / próba, csak hibátlan ellenőrzés után élesben). A könyvelő jóváhagyása az ellenőrzési kaput nem helyettesíti.
- Ha sikerült → `zeuss_chat_reply` `resolution: close`, `body`: mit csináltál (pl. „Rögzítve: IE-2026-1031 számla, bruttó 120,00 EUR = 47 640 Ft”).
- Ha nem sikerült, vagy a válasz alapján is kérdés maradt → `resolution: ask`, `body`: miért nem, mi kell még (új `suggestion` / `options` adható).
- Ha a válasz tartós szabályt mond (pl. „ennek a partnernek mindig …”), és a könyvelő nem jelölte „Jegyezd meg”-nek, a lezáró üzenetben javasold, hogy vegye fel a Megjegyzések az MI-nek közé – magad nem írsz megjegyzést.
- Ha a hivatkozott tétel közben rendeződött (pl. a könyvelő kézzel rögzítette a számlát), `close` ezzel a szöveggel.

## Kivonat hozzárendelése (`unlinked_bank_files`)
Fájlonként döntsd el, melyik főkönyvi bankszámláé – ugyanúgy, ahogy az anyagbekérő:
1. A jelek: `bank_folder` / `company_bank_account_id` (melyik bank mappájába töltötték), `folder_kind` (Bankszámlakivonatok / Tranzakciós listák), `ocr_excerpt`; ha kell, `zeuss_bank_file_preview` (számlaszám, pénznem, időszak a fájlból) és `zeuss_get_document`.
2. Összevetés a `bank_ledgers` bankszámláival (`ledger_name`, `currency_hint`, a korábbi betöltések számlaszáma a `loads`-ban) és a `zeuss_ledger_accounts` (`bank_only=1`) listával.
3. Egyértelmű (számlaszám vagy bank + pénznem egyezik, egyetlen jelölt) → `zeuss_save_bank_statement_link`: `kind: statement` (PDF kivonat) vagy `transaction_list`, `ledger_number_id`, `account_number`, `currency`, `period_from` / `period_to`, ha látszik, `confidence` ≥ 0,7, rövid `note` (mi alapján). Más cég kivonata → `not_our_statement`; nem banki irat → `not_bank_document` / `other`.
4. **Nem egyértelmű** (több jelölt, nincs illő bankszámla, olvashatatlan) → nem rendeled hozzá (vagy `confidence` 0,5 alatt), és **MI chat-kérdés** a könyvelőnek (`topic_key: bank_file:<file_comment_id>`, javaslattal: melyik bankszámlára tennéd).
5. Utána `zeuss_processing_status` újra – a hozzárendelt kivonat a bankszámla `pending_statement_file_ids`-ébe kerül, és a 2. lépés szerint tölthető.

## Ki nem olvasott számlaképek (`images_to_classify` a queue-ban)
A friss, számlával nem párosított bejövő számlaképekről még nem tudni, külföldiek-e. `zeuss_collection_status` (`month`) → `invoice_files` közül azok, amelyeknek nincs `last_check`-je: `zeuss_get_document`, majd `zeuss_save_document_extraction` (a valós típussal: `foreign_invoice`, `invoice`, `proforma`, `unreadable` …). Csak a `foreign_invoice` megy tovább a 3. lépésbe; a magyar számla a NAV-szinkronra vár, nem a te dolgod (a levelet az anyagbekérő írja).

## 2. Bankszámlakivonatok (csak a `ready` bankszámlák `pending_statement_file_ids` kivonatai; több kivonatnál időrendben)
A `done` / `partial` / `waiting` bankszámlához nem nyúlsz. Ha egy bankszámla elbukik, a többit ettől függetlenül betöltöd. Tranzakciós fájlhoz vagy szinkronhoz, amelyhez nincs hozzárendelt PDF kivonat, nem nyúlsz (`waiting`).
1. `zeuss_bank_file_preview` a PDF-re: felismerte-e a parser (`statements`: számlaszám, pénznem, tételszám, összeg), olvasható-e a nyitó / záró egyenleg (`balance_candidates`), mi az időszak.
   **Tételforrás** – a kivonat egyenlege mindig a PDF-ről jön; a tételek ebben a sorrendben:
   1. a bankszámlához rendelt **tranzakciós adatfájl** (`transaction_list_files`), amelyik a kivonat időszakát fedi: `source_file_comment_id`. Előtte `zeuss_bank_file_preview` a fájlra – CSV / XLS / XLSX: `csv_mapping` (a `suggested_mapping`, ha jó) + `csv_start_row`, Excelnél `sheet`, ha nem az első munkalap; XML (camt.053 / camt.052, Számlázz.hu banktranz): mapping nem kell, több számlánál az `account_number` választ;
   2. a **Számlázz.hu banki szinkron** (`szamlazzhu_sync` van, és a tételszám / időszak illik a kivonathoz): `transactions_source: szamlazzhu` – a kivonat számlaszáma és időszaka szerint szűr (ha a PDF-ből nem derül ki a számlaszám, add meg `account_number`-ként a kivonatról);
   3. ha egyik sincs: a **PDF** tételei (`transactions_source` nélkül).
   Egy kivonathoz egy forrás – nem keversz. Ha egy forrás csak a saját ellenőrzésén bukik el (`source_rows`, `source_account`, `source_currency`, `source_matches_statement`), próbáld a következővel; ha a kivonaton bukik (`statement_consistent`, `ledger_opening`, `ledger_closing` stb.), forrást váltani nem segít – könyvelőnek szóló hiba.
2. Bemenetek:
   - **Egyenleg**: ha a jelöltekből nem egyértelmű (üres, vagy több van és egyik pár sem egyezik a tételekkel), nyisd meg a kivonatot (`zeuss_get_document` a `document_id`-val), és add meg az `opening_balance` / `closing_balance`-t pontosan úgy, ahogy a kivonaton áll (előjel: tartozás / folyószámlahitel negatív).
   - **Több alszámla egy PDF-ben**: `account_number` – amelyik ehhez a főkönyvi bankszámlához tartozik (pénznem, számlaszám).
   - **Időszak**: ha a fejlécből nem derül ki és nem a teljes hónap, `period_from` / `period_to` a kivonatról.
   - **A parser nem ismeri a PDF-et** (`parse_error`): a tételek a fenti adatforrásból jönnek (fájl vagy Számlázz.hu szinkron); az egyenleget ilyenkor a kivonat képéről add meg (`zeuss_get_document` → `opening_balance` / `closing_balance`), és ha kell, az időszakot és a számlaszámot is. Ha nincs adatforrás, nincs betöltés: jelezd a könyvelőnek (tranzakciós fájlt kell feltölteni a kivonat mellé, vagy be kell kapcsolni a Számlázz.hu banki szinkront).
3. `zeuss_bank_statement_check` – próba, semmi nem marad bent. Nézd végig a `checks`-et:
   - `statement_consistent` (nyitó + tételek = záró) hibája → hiányzó / félreolvasott tétel vagy rossz egyenleg: nézd meg a képet; ha a kép szerint a bemenet jó, ez könyvelőnek szóló hiba.
   - `ledger_opening` hibája → a főkönyvi bankszámla nyitója az időszak elején nem egyezik a kivonattal: hiányzik az előző hónap (vagy a nyitó tétel), vagy kézi tétel került be. Könyvelőnek szóló hiba, nem töltöd be.
   - `not_loaded_yet` hibája → az időszakban már van eltérő tétel a bankszámlán (részleges / kézi import) – könyvelőnek szóló hiba.
   - `source_matches_statement` → az adatforrás tételei (db / összeg) eltérnek a PDF kivonat tételeitől: hiányos export, más időszak vagy más számla – próbáld a következő forrást; ha egyik sem egyezik, könyvelőnek szóló hiba.
   - `ledger_currency` / `account_consistent` / `collection_link` → valószínűleg rossz főkönyvi bankszámla; nézd meg a `zeuss_processing_status` többi bankszámláját, és ha a kivonat egyértelműen egy másikhoz tartozik, azzal próbáld; különben könyvelőnek szóló hiba.
4. Ha a próba `status = would_load` (vagy `already_loaded`): `zeuss_load_bank_statement` **ugyanazokkal a paraméterekkel**. Devizás számlánál nézd meg az `fx.items_without_huf`-ot (hiányzó MNB-árfolyam → könyvelőnek).
5. `status = failed` → nem töltesz be; a hibás ellenőrzések üzenete megy a könyvelőnek.

## 3. Külföldi számlák
`zeuss_list_foreign_invoices` (`month`) – `todo` és `failed` dokumentumonként:
0. **Ismert eset – ütemezett futásban csak ezt rögzíted magadtól.** Ismert eset, ha a partner már szerepel a cégnél (`zeuss_list_partners` + `zeuss_partner_history`: korábbi rögzített számla ugyanettől a partnertől), a most választott ÁFA-kód és tételjelleg ugyanaz, mint a korábbiaké, EU-s partnernél a közösségi adószám megvan és egyezik, és a dry run minden ellenőrzése `ok`. Vagy: egy `ai_notes` megjegyzés kifejezetten megmondja, hogyan rögzítsd. **Minden más esetben** (új partner, eltérő ÁFA-kód, olvashatatlan vagy kétes kép) nem rögzítesz, hanem `zeuss_chat_post`-tal kérdezel, a teljes javaslattal (partner, ÁFA-kód, nettó, pénznem, teljesítés). Ha a felhasználó a beszélgetésben maga kéri a rögzítést, a 1–6. pont szerint haladsz.
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
1. `zeuss_bank_reconciliation` (`month`) – bankszámlánként, mindig a kivonatok egyenlegeivel (a tételforrástól függetlenül): `ok` = a kivonatok lefedik a hónapot, és nyitójuk / zárójuk = a főkönyvi bankszámla nyitója / zárója (forintnál főkönyv, devizánál Banknyilvántartás); `partial` = a betöltött rész egyezik, de a hónapból még hiányzik kivonat (`coverage_gaps`); `no_statement` = még nincs kivonat; `mismatch` = eltérés (könyvelőnek).
2. `zeuss_processing_finish` (`month`, rövid `note`) – **minden futás végén**, a hiányos hónapnál is. A Zeuss maga dönti el az eredményt a Varázsló → Havi irányítópult „Anyagok betöltése” oszlopába: `ok` → zöld pipa (minden bank kész, minden külföldi számla rögzítve); `partial` → sárga „6/8 bank” (ami megjött, rendben bent van, a többi anyagra vár – `waiting` lista); `waiting` → még semmi nem volt tölthető; `failed` → piros X a `problems` listával.
3. `zeuss_finish_run`.

## 5. Összefoglaló
Cégenként:
- **Cég / hónap** – `ok` / `partial` / `waiting` / `failed`, a `counts` szerint (pl. bank 6/8, külföldi 3/4)
- **Bank**: főkönyvi bankszámlánként egy sor – kivonat (fájlnév), tételforrás (PDF / tranzakciós fájl neve / Számlázz.hu szinkron), tétel db, nyitó → záró, most betöltve / korábban már kész / anyagra vár (melyik időszak) / nem sikerült (miért)
- **Külföldi számlák**: rögzítve (számlaszám, partner, bruttó, pénznem, árfolyam) / kihagyva (miért)
- **Egyeztetés**: bankszámlánként ok / eltérés összeggel
- **Könyvelőnek**: legfeljebb 5 teendő, hol a Zeussban (Banktételek, Banknyilvántartás, Dokumentumok)
- **Megjegyzések**: hány könyvelői megjegyzést alkalmaztál, mire; amelyiket nem tudtad alkalmazni, miért
- **MI chat**: feldolgozott válaszok (mi lett belőlük) és új kérdések (tárgy) – a könyvelő az MI asszisztens → MI chat oldalon válaszol
Több cégnél elöl táblázat: cég · bankszámlák (kész / összes) · külföldi számlák (rögzítve / összes) · most betöltve · eredmény.

## 6. Ütemezett (felügyelet nélküli, éjszakai) futás
Senki nem ül a gépnél, ezért a beszélgetésben nem kérdezel. Ami bizonytalan, azt nem töltöd be, hanem **MI chat-kérdést** teszel fel a cég könyvelőjének (`zeuss_chat_post`, `topic_key`-jel), és a `zeuss_processing_finish` `note`-jába is beírod. Sorrend:
1. `zeuss_processing_queue` – a munkalista: csak ezeken a cég–hónap párokon dolgozol (`month = null`: csak megválaszolt MI chat-kérdés van, `zeuss_chat_list` `status: answered`). Üres lista → nincs teendő, rövid összefoglaló és vége.
2. Cégenként, hónaponként időrendben: `zeuss_processing_status` (`month`) → a `chat.answered` szálak feldolgozása (végrehajtás + `zeuss_chat_reply`) → kivonatok hozzárendelése (`unlinked_bank_files`) → számlaképek kiolvasása (`images_to_classify`) → 2–3. lépés (külföldi számlából csak az ismert esetet rögzíted) → új kérdések → 4. lépés az adott hónapra.
3. Egy cég hibája nem állítja meg a többit. Az összefoglalóban cégenként: hány választ dolgoztál fel, hány új kérdést tettél fel.
Ha a Zeussban még nincs MI chat (a `chat` blokk hiányzik, vagy a `zeuss_chat_post` `schema_missing` hibát ad), a régi mód szerint: kérdés helyett a `note` és az összefoglaló.
