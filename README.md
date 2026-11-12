# Zeuss Claude pluginok

Claude Code / Claude desktop plugin marketplace a **Zeuss** könyvelő rendszerhez.

| Plugin | Verzió | Leírás |
|---|---|---|
| [`zeuss-konyvelo`](plugins/zeuss-konyvelo) | 0.14.1 | Könyvelő-asszisztens: anyagbekérés, anyagbetöltés, nyitás, bankpárosítás, kontírozás, számlakép, NAV-ellenőr, havi zárás, ügyféllevél, kimutatás |

## Telepítés

Egy lépésben (Claude Code 2.1.275 vagy újabb):

```
/plugin install zeuss-konyvelo --marketplace ibookr/zeuss-claude-plugins
```

Régebbi verzión két lépésben:

```
/plugin marketplace add ibookr/zeuss-claude-plugins
/plugin install zeuss-konyvelo@zeuss
```

Frissítés később: `/plugin marketplace update zeuss`

## Előfeltétel

A plugin a Zeuss rendszer **`zeuss` nevű MCP szerverén** keresztül dolgozik, ehhez Zeuss fiók és személyes agent-token kell. A beállítás lépései a [plugin leírásában](plugins/zeuss-konyvelo/README.md#mcp-kapcsolat) vannak.

Az agentek alapból csak javaslatot és tervezetet mentenek; véglegesen könyvelni és levelet küldeni csak a könyvelő kifejezett, kétlépcsős jóváhagyásával lehet. Két kivétel, külön token-joggal: az anyagbetöltő (`load`) és a nyitás agent (`open`) jóváhagyás nélkül ír, de csak ha a Zeuss beépített ellenőrzése hibátlan (kivonat ↔ főkönyv, illetve vevő–szállító nyitott tételek ↔ nyitó napló főkönyvi számonként); különben semmi nem kerül be.

## Adatkezelés / Data handling

Mit olvas és ír a plugin, hova kerül az adat: [plugin README – Data handling](plugins/zeuss-konyvelo/README.md#data-handling-english). Adatvédelmi szabályzat: https://zeuss.hu/adatkezelesi-es-adatvedelmi-szabalyzat/

## Licenc

Zárt licenc – lásd [LICENSE](LICENSE).
