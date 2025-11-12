#!/usr/bin/env bash
set -euo pipefail
source .env

: "${REGION:?set REGION in .env}"
: "${BUCKET:?set BUCKET in .env}"

# us-east-1: create-bucket OHNE LocationConfiguration
if [ "$REGION" = "us-east-1" ]; then
  aws s3api create-bucket --bucket "$BUCKET" --region "$REGION" 2>/dev/null || true
else
  aws s3api create-bucket --bucket "$BUCKET" --region "$REGION" \
    --create-bucket-configuration LocationConstraint="$REGION" 2>/dev/null || true
fi

# Verschlüsselung
aws s3api put-bucket-encryption --bucket "$BUCKET" --server-side-encryption-configuration \
'{"Rules":[{"ApplyServerSideEncryptionByDefault":{"SSEAlgorithm":"AES256"}}]}'

# Block Public Access (alles zu)
aws s3api put-public-access-block --bucket "$BUCKET" \
  --public-access-block-configuration BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true

# CORS für Presigned PUT/GET (nur Browser)
aws s3api put-bucket-cors --bucket "$BUCKET" --cors-configuration '{
  "CORSRules":[{"AllowedMethods":["PUT","GET"],"AllowedOrigins":["*"],"AllowedHeaders":["*"],"ExposeHeaders":["ETag"],"MaxAgeSeconds":300}]
}'

echo "✓ Image-Bucket privat & bereit: s3://$BUCKET"
