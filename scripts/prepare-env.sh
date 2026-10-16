#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
TARGET="$ROOT/.local/backend.env"
if [ -e "$TARGET" ]; then
  echo 'The local backend environment already exists; it has not been overwritten.'
  exit 0
fi
install -d -m 700 "$ROOT/.local"
umask 077
{
  sed '/^JWT_SECRET=/d' "$ROOT/examples/backend.env.example"
  printf '\nJWT_SECRET=%s\n' "$(openssl rand -hex 48)"
} > "$TARGET"
echo 'Created .local/backend.env with a random JWT secret. Complete the Supabase username and passwords locally.'
