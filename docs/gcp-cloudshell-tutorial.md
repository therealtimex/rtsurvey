# Deploy RTSurvey on Google Cloud

RTSurvey is a self-hosted survey platform with mobile data collection, quality control, and analytics.

**Estimated setup time:** 5–10 minutes

---

## Step 1 — Select your project

<walkthrough-project-setup billing="true"></walkthrough-project-setup>

---

## Step 2 — Set configuration

Set your deployment variables. Edit the values below, then click to run:

```bash
export PROJECT_ID="rtsurvey"
export ADMIN_PASSWORD="ChangeMe123"
export TZ="Asia/Ho_Chi_Minh"
export ZONE="us-central1-a"
export MACHINE_TYPE="e2-standard-2"
export INSTANCE_NAME="rtsurvey-server"
```

> **Security:** Change `ADMIN_PASSWORD` before running. Use at least 8 characters.

---

## Step 3 — Open firewall ports

Allow HTTP, HTTPS, and Shiny Server traffic:

```bash
gcloud compute firewall-rules create rtsurvey-allow-web \
  --allow tcp:80,tcp:443,tcp:3838 \
  --target-tags rtsurvey \
  --description "RTSurvey web traffic" \
  --quiet 2>/dev/null || echo "Firewall rule already exists"
```

---

## Step 4 — Deploy the VM

This creates an `e2-standard-2` VM (2 vCPU / 8 GB RAM) and installs RTSurvey automatically:

```bash
gcloud compute instances create "$INSTANCE_NAME" \
  --zone="$ZONE" \
  --machine-type="$MACHINE_TYPE" \
  --image-family=ubuntu-2204-lts \
  --image-project=ubuntu-os-cloud \
  --boot-disk-size=50GB \
  --boot-disk-type=pd-ssd \
  --tags=rtsurvey \
  --metadata="startup-script=#!/bin/bash
export PROJECT_ID=\"${PROJECT_ID}\"
export ADMIN_PASSWORD=\"${ADMIN_PASSWORD}\"
export EMBED_KEYCLOAK=\"true\"
export TZ=\"${TZ}\"
curl -fsSL https://raw.githubusercontent.com/therealtimex/rtsurvey/main/scripts/gcp-compute.sh | bash"
```

---

## Step 5 — Get your server IP

```bash
gcloud compute instances describe "$INSTANCE_NAME" \
  --zone="$ZONE" \
  --format="get(networkInterfaces[0].accessConfigs[0].natIP)"
```

---

## Step 6 — Monitor setup progress

SSH into the VM and watch the setup log (takes 5–10 minutes):

```bash
gcloud compute ssh "$INSTANCE_NAME" --zone="$ZONE" \
  --command="sudo tail -f /var/log/rtsurvey-setup.log"
```

Setup is complete when you see:
```
✅ RTSurvey is ready
App URL : http://<your-ip>
Admin   : admin / <your-password>
```

---

## Step 7 — Open RTSurvey

```bash
echo "Open: http://$(gcloud compute instances describe "$INSTANCE_NAME" \
  --zone="$ZONE" \
  --format='get(networkInterfaces[0].accessConfigs[0].natIP)')"
```

Login with:
- **Username:** `admin`
- **Password:** the value you set in Step 2

---

## Next steps

- **Set up SSL:** Log in → Admin → Domain & SSL → enter your domain
- **Add users:** Admin → Users → Invite
- **Upload forms:** Dashboard → Forms → Upload XLSForm

**Docs:** [docs.rtsurvey.com](https://docs.rtsurvey.com)
