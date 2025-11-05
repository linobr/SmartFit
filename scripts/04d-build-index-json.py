#!/usr/bin/env python3
import os, sys, json, boto3
BUCKET = os.environ.get("BUCKET"); REGION = os.environ.get("REGION","us-east-1")
USER_ID = sys.argv[1] if len(sys.argv)>1 else "1"
LIMIT = int(sys.argv[2]) if len(sys.argv)>2 else 20

s3 = boto3.client("s3", region_name=REGION)
prefix = f"uploads/{USER_ID}/"
objs = []
kwargs = {"Bucket": BUCKET, "Prefix": prefix}
while True:
    r = s3.list_objects_v2(**kwargs)
    for o in r.get("Contents", []):
        k=o["Key"]
        if k.endswith("/"): continue
        objs.append({"key":k,"lm":o["LastModified"].isoformat(),"size":o["Size"]})
    if r.get("IsTruncated"):
        kwargs["ContinuationToken"]=r["NextContinuationToken"]
    else: break

objs.sort(key=lambda x:x["lm"], reverse=True)
data={"user": USER_ID, "items": objs[:LIMIT]}
os.makedirs("web", exist_ok=True)
with open("web/uploads.json","w",encoding="utf-8") as f: json.dump(data,f)
print(f"Wrote web/uploads.json with {len(data['items'])} items")

items=[]
for o in objs[:LIMIT]:
    url = s3.generate_presigned_url(
        "get_object",
        Params={"Bucket": BUCKET, "Key": o["key"]},
        ExpiresIn=900
    )
    items.append({"key":o["key"],"lm":o["lm"],"size":o["size"],"url":url})
data={"user": USER_ID, "items": items}
with open("web/uploads.json","w",encoding="utf-8") as f:
    json.dump(data, f)
print(f"Wrote web/uploads.json with {len(data['items'])} items (with presigned URLs)")
