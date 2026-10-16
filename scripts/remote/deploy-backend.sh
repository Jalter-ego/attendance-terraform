#!/usr/bin/env bash
set -euo pipefail
SHA=${1:?Commit is required}
[[ "$SHA" =~ ^[a-f0-9]{40}$ ]]
ENV_INPUT="$HOME/.attendance-backend.env"
trap 'if [ -f "$ENV_INPUT" ]; then unlink "$ENV_INPUT"; fi' EXIT
test -f "$ENV_INPUT"
chmod 600 "$ENV_INPUT"
RELEASE="/opt/attendance/releases/backend-$SHA"
mkdir -p "$RELEASE"
tar -xzf "/tmp/attendance-backend-$SHA.tgz" -C "$RELEASE"
cd "$RELEASE"
NODE_ENV=development pnpm install --frozen-lockfile
node /tmp/attendance-configure-env.cjs "$RELEASE" "$ENV_INPUT"
pnpm build

sudo node /tmp/attendance-configure-env.cjs "$RELEASE" "$ENV_INPUT" /etc/attendance/backend.env
sudo bash -s -- "$RELEASE" <<'ROOT_SCRIPT'
set -euo pipefail
ln -sfnT "$1" /opt/attendance/backend-current
cat > /etc/systemd/system/attendance-backend.service <<'SERVICE'
[Unit]
Description=Attendance NestJS API
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=ubuntu
Group=ubuntu
WorkingDirectory=/opt/attendance/backend-current
EnvironmentFile=/etc/attendance/backend.env
ExecStart=/usr/local/bin/node dist/src/main.js
Restart=on-failure
RestartSec=5
NoNewPrivileges=true
PrivateTmp=true
UMask=0027

[Install]
WantedBy=multi-user.target
SERVICE
systemctl daemon-reload
systemctl enable attendance-backend
systemctl restart attendance-backend
ROOT_SCRIPT

for attempt in $(seq 1 45); do
  if curl --fail --silent http://127.0.0.1:5000/core/api/v1 > /dev/null; then
    echo "Backend ready: $SHA"
    exit 0
  fi
  sleep 2
done
echo 'API did not become healthy. Inspect: sudo journalctl -u attendance-backend' >&2
exit 1
