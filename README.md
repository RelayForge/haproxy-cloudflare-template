# HAProxy CloudFlare Template

A production-ready template for deploying HAProxy across multiple high-availability nodes with CloudFlare DNS integration and GitHub Actions automation.

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

## Features

- 🚀 **Rolling Deployments** - Deploy to HA nodes sequentially with zero downtime
- 🔄 **Automatic Rollback** - Auto-rollback to last known good configuration on failure
- 🌐 **CloudFlare DNS Sync** - Declarative DNS management with plan/apply workflow
- ⚡ **Emergency Failover** - One-click DNS failover for disaster recovery
- 🐳 **Docker Support** - Optional containerized deployment
- ✅ **Config Validation** - Automatic syntax validation on pull requests

## Quick Start

### 1. Use This Template

Click "Use this template" on GitHub to create your own repository.

### 2. Configure Your Environment

```bash
# Copy example files
cp cloudflare/active-node.example.yml cloudflare/active-node.yml
cp cloudflare/dns-records.example.yml cloudflare/dns-records.yml
cp haproxy/haproxy.cfg.example haproxy/haproxy.cfg

# Edit with your actual values
# - Replace example IPs with your server IPs
# - Replace example.com with your domain
# - Configure your backends
```

### 3. Set Up GitHub Secrets

Go to **Settings → Secrets → Actions** and add:

| Secret | Description |
|--------|-------------|
| `CLOUDFLARE_API_TOKEN` | API token with Zone:DNS:Edit permission |
| `CLOUDFLARE_ZONE_ID` | Your CloudFlare zone ID |

### 4. Set Up Self-Hosted Runners

Install GitHub Actions runners on each HA node with labels:
- `self-hosted`
- `haproxy`
- `<node-name>` (e.g., `ha01`, `ha02`, `ha03`)

See [docs/DEPLOYMENT.md](docs/DEPLOYMENT.md) for detailed setup instructions.

### 5. Deploy

Push changes to `main` branch or manually trigger the workflow:

```bash
git add .
git commit -m "Initial HAProxy configuration"
git push
```

## Repository Structure

```
.
├── .github/workflows/          # GitHub Actions workflows
│   ├── deploy.yml              # Rolling deployment to HA nodes
│   ├── rollback.yml            # Manual rollback workflow
│   ├── cloudflare-dns.yml      # DNS sync workflow
│   ├── cloudflare-failover.yml # Emergency DNS failover
│   └── validate.yml            # PR config validation
│
├── cloudflare/                 # CloudFlare configuration
│   ├── active-node.example.yml # Active node & external IPs
│   └── dns-records.example.yml # DNS records definition
│
├── docker/                     # Docker deployment (optional)
│   ├── docker-compose.yml
│   └── README.md
│
├── docs/                       # Documentation
│   ├── SETUP.md                # Initial setup guide
│   ├── CONFIGURATION.md        # HAProxy config guide
│   ├── DNS.md                  # CloudFlare DNS management
│   └── DEPLOYMENT.md           # Deployment options
│
├── haproxy/                    # HAProxy configuration
│   └── haproxy.cfg.example     # Example configuration
│
└── scripts/                    # Deployment scripts
    ├── apply_local.sh          # Apply config on HA node
    ├── rollback_local.sh       # Rollback on HA node
    └── cloudflare_sync.sh      # CloudFlare DNS sync
```

## Workflows

### Deploy HAProxy

Automatically triggered on push to `main` when `haproxy/` files change.

- Deploys to nodes sequentially (ha01 → ha02 → ha03)
- Validates configuration before applying
- Automatically rolls back on failure
- Maintains last-known-good (LKG) backups

### CloudFlare DNS Sync

Manually triggered workflow to sync DNS records.

**Modes:**
- `check` - Validate config and API connection
- `plan` - Dry-run showing what would change
- `apply` - Apply changes (additive only)

### CloudFlare DNS Failover

Emergency failover for disaster recovery.

1. Go to Actions → CloudFlare DNS Failover
2. Select target node
3. Click "Run workflow"

## Documentation

- [Initial Setup](docs/SETUP.md) - First-time configuration
- [HAProxy Configuration](docs/CONFIGURATION.md) - Backend setup
- [CloudFlare DNS](docs/DNS.md) - DNS management
- [Deployment Options](docs/DEPLOYMENT.md) - Runner setup, Docker, alternatives

## License

MIT License - see [LICENSE](LICENSE) for details.

## Contributing

Contributions are welcome! Please see [CONTRIBUTING.md](CONTRIBUTING.md) for guidelines.
