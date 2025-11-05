#!/usr/bin/env bash
set -euo pipefail
set -a; source .env; set +a

USER_ID="${1:-1}"
FILEPATH="${2:-}"

if [ -z "$FILEPATH" ] || [ ! -f "$FILEPATH" ]; then
  echo "Usage: scripts/03d-presign-open.sh <user_id> </voller/pfad/zur/datei>"
  echo "Beispiel: scripts/03d-presign-open.sh 1 \"/mnt/c/Users/bruec/Pictures/bild.png\""
  exit 1
fi

# Content-Type aus Dateiendung
CT=$(python3 -c 'import sys, mimetypes; p=sys.argv[1]; print(mimetypes.guess_type(p)[0] or "application/octet-stream")' "$FILEPATH")

# Presign für GENAU diesen Dateinamen + CT (stdout = URL)
URL=$(scripts/03c-presign-local.py "$USER_ID" "$(basename "$FILEPATH")" "$CT" | head -n1)

# URL encoden für Query-Param
ENC_URL=$(python3 - "$URL" <<'PY'
import sys, urllib.parse
print(urllib.parse.quote(sys.argv[1], safe=""))
PY
)

SITE="http://${WEB_BUCKET}.s3-website-${REGION}.amazonaws.com/index.html?url=${ENC_URL}"

echo "Open: $SITE"
if command -v wslview >/dev/null 2>&1; then
  wslview "$SITE"
else
  xdg-open "$SITE" >/dev/null 2>&1 || true
fi
