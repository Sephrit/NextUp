#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

excluded=(
  --glob '!desktop/node_modules/**'
  --glob '!desktop/dist/**'
  --glob '!desktop/src-tauri/target/**'
  --glob '!.build/**'
  --glob '!dist/**'
  --glob '!desktop/package-lock.json'
  --glob '!desktop/src-tauri/Cargo.lock'
  --glob '!scripts/scan-secrets.sh'
  --glob '!.git/**'
)

fail=0
if find . -type f \( -name '.env' -o -name '*.pem' -o -name '*.p12' -o -name '*.pfx' -o -name 'library.json' -o -name 'library.backup.json' \) \
  -not -path './.git/*' -not -path './desktop/node_modules/*' -not -path './desktop/src-tauri/target/*' -not -path './.build/*' | grep -q .; then
  echo 'Potential secret or personal-data file found:' >&2
  find . -type f \( -name '.env' -o -name '*.pem' -o -name '*.p12' -o -name '*.pfx' -o -name 'library.json' -o -name 'library.backup.json' \) \
    -not -path './.git/*' -not -path './desktop/node_modules/*' -not -path './desktop/src-tauri/target/*' -not -path './.build/*' >&2
  fail=1
fi

patterns=(
  '-----BEGIN (RSA |EC |OPENSSH )?PRIVATE KEY-----'
  "(?i)(api[_-]?key|client[_-]?secret|access[_-]?token|password)[[:space:]]*[:=][[:space:]]*[\"']?[A-Za-z0-9_./+=-]{20,}"
  'NEXTUP_WATCHMODE_KEY=[^[:space:]#]{8,}'
)

for pattern in "${patterns[@]}"; do
  if rg -n --pcre2 "${excluded[@]}" -- "$pattern" .; then fail=1; fi
done

if (( fail )); then
  echo 'Secret scan failed. Remove the value or explicitly exclude a verified fixture.' >&2
  exit 1
fi

echo 'Secret scan passed.'
