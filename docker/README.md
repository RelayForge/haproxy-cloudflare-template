# HAProxy Docker Deployment
# Alternative approach using Docker instead of system HAProxy
#
# This setup is ideal for:
# - Quick testing and development
# - Containerized infrastructure
# - Kubernetes/Docker Swarm environments

## Quick Start

```bash
# Navigate to docker directory
cd docker

# Copy example configuration
cp ../haproxy/haproxy.cfg.example ../haproxy/haproxy.cfg

# Edit configuration for your environment
nano ../haproxy/haproxy.cfg

# Start HAProxy
docker compose up -d

# View logs
docker compose logs -f

# Reload configuration (after editing haproxy.cfg)
docker compose restart

# Stop HAProxy
docker compose down
```

## Directory Structure

```
docker/
├── docker-compose.yml     # Docker Compose configuration
└── README.md              # This file

haproxy/
└── haproxy.cfg            # HAProxy configuration (mounted read-only)

certs/
└── *.pem                  # SSL certificates (mounted read-only)

errors/
└── *.http                 # Custom error pages (optional)
```

## SSL Certificates

Place your SSL certificates in the `certs/` directory:

```bash
mkdir -p certs
# Copy your certificate bundle
cp /path/to/your/cert.pem certs/
```

HAProxy expects certificate bundles in PEM format containing:
1. Private key
2. Certificate
3. Intermediate certificates (if any)

## Configuration Reload

To reload HAProxy configuration without downtime:

```bash
# Option 1: Restart container (brief interruption)
docker compose restart

# Option 2: Send SIGUSR2 for graceful reload
docker kill -s SIGUSR2 haproxy
```

## Health Checks

The container includes a health check that validates the configuration:

```bash
# Check container health status
docker inspect haproxy --format='{{.State.Health.Status}}'

# View health check logs
docker inspect haproxy --format='{{json .State.Health}}' | jq .
```

## Logs

```bash
# Follow logs
docker compose logs -f

# View last 100 lines
docker compose logs --tail=100

# Export logs
docker compose logs > haproxy.log
```

## Resource Limits

Default limits in docker-compose.yml:
- CPU: 2 cores max, 0.5 reserved
- Memory: 512MB max, 128MB reserved

Adjust in `docker-compose.yml` under `deploy.resources`.

## Stats Dashboard

To enable the HAProxy stats dashboard:

1. Uncomment the stats section in `haproxy.cfg`
2. Uncomment port `8404` in `docker-compose.yml`
3. Restart the container

Access at: `http://localhost:8404/stats`

## Integration with CI/CD

For GitHub Actions deployment to Docker:

```yaml
- name: Deploy HAProxy
  run: |
    cd docker
    docker compose pull
    docker compose up -d --build --wait
    docker compose ps
```

## Troubleshooting

### Container won't start
```bash
# Check configuration syntax
docker run --rm -v $(pwd)/../haproxy:/etc/haproxy:ro haproxy:2.9-alpine haproxy -c -f /etc/haproxy/haproxy.cfg
```

### Permission denied on certificates
```bash
# Ensure certificates are readable
chmod 644 certs/*.pem
```

### Port already in use
```bash
# Check what's using the port
netstat -tlnp | grep -E ':80|:443'
```
