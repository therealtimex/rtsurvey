# Deploy rtSurvey on Linode (Akamai Cloud)

Deploy rtCloud on Linode using a StackScript. No configuration needed — just
create the server and follow the post-deployment steps.

---

## Step 1 — Launch the StackScript

**[Deploy rtSurvey on Linode →](https://cloud.linode.com/stackscripts/2049143)**

This opens the StackScript page in Linode Cloud Manager. Click **Deploy New Linode**.

---

## Step 2 — Fill in Linode's form

Fill in Linode's standard server creation form:

| Field | Recommended value |
|-------|------------------|
| **Image** | Ubuntu 22.04 LTS |
| **Region** | Closest to your users |
| **Plan** | Shared CPU 4 GB or larger |
| **Root Password** | Set a strong password |
| **Firewall** | No Firewall *(recommended — see note below)* |
| **Timezone** *(only our field)* | Your server timezone (default: `Asia/Ho_Chi_Minh`) |

> **Why no firewall?** The setup script needs outbound internet access (Docker
> pulls, Let's Encrypt). Blocking ports during first boot can cause the
> deployment to fail. Attach a firewall after setup is complete — see
> [Firewall rules](#firewall-rules) below.

Click **Create Linode** when done.

---

## Step 3 — Wait for setup to complete

The script runs automatically on first boot. It installs Docker, pulls the
rtSurvey image, initialises the database, and starts all services.
This takes **5–10 minutes**.

Watch progress in **Linode Cloud Manager** — no SSH required:

1. Go to your [Linode dashboard](https://cloud.linode.com/linodes)
2. Click on your newly created Linode
3. Click **Launch LISH Console** (top right) — the **Weblish** tab opens a
   live terminal in your browser

Wait until you see:

```
============================================================
 rtSurvey deployment complete!
============================================================
 Server IP : <your-server-ip>

 App URL   : http://<your-server-ip>  (HTTP only until domain is set)
 Admin     : admin / admin
============================================================
```

Or monitor via SSH:

```bash
ssh root@<linode-ip> tail -f /var/log/stackscript.log
```

---

## Step 4 — Set up SSL

Open `http://<server-ip>` in your browser. The app will redirect you to the
SSL setup screen. Follow the on-screen steps to configure HTTPS via
Let's Encrypt (free).

---

## Step 5 — Change default passwords

All passwords default to `admin`. Change them immediately after first login:

- **App admin password** — account settings inside the app
- **Keycloak admin** — `https://your-domain.com/auth/admin`
  (login: `admin` / `admin`)

---

## Firewall rules

If you attach a Linode Cloud Firewall to this server, use these rules:

### Inbound

| Label | Protocol | Port | Notes |
|-------|----------|------|-------|
| `accept-inbound-ssh` | TCP | 22 | SSH access |
| `accept-inbound-http` | TCP | 80 | Nginx + ACME challenge |
| `accept-inbound-https` | TCP | 443 | Nginx HTTPS |
| `accept-inbound-shiny` | TCP | 3838 | Shiny Server (R analytics) |
| `accept-inbound-icmp` | ICMP | — | Ping / diagnostics |
| Default inbound | **Drop** | | Block everything else |

### Outbound

| Policy | Notes |
|--------|-------|
| **Accept all** | Required for Docker pulls, certbot, DNS APIs |

### Ports NOT exposed externally

| Port | Service | Reason |
|------|---------|--------|
| 8080 | App container | Nginx proxies internally |
| 8090 | Keycloak container | Nginx proxies internally |
| 3306 | MySQL | Internal Docker network only |

---

## Troubleshooting

```bash
# Setup log
tail -200 /var/log/stackscript.log

# SSL log
tail -200 /var/log/rtsurvey-ssl.log

# Container status
docker compose -f /opt/rtsurvey/docker-compose.production.yml ps

# App logs
docker compose -f /opt/rtsurvey/docker-compose.production.yml logs -f rtcloud
```

---

## Manual deployment

The StackScript source is available at
[`scripts/linode-stackscript.sh`](../scripts/linode-stackscript.sh) if you
prefer to run it manually on an existing server:

```bash
curl -fsSL https://raw.githubusercontent.com/therealtimex/rtsurvey/main/scripts/linode-stackscript.sh | bash
```
