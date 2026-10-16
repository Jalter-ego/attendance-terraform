#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
URL=$(terraform -chdir="$ROOT/infra" output -raw frontend_url)
FRONTEND_IP=$(terraform -chdir="$ROOT/infra" output -raw frontend_ip)
TENANT_URL="http://demo.${FRONTEND_IP//./-}.sslip.io"
curl --fail --silent --show-error --noproxy '*' "$URL/" > /dev/null
curl --fail --silent --show-error --noproxy '*' "$URL/login" > /dev/null
curl --fail --silent --show-error --noproxy '*' "$URL/core/api/v1" > /dev/null
curl --fail --silent --show-error --noproxy '*' "$TENANT_URL/login" > /dev/null
curl --fail --silent --show-error --noproxy '*' "$TENANT_URL/core/api/v1" > /dev/null
echo "Frontend, SPA routing and API proxy respond at $URL"
echo "Tenant hostname and API proxy respond at $TENANT_URL"
echo 'Log in with a tenant and account that already exist in Supabase.'
