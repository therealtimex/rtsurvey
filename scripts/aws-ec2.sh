#!/bin/bash
# ==============================================================================
# rtCloud - AWS EC2 User-Data Script
# ==============================================================================
# Provisions a fresh Ubuntu 22.04 LTS EC2 instance with Docker and launches rtCloud.
#
# HOW TO USE:
#   1. In EC2 launch wizard: Advanced Details > User data > paste this entire script.
#   2. Choose Ubuntu Server 22.04 LTS (HVM) as the AMI.
#   3. Recommended: t3.medium (2 vCPU / 4 GB RAM) or larger with Keycloak.
#   4. Security Group: allow SSH (22), HTTP (80), HTTPS (443), Shiny (3838).
#
# Monitor progress:
#   ssh ubuntu@<instance-ip> sudo tail -f /var/log/rtsurvey-setup.log
#
# SSL: Configured post-boot via the app UI (Domain & SSL setup page).
#      A systemd path unit watches /opt/rtsurvey/ssl-trigger/request.json and
#      runs /opt/rtsurvey/ssl-issue.sh when the admin submits a domain.
# ==============================================================================

# ==============================================================================
# CONFIGURATION — Edit these values before pasting as user-data
# ==============================================================================

# --- Required ---
PROJECT_ID="rtsurvey"                        # Unique identifier (no spaces)
ADMIN_PASSWORD="admin"                        # rtCloud web admin password — change after first login

RTCLOUD_IMAGE="rtawebteam/rtcloud:survey-public"

# --- Domain + SSL: leave blank — configure via app UI after boot ---
# DOMAIN and LETSENCRYPT_EMAIL are set through the app UI, not here.

# --- Ports ---
APP_PORT="80"
SHINY_PORT="3838"

# --- Embedded Keycloak (built-in SSO) ---
# Requires domain + SSL to be configured via app UI after boot.
EMBED_KEYCLOAK="true"
KEYCLOAK_ADMIN_PASSWORD="${ADMIN_PASSWORD}"

# --- SSO (external OIDC — used only when EMBED_KEYCLOAK=false) ---
OIDC_ISSUER_URL=""
OIDC_CLIENT_ID=""
OIDC_CLIENT_SECRET=""
OIDC_DISCOVERY_URL=""
OIDC_AUTHORIZATION_ENDPOINT=""
OIDC_TOKEN_ENDPOINT=""
OIDC_USERINFO_ENDPOINT=""
OIDC_SCOPE="openid email"
OIDC_MOBILE_CLIENT_ID=""
OIDC_MOBILE_REDIRECT_URI=""
OPEN_REGISTRATION="true"

# --- Stata14 ---
STATA_ENABLED="false"
STATA_LICENSE_B64=""        # base64 of stata.lic (required when STATA_ENABLED=true)
#   How to encode:  base64 -w 0 stata.lic   (Linux) / base64 -i stata.lic   (macOS)

# --- Optional ---
TZ="Asia/Ho_Chi_Minh"
CSRF_VALIDATION_ENABLED="true"

# ==============================================================================
# END CONFIGURATION — Do not edit below this line
# ==============================================================================

set -euo pipefail
exec > >(tee /var/log/rtsurvey-setup.log) 2>&1
trap 'echo "ERROR: script failed at line $LINENO (exit $?)" >&2' ERR

# ------------------------------------------------------------------------------
# Helpers
# ------------------------------------------------------------------------------
normalize_bool() {
  local v="${1:-}"
  v="$(echo "$v" | tr '[:upper:]' '[:lower:]' | xargs)"
  case "$v" in
    true|1|yes|y) echo "true" ;;
    *) echo "false" ;;
  esac
}

mask() { [[ -n "${1:-}" ]] && echo "***" || echo ""; }

echo "============================================================"
echo " rtCloud AWS EC2 setup starting - $(date)"
echo "============================================================"

# Normalize booleans early
EMBED_KEYCLOAK="$(normalize_bool "${EMBED_KEYCLOAK:-true}")"
OPEN_REGISTRATION="$(normalize_bool "${OPEN_REGISTRATION:-true}")"
STATA_ENABLED="$(normalize_bool "${STATA_ENABLED:-false}")"

# Auto-generate blank passwords
MYSQL_PASSWORD="${MYSQL_PASSWORD:-admin}"
MYSQL_ROOT_PASSWORD="${MYSQL_ROOT_PASSWORD:-admin}"
ADMIN_PASSWORD="${ADMIN_PASSWORD:-admin}"
if [[ "${EMBED_KEYCLOAK}" == "true" && -z "${KEYCLOAK_ADMIN_PASSWORD:-}" ]]; then
  KEYCLOAK_ADMIN_PASSWORD="${ADMIN_PASSWORD}"
fi

# ==============================================================================
# 1. System update + Docker + Nginx
# ==============================================================================
echo "[1/7] Updating system and installing Docker and Nginx..."

export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y -qq \
  curl ca-certificates gnupg lsb-release ufw nginx openssl jq dnsutils

# Configure nginx immediately — waiting page active from the start
mkdir -p /var/www/html
rm -f /var/www/html/index.nginx-debian.html
cat > /var/www/html/waiting.html << 'WAITING_EOF'
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>rtCloud - Starting up</title>
  <style>
    * { margin: 0; padding: 0; box-sizing: border-box; }
    body {
      font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
      background: #f0f2f5;
      display: flex;
      align-items: center;
      justify-content: center;
      min-height: 100vh;
      color: #333;
    }
    .card {
      background: #fff;
      border-radius: 12px;
      padding: 48px 56px;
      text-align: center;
      box-shadow: 0 4px 24px rgba(0,0,0,0.08);
      max-width: 420px;
      width: 90%;
    }
    .spinner {
      width: 48px;
      height: 48px;
      border: 4px solid #e2e8f0;
      border-top-color: #3b82f6;
      border-radius: 50%;
      animation: spin 1s linear infinite;
      margin: 0 auto 28px;
    }
    @keyframes spin { to { transform: rotate(360deg); } }
    h1 { font-size: 1.35rem; font-weight: 600; color: #1a202c; margin-bottom: 10px; }
    p  { color: #64748b; font-size: 0.95rem; line-height: 1.6; }
    .note { margin-top: 20px; font-size: 0.82rem; color: #94a3b8; }
  </style>
</head>
<body>
  <div class="card">
    <div class="spinner"></div>
    <h1>Server is starting up</h1>
    <p>rtCloud is initializing. This may take a minute on first boot.</p>
    <p class="note">This page will reload automatically when ready.</p>
  </div>
  <script>
    setInterval(function () { window.location.reload(); }, 5000);
  </script>
</body>
</html>
WAITING_EOF

cat > /etc/nginx/sites-available/rtsurvey << 'NGINX_INIT_EOF'
server {
    listen 80 default_server;
    server_name _;

    root /var/www/html;

    location /.well-known/acme-challenge/ {
        root /var/www/html;
    }

    location = /waiting.html {
        internal;
    }

    location / {
        proxy_pass             http://127.0.0.1:8080;
        proxy_set_header       Host              $host;
        proxy_set_header       X-Real-IP         $remote_addr;
        proxy_set_header       X-Forwarded-For   $proxy_add_x_forwarded_for;
        proxy_set_header       X-Forwarded-Proto $scheme;
        proxy_connect_timeout  5s;
        proxy_read_timeout     120s;
        client_max_body_size   100M;
        proxy_intercept_errors on;
        error_page 502 503 504 /waiting.html;
    }
}
NGINX_INIT_EOF
rm -f /etc/nginx/sites-enabled/*
ln -sf /etc/nginx/sites-available/rtsurvey /etc/nginx/sites-enabled/rtsurvey
nginx -t && systemctl restart nginx
echo "  Nginx configured (waiting page active)."

# Add Docker's official GPG key
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg \
  | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
chmod a+r /etc/apt/keyrings/docker.gpg

# Add Docker repository
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
  https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" \
  > /etc/apt/sources.list.d/docker.list

apt-get update -qq
apt-get install -y -qq \
  docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

systemctl enable --now docker
echo "  Docker $(docker --version) installed."

# ==============================================================================
# 2. Write docker-compose.production.yml
# ==============================================================================
echo "[2/7] Writing docker-compose.production.yml..."

mkdir -p /opt/rtsurvey
cd /opt/rtsurvey

cat > docker-compose.production.yml << 'COMPOSE_EOF'
version: '3.8'

services:
  mysql:
    image: mysql:8.0
    container_name: ${COMPOSE_PROJECT_NAME:-rtsurvey}-mysql
    restart: ${RESTART_POLICY:-unless-stopped}
    command: --default-authentication-plugin=mysql_native_password --character-set-server=utf8 --collation-server=utf8_general_ci --sql-mode=NO_ENGINE_SUBSTITUTION

    environment:
      MYSQL_ROOT_PASSWORD: ${MYSQL_ROOT_PASSWORD}
      MYSQL_DATABASE: ${MYSQL_DATABASE:-smartsurvey}
      MYSQL_USER: ${MYSQL_USER:-smartsurvey}
      MYSQL_PASSWORD: ${MYSQL_PASSWORD}
      MYSQL_ROOT_HOST: '%'
      MYSQL_CHARSET: utf8mb4
      MYSQL_COLLATION: utf8mb4_unicode_ci

    volumes:
      - mysql_data:/var/lib/mysql
      - ./mysql-init:/docker-entrypoint-initdb.d

    networks:
      - rtsurvey-net

    healthcheck:
      test: ["CMD-SHELL", "mysqladmin ping -h localhost -u root -p$$MYSQL_ROOT_PASSWORD"]
      interval: 10s
      timeout: 5s
      retries: 5
      start_period: 30s

  rtsurvey:
    image: ${RTCLOUD_IMAGE:-rtawebteam/rtcloud:survey-public}
    container_name: ${COMPOSE_PROJECT_NAME:-rtsurvey}-app
    restart: ${RESTART_POLICY:-unless-stopped}
    entrypoint: ["/bin/entrypoint-production.sh"]

    depends_on:
      mysql:
        condition: service_healthy

    ports:
      - "127.0.0.1:${APP_PORT:-8080}:80"
      - "${SHINY_PORT:-3838}:3838"

    env_file:
      - .env

    volumes:
      - app_uploads:/var/www/html/smartsurvey/uploads
      - app_audios:/var/www/html/smartsurvey/audios
      - app_downloads:/var/www/html/smartsurvey/downloads
      - app_gallery:/var/www/html/smartsurvey/gallery
      - app_voicemail:/var/www/html/smartsurvey/voicemail
      - app_runtime:/var/www/html/smartsurvey/protected/runtime
      - app_v2_runtime:/var/www/html/smartsurvey/protected/modules/v2/runtime
      - app_cache:/var/www/html/smartsurvey/cache
      - app_tmp:/var/www/html/smartsurvey/tmp
      - app_analytics:/var/www/html/smartsurvey/analytics
      - app_aggregate:/var/www/html/smartsurvey/aggregate
      - app_converter:/var/www/html/smartsurvey/converter
      - shiny_data:/srv/shiny-server/smartsurvey
      - shiny_logs:/var/log/shiny-server
      - app_assets:/var/www/html/smartsurvey/assets
      - app_modules_survey_advance:/var/www/html/smartsurvey/protected/modules/survey-advance
      - app_modules_rtwork:/var/www/html/smartsurvey/protected/modules/rtwork
      - /opt/rtsurvey/ssl-trigger:/opt/rtsurvey/ssl-trigger

    networks:
      - rtsurvey-net

    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost/health"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 90s

    logging:
      driver: "json-file"
      options:
        max-size: "10m"
        max-file: "3"

  keycloak:
    image: quay.io/keycloak/keycloak:latest
    container_name: ${COMPOSE_PROJECT_NAME:-rtsurvey}-keycloak
    restart: ${RESTART_POLICY:-unless-stopped}
    profiles:
      - embed-keycloak
    command: start --import-realm

    environment:
      KC_BOOTSTRAP_ADMIN_USERNAME: ${KEYCLOAK_ADMIN_USER:-admin}
      KC_BOOTSTRAP_ADMIN_PASSWORD: ${KEYCLOAK_ADMIN_PASSWORD:-}
      KC_HTTP_ENABLED: "true"
      KC_HTTP_RELATIVE_PATH: /auth
      KC_PROXY_HEADERS: xforwarded
      KC_HOSTNAME: ${KC_HOSTNAME}
      KC_HOSTNAME_STRICT: "false"
      KC_DB: mysql
      KC_DB_URL_DATABASE: ${KEYCLOAK_DB:-keycloak}
      KC_DB_URL_HOST: mysql
      KC_DB_USERNAME: ${KEYCLOAK_DB_USER:-keycloak}
      KC_DB_PASSWORD: ${KEYCLOAK_DB_PASSWORD:-}

    volumes:
      - ./keycloak-import:/opt/keycloak/data/import

    ports:
      - "127.0.0.1:${KEYCLOAK_PORT:-8090}:8080"

    depends_on:
      mysql:
        condition: service_healthy

    networks:
      - rtsurvey-net

    healthcheck:
      test: ["CMD-SHELL", "(exec 3<>/dev/tcp/localhost/8080) 2>/dev/null && exit 0 || exit 1"]
      interval: 30s
      timeout: 10s
      retries: 10
      start_period: 120s

    logging:
      driver: "json-file"
      options:
        max-size: "10m"
        max-file: "3"

volumes:
  mysql_data:
    name: ${COMPOSE_PROJECT_NAME:-rtsurvey}_mysql_data
  app_uploads:
    name: ${COMPOSE_PROJECT_NAME:-rtsurvey}_uploads
  app_audios:
    name: ${COMPOSE_PROJECT_NAME:-rtsurvey}_audios
  app_downloads:
    name: ${COMPOSE_PROJECT_NAME:-rtsurvey}_downloads
  app_gallery:
    name: ${COMPOSE_PROJECT_NAME:-rtsurvey}_gallery
  app_voicemail:
    name: ${COMPOSE_PROJECT_NAME:-rtsurvey}_voicemail
  app_runtime:
    name: ${COMPOSE_PROJECT_NAME:-rtsurvey}_runtime
  app_v2_runtime:
    name: ${COMPOSE_PROJECT_NAME:-rtsurvey}_v2_runtime
  app_cache:
    name: ${COMPOSE_PROJECT_NAME:-rtsurvey}_cache
  app_tmp:
    name: ${COMPOSE_PROJECT_NAME:-rtsurvey}_tmp
  app_analytics:
    name: ${COMPOSE_PROJECT_NAME:-rtsurvey}_analytics
  app_aggregate:
    name: ${COMPOSE_PROJECT_NAME:-rtsurvey}_aggregate
  app_converter:
    name: ${COMPOSE_PROJECT_NAME:-rtsurvey}_converter
  shiny_data:
    name: ${COMPOSE_PROJECT_NAME:-rtsurvey}_shiny_data
  shiny_logs:
    name: ${COMPOSE_PROJECT_NAME:-rtsurvey}_shiny_logs
  app_assets:
    name: ${COMPOSE_PROJECT_NAME:-rtsurvey}_assets
  app_modules_survey_advance:
    name: ${COMPOSE_PROJECT_NAME:-rtsurvey}_modules_survey_advance
  app_modules_rtwork:
    name: ${COMPOSE_PROJECT_NAME:-rtsurvey}_modules_rtwork

networks:
  rtsurvey-net:
    name: ${COMPOSE_PROJECT_NAME:-rtsurvey}_network
    driver: bridge
COMPOSE_EOF

echo "  docker-compose.production.yml written."

# ==============================================================================
# 3. Write .env (HTTP-only, IP-based — same approach as Linode)
# ==============================================================================
echo "[3/7] Writing .env..."

# Detect public IP (AWS EC2 IMDSv2 metadata, with fallback)
_IMDS_TOKEN=$(curl -s -X PUT "http://169.254.169.254/latest/api/token" \
  -H "X-aws-ec2-metadata-token-ttl-seconds: 60" 2>/dev/null || true)
if [[ -n "${_IMDS_TOKEN}" ]]; then
  SERVER_IP=$(curl -s -H "X-aws-ec2-metadata-token: ${_IMDS_TOKEN}" \
    http://169.254.169.254/latest/meta-data/public-ipv4 2>/dev/null || true)
fi
SERVER_IP="${SERVER_IP:-$(curl -s --max-time 5 https://api.ipify.org 2>/dev/null || hostname -I | awk '{print $1}')}"
echo "  Server IP: ${SERVER_IP}"

KEYCLOAK_DB_PASS="admin"
KEYCLOAK_CLIENT_SECRET_GEN="admin"
KEYCLOAK_MOBILE_REDIRECT_URI="vn.rta.rtsurvey.auth://callback"

cat > .env << ENV_EOF
# Generated by AWS EC2 user-data script on $(date)

# Project
PROJECT_ID=${PROJECT_ID}
PROJECT_TYPE=rtsurvey
PROJECT_URL=${SERVER_IP}
SERVER_IP=${SERVER_IP}
PROJECT_PORT=80
HTTP_PROTOCOL=http

# Database
MYSQL_HOST=mysql
MYSQL_PORT=3306
MYSQL_DATABASE=${PROJECT_ID}
MYSQL_USER=${PROJECT_ID}
MYSQL_PASSWORD=${MYSQL_PASSWORD}
MYSQL_ROOT_PASSWORD=${MYSQL_ROOT_PASSWORD}

# Admin
ADMIN_PASSWORD=${ADMIN_PASSWORD}

# Ports (app bound to localhost — Nginx handles incoming traffic)
APP_PORT=8080
SHINY_PORT=3838
KEYCLOAK_PORT=8090

# Runtime
RUN_ENV=prod
RUN_MODE=admin
TZ=${TZ}
LOG_LEVEL=info

# Security
CSRF_VALIDATION_ENABLED=${CSRF_VALIDATION_ENABLED}
GII_ENABLED=false
OPEN_REGISTRATION=${OPEN_REGISTRATION}

# Docker
COMPOSE_PROJECT_NAME=rtsurvey
RESTART_POLICY=unless-stopped
RTCLOUD_IMAGE=${RTCLOUD_IMAGE}
DEPLOYMENT_MODEL=docker

# SSO mode
EMBED_KEYCLOAK=${EMBED_KEYCLOAK}
AUTH_PROVIDER=embedded-keycloak

# Stata14
STATA_ENABLED=${STATA_ENABLED}
LETSENCRYPT_EMAIL=info@rta.vn
STATA_BIN_PATH=/usr/bin/stata
STATA_LICENSE_B64=${STATA_LICENSE_B64:-}
ENV_EOF

if [[ "${EMBED_KEYCLOAK}" == "true" ]]; then
  cat >> .env << KC_EOF

# ----------------------------------------------------------------------------
# SSO - Embedded Keycloak
# ----------------------------------------------------------------------------
# Using server IP as placeholder -- ssl-issue.sh updates these after domain is set
OIDC_ISSUER_URL=http://${SERVER_IP}/auth/realms/rtsurvey
OIDC_CLIENT_ID=${PROJECT_ID}
OIDC_CLIENT_SECRET=${KEYCLOAK_CLIENT_SECRET_GEN}
OIDC_REDIRECT_URI=http://${SERVER_IP}/cpms/cpmsSite/auth
OIDC_DISCOVERY_URL=http://keycloak:8080/auth/realms/rtsurvey/.well-known/openid-configuration
OIDC_MOBILE_CLIENT_ID=${PROJECT_ID}
OIDC_MOBILE_REDIRECT_URI=${KEYCLOAK_MOBILE_REDIRECT_URI}

# Keycloak container config
KC_HOSTNAME=http://${SERVER_IP}/auth
KC_HEALTH_ENABLED=true
KEYCLOAK_ADMIN_USER=admin
KEYCLOAK_ADMIN_PASSWORD=${KEYCLOAK_ADMIN_PASSWORD}
KEYCLOAK_DB=keycloak
KEYCLOAK_DB_USER=keycloak
KEYCLOAK_DB_PASSWORD=${KEYCLOAK_DB_PASS}
KC_EOF
else
  OIDC_MOBILE_REDIRECT_URI_VALUE="${OIDC_MOBILE_REDIRECT_URI:-vn.rta.rtsurvey.auth://callback}"
  cat >> .env << OIDC_EOF

# ----------------------------------------------------------------------------
# SSO - Generic OIDC (external provider)
# ----------------------------------------------------------------------------
OIDC_ISSUER_URL=${OIDC_ISSUER_URL}
OIDC_CLIENT_ID=${OIDC_CLIENT_ID}
OIDC_CLIENT_SECRET=${OIDC_CLIENT_SECRET}
OIDC_REDIRECT_URI=http://${SERVER_IP}/cpms/cpmsSite/auth
OIDC_DISCOVERY_URL=${OIDC_DISCOVERY_URL}
OIDC_AUTHORIZATION_ENDPOINT=${OIDC_AUTHORIZATION_ENDPOINT}
OIDC_TOKEN_ENDPOINT=${OIDC_TOKEN_ENDPOINT}
OIDC_USERINFO_ENDPOINT=${OIDC_USERINFO_ENDPOINT}
OIDC_SCOPE=${OIDC_SCOPE}
OIDC_MOBILE_CLIENT_ID=${OIDC_MOBILE_CLIENT_ID:-${OIDC_CLIENT_ID}}
OIDC_MOBILE_REDIRECT_URI=${OIDC_MOBILE_REDIRECT_URI_VALUE}
OIDC_EOF
fi

chmod 600 .env
echo "  .env written (permissions: 600)."

echo ""
echo "=== SSO CONFIG ==="
if [[ "${EMBED_KEYCLOAK}" == "true" ]]; then
  echo "AUTH_PROVIDER=embedded-keycloak"
  echo "OIDC_ISSUER_URL=http://${SERVER_IP}/auth/realms/rtsurvey  (placeholder, updated after domain setup)"
  echo "OIDC_CLIENT_ID=${PROJECT_ID}"
  echo "OIDC_CLIENT_SECRET=$(mask "${KEYCLOAK_CLIENT_SECRET_GEN}")"
  echo "KC_HOSTNAME=http://${SERVER_IP}/auth  (placeholder, updated after domain setup)"
  echo "KEYCLOAK_ADMIN_PASSWORD=$(mask "${KEYCLOAK_ADMIN_PASSWORD}")"
else
  echo "AUTH_PROVIDER=oidc"
  echo "OIDC_ISSUER_URL=${OIDC_ISSUER_URL}"
  echo "OIDC_CLIENT_ID=${OIDC_CLIENT_ID}"
  echo "OIDC_CLIENT_SECRET=$(mask "${OIDC_CLIENT_SECRET:-}")"
fi
echo "=================="
echo ""

# ==============================================================================
# 4. Keycloak setup files (embed mode only)
# ==============================================================================
mkdir -p /opt/rtsurvey/mysql-init /opt/rtsurvey/keycloak-import

if [[ "${EMBED_KEYCLOAK}" == "true" ]]; then
  echo "  [Keycloak] Writing MySQL init script..."
  cat > /opt/rtsurvey/mysql-init/01-keycloak-db.sql << SQL_EOF
CREATE DATABASE IF NOT EXISTS \`keycloak\` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE USER IF NOT EXISTS 'keycloak'@'%' IDENTIFIED WITH mysql_native_password BY '${KEYCLOAK_DB_PASS}';
GRANT ALL PRIVILEGES ON \`keycloak\`.* TO 'keycloak'@'%';
FLUSH PRIVILEGES;
SQL_EOF

  echo "  [Keycloak] Writing realm import (realm=rtsurvey, client_id=${PROJECT_ID})..."
  cat > /opt/rtsurvey/keycloak-import/rtsurvey-realm.json << REALM_EOF
{
  "realm": "rtsurvey",
  "enabled": true,
  "ssoSessionIdleTimeout": 2592000,
  "ssoSessionMaxLifespan": 31536000,
  "sslRequired": "none",
  "registrationAllowed": false,
  "loginWithEmailAllowed": true,
  "clients": [
    {
      "clientId": "${PROJECT_ID}",
      "name": "${PROJECT_ID}",
      "enabled": true,
      "protocol": "openid-connect",
      "publicClient": true,
      "redirectUris": [
        "http://${SERVER_IP}/*",
        "vn.rta.rtsurvey.auth:/*",
        "vn.rta.rtsurvey.logout:/*"
      ],
      "webOrigins": [
        "http://${SERVER_IP}"
      ],
      "standardFlowEnabled": true,
      "directAccessGrantsEnabled": false,
      "serviceAccountsEnabled": false
    }
  ],
  "users": [
    {
      "username": "admin",
      "email": "admin@${PROJECT_ID}.local",
      "enabled": true,
      "credentials": [
        {
          "type": "password",
          "value": "${KEYCLOAK_ADMIN_PASSWORD}",
          "temporary": false
        }
      ],
      "realmRoles": ["offline_access", "uma_authorization"]
    }
  ]
}
REALM_EOF
  echo "  [Keycloak] Realm import file written."
fi

# ==============================================================================
# 5. Pull image and start services
# ==============================================================================
echo "[5/7] Pulling image and starting services..."
if [[ "${EMBED_KEYCLOAK}" == "true" ]]; then
  docker compose -f docker-compose.production.yml --profile embed-keycloak pull
  docker compose -f docker-compose.production.yml --profile embed-keycloak up -d
else
  docker compose -f docker-compose.production.yml pull
  docker compose -f docker-compose.production.yml up -d
fi
echo "  Services started."

echo "  Waiting for rtsurvey-app to be healthy before patching admin email..."
for i in $(seq 1 30); do
  STATUS=$(docker inspect --format='{{.State.Health.Status}}' rtsurvey-app 2>/dev/null || echo "missing")
  if [[ "${STATUS}" == "healthy" ]]; then break; fi
  echo "    waiting... (${i}/30)"
  sleep 10
done
PATCH_OK=false
for attempt in $(seq 1 5); do
  if docker exec rtsurvey-mysql mysql -u root -p"${MYSQL_ROOT_PASSWORD}" "${PROJECT_ID}" \
      -e "UPDATE ss_user SET email='admin@${PROJECT_ID}.local', use_pin_code=0 WHERE username='admin';"; then
    PATCH_OK=true; break
  fi
  echo "    DB patch attempt ${attempt}/5 failed, retrying in 5s..."
  sleep 5
done
if [[ "${PATCH_OK}" == "true" ]]; then
  echo "  Admin user email set to admin@${PROJECT_ID}.local (will update to domain after SSL setup)"
else
  echo "WARNING: Could not patch admin email -- set it manually after login." >&2
fi

# ==============================================================================
# 6. Nginx (HTTP-only) + SSL trigger setup
# ==============================================================================
echo "[6/7] Starting Nginx and setting up SSL trigger..."

# Create ssl-trigger dir and initial status file (container bind-mounts this)
mkdir -p /opt/rtsurvey/ssl-trigger
echo '{"status":"none","domain":""}' > /opt/rtsurvey/ssl-trigger/status.json
chmod 777 /opt/rtsurvey/ssl-trigger

systemctl enable nginx
systemctl is-active nginx && systemctl reload nginx || systemctl start nginx

# Install Certbot (used by ssl-issue.sh when admin chooses certbot type)
snap install --classic certbot
ln -sf /snap/bin/certbot /usr/bin/certbot

# --------------------------------------------------------------------------
# Write /opt/rtsurvey/ssl-issue.sh -- triggered by systemd when request.json changes
# --------------------------------------------------------------------------
cat > /opt/rtsurvey/ssl-issue.sh << 'SSLSCRIPT_EOF'
#!/bin/bash
set -euo pipefail
exec >> /var/log/rtsurvey-ssl.log 2>&1
echo "[$(date -u +%FT%TZ)] ssl-issue.sh triggered"

REQUEST=/opt/rtsurvey/ssl-trigger/request.json
STATUS=/opt/rtsurvey/ssl-trigger/status.json
ENV_FILE=/opt/rtsurvey/.env
COMPOSE_FILE=/opt/rtsurvey/docker-compose.production.yml

write_status() {
  local s="$1" extra="${2:-}"
  echo "{\"status\":\"${s}\",\"domain\":\"${DOMAIN}\",\"updated_at\":\"$(date -u +%FT%TZ)\"${extra}}" > "$STATUS"
}

[[ ! -f "$REQUEST" ]] && { echo "No request.json found"; exit 1; }

DOMAIN=$(jq -r .domain "$REQUEST")
TYPE=$(jq -r .type   "$REQUEST")
echo "  domain=${DOMAIN} type=${TYPE}"

write_status "pending"

# Load vars from .env
_env_val() { grep "^${1}=" "$ENV_FILE" | cut -d= -f2- | tr -d '\r'; }
EMBED_KEYCLOAK=$(_env_val EMBED_KEYCLOAK)
PROJECT_ID=$(_env_val PROJECT_ID)
MYSQL_ROOT_PASSWORD=$(_env_val MYSQL_ROOT_PASSWORD)
KEYCLOAK_ADMIN_PASSWORD=$(_env_val KEYCLOAK_ADMIN_PASSWORD)
LETSENCRYPT_EMAIL=$(jq -r '.email // empty' "$REQUEST")
[[ -z "$LETSENCRYPT_EMAIL" ]] && LETSENCRYPT_EMAIL=$(_env_val LETSENCRYPT_EMAIL)
KEYCLOAK_PORT=$(_env_val KEYCLOAK_PORT)
KEYCLOAK_PORT="${KEYCLOAK_PORT:-8090}"

update_env() {
  local key="$1" val="$2"
  if grep -q "^${key}=" "$ENV_FILE"; then
    sed -i "s|^${key}=.*|${key}=${val}|" "$ENV_FILE"
  else
    echo "${key}=${val}" >> "$ENV_FILE"
  fi
}

# ------------------------------------------------------------------------------
# SSL cert
# ------------------------------------------------------------------------------
CERT="" KEY="" PROTOCOL="https" PORT=443

if [[ "$TYPE" == "certbot" ]]; then
  if [[ -z "$LETSENCRYPT_EMAIL" ]]; then
    write_status "error" ",\"error\":\"email not provided\""
    exit 1
  fi

  # Wait for DNS to propagate before running certbot
  SERVER_IP_VAL=$(_env_val SERVER_IP)
  echo "  Waiting for DNS: $DOMAIN -> $SERVER_IP_VAL"
  DNS_MAX=900
  DNS_INTERVAL=30
  DNS_ELAPSED=0
  while true; do
    RESOLVED=$(dig +short "$DOMAIN" @8.8.8.8 2>/dev/null | tail -1)
    if [[ "$RESOLVED" == "$SERVER_IP_VAL" ]]; then
      echo "  DNS propagated: $DOMAIN -> $RESOLVED"
      break
    fi
    if [[ $DNS_ELAPSED -ge $DNS_MAX ]]; then
      write_status "error" ",\"error\":\"DNS not propagated after ${DNS_MAX}s -- $DOMAIN resolves to ${RESOLVED:-unresolved}, expected $SERVER_IP_VAL\""
      exit 1
    fi
    echo "  DNS not ready: $DOMAIN -> ${RESOLVED:-unresolved} (expected $SERVER_IP_VAL), retry in ${DNS_INTERVAL}s... ($DNS_ELAPSED/${DNS_MAX}s)"
    sleep $DNS_INTERVAL
    DNS_ELAPSED=$((DNS_ELAPSED + DNS_INTERVAL))
  done

  if ! certbot certonly --webroot -w /var/www/html -n --agree-tos \
      -m "$LETSENCRYPT_EMAIL" -d "$DOMAIN"; then
    write_status "error" ",\"error\":\"certbot failed -- check DNS points to this server\""
    exit 1
  fi

  CERT="/etc/letsencrypt/live/${DOMAIN}/fullchain.pem"
  KEY="/etc/letsencrypt/live/${DOMAIN}/privkey.pem"

elif [[ "$TYPE" == "rtsurvey" ]]; then
  # *.rtsurvey.com -- Cloudflare terminates SSL, origin serves HTTP only
  PROTOCOL="https"
  PORT=443
fi

# ------------------------------------------------------------------------------
# Nginx final config
# ------------------------------------------------------------------------------
KC_BLOCK=""
if [[ "${EMBED_KEYCLOAK}" == "true" ]]; then
  KC_BLOCK='    location /auth/ {
        proxy_pass              http://127.0.0.1:8090/auth/;
        proxy_set_header        Host              $host;
        proxy_set_header        X-Real-IP         $remote_addr;
        proxy_set_header        X-Forwarded-For   $proxy_add_x_forwarded_for;
        proxy_set_header        X-Forwarded-Proto $scheme;
        proxy_buffer_size       128k;
        proxy_buffers           4 256k;
        proxy_busy_buffers_size 256k;
        proxy_read_timeout      120s;
    }'
fi

if [[ "$TYPE" == "certbot" ]]; then
  cat > /etc/nginx/sites-available/rtsurvey << NGINX_EOF
server {
    listen 80;
    server_name ${DOMAIN};
    return 301 https://\$host\$request_uri;
}

server {
    listen 443 ssl;
    server_name ${DOMAIN};

    ssl_certificate     ${CERT};
    ssl_certificate_key ${KEY};
    ssl_protocols       TLSv1.2 TLSv1.3;
    ssl_ciphers         ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384:ECDHE-ECDSA-CHACHA20-POLY1305:ECDHE-RSA-CHACHA20-POLY1305:DHE-RSA-AES128-GCM-SHA256:DHE-RSA-AES256-GCM-SHA384;
    ssl_prefer_server_ciphers off;

${KC_BLOCK}
    location / {
        proxy_pass         http://127.0.0.1:8080;
        proxy_set_header   Host              \$host;
        proxy_set_header   X-Real-IP         \$remote_addr;
        proxy_set_header   X-Forwarded-For   \$proxy_add_x_forwarded_for;
        proxy_set_header   X-Forwarded-Proto \$scheme;
        proxy_read_timeout 120s;
        client_max_body_size 100M;
    }
}
NGINX_EOF

elif [[ "$TYPE" == "rtsurvey" ]]; then
  # Cloudflare proxy -- origin serves HTTP, Cloudflare handles HTTPS
  # Keep ACME challenge path so switching to certbot later still works
  cat > /etc/nginx/sites-available/rtsurvey << NGINX_EOF
server {
    listen 80;
    server_name ${DOMAIN};

    location /.well-known/acme-challenge/ {
        root /var/www/html;
    }

${KC_BLOCK}
    location / {
        proxy_pass         http://127.0.0.1:8080;
        proxy_set_header   Host              \$host;
        proxy_set_header   X-Real-IP         \$remote_addr;
        proxy_set_header   X-Forwarded-For   \$proxy_add_x_forwarded_for;
        proxy_set_header   X-Forwarded-Proto \$scheme;
        proxy_read_timeout 120s;
        client_max_body_size 100M;
    }
}
NGINX_EOF
fi

nginx -t && nginx -s reload
echo "  Nginx reloaded with new config for ${DOMAIN}"

# ------------------------------------------------------------------------------
# Update .env
# ------------------------------------------------------------------------------
update_env PROJECT_URL    "$DOMAIN"
update_env HTTP_PROTOCOL  "$PROTOCOL"
update_env PROJECT_PORT   "$PORT"
update_env OIDC_REDIRECT_URI "${PROTOCOL}://${DOMAIN}/cpms/cpmsSite/auth"

if [[ "${EMBED_KEYCLOAK}" == "true" ]]; then
  update_env OIDC_ISSUER_URL "${PROTOCOL}://${DOMAIN}/auth/realms/rtsurvey"
  update_env KC_HOSTNAME     "${PROTOCOL}://${DOMAIN}/auth"
fi

# ------------------------------------------------------------------------------
# Reload app container
# ------------------------------------------------------------------------------
docker compose -f "$COMPOSE_FILE" up -d rtsurvey
echo "  App container restarted with updated environment"

# ------------------------------------------------------------------------------
# Keycloak: restart + update client redirect URIs
# ------------------------------------------------------------------------------
if [[ "${EMBED_KEYCLOAK}" == "true" ]]; then
  echo "  Restarting Keycloak with new KC_HOSTNAME..."
  docker compose -f "$COMPOSE_FILE" --profile embed-keycloak up -d keycloak

  echo "  Waiting for Keycloak..."
  for i in $(seq 1 30); do
    if curl -sf "http://localhost:${KEYCLOAK_PORT}/auth/realms/master" > /dev/null 2>&1; then
      echo "  Keycloak ready (attempt ${i})"; break
    fi
    sleep 5
  done

  TOKEN=$(curl -s -X POST \
    "http://localhost:${KEYCLOAK_PORT}/auth/realms/master/protocol/openid-connect/token" \
    -d "client_id=admin-cli&grant_type=password&username=admin&password=${KEYCLOAK_ADMIN_PASSWORD}" \
    | jq -r .access_token)

  if [[ -n "$TOKEN" && "$TOKEN" != "null" ]]; then
    CLIENT_UUID=$(curl -s \
      "http://localhost:${KEYCLOAK_PORT}/auth/admin/realms/rtsurvey/clients?clientId=${PROJECT_ID}" \
      -H "Authorization: Bearer $TOKEN" | jq -r '.[0].id')

    if [[ -n "$CLIENT_UUID" && "$CLIENT_UUID" != "null" ]]; then
      curl -s -X PUT \
        "http://localhost:${KEYCLOAK_PORT}/auth/admin/realms/rtsurvey/clients/${CLIENT_UUID}" \
        -H "Authorization: Bearer $TOKEN" \
        -H "Content-Type: application/json" \
        -d "{
          \"redirectUris\": [\"${PROTOCOL}://${DOMAIN}/*\", \"vn.rta.rtsurvey.auth:/*\", \"vn.rta.rtsurvey.logout:/*\"],
          \"webOrigins\":   [\"${PROTOCOL}://${DOMAIN}\"]
        }"
      echo "  Keycloak client redirect URIs updated"
    fi

    curl -s -X PUT \
      "http://localhost:${KEYCLOAK_PORT}/auth/admin/realms/rtsurvey" \
      -H "Authorization: Bearer $TOKEN" \
      -H "Content-Type: application/json" \
      -d '{"sslRequired":"external"}'
    echo "  Keycloak sslRequired set to external"

    ADMIN_KC_USER_ID=$(curl -s \
      "http://localhost:${KEYCLOAK_PORT}/auth/admin/realms/rtsurvey/users?username=admin" \
      -H "Authorization: Bearer $TOKEN" | jq -r '.[0].id')
    if [[ -n "$ADMIN_KC_USER_ID" && "$ADMIN_KC_USER_ID" != "null" ]]; then
      curl -s -X PUT \
        "http://localhost:${KEYCLOAK_PORT}/auth/admin/realms/rtsurvey/users/${ADMIN_KC_USER_ID}" \
        -H "Authorization: Bearer $TOKEN" \
        -H "Content-Type: application/json" \
        -d "{\"email\":\"admin@${DOMAIN}\",\"emailVerified\":true}"
      echo "  Keycloak admin user email updated to admin@${DOMAIN}"
    fi
  else
    echo "  WARNING: Could not get Keycloak admin token -- update client URIs manually" >&2
  fi

  docker exec rtsurvey-mysql mysql -u root -p"${MYSQL_ROOT_PASSWORD}" "${PROJECT_ID}" \
    -e "UPDATE ss_user SET email='admin@${DOMAIN}', use_pin_code=0 WHERE username='admin';" || true
  echo "  Admin email & PIN code restriction updated"
fi

# ------------------------------------------------------------------------------
# Write success status
# ------------------------------------------------------------------------------
CERT_EXPIRES=""
if [[ -n "$CERT" ]] && command -v openssl > /dev/null 2>&1; then
  CERT_EXPIRES=$(openssl x509 -enddate -noout -in "$CERT" 2>/dev/null \
    | cut -d= -f2 | xargs -I{} date -d{} +%Y-%m-%d 2>/dev/null || true)
fi

CERT_FIELD=""
[[ -n "$CERT_EXPIRES" ]] && CERT_FIELD=",\"cert_expires\":\"${CERT_EXPIRES}\""
write_status "active" "$CERT_FIELD"

echo "[$(date -u +%FT%TZ)] SSL setup complete: ${DOMAIN}"
SSLSCRIPT_EOF

chmod +x /opt/rtsurvey/ssl-issue.sh

# --------------------------------------------------------------------------
# Systemd path unit -- watches request.json, fires ssl-issue.sh on change
# --------------------------------------------------------------------------
cat > /etc/systemd/system/rtsurvey-ssl.path << 'PATH_EOF'
[Unit]
Description=Watch for rtCloud SSL domain setup request

[Path]
PathModified=/opt/rtsurvey/ssl-trigger/request.json

[Install]
WantedBy=multi-user.target
PATH_EOF

cat > /etc/systemd/system/rtsurvey-ssl.service << 'SVC_EOF'
[Unit]
Description=rtCloud SSL issue script
After=network-online.target docker.service

[Service]
Type=oneshot
ExecStart=/opt/rtsurvey/ssl-issue.sh
StandardOutput=append:/var/log/rtsurvey-ssl.log
StandardError=append:/var/log/rtsurvey-ssl.log
SVC_EOF

systemctl daemon-reload
systemctl enable --now rtsurvey-ssl.path
# Edge case: if request.json already exists (reboot after form submit), trigger immediately
[[ -f /opt/rtsurvey/ssl-trigger/request.json ]] && touch /opt/rtsurvey/ssl-trigger/request.json
echo "  SSL trigger watcher enabled (systemd path unit)"
echo "  Nginx running HTTP-only — admin sets domain via app UI to activate SSL"

# ==============================================================================
# 7. Firewall
# ==============================================================================
echo "[7/7] Configuring firewall..."
ufw --force enable
ufw allow ssh
ufw allow "Nginx Full"   # ports 80 + 443
ufw allow 3838/tcp       # Shiny (direct)
echo "  Firewall: SSH, 80, 443, 3838 allowed."

# ==============================================================================
# Done
# ==============================================================================
echo ""
echo "============================================================"
echo " rtCloud deployment complete! (AWS EC2)"
echo "============================================================"
echo " Server IP : ${SERVER_IP}"
echo ""
echo " App URL   : http://${SERVER_IP}  (HTTP only until domain is set)"
echo " Admin     : admin / ${ADMIN_PASSWORD}"
echo " DB Name   : ${PROJECT_ID}"
echo " DB User   : ${PROJECT_ID}"
echo " DB Pass   : ${MYSQL_PASSWORD}"
echo " DB Root   : ${MYSQL_ROOT_PASSWORD}"
echo " Stata     : ${STATA_ENABLED}"
echo ""
echo " *** NEXT STEP: Configure domain & SSL ***"
echo "   1. Log in to the app at http://${SERVER_IP}"
echo "   2. Go to Configuration > System Properties > Domain & SSL"
echo "   3. Enter your domain and choose SSL type (certbot or rtsurvey)"
echo "   4. The server will obtain a cert and switch to HTTPS automatically"
echo ""
if [[ "${EMBED_KEYCLOAK}" == "true" ]]; then
  echo " *** EMBEDDED KEYCLOAK ***"
  echo "   Running at http://${SERVER_IP}/auth (HTTP until domain is set)"
  echo "   After SSL is active: https://<domain>/auth/admin"
  echo "   Login: admin / ${KEYCLOAK_ADMIN_PASSWORD}"
  echo ""
fi
echo " !! SECURITY: All passwords default to 'admin'."
echo "    Change them immediately after first login."
echo ""
echo " Logs  : /var/log/rtsurvey-setup.log"
echo "         /var/log/rtsurvey-ssl.log  (SSL trigger script)"
echo " Files : /opt/rtsurvey/"
echo " SSL trigger: /opt/rtsurvey/ssl-trigger/"
echo "============================================================"
