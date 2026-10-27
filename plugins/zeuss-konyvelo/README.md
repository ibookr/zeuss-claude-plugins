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
| Skill | `zeuss-anyagbetoltes` | Hiánytalan havi anyag betöltése: kivonatok a főkönyvi bankszámlákra, külföldi számlák rögzítése, bankegyeztetés (kivonat nyitó / záró ↔ főkönyv) |
| Skill | `zeuss-kimutatas` | Kimutatások, riportok |
| Agent | `zeuss-bankparosito` | → zeuss-bankparositas |
| Agent | `zeuss-kontirozo` | → zeuss-kontirozas |
| Agent | `zeuss-szamlakep-olvaso` | → zeuss-szamlakep |
| Agent | `zeuss-nav-ellenor` | → zeuss-nav-ellenor |
| Agent | `zeuss-zaras-elokeszito` | → zeuss-havi-zaras (havi zárás) |
| Agent | `zeuss-irodavezeto` | → zeuss-havi-zaras (reggeli összefoglaló) |
| Agent | `zeuss-ugyfellevel-iro` | → zeuss-ugyfellevel |
| Agent | `zeuss-anyagbekero` | → zeuss-anyagbekeres |
| Agent | `zeuss-anyagbetolto` | → zeuss-anyagbetoltes |
| Agent | `zeuss-kimutatas-keszito` | → zeuss-kimutatas |

## Teljes havi kör („csináld meg a szeptembert”)
1. anyagok + számlaképek → 1/b. anyagbetöltés (bankonként, ami megjött)
2. bankpárosítás ∥ 3. kontírozás – párhuzamosan
4. NAV-ellenőrzés
5. zárás-előkészítés (az előzőek összefoglalójára építve)
6. ügyféllevél, ha maradt kérnivaló

## Biztonsági elvek
- Nincs könyvelés, levélküldés, lépés-kipipálás, szabály-bekapcsolás vagy számlamódosítás agentből.
- Egyetlen kivétel az anyagbetöltő (`zeuss_load_bank_statement`, `zeuss_create_foreign_invoice`): jóváhagyás nélkül tölt be, bankonként azt, ami már megjött (az anyagbekérő által a bankszámlához rendelt kivonat), duplikálás nélkül, és csak ha a Zeuss beépített ellenőrzése hibátlan (kivonat nyitó + tételek = záró, főkönyvi nyitó / záró = kivonat, számlaadatok = számlakép). Külön „anyagbetöltés” (`load`) token-jog kell hozzá.
- Az állapot a Zeuss Varázsló → **Havi irányítópult** oldalán cégenként látszik (Könyvelési anyagok, Anyagok betöltése).
- `zeuss_accept_*` és `zeuss_queue_email_draft` (ügyféllevél → `email_jobs`) csak a főszálból, kétlépcsősen (előnézet → kifejezett „könyveld le” / „küldd el” → confirm_code).
- A levéltervezetet a könyvelő a felületről is kiküldheti: **Claude agent → Ügyféllevelek** (`agent_api/collection_letters.php`, minden cég egy helyen) → „Küldés a Zeuss levelezőjével”. Az anyagbekérő és az ügyféllevél-író cégenként és hónaponként ugyanazt a havi élő levelet frissíti.
- Minden szám a Zeussból jön; amit nem lát biztosan, azt az agent kihagyja.

## MCP kapcsolat
A plugin a **`zeuss` nevű MCP szervert** használja, amely a Claude desktop alkalmazásban helyben fut (stdio). A plugin szándékosan **nem** hoz saját `.mcp.json`-t, mert az azonos nevű szerver ütközne a már beállítottal, és a hozzáférés felhasználónként külön van.

Új kollégánál:
1. Állítsd be a `zeuss` MCP szervert a Claude desktopban a Zeuss telepítési útmutatója szerint, a saját Zeuss-hozzáféréseddel.
2. A szerver neve legyen pontosan `zeuss`, és az eszközök neve `zeuss_*` – a skillek és az agentek ezekre hivatkoznak.
3. Az írási eszközök (`zeuss_start_run`, `zeuss_save_*`, `zeuss_audit_run`, `zeuss_audit_assess`, `zeuss_closing_save`, `zeuss_save_office_brief`, `zeuss_save_email_draft`, `zeuss_save_report`, `zeuss_save_document_extraction`, `zeuss_save_bank_statement_link`) a felhasználó Zeuss-jogosultságától függenek. A `zeuss_queue_email_draft` (levélküldés) külön küldési jogosultságot kér, amelyet a Zeuss MCP szerver beállításánál lehet engedélyezni (MCP szerver ≥ 1.9.0). Az anyagbetöltő eszközei (`zeuss_load_bank_statement`, `zeuss_create_foreign_invoice`) az „anyagbetöltés” (`load`) jogot kérik (MCP szerver ≥ 1.12.0, Agent API ≥ 1.9.0). Ha valamelyik hiányzik, az agent a javaslatot szövegben adja vissza.

## Data handling (English)

**What the plugin is.** Markdown skills and subagents only. It ships no MCP server, scripts, hooks or binaries, and it makes no network calls of its own.

**Which service it talks to.** All data access goes through the user's own **Zeuss MCP server** (server name `zeuss`, tools `zeuss_*`). The user installs and configures that server separately, following Zeuss's own setup guide; the plugin never reads, stores or passes any credential. Zeuss is a Hungarian accounting-office system operated by IBOOKR; the server only exposes the companies that user's Zeuss account can see.

**What it reads** (from Zeuss, via `zeuss_*` tools): client companies, bank statement items, invoices and invoice images, ledger accounts, partners, open tasks and reports. This includes personal data of the accounting firm's clients and their business partners: names, e-mail addresses, postal addresses, tax numbers, bank transaction details.

**What it writes** (back into the same Zeuss account): matching, posting and booking *suggestions*, document extraction results, audit and month-end closing notes, reports, office briefs and client e-mail *drafts*. With the separate `load` permission, the material-loading agent also writes bank statement items and foreign (non-NAV) supplier invoices with their partners – only for a month whose documents are complete, and only after Zeuss's built-in checks pass (statement balances equal the ledger balances, invoice data equal the invoice image). Suggestions are not final: an accountant reviews them in the Zeuss UI. The `zeuss_accept_*` tools (final booking/matching) and `zeuss_queue_email_draft` (hands a client e-mail to Zeuss's own mailer) are only used after an explicit two-step confirmation from the user in the main conversation, never by a subagent.

**Where data goes.** Only to Claude (for processing the conversation) and to the user's Zeuss account. No third-party services. Client e-mails, when the user approves sending, are delivered by the Zeuss mail system, not by the plugin.

**Retention.** The plugin itself stores nothing. Data written to Zeuss is kept in the user's Zeuss account as part of the accounting records, subject to the Zeuss privacy policy and statutory record-keeping periods (8 years for accounting documents in Hungary).

**Privacy policy:** https://zeuss.hu/adatkezelesi-es-adatvedelmi-szabalyzat/
**Contact:** IBOOKR, via https://zeuss.hu
