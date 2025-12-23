#!/usr/bin/env bash
# rollback_container_docker.sh - Rollback HAProxy using Docker socket
#
# This script rolls back to the Last Known Good (LKG) configuration
# when using the Docker socket mount setup.
#
# Usage:
#   ./scripts/rollback_container_docker.sh

set -euo pipefail

# Configuration
HAPROXY_CONTAINER="${HAPROXY_CONTAINER:-haproxy}"
BACKUP_DIR="/haproxy-backup"
LKG_CONFIG="${BACKUP_DIR}/haproxy.cfg.LKG"

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

main() {
    log_info "=== HAProxy Rollback (Docker Socket) ==="
    
    # Check prerequisites
    if [ ! -S /var/run/docker.sock ]; then
        log_error "Docker socket not found"
        exit 1
    fi
    
    # Find rollback config
    ROLLBACK_CONFIG=""
    
    if [ -f "${LKG_CONFIG}" ]; then
        log_info "Found LKG configuration"
        ROLLBACK_CONFIG="${LKG_CONFIG}"
    else
        log_warn "No LKG found, searching for newest backup..."
        NEWEST_BACKUP=$(ls -t "${BACKUP_DIR}"/haproxy.cfg.* 2>/dev/null | head -1 || true)
        
        if [ -n "${NEWEST_BACKUP}" ]; then
            log_info "Found backup: ${NEWEST_BACKUP}"
            ROLLBACK_CONFIG="${NEWEST_BACKUP}"
        else
            log_error "No backups available!"
            exit 1
        fi
    fi
    
    # Validate the rollback config
    log_info "Validating rollback configuration..."
    docker cp "${ROLLBACK_CONFIG}" "${HAPROXY_CONTAINER}:/tmp/haproxy.cfg.rollback"
    
    if ! docker exec "${HAPROXY_CONTAINER}" haproxy -c -f /tmp/haproxy.cfg.rollback; then
        log_error "Rollback configuration is invalid!"
        docker exec "${HAPROXY_CONTAINER}" rm -f /tmp/haproxy.cfg.rollback
        exit 1
    fi
    
    # Apply rollback config
    log_info "Applying rollback configuration..."
    docker exec "${HAPROXY_CONTAINER}" \
        mv /tmp/haproxy.cfg.rollback /usr/local/etc/haproxy/haproxy.cfg
    
    # Reload HAProxy
    log_info "Reloading HAProxy..."
    docker kill -s HUP "${HAPROXY_CONTAINER}"
    
    sleep 2
    
    # Verify
    if docker ps --filter "name=${HAPROXY_CONTAINER}" --filter "status=running" | grep -q "${HAPROXY_CONTAINER}"; then
        log_info "HAProxy is running"
    else
        log_error "HAProxy container is not running! Attempting restart..."
        docker restart "${HAPROXY_CONTAINER}"
    fi
    
    log_info "=== Rollback Complete ==="
}

main "$@"
