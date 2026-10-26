---
name: "zeuss-bankparositas"
description: "Bank–számla párosítási és könyvelési javaslatok a Zeuss könyvelő rendszerben zeuss_* MCP eszközökkel; csak javaslat, indoklással."
---

# Bankpárosítás (Zeuss)

Akkor használd, ha a felhasználó nyitott banktételek párosítását, „mi ez a tétel”, vagy könyvelési javaslatot kér.

## Szabályok
- Csak javaslatot mentesz (`zeuss_save_match_suggestion`, `zeuss_save_posting_suggestion`); a könyvelő véglegesít.
- Irány: vevői (outgoing) számla ↔ bevétel, szállítói (incoming) ↔ kiadás. Jóváíró/sztornó számla iránya fordított, és ugyanannál a partnernél nettózódhat.
- A számlaszám a közleményben erős jel. Az O↔0, I↔1 elírás még ugyanaz a számla, de egy eltérő számjegy már másik számlát jelent.
- A fizetés után kelt számla gyanús, kivéve díjbekérő alapján előre fizetett tételt.
- Több azonos összegű jelöltnél jelöld `ambiguous`-nak, a konfidencia legyen ≤ 0,5. Ha nincs jó jelölt, üres `invoice_ids` + `no_match`. Soha ne találj ki számlát.
- Részfizetés, túlfizetés vagy levont banki díj esetén add meg az `allocations`-t és a megfelelő flaget.
- Az indoklás magyar, rövid, ellenőrizhető: számlaszám, partner, összeg, dátum.

## Lépések
1. `zeuss_start_run` (task: bank_invoice_matching).
2. `zeuss_work_queue`; tételenként `zeuss_invoice_candidates`. Ha az összeg nagyobb bármely jelöltnél: `zeuss_invoice_combinations`. Szükség esetén `zeuss_partner_history`, `zeuss_get_invoice`.
3. Számla nélküli tételre (`suggested_task` = posting, vagy egyértelmű bankköltség/adó/bér/kamat): `zeuss_posting_context` → `zeuss_save_posting_suggestion`.
4. `zeuss_finish_run` a darabszámokkal.
5. A chatben: összesítés (hány biztos, hány bizonytalan, hány „nincs számla”) és a tisztázandó tételek listája. Utóbbiakhoz ajánld fel az ügyféllevelet (zeuss-ugyfellevel).