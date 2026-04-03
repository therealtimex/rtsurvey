# Deploy rtSurvey on Linode

Provision a fresh Ubuntu 22.04 LTS Linode using the public rtSurvey StackScript.
The script installs Docker, configures Nginx, and launches rtSurvey automatically
on first boot.

---

## One-click deploy

**[Deploy on Linode →](https://cloud.linode.com/stackscripts/XXXXXXX)**

> Replace the link above with the published public StackScript URL once available.

---

## Requirements

| | |
|-|--|
| **Linode plan** | Shared CPU — 4 GB RAM ($24/mo minimum) |
| **Image** | Ubuntu 22.04 LTS |
| **Domain** | A DNS A record pointing to the Linode IP (for SSL) |

---

## Steps

### 1. Open the StackScript

Go to the public StackScript:
**[cloud.linode.com/stackscripts/XXXXXXX](https://cloud.linode.com/stackscripts/XXXXXXX)**

Or, in the Linode console:

1. **Create** → **Linode**
2. Under **Choose a Distribution** → select **StackScripts**
3. Search for **rtSurvey**

### 2. Fill in the UDF fields

The StackScript prompts for configuration at deploy time:

| Field | Description |
|-------|-------------|
| **Timezone** | Server timezone (default: `Asia/Ho_Chi_Minh`) |

> Admin password, image tag, and SSO settings are pre-configured in the script
> with secure defaults. Domain and SSL are set after first boot via the app UI.

### 3. Create the Linode

1. Select **Ubuntu 22.04 LTS** as the image
2. Choose a region close to your users
3. Select a plan — **Shared CPU, 4 GB RAM** or larger
4. Click **Create Linode**

Setup runs automatically on first boot and takes 5–10 minutes.

### 4. Monitor setup

```bash
ssh root@<linode-ip> tail -f /var/log/stackscript.log
```

### 5. First login

Open `http://<linode-ip>` in your browser:

| Field | Value |
|-------|-------|
| Username | `admin` |
| Password | `admin` *(change immediately after first login)* |

### 6. Configure domain and SSL

In the app: **Admin → Configuration → Domain & SSL**

Enter your domain and email. The app will request a Let's Encrypt certificate
and switch to HTTPS automatically.

---

## Manual deployment

If you prefer to run the script manually on an existing Linode, the source is
available at [`scripts/linode-stackscript.sh`](../scripts/linode-stackscript.sh).

```bash
# Download and run on a fresh Ubuntu 22.04 server
curl -fsSL https://raw.githubusercontent.com/therealtimex/rtsurvey/main/scripts/linode-stackscript.sh | bash
```

---

## Useful commands after deployment

```bash
# View setup log
ssh root@<linode-ip> tail -f /var/log/stackscript.log

# App logs
docker compose -f /opt/rtcloud/docker-compose.production.yml logs -f rtcloud

# Restart app
docker compose -f /opt/rtcloud/docker-compose.production.yml restart rtcloud

# Pull latest image and redeploy
docker compose -f /opt/rtcloud/docker-compose.production.yml pull
docker compose -f /opt/rtcloud/docker-compose.production.yml up -d
```
