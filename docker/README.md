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

| Variable | Required | Description |
|----------|----------|-------------|
| `REPO_URL` | Yes | GitHub repository URL |
| `RUNNER_TOKEN` | Yes | Runner registration token |
| `RUNNER_NAME` | Yes | Runner name (e.g., ha01) |
| `RUNNER_LABELS` | Yes | Labels (e.g., self-hosted,haproxy,ha01) |
| `RUNNER_GROUP` | No | Runner group (default: ha-servers) |

### Getting Runner Token

```bash
# Via GitHub CLI (organization runners)
gh api orgs/YOUR-ORG/actions/runners/registration-token --method POST --jq '.token'

# Via GitHub CLI (repository runners)
gh api repos/YOUR-ORG/YOUR-REPO/actions/runners/registration-token --method POST --jq '.token'
```

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
