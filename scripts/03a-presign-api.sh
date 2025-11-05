#!/usr/bin/env bash
set -euo pipefail
source .env

: "${REGION:?}"; : "${ACCOUNT_ID:?}"; : "${BUCKET:?}"; : "${PRESIGN_FN:?}"; : "${API_NAME:?}"

# 1) IAM Role für Lambda
aws iam create-role --role-name smartfit-presign-role \
  --assume-role-policy-document '{
    "Version":"2012-10-17",
    "Statement":[{"Effect":"Allow","Principal":{"Service":"lambda.amazonaws.com"},"Action":"sts:AssumeRole"}]
  }' 2>/dev/null || true

aws iam attach-role-policy --role-name smartfit-presign-role \
  --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole 2>/dev/null || true

# Inline-Policy: darf NUR in uploads/ schreiben
cat > /tmp/policy-presign.json <<POL
{"Version":"2012-10-17","Statement":[
  {"Effect":"Allow","Action":["s3:PutObject","s3:PutObjectAcl"],"Resource":["arn:aws:s3:::$BUCKET/uploads/*"]}
]}
POL
aws iam put-role-policy --role-name smartfit-presign-role --policy-name smartfit-presign-inline \
  --policy-document file:///tmp/policy-presign.json

ROLE_ARN="arn:aws:iam::$ACCOUNT_ID:role/smartfit-presign-role"

# 2) Lambda paketieren & deployen
mkdir -p lambda/build/presign
cp lambda/presign.py lambda/build/presign/
pip3 install -q -t lambda/build/presign boto3
( cd lambda/build/presign && zip -qr ../presign.zip . )

aws lambda create-function --function-name "$PRESIGN_FN" \
  --runtime python3.12 --handler presign.lambda_handler \
  --role "$ROLE_ARN" \
  --environment Variables="{BUCKET=$BUCKET}" \
  --zip-file fileb://lambda/build/presign.zip 2>/dev/null || \
aws lambda update-function-code --function-name "$PRESIGN_FN" --zip-file fileb://lambda/build/presign.zip

# 3) HTTP API mit Route /presign
API_ID=$(aws apigatewayv2 create-api --name "$API_NAME" --protocol-type HTTP \
  --query 'ApiId' --output text 2>/dev/null || true)
if [ -z "$API_ID" ]; then
  API_ID=$(aws apigatewayv2 get-apis --query "Items[?Name=='$API_NAME'].ApiId" --output text)
fi

INT_ID=$(aws apigatewayv2 create-integration --api-id $API_ID --integration-type AWS_PROXY \
  --integration-uri arn:aws:lambda:$REGION:$ACCOUNT_ID:function:$PRESIGN_FN \
  --payload-format-version 2.0 --integration-method POST --query 'IntegrationId' --output text)

aws apigatewayv2 create-route --api-id $API_ID --route-key "POST /presign" \
  --target integrations/$INT_ID >/dev/null 2>&1 || true

aws lambda add-permission --function-name "$PRESIGN_FN" --statement-id allow-apigw-presign \
  --action lambda:InvokeFunction --principal apigateway.amazonaws.com \
  --source-arn "arn:aws:execute-api:$REGION:$ACCOUNT_ID:$API_ID/*/POST/presign" >/dev/null 2>&1 || true

API_URL=$(aws apigatewayv2 get-api --api-id $API_ID --query 'ApiEndpoint' --output text)
echo "✓ Presign-API: $API_URL/presign"
