# Scaling HAProxy Nodes

This guide explains how to add, remove, and manage HAProxy nodes in your cluster. The template defaults to 3 nodes (ha01, ha02, ha03), but you can scale to any number of nodes.

## Table of Contents

- [Overview](#overview)
- [Node Naming Convention](#node-naming-convention)
- [Adding a New Node](#adding-a-new-node)
- [Removing a Node](#removing-a-node)
- [File Modification Reference](#file-modification-reference)
- [Minimum and Maximum Nodes](#minimum-and-maximum-nodes)
- [Automation Script](#automation-script)
- [Troubleshooting](#troubleshooting)

---

## Overview

The architecture supports **dynamic node detection** - workflows automatically discover online runners matching the `ha[0-9]+` pattern. However, some files contain hardcoded node lists that must be manually updated when scaling.

### What's Automatic

✅ **Deploy workflow** - Automatically detects online runners via GitHub API
✅ **Rollback workflow** - Same dynamic detection
✅ **Runner registration** - Any runner matching `ha[0-9]+` label is picked up

### What Requires Manual Updates

❌ **`cloudflare/active-node.yml`** - External IP mapping
❌ **`haproxy/haproxy.cfg`** - Backend server entries (if HAProxy backends run on HA nodes)
❌ **`.github/workflows/cloudflare-failover.yml`** - Target node dropdown options

---

## Node Naming Convention

Nodes must follow the pattern `ha[0-9]+` (e.g., ha01, ha02, ha03, ha04, etc.):

| Valid | Invalid |
|-------|---------|
| `ha01` | `haproxy1` |
| `ha02` | `node-01` |
| `ha10` | `HA01` (case-sensitive) |
| `ha99` | `ha-01` (no dashes) |

The workflows use regex `^ha[0-9]+$` to extract node identifiers from runner labels.

---

## Adding a New Node

Follow these steps to add a new HAProxy node (e.g., `ha04`):

### Step 1: Update CloudFlare Active Node Configuration

Edit `cloudflare/active-node.yml`:

```yaml
external_ips:
  ha01: "203.0.113.11"
  ha02: "203.0.113.12"
  ha03: "203.0.113.13"
  ha04: "203.0.113.14"    # ← Add new node with its external IP
```

### Step 2: Update HAProxy Configuration (if applicable)

If HAProxy backends run on the same HA nodes, edit `haproxy/haproxy.cfg` to add new server entries in each backend:

```haproxy
backend www_backend
    balance roundrobin
    option httpchk GET /health
    http-check expect status 200
    server ha01 192.168.0.11:8080 check inter 5s fall 3 rise 2
    server ha02 192.168.0.12:8080 check inter 5s fall 3 rise 2
    server ha03 192.168.0.13:8080 check inter 5s fall 3 rise 2
    server ha04 192.168.0.14:8080 check inter 5s fall 3 rise 2    # ← Add new server
```

### Step 3: Update Failover Workflow

Edit `.github/workflows/cloudflare-failover.yml` to add the new node to the dropdown:

```yaml
inputs:
  target_node:
    description: 'Target HA node for DNS failover'
    type: choice
    required: true
    options:
      - ha01
      - ha02
      - ha03
      - ha04    # ← Add new option
```

### Step 4: Set Up the Runner on the New Node

**For system-based runners:**

```bash
# On the new node (ha04)
mkdir -p ~/actions-runner && cd ~/actions-runner

# Download latest runner
curl -o actions-runner-linux-x64.tar.gz -L \
  https://github.com/actions/runner/releases/latest/download/actions-runner-linux-x64-2.311.0.tar.gz

tar xzf ./actions-runner-linux-x64.tar.gz

# Configure with correct labels
./config.sh --url https://github.com/YOUR-ORG \
  --token YOUR-TOKEN \
  --name ha04 \
  --labels self-hosted,haproxy,ha04 \
  --runnergroup ha-servers \
  --unattended

# Install as service
sudo ./svc.sh install
sudo ./svc.sh start
```

**For containerized runners:**

```bash
# On the new node (ha04)
cd docker

cat > .env << 'EOF'
REPO_URL=https://github.com/YOUR-ORG
RUNNER_TOKEN=your_runner_registration_token
RUNNER_NAME=ha04
RUNNER_LABELS=self-hosted,haproxy,ha04
RUNNER_GROUP=ha-servers
DISABLE_AUTO_UPDATE=true
EOF

docker compose -f docker-compose.socket-api.yml up -d
```

### Step 5: Install HAProxy on the New Node

```bash
# On the new node (ha04)
sudo apt-get update
sudo apt-get install -y haproxy

# Create backup directory
sudo mkdir -p /etc/haproxy/backup

# Configure sudoers for runner
sudo tee /etc/sudoers.d/haproxy-deploy << 'EOF'
runner-user ALL=(ALL) NOPASSWD: /usr/sbin/haproxy -c -f *
runner-user ALL=(ALL) NOPASSWD: /bin/cp * /etc/haproxy/*
runner-user ALL=(ALL) NOPASSWD: /bin/mkdir -p /etc/haproxy/backup
runner-user ALL=(ALL) NOPASSWD: /bin/systemctl reload haproxy
runner-user ALL=(ALL) NOPASSWD: /bin/systemctl restart haproxy
runner-user ALL=(ALL) NOPASSWD: /bin/systemctl status haproxy
EOF
```

### Step 6: Verify and Deploy

1. Commit and push your changes:
   ```bash
   git add .
   git commit -m "Add ha04 node"
   git push
   ```

2. Verify the new runner appears in GitHub:
   - Go to **Organization** → **Settings** → **Actions** → **Runners**
   - Confirm `ha04` shows as "Online"

3. Trigger a deployment to test:
   - Go to **Actions** → **Deploy HAProxy**
   - Run the workflow
   - Verify `ha04` is included in the deployment matrix

---

## Removing a Node

Follow these steps to safely remove a node (e.g., `ha03`):

### Pre-Removal Checklist

⚠️ **Before removing a node, ensure:**

- [ ] The node is **not** the `active_node` in `cloudflare/active-node.yml`
- [ ] The node is **not** handling active traffic
- [ ] Other nodes have sufficient capacity
- [ ] You have at least one other healthy node

### Step 1: Failover Traffic (if active)

If the node to be removed is the active DNS node:

```bash
# Update active-node.yml
active_node: ha01  # Change to a different node
```

Or use emergency failover:
1. Go to **Actions** → **CloudFlare DNS Failover**
2. Select a different target node
3. Run the workflow

### Step 2: Remove Runner from GitHub

**Option A: Via GitHub UI**
1. Go to **Organization** → **Settings** → **Actions** → **Runners**
2. Find the runner (e.g., `ha03`)
3. Click **⋮** → **Remove**

**Option B: Via the node itself**
```bash
cd ~/actions-runner
./config.sh remove --token YOUR-REMOVE-TOKEN
```

### Step 3: Update CloudFlare Active Node Configuration

Edit `cloudflare/active-node.yml` to remove the node:

```yaml
external_ips:
  ha01: "203.0.113.11"
  ha02: "203.0.113.12"
  # ha03 removed
```

### Step 4: Update HAProxy Configuration

Edit `haproxy/haproxy.cfg` to remove server entries:

```haproxy
backend www_backend
    balance roundrobin
    option httpchk GET /health
    http-check expect status 200
    server ha01 192.168.0.11:8080 check inter 5s fall 3 rise 2
    server ha02 192.168.0.12:8080 check inter 5s fall 3 rise 2
    # server ha03 removed
```

### Step 5: Update Failover Workflow

Edit `.github/workflows/cloudflare-failover.yml`:

```yaml
inputs:
  target_node:
    description: 'Target HA node for DNS failover'
    type: choice
    required: true
    options:
      - ha01
      - ha02
      # ha03 removed
```

### Step 6: Commit and Deploy

```bash
git add .
git commit -m "Remove ha03 node"
git push
```

### Step 7: Decommission the Server

Once verified:
1. Stop HAProxy: `sudo systemctl stop haproxy`
2. Stop runner service: `sudo ./svc.sh stop && sudo ./svc.sh uninstall`
3. Optionally remove the server from your infrastructure

---

## File Modification Reference

Quick reference for all files that need updates when scaling:

| File | Add Node | Remove Node | Notes |
|------|----------|-------------|-------|
| `cloudflare/active-node.yml` | Add to `external_ips` | Remove from `external_ips` | External (public) IPs |
| `haproxy/haproxy.cfg` | Add server entries | Remove server entries | Only if backends on HA nodes |
| `.github/workflows/cloudflare-failover.yml` | Add to `options` | Remove from `options` | Dropdown choices |
| GitHub Runners | Register new runner | Deregister runner | Labels must match pattern |

### Files That Don't Need Updates

| File | Reason |
|------|--------|
| `.github/workflows/deploy.yml` | Dynamic runner detection |
| `.github/workflows/rollback.yml` | Dynamic runner detection |
| `cloudflare/dns-records.yml` | DNS records don't reference nodes directly |
| `scripts/*.sh` | Scripts are node-agnostic |

---

## Minimum and Maximum Nodes

### Minimum: 1 Node

The system works with a single node, but you lose:
- High availability (no failover target)
- Rolling deployments (single point of deployment)
- Load distribution

**Single-node considerations:**
- Set `active_node` to your single node
- Failover workflow has nowhere to fail over to
- Consider this for development/testing only

### Recommended: 3 Nodes

Three nodes provide:
- True high availability
- Rolling deployments with redundancy
- Odd number prevents split-brain scenarios (if using consensus)

### Maximum: No Hard Limit

There's no technical maximum, but consider:
- **Deployment time** increases with more nodes (sequential deployment)
- **Failover dropdown** becomes unwieldy with many nodes
- **GitHub API rate limits** may apply with very large runner counts

**For large clusters (10+ nodes):**
- Consider grouping nodes by region/role
- May need to adjust `max-parallel` in workflow matrix
- Monitor GitHub Actions usage limits

---

## Automation Script

Use the `scripts/manage-node.sh` script to automate node addition/removal:

```bash
# Add a new node
./scripts/manage-node.sh add ha04 203.0.113.14

# Remove a node
./scripts/manage-node.sh remove ha03

# List current nodes
./scripts/manage-node.sh list
```

See [scripts/manage-node.sh](../scripts/manage-node.sh) for usage details.

---

## Troubleshooting

### New node not appearing in deployments

**Symptoms:** Added a node but it's not included in deploy workflow runs.

**Diagnosis:**
1. Check runner is online in GitHub UI
2. Verify labels include `self-hosted`, `haproxy`, and `ha##`
3. Confirm runner is in `ha-servers` group

```bash
# Check runner status via CLI
gh api orgs/YOUR-ORG/actions/runners --jq '.runners[] | select(.name == "ha04")'
```

**Solution:** Ensure runner labels match the pattern `ha[0-9]+`.

---

### Failover fails to new node

**Symptoms:** Failover workflow fails with "Could not find external IP for node."

**Cause:** Node not added to `cloudflare/active-node.yml`.

**Solution:** Add the node's external IP to `external_ips` map.

---

### HAProxy validation fails after adding node

**Symptoms:** Deploy fails with HAProxy config syntax error.

**Cause:** Incorrect server entry syntax in `haproxy.cfg`.

**Solution:** Validate locally before pushing:
```bash
haproxy -c -f haproxy/haproxy.cfg
```

---

### Removed node still appears in workflows

**Symptoms:** Old node appears in deploy matrix even after removal.

**Cause:** Runner still registered in GitHub or cached matrix.

**Solution:**
1. Verify runner is removed from GitHub UI
2. Re-run the workflow (matrix is built fresh each run)

---

### Failover dropdown doesn't show new node

**Symptoms:** New node option not available in failover workflow.

**Cause:** Forgot to update `.github/workflows/cloudflare-failover.yml`.

**Solution:** Add the node to the `options` list and push.

---

## See Also

- [SETUP.md](SETUP.md) - Initial setup guide
- [DEPLOYMENT.md](DEPLOYMENT.md) - Deployment options
- [docker/README.md](../docker/README.md) - Containerized runners
