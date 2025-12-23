#!/usr/bin/env bash
# apply_container_docker.sh - Deploy HAProxy config using Docker socket
#
# This script is designed for use inside the runner container when using
# the Docker socket mount setup (docker-compose.docker-socket.yml).
#
# It controls the HAProxy container via Docker commands.
#
# ⚠️ Security Note: Requires Docker socket mount (/var/run/docker.sock)
#
# Usage:
#   ./scripts/apply_container_docker.sh [config_path]
#
# Arguments:
#   config_path  - Path to haproxy.cfg (default: /workspace/haproxy/haproxy.cfg)

set -euo pipefail

# Configuration
HAPROXY_CONFIG="${1:-/workspace/haproxy/haproxy.cfg}"
HAPROXY_CONTAINER="${HAPROXY_CONTAINER:-haproxy}"
BACKUP_DIR="/haproxy-backup"
LKG_CONFIG="${BACKUP_DIR}/haproxy.cfg.LKG"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    if [ ! -f "${HAPROXY_CONFIG}" ]; then
        log_error "Config file not found: ${HAPROXY_CONFIG}"
        exit 1
    fi
    
    if [ ! -S /var/run/docker.sock ]; then
        log_error "Docker socket not found. This script requires Docker socket access."
        exit 1
    fi
    
    if ! command -v docker &> /dev/null; then
        log_error "Docker CLI not found in container"
        exit 1
    fi
    
    # Verify HAProxy container exists
    if ! docker ps --format '{{.Names}}' | grep -q "^${HAPROXY_CONTAINER}$"; then
        log_error "HAProxy container '${HAPROXY_CONTAINER}' not found or not running"
        exit 1
    fi
    
    mkdir -p "${BACKUP_DIR}"
}

# Validate configuration by running haproxy -c inside the container
validate_config() {
    log_info "Validating HAProxy configuration..."
    
    # Copy config to container and validate
    docker cp "${HAPROXY_CONFIG}" "${HAPROXY_CONTAINER}:/tmp/haproxy.cfg.pending"
    
    if ! docker exec "${HAPROXY_CONTAINER}" haproxy -c -f /tmp/haproxy.cfg.pending; then
        log_error "Configuration validation failed!"
        docker exec "${HAPROXY_CONTAINER}" rm -f /tmp/haproxy.cfg.pending
        exit 1
    fi
    
    log_info "Configuration syntax is valid"
}

# Backup current configuration
backup_config() {
    log_info "Backing up current configuration..."
    
    # Get current config from container
    if docker exec "${HAPROXY_CONTAINER}" test -f /usr/local/etc/haproxy/haproxy.cfg; then
        docker cp "${HAPROXY_CONTAINER}:/usr/local/etc/haproxy/haproxy.cfg" \
            "${BACKUP_DIR}/haproxy.cfg.${TIMESTAMP}"
        log_info "Backup saved: haproxy.cfg.${TIMESTAMP}"
    else
        log_warn "No existing config to backup"
    fi
}

# Apply new configuration
apply_config() {
    log_info "Applying new configuration..."
    
    # Move pending config to active location
    docker exec "${HAPROXY_CONTAINER}" \
        mv /tmp/haproxy.cfg.pending /usr/local/etc/haproxy/haproxy.cfg
}

# Graceful reload using SIGHUP
reload_haproxy() {
    log_info "Triggering graceful reload (SIGHUP)..."
    
    docker kill -s HUP "${HAPROXY_CONTAINER}"
    
    # Wait for reload to complete
    sleep 2
    
    # Verify container is still healthy
    if ! docker exec "${HAPROXY_CONTAINER}" haproxy -c -f /usr/local/etc/haproxy/haproxy.cfg; then
        log_error "HAProxy failed after reload!"
        return 1
    fi
    
    log_info "HAProxy reloaded successfully"
}

# Mark as last known good
mark_lkg() {
    log_info "Marking configuration as Last Known Good..."
    cp "${HAPROXY_CONFIG}" "${LKG_CONFIG}"
    log_info "LKG updated: ${LKG_CONFIG}"
}

# Rollback to LKG
rollback() {
    log_error "Deployment failed! Initiating rollback..."
    
    if [ -f "${LKG_CONFIG}" ]; then
        log_info "Rolling back to Last Known Good configuration..."
        
        docker cp "${LKG_CONFIG}" "${HAPROXY_CONTAINER}:/usr/local/etc/haproxy/haproxy.cfg"
        docker kill -s HUP "${HAPROXY_CONTAINER}"
        
        sleep 2
        
        if docker exec "${HAPROXY_CONTAINER}" haproxy -c -f /usr/local/etc/haproxy/haproxy.cfg; then
            log_info "Rollback successful"
        else
            log_error "Rollback also failed! Manual intervention required."
            docker restart "${HAPROXY_CONTAINER}"
        fi
    else
        log_error "No LKG config found! Restarting container..."
        docker restart "${HAPROXY_CONTAINER}"
    fi
    
    exit 1
}

# Show container status
show_status() {
    log_info "HAProxy container status:"
    docker ps --filter "name=${HAPROXY_CONTAINER}" --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
}

# Main execution
main() {
    log_info "=== HAProxy Container Deploy (Docker Socket) ==="
    log_info "Config: ${HAPROXY_CONFIG}"
    log_info "Container: ${HAPROXY_CONTAINER}"
    log_info "Timestamp: ${TIMESTAMP}"
    
    check_prerequisites
    validate_config
    backup_config
    apply_config
    
    if ! reload_haproxy; then
        rollback
    fi
    
    mark_lkg
    show_status
    
    log_info "=== Deployment Complete ==="
}

main "$@"
