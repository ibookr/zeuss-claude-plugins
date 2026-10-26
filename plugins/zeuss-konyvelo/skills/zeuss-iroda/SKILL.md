---
name: zeuss-iroda
description: "A Zeuss könyvelő rendszer irányító skillje: eldönti, melyik Zeuss-agent vagy skill kell, és sorba fűzi őket (teljes havi kör, több cég, reggeli összefoglaló). Használd, ha a felhasználó a Zeussról, egy cég könyveléséről, „csináld meg a hónapot”, „nézd át a cégeket”, „mi a helyzet a Zeussban” jellegű kérést ad, vagy több Zeuss-feladatot kér egyszerre."
---

# Zeuss iroda – irányító

A Zeuss a felhasználó saját fejlesztésű könyvelő rendszere. Az adat és minden művelet a `zeuss` MCP szerver `zeuss_*` eszközein keresztül érhető el. Mielőtt bármit csinálsz, olvasd el: `references/alapelvek.md`.

## 1. Cég és időszak
1. `zeuss_list_companies` – ha a cég nincs megnevezve és egynél több van, kérdezz rá; ha egy van, használd azt és mondd ki.
2. Időszak: amit a felhasználó mond. Havi feladatnál alapból a legrégebbi le nem zárt hónap (`last_closed_month` + 1); elemzésnél az év eleje – ma. Mindig mondd ki, melyiket vetted.
3. Gyors helyzetkép: `zeuss_company_overview` (vagy több cégnél `zeuss_office_overview`).

## 2. Melyik agent?
| Kérés | Agent | Skill |
|---|---|---|
| banktételek párosítása, „mi ez a tétel” | `zeuss-bankparosito` | zeuss-bankparositas |
| bejövő számlák kontírozása, banki szabályok | `zeuss-kontirozo` | zeuss-kontirozas |
| megjött-e a havi anyag, hiányzó bankszámlakivonat, díjbekérő, hibás feltöltés, anyagok bekérése | `zeuss-anyagbekero` | zeuss-anyagbekeres |
| bankszámlakivonatok betöltése a főkönyvbe, külföldi számlák rögzítése, bankegyeztetés (kivonat ↔ főkönyv) | `zeuss-anyagbetolto` | zeuss-anyagbetoltes |
| feltöltött számlaképek, NAV-egyeztetés, csalásgyanú | `zeuss-szamlakep-olvaso` | zeuss-szamlakep |
| NAV-ellenőrzés, átvilágítás, kockázat | `zeuss-nav-ellenor` | zeuss-nav-ellenor |
| havi zárás, zárási jegyzőkönyv | `zeuss-zaras-elokeszito` | zeuss-havi-zaras |
| reggeli / napi irodai összefoglaló | `zeuss-irodavezeto` | zeuss-havi-zaras |
| hiányzó anyagok, ügyféllevél | `zeuss-ugyfellevel-iro` | zeuss-ugyfellevel |
| kimutatás, riport, elemzés | `zeuss-kimutatas-keszito` | zeuss-kimutatas |

Egyetlen, rövid kérdésnél (pl. „hány nyitott banktétel van?”) ne indíts agentet – kérdezd le közvetlenül.
Agentnek mindig add át: cég id és név, időszak, a felhasználó pontos kérése, és amit az előző lépések találtak.

## 3. Teljes havi kör („csináld meg a hónapot”)
A sorrend azért ez, mert minden lépés a következő bemenetét tisztítja:
1. **Anyagok és számlaképek** → `zeuss-anyagbekero` („teljes havi kör része” jelzéssel – ilyenkor nem ment levelet, a tételeket visszaadja): a nem párosított számlaképek besorolása és a bankszámlakivonatok. A számlakép-olvasót külön csak csalásgyanú / NAV-eltérés vizsgálatához indítsd.
   **1/b. Anyagbetöltés** → `zeuss-anyagbetolto` az anyagbekérő után, bankonként: ami már megjött (hozzárendelt kivonat, kiolvasott külföldi számla), azt betölti és egyezteti, a többi a következő futásra marad – a már betöltött bankokhoz nem nyúl. A hiányzó anyag a 6. lépés levelébe kerül.
2. **Bankpárosítás** → `zeuss-bankparosito` (az 1/b után, mert a betöltött banktételeken dolgozik).
3. **Kontírozás + szabályok** → `zeuss-kontirozo`.
   A 2–3. lépés független adatkörön dolgozik: ha a környezet engedi, indítsd őket **párhuzamosan**.
4. **NAV-ellenőrzés** → `zeuss-nav-ellenor` (az 1–3. lépés után, hogy a már kezelt tételek ne okozzanak téves riasztást).
5. **Zárás-előkészítés** → `zeuss-zaras-elokeszito` (megkapja a 1–4. lépés összefoglalóit).
6. **Ügyféllevél** → `zeuss-ugyfellevel-iro`, csak ha maradt ügyféltől kérendő anyag – az 1. lépés hiányait (kivonat, díjbekérő, hibás feltöltés) is megkapja, hogy ügyfelenként **egy** levél legyen. Kiküldés: a könyvelő a felületen, vagy a főszál `zeuss_queue_email_draft`-tel, kétlépcsősen.

## 3/b. Anyagbekérés az összes cégnél („kérd be a hiányzó anyagokat”, „megjött minden?”, ütemezett futás)
Ütemezett feladatként a zeuss-anyagbekeres skill 8. pontja szerint (task `scheduled_document_collection`, a végén `zeuss_collection_done`; kiküldés csak a Zeuss felületén: Claude agent → Ügyféllevelek).
`zeuss_list_companies` → cégenként egy `zeuss-anyagbekero` agent (párhuzamosan), mindegyik a saját levéltervezetét menti. A végén egy táblázat: cég · hiányzó kivonat · ügyfélnek szóló tétel · tervezet id. Ha a felhasználó a chatben kéri a kiküldést: tervezetenként `zeuss_queue_email_draft` előnézet → megmutatás → kifejezett jóváhagyás → confirm_code.

Több cégnél cégenként futtasd a kört; a cégek egymástól függetlenek, párhuzamosíthatók.

## 4. Záró összefoglaló a felhasználónak
Röviden, magyarul:
- cég, időszak;
- lépésenként egy sor: mit készített az agent (darabszámok: biztos / bizonytalan / nincs találat);
- a kockázatos tételek külön (új bankszámlaszám, összegeltérés, NAV-ban nem szereplő számla, súlyos NAV-találat);
- mit kell a könyvelőnek jóváhagynia, és hol a Zeussban (Claude agent menü);
- legfeljebb 3–5 „következő teendő”.

Soha ne állítsd, hogy valami le van könyvelve, ki van küldve vagy le van zárva – az agentek csak javaslatot és tervezetet mentenek. Kivétel az anyagbetöltő: betöltöttnek / rögzítettnek csak az számít, amire a Zeuss `loaded` / `already_loaded` / `created` állapotot adott. Kiküldöttnek csak az a levél számít, amelyre a `zeuss_queue_email_draft` `executed` választ és `email_job_id`-t adott.
