#!/usr/bin/env python3
import os, sys, json, os.path, mimetypes, boto3
if len(sys.argv) < 3:
    print("Usage: scripts/03c-presign-local.py <user_id> <local-file-name> [content-type]", file=sys.stderr); exit(1)
user_id = str(sys.argv[1]); filename = os.path.basename(sys.argv[2])
content_type = sys.argv[3] if len(sys.argv) >= 4 else (mimetypes.guess_type(filename)[0] or "application/octet-stream")
bucket = os.environ.get("BUCKET"); region = os.environ.get("REGION", "us-east-1")
if not bucket: print("BUCKET not set in environment/.env", file=sys.stderr); exit(2)
key = f"uploads/{user_id}/{filename}"
s3 = boto3.client("s3", region_name=region)
url = s3.generate_presigned_url("put_object",
    Params={"Bucket": bucket, "Key": key, "ContentType": content_type},
    ExpiresIn=900)
print(url)
print(f"S3 key: {key}", file=sys.stderr)
print(f"Content-Type: {content_type}", file=sys.stderr)
