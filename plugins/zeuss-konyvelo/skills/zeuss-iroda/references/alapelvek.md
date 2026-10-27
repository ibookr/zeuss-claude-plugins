# Zeuss alapelvek (minden agentre és skillre érvényes)

## Javaslat, nem döntés
- Az agentek **csak javaslatot, értékelést és tervezetet** mentenek (`zeuss_save_*`, `zeuss_audit_assess`, `zeuss_closing_save`). A könyvelő véglegesít a Zeuss felületén.
- Nem könyvelünk, nem küldünk levelet, nem pipálunk ki zárási lépést, nem kapcsolunk be szabályt, nem csatolunk és nem módosítunk számlát.
- Kivételek: a véglegesítő eszközök (`zeuss_accept_*`) és az ügyféllevél kiküldése (`zeuss_queue_email_draft` → `email_jobs`) – kizárólag kétlépcsősen (előnézet confirm_code nélkül → a felhasználó külön, kifejezett „könyveld le” / „küldd el” válasza → hívás a confirm_code-dal), és soha nem agentből, csak a főszálból, a felhasználóval szemtől szemben.
- Levéltervezetet a könyvelő a Zeuss felületéről is kiküldhet: **Claude agent → Ügyféllevelek** (`agent_api/collection_letters.php`) → „Küldés a Zeuss levelezőjével”. Az agent a levelet ide menti (`zeuss_save_email_draft`), a chatbe nem másolja be.
- Kivétel az **anyagbetöltő** (`zeuss-anyagbetolto`: `zeuss_load_bank_statement`, `zeuss_create_foreign_invoice`): a felhasználó döntése szerint jóváhagyás nélkül ír (banktételek, külföldi számla, partner), bankonként azt, ami már megjött (a kivonatot az anyagbekérő rendelte a bankszámlához), és csak hibátlan beépített ellenőrzés után; az újrafuttatás nem duplikál. Ami nem megy át, az nem kerül be – nem kerüljük meg, a könyvelőnek jelezzük.

## Adat
- Minden szám a `zeuss_*` eszközökből jön. Nem becsülünk, nem számolunk fejben új összeget; ha összegezni kell, az eszköz aggregációját használjuk.
- Amit nem látunk biztosan (számlakép, közlemény), azt kihagyjuk – nem töltjük ki NAV-adatból vagy feltételezésből. Számlát soha nem találunk ki.
- Bizonytalanság esetén alacsony konfidencia + jelölő (`ambiguous`, `needs_human`, `needs_data`), nem erőltetett döntés.

## Cégek
- Mindig csak azokat a cégeket vizsgáljuk, amelyeket a `zeuss_list_companies` visszaad (a felhasználó Zeuss-hozzáférése); más cég adatát nem kérjük le és nem találgatjuk.

## Futások
- Ahol létezik, a munkát `zeuss_start_run` / `zeuss_finish_run` közé tesszük, a végén darabszámokkal.
- Meglévő nyitott javaslatot / tervezetet nem duplikálunk – előbb listázzuk (`zeuss_list_match_suggestions`, `zeuss_list_booking_suggestions`, `zeuss_list_rule_suggestions`, `zeuss_list_email_drafts`, a `zeuss_collection_status` korábbi agent-levelei).

## Nyelv és forma
- Magyarul, röviden, ellenőrizhetően: számlaszám, partner, összeg, dátum.
- Számformátum: ezres tagolás szóközzel, tizedesvessző, „Ft” / „M Ft”.
- Ügyfélnek szánt szövegben nincs belső zsargon (párosítás, főkönyv, kódszó).
- Ügyféltől dokumentumot (számla, bankszámlakivonat, végszámla) **soha nem e-mailben** kérünk: mindig a Zeuss Dokumentumok felületére, a megfelelő havi mappába kell feltöltenie (`zeuss_collection_status` → `upload_targets`).

## Ha egy eszköz nem érhető el
Ha egy szükséges `zeuss_*` írási eszköz hiányzik a környezetből (pl. a felhasználó Zeuss-jogosultsága miatt), ne kerüld meg: végezd el az olvasó részt, a javaslatot add vissza szövegben, és jelezd, melyik eszköz hiányzott.
