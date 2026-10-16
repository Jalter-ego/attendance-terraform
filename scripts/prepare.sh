#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
PROFILE=${AWS_PROFILE:-attendance-terraform}
REGION=$(aws configure get region --profile "$PROFILE")
: "${REGION:?Configure a region in your AWS CLI profile first}"
ACCOUNT=$(aws sts get-caller-identity --profile "$PROFILE" --query Account --output text --no-cli-pager)
IP=$(curl --fail --silent --show-error --retry 3 https://checkip.amazonaws.com)
NAME=${ATTENDANCE_DEPLOYMENT:-attendance-tf-$(id -un)}
KEY="$ROOT/.local/ssh/attendance-terraform"

if [ -e "$ROOT/infra/lab.auto.tfvars.json" ]; then
  echo 'Local configuration already exists. Edit infra/lab.auto.tfvars.json to change it.'
  exit 1
fi
install -d -m 700 "$ROOT/.local" "$ROOT/.local/ssh"
if [ ! -f "$KEY" ]; then
  ssh-keygen -t ed25519 -N '' -C "$NAME-operator" -f "$KEY"
fi
if [ ! -f "$KEY.pub" ]; then ssh-keygen -y -f "$KEY" > "$KEY.pub"; fi
chmod 600 "$KEY"

umask 077
jq -n --arg profile "$PROFILE" --arg region "$REGION" --arg account "$ACCOUNT" \
  --arg name "$NAME" --arg cidr "$IP/32" '{
    aws_profile: $profile, aws_region: $region, aws_account_id: $account,
    deployment_name: $name, ssh_allowed_cidr: $cidr,
    ssh_public_key_path: "../.local/ssh/attendance-terraform.pub", instance_type: "t3.small"
  }' > "$ROOT/infra/lab.auto.tfvars.json"
echo "Prepared $NAME in $REGION. No AWS resources have been created."
