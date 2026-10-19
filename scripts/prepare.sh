#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
PROFILE=${AWS_PROFILE:-attendance-terraform}
REGION=$(jq -er '.aws_region' "$ROOT/infra/team.auto.tfvars.json")
EXPECTED_ACCOUNT=$(jq -er '.aws_account_id' "$ROOT/infra/team.auto.tfvars.json")
ACCOUNT=$(aws sts get-caller-identity --profile "$PROFILE" --query Account --output text --no-cli-pager)
if [ "$ACCOUNT" != "$EXPECTED_ACCOUNT" ]; then
  echo "Expected AWS account $EXPECTED_ACCOUNT; the selected profile belongs to $ACCOUNT." >&2
  exit 1
fi
NAME=$(jq -er '.deployment_name' "$ROOT/infra/team.auto.tfvars.json")
KEY="$ROOT/.local/ssh/attendance-terraform"

if [ -e "$ROOT/infra/lab.auto.tfvars.json" ]; then
  echo 'An old personal infra/lab.auto.tfvars.json exists. Back it up under .local/ before joining the shared environment.' >&2
  exit 1
fi
if [ -e "$ROOT/infra/terraform.tfvars" ] || [ -e "$ROOT/infra/terraform.tfvars.json" ]; then
  echo 'Remove personal Terraform variable overrides before joining the shared environment.' >&2
  exit 1
fi
install -d -m 700 "$ROOT/.local" "$ROOT/.local/ssh"
if [ ! -f "$KEY" ]; then
  ssh-keygen -t ed25519 -N '' -C "$NAME-$(id -un)" -f "$KEY"
fi
if [ ! -f "$KEY.pub" ]; then ssh-keygen -y -f "$KEY" > "$KEY.pub"; fi
chmod 600 "$KEY"

echo "Prepared personal access for $NAME in $REGION using AWS profile $PROFILE."
echo 'Shared variables have not been changed. Share only the .pub key with the operator when SSH access is needed.'
echo "Next: export AWS_PROFILE=$PROFILE; terraform -chdir=infra init"
