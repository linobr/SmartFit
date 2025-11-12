#!/usr/bin/env bash
set -euo pipefail

# ===== .env laden (optional) =====
ENV_FILE="${ENV_FILE:-$(cd "$(dirname "$0")/.." && pwd)/.env}"
if [[ -f "$ENV_FILE" ]]; then
  set -o allexport; . "$ENV_FILE"; set +o allexport
  echo "[INFO] .env geladen: $ENV_FILE"
else
  echo "[WARN] .env fehlt: $ENV_FILE"
fi

# ===== Defaults =====
AWS_PROFILE="${AWS_PROFILE:-default}"
AWS_REGION="${AWS_REGION:-us-east-1}"
STACK_PREFIX="${STACK_PREFIX:-smartfit}"

WEB_INSTANCE_NAME="${WEB_INSTANCE_NAME:-${STACK_PREFIX}-web}"
WEB_SG_NAME="${WEB_SG_NAME:-${STACK_PREFIX}-web-sg}"
WEB_INSTANCE_TYPE="${WEB_INSTANCE_TYPE:-t3.micro}"

DB_INSTANCE_NAME="${DB_INSTANCE_NAME:-${STACK_PREFIX}-db}"
DB_SG_NAME="${DB_SG_NAME:-${STACK_PREFIX}-db-sg}"
DB_NAME="${DB_NAME:-smartfit}"
DB_USER="${DB_USER:-smartfit_admin}"
DB_PASS="${DB_PASS:-}"

MY_IP_CIDR="${MY_IP_CIDR:-}"
[[ -z "$MY_IP_CIDR" ]] && MY_IP_CIDR="$(curl -s https://checkip.amazonaws.com)/32"

UPLOAD_MAX_MB="${UPLOAD_MAX_MB:-10}"
UPLOAD_MAX_MB_NUM="$(printf '%s\n' "$UPLOAD_MAX_MB" | tr -cd '0-9')"
[[ -z "$UPLOAD_MAX_MB_NUM" ]] && UPLOAD_MAX_MB_NUM=10
POST_MAX_MB=$((UPLOAD_MAX_MB_NUM + 2))

AMI_PARAM="/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64"

# ===== Required Vars =====
for v in AWS_PROFILE AWS_REGION STACK_PREFIX DB_NAME DB_USER DB_PASS; do
  [[ -z "${!v:-}" ]] && echo "[ERR] fehlende Variable: $v" >&2 && exit 1
done

# ===== Default VPC + AZ/Subnet =====
VPC_ID=$(aws ec2 describe-vpcs --region "$AWS_REGION" --profile "$AWS_PROFILE" \
  --filters Name=isDefault,Values=true --query "Vpcs[0].VpcId" --output text)
[[ -z "$VPC_ID" || "$VPC_ID" == "None" ]] && { echo "[ERR] Keine Default VPC."; exit 1; }

AZS=$(aws ec2 describe-instance-type-offerings \
  --region "$AWS_REGION" --profile "$AWS_PROFILE" \
  --location-type availability-zone \
  --filters Name=instance-type,Values="$WEB_INSTANCE_TYPE" \
  --query "InstanceTypeOfferings[].Location" --output text)

SUBNET_ID=""; SELECTED_AZ=""
for az in $AZS; do
  cand=$(aws ec2 describe-subnets --region "$AWS_REGION" --profile "$AWS_PROFILE" \
    --filters Name=vpc-id,Values="$VPC_ID" Name=availability-zone,Values="$az" \
    --query "Subnets[?DefaultForAz==\`true\`][0].SubnetId" --output text)
  [[ -z "$cand" || "$cand" == "None" ]] && cand=$(aws ec2 describe-subnets --region "$AWS_REGION" --profile "$AWS_PROFILE" \
    --filters Name=vpc-id,Values="$VPC_ID" Name=availability-zone,Values="$az" \
    --query "Subnets[0].SubnetId" --output text)
  if [[ -n "$cand" && "$cand" != "None" ]]; then
    SUBNET_ID="$cand"; SELECTED_AZ="$az"; break
  fi
done
[[ -z "$SUBNET_ID" ]] && { echo "[ERR] Kein passendes Subnet für $WEB_INSTANCE_TYPE gefunden."; exit 1; }
echo "[INFO] Verwende Subnet $SUBNET_ID in AZ $SELECTED_AZ (unterstützt $WEB_INSTANCE_TYPE)"

# ===== Web SG =====
WEB_SG_ID=$(aws ec2 describe-security-groups --region "$AWS_REGION" --profile "$AWS_PROFILE" \
  --filters Name=group-name,Values="$WEB_SG_NAME" Name=vpc-id,Values="$VPC_ID" \
  --query "SecurityGroups[0].GroupId" --output text 2>/dev/null || true)
if [[ -z "$WEB_SG_ID" || "$WEB_SG_ID" == "None" ]]; then
  WEB_SG_ID=$(aws ec2 create-security-group --region "$AWS_REGION" --profile "$AWS_PROFILE" \
    --group-name "$WEB_SG_NAME" --description "SmartFit Web SG" --vpc-id "$VPC_ID" \
    --query "GroupId" --output text)
  aws ec2 authorize-security-group-ingress --region "$AWS_REGION" --profile "$AWS_PROFILE" \
    --group-id "$WEB_SG_ID" \
    --ip-permissions "IpProtocol=tcp,FromPort=80,ToPort=80,IpRanges=[{CidrIp=0.0.0.0/0,Description=HTTP}]"
  aws ec2 authorize-security-group-ingress --region "$AWS_REGION" --profile "$AWS_PROFILE" \
    --group-id "$WEB_SG_ID" \
    --ip-permissions "IpProtocol=tcp,FromPort=22,ToPort=22,IpRanges=[{CidrIp=${MY_IP_CIDR},Description=SSH}]"
  echo "[INFO] Web SG erstellt: $WEB_SG_ID"
else
  echo "[INFO] Web SG reuse: $WEB_SG_ID"
fi

# ===== DB Instance + SG Lookup =====
DB_ID=$(aws ec2 describe-instances \
  --region "$AWS_REGION" --profile "$AWS_PROFILE" \
  --filters Name=tag:Name,Values="$DB_INSTANCE_NAME" Name=instance-state-name,Values=running,pending,stopped,stopping \
  --query "Reservations[0].Instances[0].InstanceId" --output text)
[[ -z "$DB_ID" || "$DB_ID" == "None" ]] && { echo "[ERR] DB-Instance '$DB_INSTANCE_NAME' nicht gefunden."; exit 1; }

DB_AZ=$(aws ec2 describe-instances --region "$AWS_REGION" --profile "$AWS_PROFILE" \
  --instance-ids "$DB_ID" --query "Reservations[0].Instances[0].Placement.AvailabilityZone" --output text)

DB_DNS=$(aws ec2 describe-instances --region "$AWS_REGION" --profile "$AWS_PROFILE" \
  --instance-ids "$DB_ID" --query "Reservations[0].Instances[0].PublicDnsName" --output text)

DB_PRIVATE_IP=$(aws ec2 describe-instances --region "$AWS_REGION" --profile "$AWS_PROFILE" \
  --instance-ids "$DB_ID" --query "Reservations[0].Instances[0].PrivateIpAddress" --output text)

DB_SG_ID=$(aws ec2 describe-instances --region "$AWS_REGION" --profile "$AWS_PROFILE" \
  --instance-ids "$DB_ID" --query "Reservations[0].Instances[0].SecurityGroups[0].GroupId" --output text)
if [[ -z "$DB_SG_ID" || "$DB_SG_ID" == "None" ]]; then
  DB_SG_ID=$(aws ec2 describe-security-groups --region "$AWS_REGION" --profile "$AWS_PROFILE" \
    --filters Name=group-name,Values="$DB_SG_NAME" Name=vpc-id,Values="$VPC_ID" \
    --query "SecurityGroups[0].GroupId" --output text 2>/dev/null || true)
fi
[[ -z "$DB_SG_ID" || "$DB_SG_ID" == "None" ]] && { echo "[ERR] DB Security Group nicht gefunden."; exit 1; }

echo "DB_ID=$DB_ID  DB_AZ=$DB_AZ  DB_DNS=$DB_DNS  DB_PRIV=$DB_PRIVATE_IP  DB_SG_ID=$DB_SG_ID"

# ===== Erlaube Web -> DB (5432) =====
aws ec2 authorize-security-group-ingress --region "$AWS_REGION" --profile "$AWS_PROFILE" \
  --group-id "$DB_SG_ID" \
  --ip-permissions "IpProtocol=tcp,FromPort=5432,ToPort=5432,UserIdGroupPairs=[{GroupId=${WEB_SG_ID},Description=Web-DB}]" \
  >/dev/null || true

# ===== AMI =====
AMI_ID=$(aws ssm get-parameter --name "$AMI_PARAM" --region "$AWS_REGION" --profile "$AWS_PROFILE" \
  --query Parameter.Value --output text)

# ===== User-Data (Apache/PHP + Mini-App mit DB-Fallback) =====
DB_PASS_ESC=${DB_PASS//\'/\'\"\'\"\'}

UD=$(cat <<'EOF'
#!/bin/bash
set -euxo pipefail

# --- Pakete robust installieren ---
attempt=0
until dnf -y makecache && dnf -y install httpd php php-pgsql php-cli; do
  attempt=$((attempt+1))
  if [ "$attempt" -ge 3 ]; then
    echo "DNF Install (Web) nach 3 Versuchen fehlgeschlagen" >&2
    exit 1
  fi
  sleep 5
done

# --- PHP Limits ---
echo "upload_max_filesize=__UPLOAD_MAX_MB__M" > /etc/php.d/99-smartfit.ini
echo "post_max_size=__POST_MAX_MB__M" >> /etc/php.d/99-smartfit.ini

# --- Webroot vorbereiten ---
mkdir -p /var/www/html/uploads
chown -R apache:apache /var/www/html
chmod 775 /var/www/html/uploads

# --- Warten, bis die DB (TCP) erreichbar ist (max ~2 min) ---
DB_HOST="__DB_PRIVATE_IP__"
for i in {1..120}; do
  if timeout 1 bash -c "cat < /dev/null > /dev/tcp/${DB_HOST}/5432" 2>/dev/null; then
    break
  fi
  sleep 1
done

# --- db.php (ohne e()-Helper; Fallback & Auto-Create wenn CREATEDB-Recht) ---
cat >/var/www/html/db.php <<'PHP'
<?php
$host = '__DB_PRIVATE_IP__';
$db   = '__DB_NAME__';
$user = '__DB_USER__';
$pass = '__DB_PASS_ESC__';

function pdo_connect($host,$db,$user,$pass){
  return new PDO("pgsql:host=$host;port=5432;dbname=$db", $user, $pass, [
    PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION,
    PDO::ATTR_DEFAULT_FETCH_MODE => PDO::FETCH_ASSOC
  ]);
}

try {
  $pdo = pdo_connect($host,$db,$user,$pass);
} catch (Throwable $e) {
  $msg = (string)$e->getMessage();
  if (stripos($msg, 'database "' . $db . '" does not exist') !== false) {
    try {
      $pdoAdmin = pdo_connect($host,'postgres',$user,$pass);
      $exists = $pdoAdmin->prepare("SELECT 1 FROM pg_database WHERE datname = :d");
      $exists->execute([':d'=>$db]);
      if (!$exists->fetchColumn()) {
        try { $pdoAdmin->exec("CREATE DATABASE ".$db); }
        catch (Throwable $ce) {
          http_response_code(500);
          echo "DB-Fehler: Datenbank '".htmlspecialchars($db, ENT_QUOTES, 'UTF-8')."' fehlt und konnte nicht automatisch erstellt werden. ".
               "Bitte gib dem Benutzer '".htmlspecialchars($user, ENT_QUOTES, 'UTF-8')."' das Recht CREATEDB oder erstelle die DB serverseitig.<br><small>"
               .htmlspecialchars($ce->getMessage(), ENT_QUOTES, 'UTF-8')."</small>";
          exit;
        }
      }
      $pdo = pdo_connect($host,$db,$user,$pass);
    } catch (Throwable $e2) {
      http_response_code(500);
      echo "DB-Fehler: ".htmlspecialchars($e2->getMessage(), ENT_QUOTES, 'UTF-8');
      exit;
    }
  } else {
    http_response_code(500);
    echo "DB-Fehler: ".htmlspecialchars($msg, ENT_QUOTES, 'UTF-8');
    exit;
  }
}
PHP

# --- Helpers ---
cat >/var/www/html/includes.php <<'PHP'
<?php
function e(string $s): string { return htmlspecialchars($s, ENT_QUOTES, 'UTF-8'); }
function allowed_mimes(): array { return ['image/jpeg'=>['jpg','jpeg'],'image/png'=>['png'],'image/webp'=>['webp']]; }
function detect_mime(string $tmp): string { $f=new finfo(FILEINFO_MIME_TYPE); return $f->file($tmp)?:'application/octet-stream'; }
PHP

# --- App: Upload ---
cat >/var/www/html/index.php <<'PHP'
<?php require __DIR__.'/db.php'; require __DIR__.'/includes.php';
$msg="";
if ($_SERVER['REQUEST_METHOD']==='POST' && isset($_FILES['image']) && $_FILES['image']['error']===UPLOAD_ERR_OK) {
  $f=$_FILES['image']; $mime=detect_mime($f['tmp_name']); $allowed=allowed_mimes();
  if (!isset($allowed[$mime])) $msg="Nur JPEG/PNG/WEBP";
  else { $ext=strtolower(pathinfo($f['name'], PATHINFO_EXTENSION));
    if (!in_array($ext, $allowed[$mime], true)) $msg="Endung passt nicht zum MIME";
    else {
      $stored=bin2hex(random_bytes(8))."-".time().".$ext";
      if (move_uploaded_file($f['tmp_name'], __DIR__."/uploads/".$stored)) {
        $pdo->prepare("INSERT INTO items (user_id,image_path,created_at,updated_at) VALUES (NULL,:p,NOW(),NOW())")
            ->execute([':p'=>"/uploads/".$stored]);
        $msg="Upload ok";
      } else $msg="Upload fehlgeschlagen";
} } }
?>
<!doctype html><meta charset="utf-8"><title>SmartFit Upload</title>
<link rel="stylesheet" href="https://unpkg.com/mvp.css">
<main>
<header><h2>SmartFit · Upload</h2><nav><a href="/index.php">Upload</a><a href="/gallery.php">Galerie</a><a href="/health.php">Health</a></nav></header>
<?php if ($msg!==""): ?><p><mark><?=e($msg)?></mark></p><?php endif; ?>
<form method="post" enctype="multipart/form-data">
  <label>Bild (JPEG/PNG/WEBP, max __UPLOAD_MAX_MB__MB)
    <input type="file" name="image" accept=".jpg,.jpeg,.png,.webp,image/jpeg,image/png,image/webp" required>
  </label>
  <button>Hochladen</button>
</form>
</main>
PHP

# --- App: Galerie ---
cat >/var/www/html/gallery.php <<'PHP'
<?php require __DIR__.'/db.php'; require __DIR__.'/includes.php';
$rows=$pdo->query("SELECT id,image_path,created_at FROM items ORDER BY created_at DESC LIMIT 200")->fetchAll();
?>
<!doctype html><meta charset="utf-8"><title>SmartFit Galerie</title>
<link rel="stylesheet" href="https://unpkg.com/mvp.css">
<main>
<header><h2>SmartFit · Galerie</h2><nav><a href="/index.php">Upload</a><a href="/gallery.php" class="active">Galerie</a><a href="/health.php">Health</a></nav></header>
<?php if (!$rows): ?><p>Noch keine Bilder.</p><?php else: ?><section>
<?php foreach ($rows as $r): ?>
  <figure><img src="<?=e($r['image_path'])?>" style="max-width:260px;height:auto;border-radius:8px;border:1px solid #222">
  <figcaption>#<?= (int)$r['id'] ?> · <?= e(substr((string)$r['created_at'],0,16)) ?></figcaption></figure>
<?php endforeach; ?>
</section><?php endif; ?>
</main>
PHP

# --- Health: zeigt den aktuellen DB-Namen ---
cat >/var/www/html/health.php <<'PHP'
<?php
require __DIR__.'/db.php';
try {
  $ok = $pdo->query("SELECT current_database() db")->fetchColumn();
  echo "OK: DB-Verbindung erfolgreich (".htmlspecialchars($ok, ENT_QUOTES,'UTF-8').")";
} catch (Throwable $e) {
  http_response_code(500);
  echo "Health-Fehler: ".htmlspecialchars($e->getMessage(), ENT_QUOTES,'UTF-8');
}
PHP

# --- Redirect auf /index.php ---
cat >/var/www/html/index.html <<'HTML'
<!doctype html><meta http-equiv="refresh" content="0; url=/index.php">
HTML

# --- Apache starten ---
systemctl enable --now httpd
EOF
)

# Platzhalter ersetzen
UD="${UD//__DB_PRIVATE_IP__/$DB_PRIVATE_IP}"
UD="${UD//__DB_NAME__/$DB_NAME}"
UD="${UD//__DB_USER__/$DB_USER}"
UD="${UD//__DB_PASS_ESC__/$DB_PASS_ESC}"
UD="${UD//__UPLOAD_MAX_MB__/$UPLOAD_MAX_MB_NUM}"
UD="${UD//__POST_MAX_MB__/$POST_MAX_MB}"

# ===== EC2 starten =====
NET_IF="DeviceIndex=0,SubnetId=${SUBNET_ID},AssociatePublicIpAddress=true,Groups=${WEB_SG_ID}"
ARGS=( --image-id "$AMI_ID" --instance-type "$WEB_INSTANCE_TYPE"
  --network-interfaces "$NET_IF"
  --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=${WEB_INSTANCE_NAME}}]"
  --user-data "$UD"
)
[[ -n "${SSH_KEY_NAME:-}" ]] && ARGS+=( --key-name "$SSH_KEY_NAME" )

IID=$(aws ec2 run-instances --region "$AWS_REGION" --profile "$AWS_PROFILE" \
  "${ARGS[@]}" --query "Instances[0].InstanceId" --output text)

aws ec2 wait instance-status-ok --instance-ids "$IID" --region "$AWS_REGION" --profile "$AWS_PROFILE"

DNS=$(aws ec2 describe-instances --instance-ids "$IID" --region "$AWS_REGION" --profile "$AWS_PROFILE" \
  --query "Reservations[0].Instances[0].PublicDnsName" --output text)

echo "=== Web/File bereit ===
Name       : $WEB_INSTANCE_NAME
InstanceId : $IID
URL Upload : http://$DNS/
URL Galerie: http://$DNS/gallery.php
Health     : http://$DNS/health.php
DB Private : $DB_PRIVATE_IP
SG Regeln  : 80 Welt, 22 ${MY_IP_CIDR}; DB 5432 nur Web-DB"
