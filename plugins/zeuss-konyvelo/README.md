# zeuss-konyvelo

Claude könyvelő-asszisztens a **Zeuss** könyvelő rendszerhez. Szakterületenként egy-egy agent dolgozik a `zeuss` MCP szerver `zeuss_*` eszközeivel. **Mindig csak javaslatot és tervezetet mentenek**, a véglegesítés a könyvelőé a Zeuss felületén.

## Telepítés
```
/plugin install zeuss-konyvelo --marketplace ibookr/zeuss-claude-plugins
```
Régebbi Claude Code-on: `/plugin marketplace add ibookr/zeuss-claude-plugins`, majd `/plugin install zeuss-konyvelo@zeuss`. A használathoz a `zeuss` MCP szerver is kell (lásd lent: MCP kapcsolat).

## Összetevők

| Típus | Név | Feladat |
|---|---|---|
| Skill (irányító) | `zeuss-iroda` | Kiválasztja és sorba fűzi az agenteket; teljes havi kör, több cég |
| Skill | `zeuss-bankparositas` | Bank–számla párosítás, számla nélküli tételek könyvelési javaslata |
| Skill | `zeuss-kontirozas` | Bejövő számlák kontírozása, tanuló banki szabályok |
| Skill | `zeuss-szamlakep` | Számlaképek kiolvasása, NAV-egyeztetés, csalásgyanú |
| Skill | `zeuss-nav-ellenor` | 34 pontos NAV-szemű átvilágítás és értékelés |
| Skill | `zeuss-havi-zaras` | Havi zárás jegyzőkönyv; reggeli irodai összefoglaló |
| Skill | `zeuss-ugyfellevel` | Ügyféllevél-tervezet a hiányzó anyagokról, kiküldés a Zeuss levelezőjével |
| Skill | `zeuss-anyagbekeres` | Havi anyagok beszedése: nem párosított számlaképek besorolása, bankszámlakivonatok a főkönyvi bankszámlák szerint, levél a hiányokról |
| Skill | `zeuss-kimutatas` | Kimutatások, riportok |
| Agent | `zeuss-bankparosito` | → zeuss-bankparositas |
| Agent | `zeuss-kontirozo` | → zeuss-kontirozas |
| Agent | `zeuss-szamlakep-olvaso` | → zeuss-szamlakep |
| Agent | `zeuss-nav-ellenor` | → zeuss-nav-ellenor |
| Agent | `zeuss-zaras-elokeszito` | → zeuss-havi-zaras (havi zárás) |
| Agent | `zeuss-irodavezeto` | → zeuss-havi-zaras (reggeli összefoglaló) |
| Agent | `zeuss-ugyfellevel-iro` | → zeuss-ugyfellevel |
| Agent | `zeuss-anyagbekero` | → zeuss-anyagbekeres |
| Agent | `zeuss-kimutatas-keszito` | → zeuss-kimutatas |

## Teljes havi kör („csináld meg a szeptembert”)
1. anyagok + számlaképek ∥ 2. bankpárosítás ∥ 3. kontírozás – párhuzamosan
4. NAV-ellenőrzés
5. zárás-előkészítés (az előzőek összefoglalójára építve)
6. ügyféllevél, ha maradt kérnivaló

## Biztonsági elvek
- Nincs könyvelés, levélküldés, lépés-kipipálás, szabály-bekapcsolás vagy számlamódosítás agentből.
- `zeuss_accept_*` és `zeuss_queue_email_draft` (ügyféllevél → `email_jobs`) csak a főszálból, kétlépcsősen (előnézet → kifejezett „könyveld le” / „küldd el” → confirm_code).
- A levéltervezetet a könyvelő a felületről is kiküldheti: `email_drafts.php` → „Küldés a Zeuss levelezőjével”.
- Minden szám a Zeussból jön; amit nem lát biztosan, azt az agent kihagyja.

## MCP kapcsolat
A plugin a **`zeuss` nevű MCP szervert** használja, amely a Claude desktop alkalmazásban helyben fut (stdio). A plugin szándékosan **nem** hoz saját `.mcp.json`-t, mert az azonos nevű szerver ütközne a már beállítottal, és a tokenek felhasználónként külön vannak.

Új kollégánál:
1. Állítsd be a `zeuss` MCP szervert a Claude desktopban a saját, személyes agent-tokeneddel.
2. A szerver neve legyen pontosan `zeuss`, és az eszközök neve `zeuss_*` – a skillek és az agentek ezekre hivatkoznak.
3. Az írási eszközök (`zeuss_start_run`, `zeuss_save_*`, `zeuss_audit_run`, `zeuss_audit_assess`, `zeuss_closing_save`, `zeuss_save_office_brief`, `zeuss_save_email_draft`, `zeuss_save_report`, `zeuss_save_document_extraction`, `zeuss_save_bank_statement_link`) a token jogosultságától függenek. A `zeuss_queue_email_draft` `send` jogú tokent és `ZEUSS_ALLOW_COMMIT=1`-et kér (MCP szerver ≥ 1.9.0, agent API ≥ 1.6.0). Ha valamelyik hiányzik, az agent a javaslatot szövegben adja vissza.
