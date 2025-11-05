#!/usr/bin/env bash
set -euo pipefail
source .env

: "${REGION:?set REGION in .env}"
: "${BUCKET:?set BUCKET in .env}"

USER_ID="${1:-1}"
FILEPATH="${2:-}"
if [ -z "$FILEPATH" ]; then
  echo "Usage: scripts/03b-presign-local.sh <user_id> <local-file-name>" >&2
  exit 1
fi

FILENAME="$(basename "$FILEPATH")"
KEY="uploads/${USER_ID}/${FILENAME}"

# AWS CLI v2: presigned PUT
URL=$(aws s3 presign "s3://${BUCKET}/${KEY}" --region "$REGION" --expires-in 900 --http-method PUT)
echo "$URL"
echo "S3 key: ${KEY}" >&2
