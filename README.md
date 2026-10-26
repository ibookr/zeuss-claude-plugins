# Zeuss Claude pluginok

Claude Code / Claude desktop plugin marketplace a **Zeuss** könyvelő rendszerhez.

| Plugin | Verzió | Leírás |
|---|---|---|
| [`zeuss-konyvelo`](plugins/zeuss-konyvelo) | 0.4.0 | Könyvelő-asszisztens: anyagbekérés, bankpárosítás, kontírozás, számlakép, NAV-ellenőr, havi zárás, ügyféllevél, kimutatás |

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

Az agentek mindig csak javaslatot és tervezetet mentenek; könyvelni és levelet küldeni csak a könyvelő kifejezett jóváhagyásával lehet.

## Licenc

Zárt licenc – lásd [LICENSE](LICENSE).
