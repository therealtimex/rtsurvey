<div align="center">

# rtSurvey

**All-in-one CAPI survey platform for field data collection**

Self-hosted · Offline-first · Real-time analytics · Enterprise-ready

[![Docs](https://img.shields.io/badge/docs-docs.rtsurvey.com-blue)](https://docs.rtsurvey.com)
[![License](https://img.shields.io/badge/license-Proprietary-red)](LICENSE)
[![Twitter](https://img.shields.io/badge/twitter-@RtSurvey-1DA1F2)](https://twitter.com/RtSurvey)

[📖 Documentation](https://docs.rtsurvey.com) · [🌐 Website](https://rtsurvey.com) · [🚀 Quick Start](#-quick-start)

</div>

---

## What is rtSurvey?

**rtSurvey** is a self-hosted CAPI (Computer-Assisted Personal Interviewing) platform that covers the entire data collection lifecycle — from designing surveys to collecting data in the field to analyzing results in real time. All data stays on your own infrastructure.

```
Design forms  →  Collect data (online or offline)  →  Analyze & export
```

**Built for:**
- Research organizations and universities
- Government agencies and development programs
- NGOs conducting longitudinal field studies
- Teams needing full data sovereignty

---

## Features

### Survey Design
- XLSForm-based forms with a visual drag-and-drop builder
- 25+ question types: text, choice, GPS, barcode, media capture, and more
- Branching logic, skip conditions, and calculated fields
- Multi-language support per form
- Reusable templates and component library

### Data Collection
- Mobile app (Android/iOS), web app, and anonymous web forms
- **Offline-first** — collect data without internet, sync automatically when back online
- Progress saving, file attachments, and multimedia capture
- Authenticated and public submission modes

### Submission Management
- Advanced workflows: return submissions for editing, forward for review or collaboration
- Quality control and validation rules
- Longitudinal data tracking for repeated-measures studies
- Interactive data table preview

### Analytics & Reporting
- Real-time dashboards powered by **R/Shiny**
- Custom reports with R and Python scripts
- Export to CSV, Excel, SPSS, Stata, Power BI
- Optional: Stata 14 statistical analysis (separate license)

### User & Project Management
- Role-based access control (RBAC) with fine-grained permissions
- Multi-tenant support — isolate projects and teams
- Audit logging
- SSO via Keycloak, Azure AD, or any OIDC provider

### Integration
- REST API (v2)
- Webhooks for event-driven workflows
- Elasticsearch for advanced search and full-text indexing
- Matrix chat notifications
- External database connections
- Power BI connector

---

## Quick Start

### Prerequisites

- Docker 24.0+ and Docker Compose v2
- 4 GB RAM minimum (8 GB recommended for production)
- 50 GB disk space
- Valid rtSurvey license key

### Development (local)

```bash
git clone https://github.com/therealtimex/rtsurvey.git
cd rtsurvey
cp .env.sample .env
docker compose up -d
```

Open [http://localhost:8080](http://localhost:8080)

### Production

```bash
# 1. Configure environment
cp .env.production.sample .env.production
#    Set PROJECT_URL, RTCLOUD_LICENSE_KEY, and credentials

# 2. Generate secure secrets
chmod +x scripts/generate-secrets.sh && ./scripts/generate-secrets.sh

# 3. Deploy
chmod +x scripts/deploy.sh && ./scripts/deploy.sh

# 4. Verify
docker compose logs -f rtcloud
# ✓ License validation successful
# ✓ Database migrations completed
# ✓ Application started
```

### One-click cloud deployment

Automated scripts handle Docker installation, Nginx reverse proxy, Let's Encrypt TLS, and firewall setup:

| Provider | Guide |
|----------|-------|
| Linode | [deploy-linode.md](docs/deploy-linode.md) |
| DigitalOcean | [deploy-digitalocean.md](docs/deploy-digitalocean.md) |

---

## Architecture

### Technology Stack

| Layer | Technology |
|-------|-----------|
| Web framework | PHP 7.4 + Yii Framework 1.1 |
| Web server | Apache 2.4 |
| Frontend | Vue.js 2 + Vuex |
| Database | MySQL 8.0 |
| Analytics | R 4.1 + Shiny Server |
| Background queue | Beanstalkd |
| Container runtime | Docker 24.0+ |

### Container Layout

```
┌──────────────────────────────────────────────────────┐
│  rtcloud  (monolithic container)                     │
├──────────────────────────────────────────────────────┤
│  Apache + PHP 7.4  │  Shiny (R 4.1)  │  Beanstalkd  │
│                                                      │
│  modules/                                            │
│    survey-minimal/   ← always present                │
│    survey-advance/   ← advanced + rtwork tiers       │
│    rtwork/           ← rtwork tier only              │
└──────────────────────────────────────────────────────┘
                        │
                        ▼
┌──────────────────────────────────────────────────────┐
│  mysql  —  MySQL 8.0 with persistent volume          │
└──────────────────────────────────────────────────────┘
```

### Build Tiers

The same codebase ships as three tiers — upgrade from minimal → advanced → rtwork at any time, migrations are additive only.

| Tier | Includes |
|------|----------|
| **minimal** | Core survey platform |
| **advanced** | + REST API v2, advanced analytics |
| **rtwork** | + CRM, dynamic data models, workspace |

### Persistent Volumes

| Volume | Contents |
|--------|----------|
| `mysql_data` | Database |
| `app_uploads` | User-uploaded files |
| `app_runtime` | Cache and logs |
| `shiny_data` | Shiny server data |

### Ports

| Port | Service |
|------|---------|
| `8080` | Web interface |
| `3838` | Shiny analytics dashboards |

---

## System Requirements

|  | Minimum | Recommended |
|--|---------|-------------|
| CPU | 2 cores | 4+ cores |
| RAM | 4 GB | 8 GB+ |
| Disk | 50 GB | 100 GB SSD |
| OS | Ubuntu 20.04+ | Ubuntu 22.04 LTS |

---

## Documentation

Full documentation is available at **[docs.rtsurvey.com](https://docs.rtsurvey.com)**

Sections include:

- **Getting Started** — overview, quick start, cloud deployment, first login
- **Survey Design** — XLSForm reference, question types, skip logic, multilingual forms
- **Data Collection** — online/offline modes, quality control, field practices
- **Project Management** — user roles, permissions, team management
- **Analytics & Reporting** — R/Shiny dashboards, custom reports, Python integration
- **API & Integration** — REST API reference, webhook setup, SSO configuration
- **Troubleshooting** — common issues and FAQ

---

## Security

- CSRF protection enabled by default
- SQL injection prevention via parameterized queries
- XSS protection headers
- Secrets managed through Docker secrets (never in version control)
- Role-based access control
- SSL/TLS support
- Audit logging

**To report a security vulnerability**, do not open a public issue. Contact the security team directly (see [rtsurvey.com](https://rtsurvey.com)).

---

## Optional Add-ons

### Stata 14 Statistical Analysis

Requires a separate commercial license from [StataCorp](https://www.stata.com) ($595–$3,595).

```bash
STATA_ENABLED=true  # in .env.production
```

See [docs/STATA_INSTALLATION.md](docs/STATA_INSTALLATION.md). The built-in R/Shiny analytics are a free alternative.

### Elasticsearch

Advanced full-text search and indexing. See [docs/elasticsearch.md](docs/elasticsearch.md).

### Push Notifications

Firebase Cloud Messaging (FCM) for mobile app notifications.

---

## License

**Proprietary Software** — requires a valid license key.

- Licensed for internal business use
- Modify configuration and integrate with your systems
- Redistribution and sublicensing are prohibited

See [LICENSE](LICENSE) for complete terms.

**License types:** Single Instance · Multi-Instance · Enterprise (unlimited) · Development/Testing

---

## Support & Contact

| | |
|-|--|
| **Documentation** | [docs.rtsurvey.com](https://docs.rtsurvey.com) |
| **Website** | [rtsurvey.com](https://rtsurvey.com) |
| **GitHub** | [github.com/therealtimex/rtsurvey](https://github.com/therealtimex/rtsurvey) |
| **Twitter** | [@RtSurvey](https://twitter.com/RtSurvey) |

For sales, support, or trial access, visit [rtsurvey.com](https://rtsurvey.com).

---

<div align="center">

Built with [Yii Framework](https://www.yiiframework.com) · [R/Shiny](https://shiny.posit.co) · [Docker](https://www.docker.com)

© 2024 rtSurvey. All Rights Reserved.

</div>
