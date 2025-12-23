# Initial Setup Guide

This guide walks you through setting up the HAProxy + CloudFlare deployment system for your environment.

## Prerequisites

- GitHub account with permissions to create repositories and configure secrets
- CloudFlare account with your domain configured
- 1-3 Linux servers (HA nodes) with:
  - HAProxy installed (`apt install haproxy`)
  - SSH access
  - Sudo privileges
  - Network connectivity to backend servers

## Step 1: Create Your Repository

### Option A: Use Template (Recommended)

1. Go to the template repository on GitHub
2. Click **"Use this template"** → **"Create a new repository"**
3. Name your repository (e.g., `haproxy-config`)
4. Choose public or private
5. Click **"Create repository from template"**

### Option B: Fork Repository

1. Fork this repository to your account
2. Clone locally: `git clone https://github.com/YOUR-USERNAME/haproxy-config.git`

## Step 2: Configure CloudFlare

### Get Zone ID

1. Log in to [CloudFlare Dashboard](https://dash.cloudflare.com)
2. Select your domain
3. On the Overview page, find **Zone ID** in the right sidebar
4. Copy this value

### Create API Token

1. Go to **My Profile** → **API Tokens**
2. Click **"Create Token"**
3. Use template: **"Edit zone DNS"**
4. Configure:
   - **Permissions**: Zone → DNS → Edit
   - **Zone Resources**: Include → Specific zone → Select your domain
5. Click **"Continue to summary"** → **"Create Token"**
6. Copy the token (you won't see it again!)

### Add GitHub Secrets

1. Go to your repository → **Settings** → **Secrets and variables** → **Actions**
2. Click **"New repository secret"**
3. Add these secrets:

| Name | Value | Required For |
|------|-------|--------------|
| `CLOUDFLARE_API_TOKEN` | CloudFlare API token with Zone:DNS:Edit | DNS workflows |
| `CLOUDFLARE_ZONE_ID` | Your CloudFlare Zone ID | DNS workflows |
| `RUNNER_PAT` | GitHub PAT with `admin:org` scope | Deploy/Rollback workflows |

### Create Runner PAT

The `RUNNER_PAT` is needed to dynamically detect online self-hosted runners:

1. Go to **GitHub** → **Settings** → **Developer settings** → **Personal access tokens** → **Tokens (classic)**
2. Click **"Generate new token (classic)"**
3. Configure:
   - **Note**: `HAProxy Runner Detection`
   - **Expiration**: Set appropriate expiration
   - **Scopes**: Select `admin:org` (for organization runner groups)
4. Click **"Generate token"**
5. Copy and save as `RUNNER_PAT` secret

## Step 3: Configure Active Node File

```bash
# Copy example file
cp cloudflare/active-node.example.yml cloudflare/active-node.yml
```

Edit `cloudflare/active-node.yml`:

```yaml
# Set your default active node
active_node: ha01

# Replace with your actual public IPs
external_ips:
  ha01: "YOUR.PUBLIC.IP.1"
  ha02: "YOUR.PUBLIC.IP.2"
  ha03: "YOUR.PUBLIC.IP.3"
```

## Step 4: Configure DNS Records

```bash
# Copy example file
cp cloudflare/dns-records.example.yml cloudflare/dns-records.yml
```

Edit `cloudflare/dns-records.yml`:

```yaml
zones:
  - zone: yourdomain.com  # Your actual domain
    records:
      # Failover record - points to active HA node
      - name: currentha
        type: A
        content: "{{active_node_ip}}"
        proxied: false
        ttl: 60
        comment: "Active HA node for failover"

      # Your application subdomains
      - name: www
        type: CNAME
        content: currentha.yourdomain.com
        proxied: true
        comment: "Main website"

      - name: api
        type: CNAME
        content: currentha.yourdomain.com
        proxied: true
        comment: "API endpoint"

      # Add more records as needed
```

## Step 5: Configure HAProxy

```bash
# Copy example file
cp haproxy/haproxy.cfg.example haproxy/haproxy.cfg
```

Edit `haproxy/haproxy.cfg`:

1. **Update domain ACLs** in the frontend section:
   ```haproxy
   acl is_www hdr(host) -i www.yourdomain.com
   acl is_api hdr(host) -i api.yourdomain.com
   ```

2. **Update backend servers** with your actual IPs:
   ```haproxy
   backend www_backend
       balance roundrobin
       option httpchk GET /health
       http-check expect status 200
       server app1 10.0.0.11:8080 check inter 5s fall 3 rise 2
       server app2 10.0.0.12:8080 check inter 5s fall 3 rise 2
   ```

3. **Configure SSL certificates** (see [CONFIGURATION.md](CONFIGURATION.md))

## Step 6: Set Up Self-Hosted Runners

See [DEPLOYMENT.md](DEPLOYMENT.md) for detailed runner setup instructions.

### Create Runner Group

1. Go to your **Organization** → **Settings** → **Actions** → **Runner groups**
2. Click **"New runner group"**
3. Name it `ha-servers` (or customize in workflow files)
4. Select repositories that can use this group
5. Click **"Create group"**

### Install Runners

For each HA node:

1. Go to **Organization** → **Settings** → **Actions** → **Runners**
2. Click **"New runner"** → **"New self-hosted runner"**
3. Follow installation instructions for Linux
4. During configuration, add labels: `self-hosted`, `haproxy`, `ha01` (adjust node name)
5. Add runner to the `ha-servers` group
6. Install as service:
   ```bash
   sudo ./svc.sh install
   sudo ./svc.sh start
   ```

### Runner Label Convention

Each runner must have these labels:
- `self-hosted` - Standard self-hosted runner label
- `haproxy` - Identifies HAProxy deployment runners
- `ha01`, `ha02`, `ha03` - Node-specific label (must match pattern `ha[0-9]+`)

## Step 7: Initial Deployment

1. Commit your configuration:
   ```bash
   git add .
   git commit -m "Initial HAProxy and DNS configuration"
   git push
   ```

2. Sync DNS records:
   - Go to **Actions** → **CloudFlare DNS Sync**
   - Click **"Run workflow"**
   - Select mode: `plan` first, then `apply`

3. Deploy HAProxy:
   - The deploy workflow runs automatically on push
   - Or manually trigger via **Actions** → **Deploy HAProxy**

## Step 8: Verify Deployment

```bash
# Check HAProxy status on each node
ssh ha01 'systemctl status haproxy'

# Test health endpoint
curl -I https://www.yourdomain.com/health

# Verify DNS resolution
dig +short www.yourdomain.com
dig +short currentha.yourdomain.com
```

## Next Steps

- Read [CONFIGURATION.md](CONFIGURATION.md) for advanced HAProxy setup
- Read [DNS.md](DNS.md) for CloudFlare management
- Read [DEPLOYMENT.md](DEPLOYMENT.md) for alternative deployment methods

## Troubleshooting

### Workflow fails with "runner not found"

- Ensure runners are online and have correct labels
- Check runner logs: `journalctl -u actions.runner.* -f`

### CloudFlare API errors

- Verify `CLOUDFLARE_API_TOKEN` has Zone:DNS:Edit permission
- Verify `CLOUDFLARE_ZONE_ID` is correct
- Test with `--check` mode first

### HAProxy validation fails

- Run validation locally: `haproxy -c -f haproxy/haproxy.cfg`
- Check for syntax errors in configuration
- Ensure all referenced files (certs, errors) exist
