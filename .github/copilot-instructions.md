# Copilot Instructions for HAProxy CloudFlare Template

## Repository Overview

This is a template repository for deploying HAProxy across multiple HA nodes with CloudFlare DNS integration and GitHub Actions automation.

---

## Structure

```
.
├── .github/workflows/          # GitHub Actions workflows
│   ├── deploy.yml              # Rolling deployment
│   ├── rollback.yml            # Manual rollback
│   ├── cloudflare-dns.yml      # DNS sync
│   ├── cloudflare-failover.yml # Emergency failover
│   └── validate.yml            # PR validation
├── cloudflare/                 # CloudFlare config (examples)
├── docker/                     # Docker setup (optional)
├── docs/                       # Documentation
├── haproxy/                    # HAProxy config (example)
└── scripts/                    # Deployment scripts
```

---

## Configuration Conventions

### Example Files

All configuration files that contain real/sensitive values have `.example` versions:
- `cloudflare/active-node.example.yml` → `cloudflare/active-node.yml`
- `cloudflare/dns-records.example.yml` → `cloudflare/dns-records.yml`
- `haproxy/haproxy.cfg.example` → `haproxy/haproxy.cfg`

Real config files are gitignored.

### IP Addresses

Use RFC documentation IPs in examples:
- `192.0.2.x` (TEST-NET-1)
- `198.51.100.x` (TEST-NET-2)
- `203.0.113.x` (TEST-NET-3)

### Domains

Use `example.com` in example configurations.

---

## Shell Script Conventions

- Always use `set -euo pipefail` at the start
- Use `sudo` for system operations
- Validate before applying
- Implement rollback on failure

---

## GitHub Actions Conventions

### Matrix Strategy for Rolling Deploy

```yaml
strategy:
  fail-fast: true
  max-parallel: 1
  matrix:
    include:
      - node: ha01
      - node: ha02
      - node: ha03
```

### Runner Selection

```yaml
runs-on:
  - self-hosted
  - haproxy
  - ${{ matrix.node }}
```

---

## CloudFlare DNS Conventions

### Template Variables

- `{{active_node_ip}}` - Replaced with IP from active-node.yml

### Record Types

- CNAME for application subdomains (proxied)
- A record for failover endpoint (not proxied, TTL=60)

---

## Code Generation Guidelines

When generating configuration or scripts:

1. Use RFC documentation IPs, not real IPs
2. Use `example.com`, not real domains
3. Include `CUSTOMIZE:` comments for sections needing user changes
4. Always include `set -euo pipefail` in bash scripts
5. Always validate HAProxy config with `haproxy -c`
6. Use graceful reload (`systemctl reload haproxy`)
7. Implement LKG rollback on failure
