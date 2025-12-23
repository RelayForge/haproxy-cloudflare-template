# CloudFlare DNS Management

This guide covers managing DNS records through CloudFlare for HAProxy routing.

## Architecture

```
                    CloudFlare (CDN/Proxy)
                           │
                           ▼
┌─────────────────────────────────────────────────────────────┐
│                    DNS Records                               │
├─────────────────────────────────────────────────────────────┤
│  www.example.com      CNAME → currentha.example.com         │
│  api.example.com      CNAME → currentha.example.com         │
│  admin.example.com    CNAME → currentha.example.com         │
│  currentha.example.com   A → 192.0.2.11 (active HA node)   │
└─────────────────────────────────────────────────────────────┘
                           │
                           ▼
                    Active HA Node
                     (HAProxy)
                           │
            ┌──────────────┼──────────────┐
            ▼              ▼              ▼
        Backend 1     Backend 2     Backend 3
```

## Configuration Files

### active-node.yml

Defines which HA node is currently active and the external IP addresses.

```yaml
# Current active node
active_node: ha01

# Public IP addresses for each HA node
external_ips:
  ha01: "144.76.152.155"
  ha02: "138.201.254.8"
  ha03: "144.76.117.54"
```

### dns-records.yml

Declarative DNS records configuration.

```yaml
zones:
  - zone: example.com
    records:
      # Failover record - points to active HA node (NOT proxied)
      - name: currentha
        type: A
        content: "{{active_node_ip}}"
        proxied: false
        ttl: 60
        comment: "Active HA node for failover"

      # Application records - CNAME to currentha (proxied through CloudFlare)
      - name: www
        type: CNAME
        content: currentha.example.com
        proxied: true
        comment: "Main website"

      - name: api
        type: CNAME
        content: currentha.example.com
        proxied: true
        comment: "API endpoint"
```

## Template Variables

| Variable | Description | Source |
|----------|-------------|--------|
| `{{active_node_ip}}` | IP address of active HA node | Resolved from `active-node.yml` |

## Record Types

### CNAME Records (Recommended)

Use CNAME records for application subdomains pointing to `currentha`:

```yaml
- name: www
  type: CNAME
  content: currentha.example.com
  proxied: true
  comment: "Main website"
```

**Pros:**
- Automatic failover - change `active_node` and all subdomains update
- Simpler management

**Cons:**
- Cannot use CNAME at apex (root) domain
- Slight DNS resolution overhead

### A Records (Direct IP)

Use A records when you need direct IP mapping:

```yaml
- name: currentha
  type: A
  content: "{{active_node_ip}}"
  proxied: false
  ttl: 60
  comment: "Active HA node"
```

**Use cases:**
- Failover record (`currentha`)
- When CNAME is not supported
- Direct IP requirements

## Proxied vs Direct

### Proxied (Orange Cloud) ☁️

Traffic routes through CloudFlare:

```yaml
proxied: true
```

**Benefits:**
- DDoS protection
- CDN caching
- SSL/TLS termination
- Web Application Firewall (WAF)
- Analytics

**Limitations:**
- Only works for HTTP/HTTPS (ports 80, 443)
- Cannot use for non-web protocols

### Direct (Grey Cloud) ☁️

DNS-only, traffic goes directly to your server:

```yaml
proxied: false
```

**Use cases:**
- Failover record (needs low TTL)
- Non-HTTP services (mail, FTP)
- When you need client's real IP
- WebSocket connections (optional)

## Workflows

### CloudFlare DNS Sync

Synchronizes records from configuration to CloudFlare.

**Modes:**

| Mode | Description |
|------|-------------|
| `check` | Validate config and API connection |
| `plan` | Dry-run, shows what would change |
| `apply` | Create/update records |

**Options:**

| Option | Description |
|--------|-------------|
| `filter` | Only process matching records |
| `force_overwrite` | Delete records with type conflicts |

**Usage:**

```bash
# Via GitHub Actions
gh workflow run cloudflare-dns.yml -f mode=plan
gh workflow run cloudflare-dns.yml -f mode=apply

# Or locally
export CLOUDFLARE_API_TOKEN="your-token"
export CLOUDFLARE_ZONE_ID="your-zone-id"
./scripts/cloudflare_sync.sh --plan
./scripts/cloudflare_sync.sh --apply
```

### CloudFlare DNS Failover

Emergency DNS failover without git commit.

**Usage:**

1. Go to **Actions** → **CloudFlare DNS Failover**
2. Select target node (ha01, ha02, ha03)
3. Enter reason (optional)
4. Click **"Run workflow"**

**Note:** After emergency failover, update `active-node.yml` to match.

## Failover Procedures

### Standard Failover (with git tracking)

1. Edit `cloudflare/active-node.yml`:
   ```yaml
   active_node: ha02  # Change to target node
   ```

2. Commit and push:
   ```bash
   git add cloudflare/active-node.yml
   git commit -m "Failover to ha02 - maintenance"
   git push
   ```

3. Run DNS sync:
   ```bash
   gh workflow run cloudflare-dns.yml -f mode=apply
   ```

### Emergency Failover

For immediate failover without git:

1. Go to **Actions** → **CloudFlare DNS Failover**
2. Select target node
3. Run workflow

### Verify Failover

```bash
# Check DNS resolution
dig +short currentha.example.com

# Should return the new node's IP
# e.g., 138.201.254.8 for ha02
```

## Adding New DNS Records

### Step 1: Add to dns-records.yml

```yaml
zones:
  - zone: example.com
    records:
      # ... existing records ...

      # New application
      - name: newapp
        type: CNAME
        content: currentha.example.com
        proxied: true
        comment: "New Application - Production"
```

### Step 2: Add to HAProxy config

In `haproxy/haproxy.cfg`:

```haproxy
frontend https_front
    # Add ACL
    acl is_newapp hdr(host) -i newapp.example.com

    # Add routing rule
    use_backend newapp_backend if is_newapp

# Add backend
backend newapp_backend
    balance roundrobin
    option httpchk GET /health
    http-check expect status 200
    server app1 10.0.0.1:8080 check
```

### Step 3: Deploy

```bash
git add cloudflare/dns-records.yml haproxy/haproxy.cfg
git commit -m "Add newapp subdomain and backend"
git push

# Sync DNS
gh workflow run cloudflare-dns.yml -f mode=apply

# HAProxy deploys automatically on push
```

## Type Conflicts

When a record exists with a different type than configured:

```
Example: Existing A record, config wants CNAME
```

**Without force_overwrite:**
- Record is skipped with error
- Manual intervention required

**With force_overwrite:**
- Old record is deleted
- New record is created

```bash
# Force overwrite
gh workflow run cloudflare-dns.yml \
  -f mode=apply \
  -f force_overwrite=true
```

## Sync Behavior

| Scenario | Behavior |
|----------|----------|
| Record doesn't exist | Created |
| Record exists, same type | Updated |
| Record exists, different type | Skipped (or deleted if force_overwrite) |
| Record in CloudFlare not in config | Left untouched |

**Note:** The sync is additive only - it never deletes records that aren't in the config.

## CloudFlare API Token

### Required Permissions

- **Zone:DNS:Edit** - Create and modify DNS records

### Create Token

1. Go to **CloudFlare Dashboard** → **My Profile** → **API Tokens**
2. Click **"Create Token"**
3. Use template: **"Edit zone DNS"**
4. Configure:
   - **Permissions**: Zone → DNS → Edit
   - **Zone Resources**: Include → Specific zone → Your domain
5. Create and copy token

### Token Security

- Store only in GitHub Secrets
- Never commit to repository
- Rotate periodically
- Use minimum required permissions

## Troubleshooting

### "API token invalid"

- Verify token has correct permissions
- Check token hasn't expired
- Ensure secret name is exactly `CLOUDFLARE_API_TOKEN`

### "Zone not found"

- Verify `CLOUDFLARE_ZONE_ID` is correct
- Check token has access to the zone
- Zone ID is in CloudFlare Dashboard → Overview → Right sidebar

### "Record already exists"

- Record has different type than config
- Use `force_overwrite` option to replace
- Or manually delete conflicting record in CloudFlare

### "DNS not updating"

- CloudFlare caches DNS (check cache rules)
- Proxied records may have longer propagation
- Use `dig` or `nslookup` to verify changes

```bash
# Direct DNS query (bypasses cache)
dig @1.1.1.1 +short www.example.com

# Check TTL
dig www.example.com | grep -A1 "ANSWER SECTION"
```
