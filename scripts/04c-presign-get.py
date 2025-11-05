#!/usr/bin/env python3
import os, sys, boto3
if len(sys.argv) < 3:
    print("Usage: scripts/04c-presign-get.py <user_id> <filename>", file=sys.stderr); exit(1)
bucket=os.environ.get("BUCKET"); region=os.environ.get("REGION","us-east-1")
user, name = sys.argv[1], sys.argv[2]
key=f"uploads/{user}/{name}"
s3=boto3.client("s3", region_name=region)
print(s3.generate_presigned_url("get_object", Params={"Bucket":bucket,"Key":key}, ExpiresIn=900))
