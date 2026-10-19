#!/usr/bin/env bash
# Run once by the operator. The application Terraform must not own its own state bucket.
set -euo pipefail
ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
PROFILE=${AWS_PROFILE:-attendance-terraform}
BACKEND="$ROOT/infra/backend.tf"
BUCKET=$(awk -F '"' '/^[[:space:]]*bucket[[:space:]]*=/ {print $2}' "$BACKEND")
REGION=$(awk -F '"' '/^[[:space:]]*region[[:space:]]*=/ {print $2}' "$BACKEND")
EXPECTED_ACCOUNT=$(jq -er '.aws_account_id' "$ROOT/infra/team.auto.tfvars.json")
[[ "$BUCKET" =~ ^[a-z0-9][a-z0-9.-]{1,61}[a-z0-9]$ && "$REGION" =~ ^[a-z]{2}-[a-z]+-[0-9]+$ ]]
AWS=(aws --profile "$PROFILE" --region "$REGION" --no-cli-pager)
ACCOUNT=$("${AWS[@]}" sts get-caller-identity --query Account --output text)
if [ "$ACCOUNT" != "$EXPECTED_ACCOUNT" ]; then
  echo "Expected AWS account $EXPECTED_ACCOUNT; selected profile belongs to $ACCOUNT." >&2
  exit 1
fi

install -d -m 700 "$ROOT/.local"
ERROR_FILE=$(mktemp "$ROOT/.local/state-bucket-error.XXXXXX")
trap 'unlink "$ERROR_FILE"' EXIT
if "${AWS[@]}" s3api head-bucket --bucket "$BUCKET" --expected-bucket-owner "$ACCOUNT" 2> "$ERROR_FILE"; then
  echo "Using existing state bucket: $BUCKET"
elif grep -Eq '\(404\)|NoSuchBucket|Not Found' "$ERROR_FILE"; then
  if [ "$REGION" = us-east-1 ]; then
    "${AWS[@]}" s3api create-bucket --bucket "$BUCKET" > /dev/null
  else
    "${AWS[@]}" s3api create-bucket --bucket "$BUCKET" \
      --create-bucket-configuration "LocationConstraint=$REGION" > /dev/null
  fi
  echo "Created state bucket: $BUCKET"
else
  echo 'Cannot verify the state bucket. No bucket was created; check ownership and permissions.' >&2
  cat "$ERROR_FILE" >&2
  exit 1
fi

"${AWS[@]}" s3api put-public-access-block --bucket "$BUCKET" --expected-bucket-owner "$ACCOUNT" \
  --public-access-block-configuration '{"BlockPublicAcls":true,"IgnorePublicAcls":true,"BlockPublicPolicy":true,"RestrictPublicBuckets":true}'
"${AWS[@]}" s3api put-bucket-ownership-controls --bucket "$BUCKET" --expected-bucket-owner "$ACCOUNT" \
  --ownership-controls '{"Rules":[{"ObjectOwnership":"BucketOwnerEnforced"}]}'
"${AWS[@]}" s3api put-bucket-versioning --bucket "$BUCKET" --expected-bucket-owner "$ACCOUNT" \
  --versioning-configuration Status=Enabled
"${AWS[@]}" s3api put-bucket-encryption --bucket "$BUCKET" --expected-bucket-owner "$ACCOUNT" \
  --server-side-encryption-configuration '{"Rules":[{"ApplyServerSideEncryptionByDefault":{"SSEAlgorithm":"AES256"},"BucketKeyEnabled":false}]}'
POLICY=$(jq -n --arg bucket "$BUCKET" '{
  Version: "2012-10-17",
  Statement: [{Sid: "DenyInsecureTransport", Effect: "Deny", Principal: "*", Action: "s3:*",
    Resource: ["arn:aws:s3:::" + $bucket, "arn:aws:s3:::" + $bucket + "/*"],
    Condition: {Bool: {"aws:SecureTransport": "false"}}}]
}')
"${AWS[@]}" s3api put-bucket-policy --bucket "$BUCKET" --expected-bucket-owner "$ACCOUNT" --policy "$POLICY"
"${AWS[@]}" s3api put-bucket-tagging --bucket "$BUCKET" --expected-bucket-owner "$ACCOUNT" \
  --tagging '{"TagSet":[{"Key":"Project","Value":"attendance"},{"Key":"Purpose","Value":"terraform-state"}]}'
echo 'State bucket ready: private, versioned, encrypted and HTTPS-only.'
echo 'This script did not create EC2 instances, migrate state or grant access to other users.'
