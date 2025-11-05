#!/usr/bin/env bash
set -euo pipefail
source .env

: "${REGION:?set REGION in .env}"
: "${WEB_BUCKET:?set WEB_BUCKET in .env}"

# 1) Bucket anlegen (idempotent)
aws s3api create-bucket \
  --bucket "$WEB_BUCKET" \
  --region "$REGION" \
  --create-bucket-configuration LocationConstraint="$REGION" 2>/dev/null || true

# 2) Static Website Hosting aktivieren
aws s3 website s3://"$WEB_BUCKET" --index-document index.html --error-document index.html

# 3) Öffentliche Lese-Policy NUR für Website-Objekte
cat > /tmp/web-policy.json <<POL
{"Version":"2012-10-17","Statement":[{"Sid":"PublicReadGetObject","Effect":"Allow",
"Principal":"*","Action":["s3:GetObject"],"Resource":["arn:aws:s3:::$WEB_BUCKET/*"]}]}
POL
aws s3api put-bucket-policy --bucket "$WEB_BUCKET" --policy file:///tmp/web-policy.json

# 4) index.html hochladen
aws s3 cp web/index.html s3://"$WEB_BUCKET"/index.html

echo
echo "✓ Website bereit:"
echo "  URL: http://${WEB_BUCKET}.s3-website-${REGION}.amazonaws.com"
