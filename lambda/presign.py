import json, os
import boto3

s3 = boto3.client("s3")
BUCKET = os.environ.get("BUCKET")

def lambda_handler(event, ctx):
    body = json.loads(event.get("body") or "{}")
    user_id = str(body.get("user_id", 1))
    file_name = body.get("file_name")
    content_type = body.get("content_type", "image/jpeg")

    if not file_name:
        return {"statusCode": 400, "body": json.dumps({"error": "file_name required"})}

    key = f"uploads/{user_id}/{file_name}"
    url = s3.generate_presigned_url(
        "put_object",
        Params={"Bucket": BUCKET, "Key": key, "ContentType": content_type},
        ExpiresIn=900
    )
    return {
        "statusCode": 200,
        "headers": {"Content-Type": "application/json"},
        "body": json.dumps({"upload_url": url, "key": key})
    }
