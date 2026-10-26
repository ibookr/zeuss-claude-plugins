#!/bin/zsh
# Új verzió kiadása: ./release.sh 0.4.1 "mi változott"
# Emeli a verziót a plugin.json-ban és a marketplace.json-ban, ellenőriz, commitol és feltölt.
set -euo pipefail
cd "${0:A:h}"

VERSION="${1:?Add meg a verziót, pl. ./release.sh 0.4.1 \"mi változott\"}"
MESSAGE="${2:-zeuss-konyvelo $VERSION}"
PLUGIN=plugins/zeuss-konyvelo

python3 -I - "$VERSION" "$PLUGIN" <<'EOF'
import json, sys
version, plugin = sys.argv[1], sys.argv[2]
for path in (f"{plugin}/.claude-plugin/plugin.json", ".claude-plugin/marketplace.json"):
    data = json.load(open(path))
    if "plugins" in data:
        data["metadata"]["version"] = version
        for p in data["plugins"]:
            if p["name"] == "zeuss-konyvelo":
                p["version"] = version
    else:
        data["version"] = version
    with open(path, "w") as f:
        json.dump(data, f, ensure_ascii=False, indent=2)
        f.write("\n")
    print(f"{path}: {version}")
EOF
sed -i '' -E "s/\| ([0-9]+\.[0-9]+\.[0-9]+) \|/| $VERSION |/" README.md

# Ellenőrzés a Claude desktop app beépített CLI-jével (ideiglenes konfigurációval)
CLAUDE_BIN=$(command -v claude || ls -t "$HOME/Library/Application Support/Claude/claude-code"/*/*/claude.app/Contents/MacOS/claude 2>/dev/null | head -1)
if [[ -n "$CLAUDE_BIN" ]]; then
  TMP=$(mktemp -d)
  CLAUDE_CONFIG_DIR=$TMP "$CLAUDE_BIN" plugin validate .
  CLAUDE_CONFIG_DIR=$TMP "$CLAUDE_BIN" plugin validate "$PLUGIN" --strict
  rm -rf "$TMP"
else
  echo "Figyelem: nem találtam claude CLI-t, az ellenőrzés kimaradt." >&2
fi

git add -A
git commit -m "$MESSAGE"
git push
echo "Kész: $VERSION feltöltve. Kollégáknak: /plugin marketplace update zeuss"
