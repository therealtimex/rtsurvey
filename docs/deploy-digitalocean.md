# Deploy rtSurvey on DigitalOcean

Provision a fresh Ubuntu 22.04 LTS Droplet and launch rtSurvey automatically
using the user-data script [`scripts/digitalocean-droplet.sh`](../scripts/digitalocean-droplet.sh).

---

## Requirements

| | |
|-|--|
| **Droplet size** | Basic — 2 vCPUs / 4 GB RAM ($24/mo minimum) |
| **Image** | Ubuntu 22.04 LTS x64 |
| **Domain** | A DNS A record pointing to the Droplet IP (for SSL) |

---

## Steps

### 1. Configure the script

Open [`scripts/digitalocean-droplet.sh`](../scripts/digitalocean-droplet.sh) and
edit the `CONFIGURATION` block near the top:

```bash
# --- Required ---
PROJECT_ID="myproject"          # unique identifier, no spaces
ADMIN_PASSWORD="changeme"       # web admin password — change after first login

RTCLOUD_IMAGE="rtawebteam/rta-smartsurvey:survey-dockerize"

# --- Ports ---
APP_PORT="80"
SHINY_PORT="3838"

# --- Embedded Keycloak (built-in SSO) ---
EMBED_KEYCLOAK="true"           # set false to use an external OIDC provider

# --- Stata14 (optional) ---
STATA_ENABLED="false"
```

> **Note:** Domain and SSL are configured after first boot through the app UI
> (Admin → Configuration → Domain & SSL). You do not need to set `DOMAIN` or
> `LETSENCRYPT_EMAIL` before deploying.

### 2. Create the Droplet

1. Log in to [cloud.digitalocean.com](https://cloud.digitalocean.com)
2. **Create** → **Droplets**
3. Choose **Ubuntu 22.04 LTS** as the image
4. Select a plan — **Basic, 2 vCPUs / 4 GB RAM** or larger
5. Choose a datacenter region close to your users
6. Under **Advanced Options** → enable **Add Initialization scripts**
7. Paste the full contents of the configured script into the text area
8. Click **Create Droplet**

### 3. Monitor setup

Setup runs automatically on first boot and takes 5–10 minutes.

```bash
ssh root@<droplet-ip> tail -f /var/log/rtcloud-setup.log
```

You'll see confirmation when complete:

```
============================================================
 rtSurvey setup complete
============================================================
  App:      http://<droplet-ip>
  Shiny:    http://<droplet-ip>:3838
  Admin:    admin / <your-password>
```

### 4. First login

Open `http://<droplet-ip>` in your browser and log in with:

| Field | Value |
|-------|-------|
| Username | `admin` |
| Password | value of `ADMIN_PASSWORD` |

> Change the admin password after first login.

### 5. Configure domain and SSL

In the app: **Admin → Configuration → Domain & SSL**

Enter your domain name and email address. The app will:
- Update Nginx with your domain
- Request a Let's Encrypt certificate automatically
- Switch to HTTPS

---

## Keycloak SSO

Embedded Keycloak is enabled by default (`EMBED_KEYCLOAK=true`). It provides
SSO for both the web app and the mobile app out of the box.

To use an external OIDC provider (Google, Azure AD, Auth0, etc.), set:

```bash
EMBED_KEYCLOAK="false"
OIDC_ISSUER_URL="https://your-provider.com"
OIDC_CLIENT_ID="your-client-id"
OIDC_CLIENT_SECRET="your-client-secret"
```

---

## Useful commands after deployment

```bash
# View logs
ssh root@<droplet-ip> tail -f /var/log/rtcloud-setup.log

# App logs
docker compose -f /opt/rtcloud/docker-compose.production.yml logs -f rtcloud

# Restart app
docker compose -f /opt/rtcloud/docker-compose.production.yml restart rtcloud

# Stop all services
docker compose -f /opt/rtcloud/docker-compose.production.yml down

# Pull latest image and redeploy
docker compose -f /opt/rtcloud/docker-compose.production.yml pull
docker compose -f /opt/rtcloud/docker-compose.production.yml up -d
```

---

## Full script

[`scripts/digitalocean-droplet.sh`](../scripts/digitalocean-droplet.sh)
