# HAProxy Docker Deployment

This directory contains Docker Compose configurations for running HAProxy in containers. Multiple deployment options are available based on your security and control requirements.

## Deployment Options

| Option | File | Recommended | Description |
|--------|------|-------------|-------------|
| **HAProxy Only** | `docker-compose.yml` | For testing | Standalone HAProxy container |
| **Socket API** | `docker-compose.socket-api.yml` | ✅ Production | HAProxy + Runner with shared socket volume |
| **Docker Socket** | `docker-compose.docker-socket.yml` | ⚠️ Alternative | Runner controls HAProxy via Docker socket |

---

## Option 1: HAProxy Only (Testing/Development)

Simple standalone HAProxy container without an integrated runner.

```bash
# Quick start
cp ../haproxy/haproxy.cfg.example ../haproxy/haproxy.cfg
docker compose up -d
docker compose logs -f
```

---

## Option 2: Socket API (Recommended for Production)

This approach uses HAProxy's Runtime API socket for configuration control. The runner container communicates with HAProxy via a shared Unix socket volume.

### Benefits

- ✅ **More secure** - No Docker socket exposure
- ✅ **Granular control** - Enable/disable servers without restart
- ✅ **Live updates** - Runtime configuration changes
- ✅ **Minimal attack surface** - Runner has limited permissions

### Architecture

```
┌─────────────────────────────────────────────────────────┐
│                    Docker Host                          │
│  ┌─────────────────┐       ┌────────────────────────┐  │
│  │    HAProxy      │       │   GitHub Runner        │  │
│  │                 │       │                        │  │
│  │  /var/run/      │◄─────►│  /var/run/             │  │
│  │  haproxy/       │       │  haproxy/              │  │
│  │  admin.sock     │       │  admin.sock            │  │
│  │                 │       │                        │  │
│  │  stats socket   │       │  socat commands        │  │
│  └─────────────────┘       └────────────────────────┘  │
│           ▲                         ▲                   │
│           │    haproxy_socket       │                   │
│           └─────────────────────────┘                   │
│                 (shared volume)                         │
└─────────────────────────────────────────────────────────┘
```

### Quick Start

```bash
# 1. Copy example configuration
cp ../haproxy/haproxy.cfg.example ../haproxy/haproxy.cfg

# 2. Configure HAProxy (ensure stats socket is enabled)
#    stats socket /var/run/haproxy/admin.sock level admin

# 3. Create environment file
cat > .env << 'EOF'
REPO_URL=https://github.com/YOUR-ORG/YOUR-REPO
RUNNER_TOKEN=your_runner_registration_token
RUNNER_NAME=ha01
RUNNER_LABELS=self-hosted,haproxy,ha01
RUNNER_GROUP=ha-servers
EOF

# 4. Initialize config volume
docker compose -f docker-compose.socket-api.yml up haproxy -d --wait
docker cp ../haproxy/haproxy.cfg haproxy:/usr/local/etc/haproxy/
docker restart haproxy

# 5. Start runner
docker compose -f docker-compose.socket-api.yml up -d

# 6. Verify
docker compose -f docker-compose.socket-api.yml ps
```

### Deploy Script Usage

From the runner container (via GitHub Actions):

```bash
./scripts/apply_container.sh /workspace/haproxy/haproxy.cfg
```

### Runtime Commands

```bash
# Show server status
echo "show servers state" | socat stdio /var/run/haproxy/admin.sock

# Disable a server
echo "disable server backend_name/server_name" | socat stdio /var/run/haproxy/admin.sock

# Enable a server
echo "enable server backend_name/server_name" | socat stdio /var/run/haproxy/admin.sock

# Show info
echo "show info" | socat stdio /var/run/haproxy/admin.sock

# Show stats
echo "show stat" | socat stdio /var/run/haproxy/admin.sock
```

---

## Option 3: Docker Socket Mount (Alternative)

This approach gives the runner container access to the Docker socket, allowing full control over the HAProxy container.

### ⚠️ Security Warning

Docker socket access grants **root-equivalent permissions** on the host. Only use this in trusted environments.

### Benefits

- Full container control (restart, logs, exec)
- Similar to host-based runner experience
- Can update and fully reload HAProxy

### Risks

- Runner compromise = full host compromise
- Container escape is trivial with Docker socket
- Not recommended for production environments

### Architecture

```
┌─────────────────────────────────────────────────────────┐
│                    Docker Host                          │
│                                                         │
│  ┌─────────────────┐       ┌────────────────────────┐  │
│  │    HAProxy      │       │   GitHub Runner        │  │
│  │                 │       │                        │  │
│  │                 │◄──────│  docker exec           │  │
│  │                 │       │  docker kill -s HUP    │  │
│  │                 │       │  docker cp             │  │
│  │                 │       │                        │  │
│  └─────────────────┘       └────────────────────────┘  │
│                                    │                    │
│                                    ▼                    │
│                            /var/run/docker.sock         │
│                                                         │
└─────────────────────────────────────────────────────────┘
```

### Quick Start

```bash
# 1. Copy example configuration
cp ../haproxy/haproxy.cfg.example ../haproxy/haproxy.cfg

# 2. Create environment file
cat > .env << 'EOF'
REPO_URL=https://github.com/YOUR-ORG/YOUR-REPO
RUNNER_TOKEN=your_runner_registration_token
RUNNER_NAME=ha01
RUNNER_LABELS=self-hosted,haproxy,ha01
RUNNER_GROUP=ha-servers
EOF

# 3. Start containers
docker compose -f docker-compose.docker-socket.yml up -d

# 4. Verify
docker compose -f docker-compose.docker-socket.yml ps
```

### Deploy Script Usage

From the runner container (via GitHub Actions):

```bash
./scripts/apply_container_docker.sh /workspace/haproxy/haproxy.cfg
```

---

## HAProxy Configuration Requirements

Ensure your `haproxy.cfg` includes the stats socket for Socket API method:

```haproxy
global
    # ... other settings ...
    
    # Runtime API socket (required for Socket API method)
    stats socket /var/run/haproxy/admin.sock level admin mode 660
    
    # Optional: TCP socket for remote access
    # stats socket ipv4@127.0.0.1:9999 level admin
```

---

## Volumes

### Socket API Method

| Volume | Purpose |
|--------|---------|
| `haproxy_socket` | Shared Unix socket for Runtime API |
| `haproxy_config` | HAProxy configuration files |
| `haproxy_backup` | Configuration backups and LKG |

### Docker Socket Method

| Volume | Purpose |
|--------|---------|
| `haproxy_backup` | Configuration backups and LKG |
| `/var/run/docker.sock` | Docker socket (bind mount) |

---

## Environment Variables

| Variable | Required | Default | Example | Description |
|----------|----------|---------|---------|-------------|
| `REPO_URL` | Yes | - | `https://github.com/acme/haproxy` | GitHub repository or organization URL |
| `RUNNER_TOKEN` | Yes | - | `AABCDEF...` | Runner registration token (expires in 1 hour) |
| `RUNNER_NAME` | Yes | - | `ha01` | Unique runner name matching node label |
| `RUNNER_LABELS` | Yes | - | `self-hosted,haproxy,ha01` | Comma-separated labels for runner selection |
| `RUNNER_GROUP` | No | `ha-servers` | `ha-servers` | Organization runner group name |
| `RUNNER_WORKDIR` | No | `/workspace` | `/workspace` | Working directory for job execution |
| `DISABLE_AUTO_UPDATE` | No | `false` | `true` | Disable automatic runner updates (recommended for containers) |

---

### Organization vs Repository Runners

| Type | URL Format | Best For | Runner Group Support |
|------|------------|----------|---------------------|
| **Organization** | `https://github.com/YOUR-ORG` | Multiple repos, centralized management | ✅ Yes |
| **Repository** | `https://github.com/YOUR-ORG/YOUR-REPO` | Single repo, isolated runners | ❌ No |

**Recommendation:** Use **organization runners** with runner groups for multi-node HAProxy deployments. This allows:
- Centralized runner management
- Runner groups for access control
- Dynamic runner detection across repositories

---

### Getting Each Value

#### REPO_URL

The GitHub URL where the runner will be registered.

**For organization runners (recommended):**
```
https://github.com/YOUR-ORG
```

**For repository runners:**
```
https://github.com/YOUR-ORG/YOUR-REPO
```

**How to find it:**
1. Navigate to your GitHub organization or repository
2. Copy the URL from your browser's address bar
3. Remove any trailing paths (e.g., `/settings`)

---

#### RUNNER_TOKEN

A temporary token used to register the runner with GitHub. **Tokens expire after 1 hour.**

**Option A: Via GitHub Web UI (Recommended)**

1. **For organization runners:**
   - Go to **Organization** → **Settings** → **Actions** → **Runners**
   - Click **"New runner"** → **"New self-hosted runner"**
   - Select **Linux** as the operating system
   - The token is shown in the configuration command:
     ```bash
     ./config.sh --url https://github.com/YOUR-ORG --token AABCDEFGHIJKLMNOP...
     ```
   - Copy the token value (starts with `AA...`)

2. **For repository runners:**
   - Go to **Repository** → **Settings** → **Actions** → **Runners**
   - Click **"New self-hosted runner"**
   - Copy the token from the configuration command

**Option B: Via GitHub CLI**

First, install and authenticate the GitHub CLI:
```bash
# Install (Ubuntu/Debian)
curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg | sudo dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg
echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" | sudo tee /etc/apt/sources.list.d/github-cli.list > /dev/null
sudo apt update && sudo apt install gh

# Authenticate
gh auth login
```

Then generate the token:
```bash
# Organization runners
gh api orgs/YOUR-ORG/actions/runners/registration-token --method POST --jq '.token'

# Repository runners
gh api repos/YOUR-ORG/YOUR-REPO/actions/runners/registration-token --method POST --jq '.token'
```

⚠️ **Important:** Tokens expire after **1 hour**. If registration fails with "token expired", generate a new token.

---

#### RUNNER_NAME

A unique identifier for this runner. Must be unique across all runners in the organization/repository.

**Naming convention:**
- Match the node label for consistency: `ha01`, `ha02`, `ha03`
- Use only alphanumeric characters, dashes, and underscores
- Keep names short and descriptive

**Examples:**
| Node | Runner Name |
|------|-------------|
| HA Node 1 | `ha01` |
| HA Node 2 | `ha02` |
| HA Node 3 | `ha03` |

---

#### RUNNER_LABELS

Comma-separated labels that identify this runner. Used by workflows to select which runners execute jobs.

**Required labels for this template:**
- `self-hosted` - Standard self-hosted runner identifier
- `haproxy` - Identifies runners for HAProxy deployment
- `ha01`/`ha02`/`ha03` - Node-specific label (must match pattern `ha[0-9]+`)

**Format:**
```
self-hosted,haproxy,ha01
```

The dynamic runner detection in workflows uses these labels to:
1. Find runners in the `ha-servers` group with `haproxy` label
2. Extract node identifiers matching `ha[0-9]+` pattern
3. Build a deployment matrix

---

#### RUNNER_GROUP

The organization runner group this runner belongs to. Runner groups provide access control for which repositories can use runners.

**Default:** `ha-servers`

**To create a runner group:**
1. Go to **Organization** → **Settings** → **Actions** → **Runner groups**
2. Click **"New runner group"**
3. Name: `ha-servers`
4. Select repositories that can access this group
5. Click **"Create group"**

⚠️ **Note:** Runner groups are only available for **organization runners**, not repository runners.

See also: [docs/SETUP.md](../docs/SETUP.md#step-6-set-up-self-hosted-runners) for detailed runner group setup.

---

#### RUNNER_WORKDIR

The directory inside the container where GitHub Actions jobs are executed.

**Default:** `/workspace`

This directory is used for:
- Checking out repository code during workflow runs
- Executing scripts and commands
- Storing temporary job files

You typically don't need to change this unless you have specific path requirements.

---

#### DISABLE_AUTO_UPDATE

Controls whether the GitHub Actions runner automatically updates itself.

**Default:** `false`
**Recommended for containers:** `true`

**Why set to `true` in containers?**
- Container images should be immutable
- You control the runner version via the image tag
- Auto-updates can cause unexpected behavior
- Updates may conflict with container-installed packages

**To update the runner:** Pull a new version of the `myoung34/github-runner` image.

---

## SSL Certificates

Place certificates in the `certs/` directory:

```bash
mkdir -p ../certs
cp /path/to/your/cert.pem ../certs/
```

Certificates are mounted read-only in all configurations.

---

## Workflow Integration

Update your deploy workflow to use container scripts:

```yaml
# For Socket API method (recommended)
- name: Deploy HAProxy config
  run: |
    set -euo pipefail
    ./scripts/apply_container.sh

# For Docker Socket method
- name: Deploy HAProxy config
  run: |
    set -euo pipefail
    ./scripts/apply_container_docker.sh
```

---

## Stats Dashboard

To enable the HAProxy stats dashboard:

1. Uncomment the stats section in `haproxy.cfg`
2. Uncomment port `8404` in the compose file
3. Restart the container

Access at: `http://localhost:8404/stats`

---

## Comparison Table

| Feature | HAProxy Only | Socket API | Docker Socket |
|---------|--------------|------------|---------------|
| Use case | Testing | ✅ Production | Trusted envs |
| Security | N/A | ✅ High | ⚠️ Low |
| Server control | Manual | Enable/disable | Full restart |
| Config reload | Manual restart | Via file + restart | Via SIGHUP |
| Live stats | Manual | ✅ Yes | Via exec |
| Integrated runner | ❌ No | ✅ Yes | ✅ Yes |
| Attack surface | Minimal | Minimal | Container escape risk |

---

## Troubleshooting

### Socket not found (Socket API)

```bash
# Check if socket exists
docker exec haproxy ls -la /var/run/haproxy/

# Verify HAProxy config includes stats socket
docker exec haproxy grep "stats socket" /usr/local/etc/haproxy/haproxy.cfg
```

### Permission denied (Docker Socket)

```bash
# Check Docker socket permissions
ls -la /var/run/docker.sock

# Runner may need to be in docker group
docker exec github-runner groups
```

### Container won't start

```bash
# Check configuration syntax
docker run --rm -v $(pwd)/../haproxy:/etc/haproxy:ro haproxy:2.9-alpine haproxy -c -f /etc/haproxy/haproxy.cfg

# Check health status
docker inspect haproxy --format='{{json .State.Health}}' | jq .
```

### Runner not connecting

```bash
# Check runner logs
docker logs github-runner

# Verify runner token
docker exec github-runner cat /runner/.runner | jq .

# Re-register runner (remove and restart)
docker compose -f docker-compose.socket-api.yml down runner
docker compose -f docker-compose.socket-api.yml up runner -d
```

### Port already in use

```bash
# Check what's using the port
netstat -tlnp | grep -E ':80|:443'
```

---

## Runner Registration Errors

Common errors when registering GitHub Actions runners in containers.

### Token expired

**Error:**
```
The registration token expired. Please generate a new token.
```

**Cause:** Runner registration tokens are valid for only 1 hour.

**Solution:**
1. Generate a new token via GitHub UI or CLI (see [Getting Runner Token](#runner_token))
2. Update the `RUNNER_TOKEN` in your `.env` file
3. Restart the runner container:
   ```bash
   docker compose -f docker-compose.socket-api.yml down runner
   docker compose -f docker-compose.socket-api.yml up runner -d
   ```

---

### Runner already exists

**Error:**
```
A runner with the name 'ha01' already exists in this organization.
```

**Cause:** A runner with the same name is already registered.

**Solution A: Remove the existing runner**
1. Go to **Organization** → **Settings** → **Actions** → **Runners**
2. Find the runner with the conflicting name
3. Click the **⋮** menu → **Remove**
4. Retry registration

**Solution B: Use --replace flag (manual registration only)**
```bash
./config.sh --url https://github.com/YOUR-ORG --token YOUR-TOKEN --replace
```

---

### Permission denied / Access denied

**Error:**
```
Access denied. Verify that you have admin access to the organization or repository.
```

**Cause:** The token lacks required permissions or user isn't an admin.

**Solution:**
1. **For organization runners:** Ensure you have **Owner** or **Admin** role
2. **For repository runners:** Ensure you have **Admin** access to the repository
3. If using GitHub CLI, ensure your PAT has:
   - `admin:org` scope for organization runners
   - `repo` scope for repository runners

---

### Runner group not found

**Error:**
```
Could not find the runner group 'ha-servers'.
```

**Cause:** The specified runner group doesn't exist or the repository lacks access.

**Solution:**
1. Create the runner group:
   - Go to **Organization** → **Settings** → **Actions** → **Runner groups**
   - Click **"New runner group"**
   - Name: `ha-servers`
   - Add repositories that should have access
2. Or change `RUNNER_GROUP` to an existing group name

---

### Network connection failed

**Error:**
```
Unable to connect to GitHub.com
```
or
```
A]connection attempt failed because the connected party did not properly respond
```

**Cause:** Firewall or proxy blocking GitHub endpoints.

**Solution:**
Ensure outbound HTTPS (port 443) access to:
- `github.com`
- `api.github.com`
- `*.actions.githubusercontent.com`
- `ghcr.io` (for container images)

```bash
# Test connectivity
curl -I https://github.com
curl -I https://api.github.com
```

---

### Service installation failed

**Error:**
```
Must run as sudo
```
or
```
Service already exists
```

**Cause:** Permission issues or previous installation remnants.

**Solution:**
```bash
# Remove existing service
sudo ./svc.sh uninstall

# Reinstall
sudo ./svc.sh install
sudo ./svc.sh start
```

---

### Runner offline in GitHub UI

**Symptoms:** Runner shows as "Offline" in GitHub Settings even though container is running.

**Diagnosis:**
```bash
# Check container status
docker ps | grep github-runner

# Check runner logs
docker logs github-runner --tail 100

# Check if runner process is running inside container
docker exec github-runner ps aux | grep Runner
```

**Common causes:**
1. Token expired during registration
2. Network connectivity issues
3. Runner crashed after startup

**Solution:**
```bash
# Restart the runner container
docker compose -f docker-compose.socket-api.yml restart runner

# Or recreate with fresh token
docker compose -f docker-compose.socket-api.yml down runner
# Update RUNNER_TOKEN in .env
docker compose -f docker-compose.socket-api.yml up runner -d
```
