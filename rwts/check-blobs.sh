#!/usr/bin/env bash
# Check that both custom.txt blobs verify against the key compiled into
# src/common.rs. Needs python3 with PyNaCl (pip install pynacl).
set -euo pipefail
cd "$(dirname "$0")/.."
KEY=$(grep -oE 'const KEY: &str = "[^"]+"' src/common.rs | sed -E 's/.*"([^"]+)"/\1/')
for f in rwts/quicksupport.custom.txt rwts/technician.custom.txt; do
  python3 - "$f" "$KEY" <<'PY'
import base64, json, sys
from nacl.signing import VerifyKey
blob, key = open(sys.argv[1]).read().strip(), sys.argv[2]
settings = json.loads(VerifyKey(base64.b64decode(key)).verify(base64.b64decode(blob)))
assert settings["app-name"].startswith("RWTS QuickSupport"), settings
assert settings.get("hide-powered-by-me") == "Y", settings
print(f"{sys.argv[1]}: ok, conn-type={settings.get('conn-type')}")
PY
done
