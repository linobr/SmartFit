#!/usr/bin/env python3
import os, sys, boto3, html, time
from urllib.parse import quote

BUCKET = os.environ.get("BUCKET")
REGION = os.environ.get("REGION", "us-east-1")
WEB_BUCKET = os.environ.get("WEB_BUCKET")
USER_ID = sys.argv[1] if len(sys.argv) > 1 else "1"
EXPIRES = int(sys.argv[2]) if len(sys.argv) > 2 else 900  # Sekunden

if not BUCKET or not WEB_BUCKET:
    print("BUCKET/WEB_BUCKET not set in env (.env)", file=sys.stderr); sys.exit(2)

s3 = boto3.client("s3", region_name=REGION)

# 1) Objekte listen
prefix = f"uploads/{USER_ID}/"
keys = []
kwargs = {"Bucket": BUCKET, "Prefix": prefix}
while True:
    resp = s3.list_objects_v2(**kwargs)
    for o in resp.get("Contents", []):
        k = o["Key"]
        if k.endswith("/") or k.lower().endswith(".json"):  # filtern falls nötig
            continue
        keys.append((k, o["LastModified"], o["Size"]))
    if resp.get("IsTruncated"):
        kwargs["ContinuationToken"] = resp["NextContinuationToken"]
    else:
        break

# Neueste zuerst
keys.sort(key=lambda x: x[1], reverse=True)

# 2) Presigned GET URLs
items = []
for k, lm, sz in keys[:100]:
    url = s3.generate_presigned_url(
        "get_object", Params={"Bucket": BUCKET, "Key": k}, ExpiresIn=EXPIRES
    )
    items.append({"key": k, "url": url, "lm": lm, "size": sz})

# 3) HTML schreiben (lokal nach web/gallery.html)
os.makedirs("web", exist_ok=True)
with open("web/gallery.html", "w", encoding="utf-8") as f:
    f.write("""<!doctype html>
<html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>SmartFit – Galerie</title>
<style>
body{font-family:system-ui,sans-serif;max-width:960px;margin:30px auto;padding:0 12px}
.grid{display:grid;grid-template-columns:repeat(auto-fill,minmax(180px,1fr));gap:12px}
.card{border:1px solid #e5e7eb;border-radius:10px;padding:8px}
.card img{max-width:100%;height:160px;object-fit:cover;border-radius:8px}
.meta{font-size:12px;color:#6b7280;word-break:break-all}
.top{display:flex;justify-content:space-between;align-items:center;margin-bottom:12px}
a.btn{padding:8px 10px;border:1px solid #e5e7eb;border-radius:8px;text-decoration:none}
</style></head><body>
<div class="top"><h1>SmartFit – Galerie (User """ + html.escape(USER_ID) + """)</h1>
<a class="btn" href="index.html">⬅ Upload</a></div>
<p>Links laufen nach """ + str(EXPIRES) + """ Sekunden ab – Seite dann neu laden.</p>
<div class="grid">
""")
    for it in items:
        f.write(
            '<div class="card">'
            f'<a href="{html.escape(it["url"])}" target="_blank">'
            f'<img src="{html.escape(it["url"])}" alt="{html.escape(it["key"])}"></a>'
            f'<div class="meta">{html.escape(it["key"])}<br>'
            f'{it["lm"]} · {it["size"]} bytes</div></div>\n'
        )
    f.write("</div></body></html>")

print(f"Wrote web/gallery.html with {len(items)} items")
