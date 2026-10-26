---
name: "zeuss-szamlakep"
description: "Feltöltött számlaképek kiolvasása és összevetése a NAV-adattal a Zeussban (zeuss_get_document, zeuss_save_document_extraction); eltérés, csalásgyanú, NAV-ban nem szereplő számla."
---

# Számlakép-olvasó és NAV-egyeztetés (Zeuss)

Használd, ha a felhasználó a feltöltött számlaképek átnézését, csatolását, vagy a NAV-adatokkal való összevetését kéri.
Ha a kérés a havi anyagok teljességéről szól (megjött-e minden, mi hiányzik, bankszámlakivonatok), a **zeuss-anyagbekeres** skill a megfelelő: az a számlával nem párosított számlaképeket ugyanígy vizsgálja, és a bankot is.

## Lépések
1. `zeuss_list_documents` (alap: csatolatlan fájlok; `not_extracted` = még nem olvasott). Dolgozz a régebbi fájloktól az újabbak felé: a bankszámlaszám-változást a Zeuss a korábbi keltű számlákhoz méri.
2. Fájlonként `zeuss_get_document` – a számlát képként kapod. Olvasd ki pontosan, amit LÁTSZ:
   számlaszám, eladó neve és adószáma, vevő, kelt, teljesítés, fizetési határidő, fizetési mód, pénznem, nettó, ÁFA, bruttó, bankszámlaszám (IBAN vagy 8-8-8), tételek röviden.
   Amit nem látsz vagy nem tudsz biztosan elolvasni, hagyd ki – ne találgass, ne a NAV-adatból töltsd ki.
3. `document_type`: `invoice`, `receipt` (nyugta), `foreign_invoice`, `credit_note`, `proforma` (díjbekérő, előlegbekérő – nem számla), `other` (szerződés, ajánlat, szállítólevél, fotó…), `unreadable`.
4. Jelzők, ha látod: `handwritten_change` (kézzel átírt összeg), `missing_mandatory_element`, `poor_quality`, `duplicate_suspect`,
   `wrong_folder` (bejövő a kimenők között vagy fordítva, kivonat a számlák között), `not_our_document` (nem a cég a vevő / az eladó),
   `blank_or_corrupt` (üres, sérült fájl), `partial_document` (hiányzó oldal, levágott számla).
5. `zeuss_save_document_extraction` – a Zeuss megkeresi a NAV-számlát és mezőnként összeveti. Ítélet: `match` / `mismatch` / `not_in_nav` / `ambiguous` / `unreadable`.
6. Ha `ambiguous`: nézd meg a jelölteket (`zeuss_get_invoice`), és ha biztos vagy, mentsd újra `invoice_id`-vel.

## Összefoglaló a könyvelőnek
- Először a kockázatos esetek: **új bankszámlaszám** (számlacserés csalási minta – fizetés előtt telefonon, ismert elérhetőségen ellenőrizni), összegeltérés (kép vs. NAV), magyar ÁFÁ-s számla NAV-jelentés nélkül.
- Utána: külföldi számlák és nyugták, amelyeket rögzíteni kell.
- Díjbekérők (`proforma` jelölő): ezekhez az ügyféltől a végszámlát kell kérni, ha fizetett; hibás feltöltések (`unreadable`, `blank_or_corrupt`, `partial_document`, `not_our_document`): újra kell kérni → zeuss-anyagbekeres / zeuss-ugyfellevel.
- Végül: egyező, csatolható fájlok száma.
- A csatolást a könyvelő végzi: Claude agent → Számlaképek → „Csatolás a számlához”. Az agent nem módosít számlát.

## Mérés (lokális demó)
`docker compose -f docker-compose.local.yml exec app php agent_api/tools/evaluate_agents.php documents`