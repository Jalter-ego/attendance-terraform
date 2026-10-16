#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
SCOPE=${1:-all}
case "$SCOPE" in
  all|--frontend-only) ;;
  *) echo 'Usage: ./scripts/deploy.sh [--frontend-only]' >&2; exit 1 ;;
esac
FRONTEND_SOURCE=${ATTENDANCE_FRONTEND_SOURCE:-$ROOT/../attendance}
BACKEND_SOURCE=${ATTENDANCE_BACKEND_SOURCE:-$ROOT/../attendance_core}
FRONTEND_REF=${ATTENDANCE_FRONTEND_REF:-origin/master}
BACKEND_REF=${ATTENDANCE_BACKEND_REF:-origin/master}
KEY=${ATTENDANCE_SSH_KEY:-$ROOT/.local/ssh/attendance-terraform}
BACKEND_ENV=${ATTENDANCE_BACKEND_ENV:-$ROOT/.local/backend.env}
if [ "$SCOPE" = all ] && [ ! -f "$BACKEND_ENV" ]; then
  echo 'Create .local/backend.env with ./scripts/prepare-env.sh and complete the Supabase credentials.' >&2
  exit 1
fi
if [ "$SCOPE" = all ]; then chmod 600 "$BACKEND_ENV"; fi
OUTPUT=$(terraform -chdir="$ROOT/infra" output -json)
FRONTEND_IP=$(jq -er '.frontend_ip.value' <<< "$OUTPUT")
BACKEND_IP=$(jq -er '.backend_ip.value' <<< "$OUTPUT")
BACKEND_PRIVATE_IP=$(jq -er '.backend_private_ip.value' <<< "$OUTPUT")
for ip in "$FRONTEND_IP" "$BACKEND_IP" "$BACKEND_PRIVATE_IP"; do
  if [[ ! "$ip" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then echo 'Invalid instance IP' >&2; exit 1; fi
done
FRONTEND_BASE_DOMAIN="${FRONTEND_IP//./-}.sslip.io"
FRONTEND_SHA=$(git -C "$FRONTEND_SOURCE" rev-parse --verify --end-of-options "$FRONTEND_REF^{commit}")
install -d -m 700 "$ROOT/.local/packages"
SSH_OPTIONS=(-i "$KEY" -o IdentitiesOnly=yes -o ConnectTimeout=10
  -o StrictHostKeyChecking=accept-new -o "UserKnownHostsFile=$ROOT/.local/known_hosts")

wait_for_instance() {
  local ip=$1
  for attempt in $(seq 1 90); do
    if ssh "${SSH_OPTIONS[@]}" "ubuntu@$ip" true 2>/dev/null; then
      ssh "${SSH_OPTIONS[@]}" "ubuntu@$ip" \
        'sudo timeout 1200 cloud-init status --wait; sudo test -f /var/lib/attendance/bootstrap.ready'
      return
    fi
    sleep 5
  done
  echo "SSH is not available at $ip. Check the allowed /32, instance status and bootstrap logs." >&2
  return 1
}

if [ "$SCOPE" = all ]; then
  BACKEND_SHA=$(git -C "$BACKEND_SOURCE" rev-parse --verify --end-of-options "$BACKEND_REF^{commit}")
  echo "Preparing backend commit $BACKEND_SHA"
  git -C "$BACKEND_SOURCE" archive --format=tar.gz \
    --output="$ROOT/.local/packages/backend-$BACKEND_SHA.tgz" "$BACKEND_SHA"
  wait_for_instance "$BACKEND_IP"
  scp "${SSH_OPTIONS[@]}" "$ROOT/.local/packages/backend-$BACKEND_SHA.tgz" \
    "ubuntu@$BACKEND_IP:/tmp/attendance-backend-$BACKEND_SHA.tgz"
  scp "${SSH_OPTIONS[@]}" "$BACKEND_ENV" "ubuntu@$BACKEND_IP:.attendance-backend.env"
  scp "${SSH_OPTIONS[@]}" "$ROOT/scripts/remote/configure-env.cjs" \
    "ubuntu@$BACKEND_IP:/tmp/attendance-configure-env.cjs"
  ssh "${SSH_OPTIONS[@]}" "ubuntu@$BACKEND_IP" "bash -s -- $BACKEND_SHA" \
    < "$ROOT/scripts/remote/deploy-backend.sh"
fi

echo "Preparing frontend commit $FRONTEND_SHA"
git -C "$FRONTEND_SOURCE" archive --format=tar.gz \
  --output="$ROOT/.local/packages/frontend-$FRONTEND_SHA.tgz" "$FRONTEND_SHA"
wait_for_instance "$FRONTEND_IP"
scp "${SSH_OPTIONS[@]}" "$ROOT/.local/packages/frontend-$FRONTEND_SHA.tgz" \
  "ubuntu@$FRONTEND_IP:/tmp/attendance-frontend-$FRONTEND_SHA.tgz"
ssh "${SSH_OPTIONS[@]}" "ubuntu@$FRONTEND_IP" "bash -s -- $FRONTEND_SHA $BACKEND_PRIVATE_IP $FRONTEND_BASE_DOMAIN" \
  < "$ROOT/scripts/remote/deploy-frontend.sh"

if [ "$SCOPE" = all ]; then
  jq -n --arg frontend "$FRONTEND_SHA" --arg backend "$BACKEND_SHA" \
    '{frontend_commit: $frontend, backend_commit: $backend}' > "$ROOT/.local/releases.json"
else
  RELEASES='{}'
  if [ -f "$ROOT/.local/releases.json" ]; then RELEASES=$(cat "$ROOT/.local/releases.json"); fi
  jq --arg frontend "$FRONTEND_SHA" '.frontend_commit = $frontend' \
    <<< "$RELEASES" > "$ROOT/.local/releases.json"
fi
echo "Deployment ready at http://demo.$FRONTEND_BASE_DOMAIN/ (tenant demo must exist in Supabase)"
echo "Access by IP: http://$FRONTEND_IP/"
