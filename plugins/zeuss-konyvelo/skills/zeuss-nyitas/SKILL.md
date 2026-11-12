---
name: "zeuss-nyitas"
description: "Nyitás a Zeussban egy cégnél: a nyitott vevő–szállító számlák (egy vagy több fájl) és a nyitó napló importja a cég Nyitas mappájából (uploads/<cég>/Nyitas). A fájl az irányadó: a Zeuss bemásolós sablonja, a Kulcs-Soft analitika / főkönyvi összesítő / főkönyvi kivonat és a többi könyvelőprogram-formátum átalakítás nélkül megy; egyeztetés főkönyvi számonként (31x vevő, 454x szállító: számlák nyitott összege + számla nélküli tételek ↔ nyitó napló egyenleg); a NAV-ból letöltött számla nem írja felül a fájl adatát (árfolyam, előjel, összeg); a főkönyvi számok fordítását név szerint is ellenőrzi; csak hibátlan ellenőrzés után importál. Jóváhagyást nem kér, de ami a könyvelő döntése, azt megkérdezi (MI chat)."
---

# Nyitás – nyitott vevő–szállító számlák + nyitó napló (Zeuss)

Akkor használd, ha a felhasználó egy vagy több cégnél a nyitást kéri. Eszközök: a `zeuss` MCP szerver `zeuss_opening_*` eszközei. Közös elvek: `${CLAUDE_PLUGIN_ROOT}/skills/zeuss-iroda/references/alapelvek.md` – ez a skill az ott leírt „nem könyvelünk” elv **kifejezett kivétele**: a felhasználó döntése szerint a nyitáshoz nem kell jóváhagyás, a kapu a Zeuss beépített ellenőrzése.

## Két alapszabály

**1. Egyezés nélkül semmi nem kerül be.** A Zeuss (`zeuss_opening_import`) csak akkor ír, ha **minden ellenőrzés `ok`**, és főkönyvi számonként a vevő–szállító fájlok nyitott összege egyezik a nyitó napló egyenlegével:
- vevő (31x): Σ(bruttó − rendezett) + számla nélküli tételek = a napló T − K egyenlege;
- szállító (454x): Σ(bruttó − rendezett) + számla nélküli tételek = a napló K − T egyenlege; a jóváíró számla és a túlfizetés negatív.
- Ha nem egyezik: **nem importálsz**, nem igazítod az adatot. Leírod főkönyvi számonként az eltérést, és ha látszik az oka, azt is.

**2. A fájl az irányadó – a NAV nem írhatja felül.** A könyvelő a régi program fordulónapi állapotát tölti fel (pl. az előző évi devizás számla év végén átértékelt árfolyamon áll benne). Ezt változtatás nélkül kell megnyitni:
- **Ne alakítsd át** azt a fájlt, amit a Zeuss közvetlenül olvas (lásd 2. lépés). Az átalakítás a hibák fő forrása: egy korábbi nyitásnál az agent a „számla összege 0, rendezve 72 006” túlfizetés-sort negatív számlává alakította, a Zeuss pedig a NAV-ban azonos számon lévő rendes számlával párosította.
- Soha nem változtatsz összeget, előjelet, árfolyamot, dátumot, sort azért, hogy az egyeztetés kijöjjön. A főkönyvi **szám fordítása** a forrásprogram számlatükréről a Zeusséra (pl. 31100 → 311) megengedett – az nem az adat módosítása (lásd 3. lépés, `account_map`).
- `zeuss_accept_*`, `zeuss_queue_email_draft` – soha.

## 0. Cég, futás
- Cég: amit a felhasználó mond; ha semmi, `zeuss_list_companies`, és azok a cégek, ahol a Nyitas mappában van fájl (`zeuss_opening_status` → `files`). Cégenként külön, egymástól függetlenül (párhuzamosítható).
- Cégenként `zeuss_start_run` (`task: opening_import`), a végén `zeuss_finish_run` darabszámokkal; a `run_id`-t add át a check / import hívásnak.
- Ha van megválaszolt MI chat-kérdésed a cégnél (`zeuss_chat_list`, `agent: nyito`, `status: answered`), azzal kezdd: a könyvelő válasza a hiányzó döntés (lásd 5. lépés).

## 1. Helyzetkép – `zeuss_opening_status`
- `files` – a Nyitas mappa fájljai (`file_comment_id`), a könyvelő vegyesen tölti fel őket: **Nyitás → MI nyitás – fájlok feltöltése**. Ha üres: jelezd, hogy a fájlokat ott kell feltölteni (vagy ha a felhasználó megadja őket, `zeuss_opening_upload_file`-lal feltöltöd – változatlanul).
- `existing_opening_journal` – ha a nyitás évére már van nyitó tétel, a Zeuss csak akkor engedi tovább, ha főkönyvi számonként egyezik a fájllal (`already_loaded`); eltérőnél megáll (nem duplikál). Ilyenkor a könyvelő vonhatja vissza a nyitást: **Nyitás → Nyitás visszavonása** (Admin / Irodavezető) – te nem tudod.
- `formats` – a választható importformátumok (`vevo_szallito` / `nyito_naplo`).

## 2. Formátum – fájlonként `zeuss_opening_file_preview`
A `detected` megmondja, mely importálók olvassák be a fájlt (type + format, tételszám, `open_by_ledger`, számla nélküli tételek száma). Döntsd el fájlonként, hogy **vevő–szállító** vagy **nyitó napló**, és melyik formátum. A gyakori esetek:

**Zeuss bemásolós sablon** (fejléc: Számlaszám, Partner neve, Teljesítés dátuma, Számla összege, Rendezve [, Rendezés dátuma, Adószám, Deviza, Devizaösszeg, Árfolyam]) → `format: zeuss`, **átalakítás nélkül**.
- Az irány a fájlnévből jön (vevő → 311, szállító → 4541); ha a névből nem derül ki, vagy más főkönyvi szám kell: `direction` (311 / 4541) vagy `ledger_code` (pl. 312, 4542).
- Ahol a „Számla összege” 0 vagy üres, és van „Rendezve” összeg: **számla nélküli tétel** (a partner túlfizetése / előlege). A Zeuss nem készít belőle számlát, de az egyeztetésben számol vele (`unbilled_items`). Így van jól – ne csinálj belőle negatív számlát.

**Kulcs-Soft csomag** (a leggyakoribb forrás):
- „Vevő analitika” / „Szállító analitika” XLS, főkönyvi számonként egy fájl → `format: kulcs_analitika_xls`, a fájlok egy specben is mehetnek (`files: {"main": [id1, id2, …]}`). **Nem kell `ledger_code`**: a fájl forrás főkönyvi számát (pl. 45400, 4551) a nyitó napló számfordítása viszi a Zeuss számára (45400 → 4541, 4551 „Külföldi szállítók” → 4542), így a fájl és a napló ugyanarra a számra kerül. A számla nélküli kiegyenlítések (túlfizetés, kártyás fizetés) itt is számla nélküli tételek.
- **Főkönyvi összesítő** (F.szám, megnevezés, Cég, Tartozik, Követel [, Devizanem, Deviza Tartozik / Követel]; a fejléc „Tartozik (HUF)” alakban is jó) → `format: kulcs_fokonyvi_osszesito`. Partnerbontást tartalmaz – ez a jó forrás a nyitó naplóhoz.
- **Főkönyvi kivonat**, ahogy a Kulcs exportálja (Nyitó érték / Halmozott forgalom / Halmozott egyenleg) → `format: kulcs_fokonyvi_kivonat`. A halmozott egyenleget veszi. **Nincs benne partnerbontás** – csak akkor használd, ha nincs összesítő és nincs a könyvelő által előkészített lap, és jelezd, hogy a vevő / szállító nyitó egyenleg partner nélkül megy be.

**Többlapos fájl:** ha a fájlban a nyers export mellett a könyvelő által előkészített lap is van (pl. „Feltöltő file”: Dátum, Főkönyvi szám, Tartozik, Követel, Ellenszámla, Partner neve), **az az irányadó** (`format: zeuss`) – abban vannak a zárási módosításai. A Zeuss a fejléc alapján megtalálja a lapot; a `sheet` paraméterrel megadhatod. Ha a preview a nyers kivonatot is felismeri, azt ilyenkor nem használod, de a visszatérésben megemlíted.

**Többi programformátum** (RLB, TenSoft, Novitax, Relax, Forint-Soft, Infotéka, SMARTBooks): a `detected` szerint; több fájlos formátumnál a `files` térképpel (`{"main": [id], "items": [id], "clients": [id]}`).

**Csak ha egyik importáló sem ismeri fel** (`detected` üres), vagy a felismert formátum nyilvánvalóan hibás eredményt ad: alakítsd át, minden sort **változatlan értékkel** átvéve, és jelezd a visszatérésben, melyik fájlt és hogyan.
- vevő–szállító → a **bemásolós sablon** alakjára (pontosvesszős CSV, UTF-8): `Számlaszám;Partner neve;Teljesítés dátuma;Számla összege;Rendezve;Rendezés dátuma;Adószám;Deviza;Devizaösszeg;Árfolyam;Rendezve deviza`
  - `Számla összege`: a teljes bruttó forintban (jóváíró negatív), **nem** a nyitott összeg; `Rendezve`: a fordulónapig kiegyenlített rész (ha a forrásban csak a nyitott összeg van: bruttó − nyitott);
  - számla nélküli kiegyenlítés (túlfizetés, előleg): `Számla összege` = 0, `Rendezve` = az összeg – **nem negatív számla**;
  - devizás számlánál `Deviza`, `Devizaösszeg`, és az `Árfolyam` a **forrás** árfolyama (a forintérték is a forrásé – ne számold újra).
- nyitó napló (pontosvesszős CSV, UTF-8): `Dátum;Főkönyvi szám;Ellenszámla;Tartozik;Követel;Partner neve;Megjegyzés[;Devizanem;Deviza tartozik;Deviza követel]` – soronként a főkönyvi szám az ellenszámlával szemben (jellemzően 491); a `Megjegyzés` a forrás számla megnevezése (ebből lesz az új főkönyvi szám neve).
- Fájlnév: `<eredeti név>_zeuss.csv` (a vevő / szállító szó maradjon a névben); `zeuss_opening_upload_file`, majd újra `zeuss_opening_file_preview`: a tételszám és az `open_by_ledger` egyezzen a forrással. Az eredeti fájl marad.

## 3. Ellenőrzés – `zeuss_opening_check` (írás nélkül)
Paraméterek: `customer_supplier_files` (egy vagy több `{file_comment_id | files, format, direction?, ledger_code?}`), `journal_file` (`{file_comment_id, format, sheet?, account_map?}`), `opening_date`, szükség szerint `create_missing_accounts`, `account_names`, `journal_partners`, `after_cutoff_invoices`, `accept_journal_imbalance`, `run_id`.

Nézd végig a `checks`-et (mind `ok` kell). Hogy mi a te döntésed és mi a könyvelőé:

| Ellenőrzés | Mit jelent | Ki dönt |
|---|---|---|
| `reconciliation` | főkönyvi számonként a két oldal és az eltérés | senki: eltérésnél nincs import, leírod |
| `customer_supplier_parsed`, `journal_parsed` | olvasási hiba / hibás sor | senki: hibás forrásnál nincs import |
| `unbilled_items` | számla nélküli tételek listája: túlfizetés / előleg, kerekítés, vevő-értékvesztés (319) (tájékoztató) | – (a visszatérésben felsorolod) |
| `journal_balanced` | a nyitó napló fájljában a tartozik ≠ követel – a különbözet az ellenszámlán (491) maradna | **a könyvelő** |
| `after_cutoff_invoices` | a nyitott listában fordulónapon / utána teljesített számla van | **a könyvelő** |
| `nav_differences` | a fájl és a Zeussban lévő (NAV-os) számla eltér | `block`: **a könyvelő**; a többi tájékoztató |
| `account_map_names` | a fordítás célszámának neve más, mint a forrásé | **te**, a nevek alapján; ha nem egyértelmű, a könyvelő |
| `ledger_accounts` | hiányzó főkönyvi számok | te: `create_missing_accounts: true`; ami nem hozható létre, a könyvelő |
| `postable` | gyűjtőszámlára nem lehet nyitni | a könyvelő |
| `journal_partners` | a nyitó napló partnerei | te, a jelöltek alapján |
| `journal_currency` | devizás pénzeszköz-számlán hiányzik a devizaösszeg | a könyvelő (a forrásból kell) |
| `journal_not_loaded_yet` | az évre már eltérő nyitó tételek vannak | a könyvelő (Nyitás visszavonása) |
| `opening_date`, `period_open`, `currency` | dátum, lezárt időszak, devizás számlák összesítője | – |

Részletek:

- **`reconciliation`** – gyakori ok: hiányzik egy vevő–szállító fájl, más főkönyvi számon van a fájl, a rendezett összeg nem a fordulónapig szól. Csak akkor módosítasz paramétert, ha a forrásból egyértelmű; egyébként könyvelőnek szóló hiba.
- **`after_cutoff_invoices`** – pl. időszakos elszámolású számla (a teljesítés a fizetési határidő), amit a régi program már lekönyvelt. **Nem döntesz helyette**: megkérdezed a könyvelőt (MI chat, 5. lépés), és a válasza szerint adod meg: `opening` = a régi programban már le volt könyvelve, a nyitó napló egyenlege tartalmazza (nyitó tételként megy, az ÁFA-ját a teljesítés hónapjában a könyvelő rendezi); `defer` = nincs a nyitó egyenlegben, a Zeussban kell majd lekönyvelni (az egyeztetésből kimarad). Támpont a kérdéshez: ha a számlákkal együtt egyezik az egyeztetés, a napló tartalmazza őket – ezt írd bele a javaslatba.
- **`journal_balanced`** – a forrásfájl (pl. Kulcs főkönyvi összesítő) nem egyenlő: import után a különbözet a 491-en maradna, a nyitómérleg nem zárna. **Nem javítod ki a fájlt, és nem döntesz helyette**: megkérdezed a könyvelőt (MI chat, 5. lépés). Ha javítja a forrást (pl. kerekítési sorral), az új fájllal futtatod; ha kifejezetten azt kéri, hogy így menjen, `accept_journal_imbalance: true`-val (a visszatérésben jelzed, hogy a 491-en maradt összeg rendezendő).
- **`nav_differences`** – a Zeuss a fájl sorát számlaszám + irány alapján párosítja a már bent lévő számlával. `apply`: devizás számla árfolyama / forintértéke eltér – a nyitás a **fájl** értékét írja a számlára (pl. év végén átértékelt árfolyam), ezt a visszatérésben felsorolod. `info`: pl. a fájlban más adószám áll, mint a számlán – a számla és a nyitó napló sora a számla partnerén lesz. `block`: más előjel, pénznem vagy összeg – a két adat nem ugyanarról a bizonylatról szól; **megállsz**, a könyvelő tisztázza (nem írod át a fájlt). A NAV-ra váró számlákat a Zeuss az import közben, a letöltés után veti össze.
- **`account_map_names`** – a Zeuss a forrásprogram főkönyvi számait maga fordítja (`journal.account_map`, részletek: `journal.account_map_details`: szabály, a cél neve, `name_match`, `suggestions`). Ahol `name_match = differs`, nézd meg a két nevet:
  - ugyanazt jelenti, csak a megfogalmazás más (pl. „Jövedelemelszámolási számla” ↔ „Keresetelszámolási számla”) → erősítsd meg ugyanazzal a céllal: `journal_file.account_map: {"47100": "4711"}`;
  - a jelölt a helyes (pl. a 46100 „KIVA elszámolása” célja nem a 461 „Társasági adó”, hanem a jelölt 4637 „KIVA elszámolása”) → a jelöltet add meg;
  - nem egyértelmű, vagy egyik sem jó → kérdezd meg a könyvelőt.
  A megerősített fordítást a Zeuss megjegyzi (irodai szótár), a következő cégnél már magától így fordít. A fordításokat a visszatérésben sorold fel.
- **`ledger_accounts`** – `create_missing_accounts: true`: a Zeuss a cég számlatükör sablonjában hozza létre a hiányzó számokat a **hiányzó szülő szintekkel együtt** (ha nincs sablon, előbb létrehoz egyet a cég nevével). A nevek a forrásból jönnek (`planned_names`: `given` = a forrás megnevezése, `children` = a szülő neve az alszámláiból, `fallback` = „Nyitó import …”); `account_names`-t csak akkor adj, ha a forrásban van jobb név. Ne találj ki nevet: a `fallback` nevűeket a visszatérésben jelezd átnevezésre. Nem hozható létre (könyvelőnek szóló hiba): „nem bontható” / banki szülő alá; ha az ős most válna gyűjtőszámlává, de már van rajta könyvelés; ha a nyitó napló a gyűjtővé váló számra is könyvel (pl. az 529-re és az 5298-ra is) – ilyenkor a könyvelő dönt (a rövidebb is alszámlára megy, vagy összevonja őket), ne írd át helyette.
- **`journal_partners`** (`journal.partner_plan`) – a Zeuss magától dönt: a partner Zeussban meglévő számláinak partnere → adószám a vevő–szállító fájlból → pontos névegyezés → a vevő–szállító import új partnere; ha a napló más írásmóddal hozza ugyanazt a partnert, összeg + név alapján azonosítja (`same_as`). Ha csak **hasonló** partner van (`candidates`), te döntesz: `journal_partners: [{"row": 12, "partner_id": 345}]`, `{"row": 12, "action": "new"}` vagy `{"partner_name": "…", …}`. Meglévőt akkor válassz, ha a név lényegében azonos és az adószám nem mond ellent. A döntéseidet indokold.
- **Azonos számlaszám két partnernél** (`customer_supplier_parsed` hiba): a Zeuss a számlát szám + irány alapján azonosítja, ezért a kettő együtt nem importálható. Ne írd át: a könyvelő teszi egyedivé az egyiket a forrásban.

## 4. Import – `zeuss_opening_import` (ugyanazokkal a paraméterekkel)
Csak ha a check `status = ready`. A Zeuss az elején újra ellenőriz.
- `nav_in_progress` → a vevő–szállító számlák NAV szinkronja folyik (a könyvelésbe még semmi nem került): hívd **újra ugyanígy**, amíg el nem fogy (`nav.remaining`).
- `failed`, `step: after_nav_sync` → a NAV-ból most letöltött számlák közül valamelyik nem egyezik a fájllal (`nav_differences` `block`), vagy emiatt partnerdöntés kell. A könyvelésbe semmi nem került; a hibás pontot a könyvelőnek (vagy a partnerdöntést megadva újra).
- `failed`, „a megnyitott számlák Zeuss szerinti nyitott értéke nem egyezik a fájllal” → az utóellenőrzés visszagörgette a vevő–szállító importot. Tételesen a könyvelőnek; `accept_analytics_differences`-t **csak a könyvelő kifejezett kérésére** adsz.
- `imported` → kész. A `customer_supplier.book_value_overrides` a devizás számlák, amelyek a fájl árfolyamát kapták (az eredeti NAV-érték megőrizve); a `verification` szerint a főkönyv nyitó tételei egyeznek a fájllal.
- `journal_failed` → a vevő–szállító import **bent van**, a nyitó napló technikai hiba miatt nem. Egyszer később ugyanezzel a kéréssel próbáld újra (nem duplikál).
- `imported_with_differences` → bent van, de a visszaellenőrzés eltérést mutat: tételesen a könyvelőnek.
- Egyéb `failed` → semmi nem került be; a hibás ellenőrzések / a hibaüzenet a könyvelőnek.

A már betöltött nyitást nem tudod módosítani vagy törölni. Ha javítani kell: a könyvelő **Nyitás → Nyitás visszavonása** (Admin / Irodavezető) után újra futtatható; a visszavonás megáll, ha a nyitásra már más könyvelés épül (bankpárosítás, átvezetés, átértékelés).

## 5. Amit a könyvelőnek kell eldöntenie – MI chat
Futás közben senkit nem kérdezel meg közvetlenül, és **nem adsz hibát ott, ahol kérdezni lehet**. A könyvelő döntését a Zeuss MI chatjében kéred (`zeuss_chat_post`, `agent: nyito`), cégenként, témánként egy szálban:
- `after_cutoff_invoices` → `topic_key: opening:after_cutoff:<nyitás dátuma>`; a `body`-ban a számlák (szám, partner, teljesítés, összeg); `options`: „Nyitó tételként mennek (a nyitó egyenleg tartalmazza őket)” / „Könyvelésre várnak (nincsenek a nyitó egyenlegben)”; a `suggestion` az, amit az egyeztetés alátámaszt.
- `nav_differences` `block` → `opening:nav_difference:<számlaszám>`; mit mond a fájl és mit a Zeuss.
- `account_map_names`, ha nem egyértelmű → `opening:account_map:<forrásszám>`; a forrás neve, a cél neve, a jelöltek opcióként.
- gyűjtő-ütközés, nem létrehozható főkönyvi szám → `opening:ledger:<szám>`.
- `journal_balanced` → `topic_key: opening:journal_balance:<nyitás dátuma>`; a `body`-ban a fájl tartozik és követel összege és a különbözet; `options`: „Javítom a forrásfájlt” / „Így menjen, a különbözet a 491-en marad”; a `suggestion` a fájl javítása.
- egyeztetési eltérés, aminek az oka nem látszik → `opening:reconciliation:<főkönyvi szám>`, `outcome: blocked`.

A még nyitott kérdést nem kérdezed újra. A megválaszolt szálat a következő futás elején dolgozod fel: a válasz szerinti paraméterrel futtatod a checket / importot, majd `zeuss_chat_reply` `resolution: close`, a `body`-ban azzal, amit csináltál. Sikeres import után rövid beszámoló: `zeuss_chat_post` `outcome: done`.
Ha a Zeussban még nincs MI chat (`schema_missing`), a kérdéseket a visszatérésbe írod. Ha a felhasználó a beszélgetésben jelen van és maga a könyvelő, a kérdést neki is felteheted – a döntését akkor is ő hozza, nem te.

## 6. Visszatérés
Az agent leírásában lévő formátum szerint: egyeztetés főkönyvi számonként, import darabszámok, a fájl ↔ NAV eltérések és amit a fájl szerint állítottál be, számla nélküli tételek, számfordítás (mit erősítettél meg / írtál át), partnerdöntések, a könyvelőnek feltett kérdések, legfeljebb 5 teendő (hol a Zeussban: Nyitás → Nyitó tételek, Vevő–szállító import, Nyitás visszavonása, Partnerek, Számlatükör).
Betöltöttnek csak azt mondod, amire a Zeuss `imported` / `already_loaded` állapotot adott.
