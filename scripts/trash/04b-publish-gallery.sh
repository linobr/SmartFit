#!/usr/bin/env bash
set -euo pipefail
set -a; source .env; set +a
USER_ID="${1:-1}"
EXPIRES="${2:-900}"   # Sekunden

python3 scripts/04a-build-gallery.py "$USER_ID" "$EXPIRES"

# Hochladen (als Website-Seite)
aws s3 cp web/gallery.html "s3://${WEB_BUCKET}/gallery.html" --content-type text/html

echo "Galerie-URL: http://${WEB_BUCKET}.s3-website-${REGION}.amazonaws.com/gallery.html"
