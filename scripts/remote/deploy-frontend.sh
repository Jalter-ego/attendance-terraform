#!/usr/bin/env bash
set -euo pipefail
SHA=${1:?Commit is required}
BACKEND_IP=${2:?Backend private IP is required}
BASE_DOMAIN=${3:?Frontend tenant base domain is required}
[[ "$SHA" =~ ^[a-f0-9]{40}$ && "$BACKEND_IP" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ && "$BASE_DOMAIN" =~ ^[0-9]+-[0-9]+-[0-9]+-[0-9]+\.sslip\.io$ ]]
RELEASE="/opt/attendance/releases/frontend-$SHA"
mkdir -p "$RELEASE"
tar -xzf "/tmp/attendance-frontend-$SHA.tgz" -C "$RELEASE"
cd "$RELEASE"
NODE_ENV=development pnpm install --frozen-lockfile
VITE_API_URL=/core/api/v1 VITE_TENANT_BASE_DOMAIN="$BASE_DOMAIN" VITE_DEFAULT_TENANT=demo pnpm build

sudo install -d "/var/www/attendance/releases/$SHA"
sudo cp -a dist/. "/var/www/attendance/releases/$SHA/"
sudo ln -sfnT "/var/www/attendance/releases/$SHA" /var/www/attendance/current
sudo tee /etc/nginx/sites-available/attendance > /dev/null <<'NGINX'
server {
    listen 80 default_server;
    server_name _;
    root /var/www/attendance/current;
    index index.html;
    client_max_body_size 25m;

    location /core/api/v1 {
        proxy_pass http://@BACKEND_IP@:5000;
        proxy_http_version 1.1;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }

    location / {
        try_files $uri $uri/ /index.html;
    }
}
NGINX
sudo sed -i "s/@BACKEND_IP@/$BACKEND_IP/g" /etc/nginx/sites-available/attendance
if [ -L /etc/nginx/sites-enabled/default ]; then sudo unlink /etc/nginx/sites-enabled/default; fi
sudo ln -sfn /etc/nginx/sites-available/attendance /etc/nginx/sites-enabled/attendance
sudo nginx -t
sudo systemctl reload nginx
curl --fail --silent --show-error --retry 5 --retry-connrefused --retry-delay 2 http://127.0.0.1/ > /dev/null
curl --fail --silent --show-error --retry 5 --retry-connrefused --retry-delay 2 http://127.0.0.1/core/api/v1 > /dev/null
echo "Frontend ready: $SHA"
