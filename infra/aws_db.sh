#!/usr/bin/env bash
set -euo pipefail

# ==== .env robust laden ====
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SEARCH_DIR="$SCRIPT_DIR"

# Suche .env nach oben, bis Root erreicht ist
while [[ "$SEARCH_DIR" != "/" && ! -f "$SEARCH_DIR/.env" ]]; do
  SEARCH_DIR="$(dirname "$SEARCH_DIR")"
done

ENV_FILE="$SEARCH_DIR/.env"

if [[ -f "$ENV_FILE" ]]; then
  set -o allexport
  # shellcheck disable=SC1090
  . "$ENV_FILE"
  set +o allexport
  echo "[INFO] .env geladen: $ENV_FILE"
else
  echo "[WARN] .env nicht gefunden – nutze aktuelle ENV"
fi


# ===== Defaults =====
AWS_PROFILE="${AWS_PROFILE:-default}"
AWS_REGION="${AWS_REGION:-us-east-1}"
STACK_PREFIX="${STACK_PREFIX:-smartfit}"
DB_INSTANCE_NAME="${DB_INSTANCE_NAME:-${STACK_PREFIX}-db}"
DB_SG_NAME="${DB_SG_NAME:-${STACK_PREFIX}-db-sg}"
DB_INSTANCE_TYPE="${DB_INSTANCE_TYPE:-t3.micro}"
DB_NAME="${DB_NAME:-smartfit}"
DB_USER="${DB_USER:-smartfit_admin}"
DB_PASS="${DB_PASS:-Riethuesli>12345}"
AMI_PARAM="/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64"

# ===== Checks =====
for v in AWS_PROFILE AWS_REGION STACK_PREFIX DB_NAME DB_USER DB_PASS; do
  [[ -z "${!v:-}" ]] && echo "[ERR] fehlende Variable: $v" >&2 && exit 1
done

# ===== Default VPC/Subnet =====
# ===== Default VPC =====
VPC_ID=$(aws ec2 describe-vpcs --region "$AWS_REGION" --profile "$AWS_PROFILE" \
  --filters Name=isDefault,Values=true --query "Vpcs[0].VpcId" --output text)
[[ -z "$VPC_ID" || "$VPC_ID" == "None" ]] && { echo "[ERR] Keine Default VPC."; exit 1; }

# ===== AZ finden, die den Instance-Typ unterstützt =====
AZS=$(aws ec2 describe-instance-type-offerings \
  --region "$AWS_REGION" --profile "$AWS_PROFILE" \
  --location-type availability-zone \
  --filters Name=instance-type,Values="$DB_INSTANCE_TYPE" \
  --query "InstanceTypeOfferings[].Location" --output text)

SUBNET_ID=""
for az in $AZS; do
  cand=$(aws ec2 describe-subnets --region "$AWS_REGION" --profile "$AWS_PROFILE" \
    --filters Name=vpc-id,Values="$VPC_ID" Name=availability-zone,Values="$az" \
    --query "Subnets[?DefaultForAz==\`true\`][0].SubnetId" --output text)
  [[ -z "$cand" || "$cand" == "None" ]] && cand=$(aws ec2 describe-subnets --region "$AWS_REGION" --profile "$AWS_PROFILE" \
    --filters Name=vpc-id,Values="$VPC_ID" Name=availability-zone,Values="$az" \
    --query "Subnets[0].SubnetId" --output text)
  if [[ -n "$cand" && "$cand" != "None" ]]; then SUBNET_ID="$cand"; SELECTED_AZ="$az"; break; fi
done
[[ -z "$SUBNET_ID" ]] && { echo "[ERR] Kein passendes Subnet für $DB_INSTANCE_TYPE gefunden."; exit 1; }
echo "[INFO] Verwende Subnet $SUBNET_ID in AZ $SELECTED_AZ (unterstützt $DB_INSTANCE_TYPE)"


# ===== DB SG (nur intern, Port 5432 – Ingress-Berechtigung folgt im Web-Script) =====
DB_SG_ID=$(aws ec2 describe-security-groups --region "$AWS_REGION" --profile "$AWS_PROFILE" \
  --filters Name=group-name,Values="$DB_SG_NAME" Name=vpc-id,Values="$VPC_ID" \
  --query "SecurityGroups[0].GroupId" --output text 2>/dev/null || true)
if [[ -z "$DB_SG_ID" || "$DB_SG_ID" == "None" ]]; then
  DB_SG_ID=$(aws ec2 create-security-group --region "$AWS_REGION" --profile "$AWS_PROFILE" \
    --group-name "$DB_SG_NAME" --description "SmartFit DB SG" --vpc-id "$VPC_ID" \
    --query "GroupId" --output text)
  echo "[INFO] DB SG erstellt: $DB_SG_ID"
else
  echo "[INFO] DB SG reuse: $DB_SG_ID"
fi

# ===== Reuse Instance? =====
EXIST_ID=$(aws ec2 describe-instances --region "$AWS_REGION" --profile "$AWS_PROFILE" \
  --filters Name=tag:Name,Values="$DB_INSTANCE_NAME" Name=instance-state-name,Values=pending,running,stopping,stopped \
  --query "Reservations[0].Instances[0].InstanceId" --output text 2>/dev/null || true)
if [[ -n "$EXIST_ID" && "$EXIST_ID" != "None" ]]; then
  PRIV=$(aws ec2 describe-instances --instance-ids "$EXIST_ID" --region "$AWS_REGION" --profile "$AWS_PROFILE" \
    --query "Reservations[0].Instances[0].PrivateIpAddress" --output text)
  DNS=$(aws ec2 describe-instances --instance-ids "$EXIST_ID" --region "$AWS_REGION" --profile "$AWS_PROFILE" \
    --query "Reservations[0].Instances[0].PublicDnsName" --output text)
  echo "=== DB bereit (reuse) ===
Name       : $DB_INSTANCE_NAME
InstanceId : $EXIST_ID
Private IP : $PRIV
Public DNS : $DNS
DB         : $DB_NAME (User: $DB_USER)
DB SG ID   : $DB_SG_ID"
  exit 0
fi

# ===== AMI =====
AMI_ID=$(aws ssm get-parameter --name "$AMI_PARAM" --region "$AWS_REGION" --profile "$AWS_PROFILE" \
  --query Parameter.Value --output text)

# ===== User-Data (Postgres + Schema) =====
UD=$(cat <<'EOT'
#!/bin/bash
set -euxo pipefail
dnf -y update
dnf -y install postgresql15 postgresql15-server postgresql15-contrib curl

/usr/bin/postgresql-setup --initdb
sed -i "s/^#listen_addresses.*/listen_addresses = '*'/" /var/lib/pgsql/data/postgresql.conf

# VPC-CIDR für interne Auth
curl -s http://169.254.169.254/latest/meta-data/network/interfaces/macs/ > /tmp/macs
MAC=$(head -n1 /tmp/macs)
VPC_CIDR=$(curl -s "http://169.254.169.254/latest/meta-data/network/interfaces/macs/${MAC}/vpc-ipv4-cidr-block")
echo "host    all             all             ${VPC_CIDR}            md5" >> /var/lib/pgsql/data/pg_hba.conf

systemctl enable --now postgresql

sudo -u postgres psql -v ON_ERROR_STOP=1 <<'SQL'
CREATE USER __DB_USER__ WITH PASSWORD '__DB_PASS__';
DO $$BEGIN
   IF NOT EXISTS (SELECT FROM pg_database WHERE datname='__DB_NAME__') THEN
      CREATE DATABASE __DB_NAME__ OWNER __DB_USER__;
   END IF;
END$$;

\c __DB_NAME__
CREATE EXTENSION IF NOT EXISTS citext;

CREATE TABLE IF NOT EXISTS users (
  id BIGSERIAL PRIMARY KEY,
  username TEXT NOT NULL UNIQUE,
  email TEXT NOT NULL UNIQUE,
  created_at TIMESTAMPTZ DEFAULT now(),
  preferences JSONB
);

CREATE TABLE IF NOT EXISTS items (
  id BIGSERIAL PRIMARY KEY,
  user_id BIGINT REFERENCES users(id) ON DELETE CASCADE,
  image_path TEXT,
  category TEXT,
  color_name TEXT,
  color_hex TEXT CHECK (color_hex ~ '^#([0-9A-Fa-f]{6})$'),
  waterproof BOOLEAN,
  warmth TEXT CHECK (warmth IN ('summer','transition','winter')),
  formality TEXT CHECK (formality IN ('casual','business','party')),
  tags JSONB,
  ai_confidence REAL CHECK (ai_confidence BETWEEN 0 AND 1),
  created_at TIMESTAMPTZ DEFAULT now(),
  updated_at TIMESTAMPTZ DEFAULT now()
);

CREATE TABLE IF NOT EXISTS outfits (
  id BIGSERIAL PRIMARY KEY,
  user_id BIGINT REFERENCES users(id) ON DELETE CASCADE,
  name TEXT NOT NULL,
  description TEXT,
  weather_tag TEXT,
  color_focus TEXT,
  formality TEXT,
  created_by_ai BOOLEAN DEFAULT false,
  created_at TIMESTAMPTZ DEFAULT now(),
  updated_at TIMESTAMPTZ DEFAULT now()
);

-- sicherstellen: outfit_items hat image_path
ALTER TABLE IF EXISTS outfit_items ADD COLUMN IF NOT EXISTS image_path TEXT;

CREATE TABLE IF NOT EXISTS outfit_items (
  id BIGSERIAL PRIMARY KEY,
  outfit_id BIGINT REFERENCES outfits(id) ON DELETE CASCADE,
  item_id BIGINT REFERENCES items(id) ON DELETE CASCADE,
  role TEXT CHECK (role IN ('top','bottom','shoes','outerwear')),
  image_path TEXT,
  UNIQUE (outfit_id, item_id)
);

CREATE TABLE IF NOT EXISTS prompts (
  id BIGSERIAL PRIMARY KEY,
  user_id BIGINT REFERENCES users(id) ON DELETE CASCADE,
  raw_text TEXT NOT NULL,
  parsed_json JSONB,
  created_at TIMESTAMPTZ DEFAULT now(),
  related_outfit_id BIGINT REFERENCES outfits(id) ON DELETE SET NULL
);

CREATE TABLE IF NOT EXISTS settings (
  id BIGSERIAL PRIMARY KEY,
  key TEXT UNIQUE NOT NULL,
  value TEXT,
  updated_at TIMESTAMPTZ DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_items_user ON items(user_id);
CREATE INDEX IF NOT EXISTS idx_items_filters ON items(formality, category, waterproof);
CREATE INDEX IF NOT EXISTS idx_items_color ON items(color_name, color_hex);
CREATE INDEX IF NOT EXISTS idx_items_tags_gin ON items USING GIN (tags);
CREATE INDEX IF NOT EXISTS idx_prompts_user ON prompts(user_id);
CREATE INDEX IF NOT EXISTS idx_outfits_user ON outfits(user_id);
SQL
EOT
)


UD="${UD//__DB_NAME__/$DB_NAME}"
UD="${UD//__DB_USER__/$DB_USER}"
DB_PASS_ESC=${DB_PASS//\'/\'\"\'\"\'}
UD="${UD//__DB_PASS__/$DB_PASS_ESC}"

# ===== Start EC2 =====
NET_IF="DeviceIndex=0,SubnetId=${SUBNET_ID},AssociatePublicIpAddress=true,Groups=${DB_SG_ID}"
ARGS=( --image-id "$AMI_ID" --instance-type "$DB_INSTANCE_TYPE"
  --network-interfaces "$NET_IF"
  --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=${DB_INSTANCE_NAME}}]"
  --user-data "$UD"
)
[[ -n "${SSH_KEY_NAME:-}" ]] && ARGS+=( --key-name "$SSH_KEY_NAME" )

IID=$(aws ec2 run-instances --region "$AWS_REGION" --profile "$AWS_PROFILE" \
  "${ARGS[@]}" --query "Instances[0].InstanceId" --output text)
aws ec2 wait instance-status-ok --instance-ids "$IID" --region "$AWS_REGION" --profile "$AWS_PROFILE"

PRIV=$(aws ec2 describe-instances --instance-ids "$IID" --region "$AWS_REGION" --profile "$AWS_PROFILE" \
  --query "Reservations[0].Instances[0].PrivateIpAddress" --output text)
DNS=$(aws ec2 describe-instances --instance-ids "$IID" --region "$AWS_REGION" --profile "$AWS_PROFILE" \
  --query "Reservations[0].Instances[0].PublicDnsName" --output text)

echo "=== DB bereit ===
Name       : $DB_INSTANCE_NAME
InstanceId : $IID
Private IP : $PRIV
Public DNS : $DNS
DB         : $DB_NAME (User: $DB_USER)
DB SG ID   : $DB_SG_ID"
