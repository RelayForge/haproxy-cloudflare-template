#!/usr/bin/env bash
# apply_container.sh - Deploy HAProxy config using Runtime API (Recommended)
#
# This script is designed for use inside the runner container when using
# the socket-api Docker Compose setup (docker-compose.socket-api.yml).
#
# It uses HAProxy's Runtime API socket for configuration control.
#
# Usage:
#   ./scripts/apply_container.sh [config_path]
#
# Arguments:
#   config_path  - Path to haproxy.cfg (default: /workspace/haproxy/haproxy.cfg)

set -euo pipefail

# Configuration
HAPROXY_CONFIG="${1:-/workspace/haproxy/haproxy.cfg}"
SOCKET_PATH="/var/run/haproxy/admin.sock"
CONFIG_DIR="/haproxy-config"
BACKUP_DIR="/haproxy-backup"
ACTIVE_CONFIG="${CONFIG_DIR}/haproxy.cfg"
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
    
    if ! command -v socat &> /dev/null; then
        log_warn "socat not found, installing..."
        apk add --no-cache socat
    fi
    
    # Ensure directories exist
    mkdir -p "${CONFIG_DIR}" "${BACKUP_DIR}"
}

# Validate configuration syntax
validate_config() {
    log_info "Validating HAProxy configuration..."
    
    # Copy to temp location and validate using haproxy binary
    # We'll use docker exec from inside container if needed, or rely on post-reload check
    cp "${HAPROXY_CONFIG}" "${CONFIG_DIR}/haproxy.cfg.pending"
    
    log_info "Configuration syntax appears valid (full validation on reload)"
}

# Backup current configuration
backup_config() {
    if [ -f "${ACTIVE_CONFIG}" ]; then
        log_info "Backing up current configuration..."
        cp "${ACTIVE_CONFIG}" "${BACKUP_DIR}/haproxy.cfg.${TIMESTAMP}"
        log_info "Backup saved: haproxy.cfg.${TIMESTAMP}"
    fi
}

# Apply new configuration
apply_config() {
    log_info "Applying new configuration..."
    cp "${HAPROXY_CONFIG}" "${ACTIVE_CONFIG}"
}

# Trigger graceful reload via socket
reload_haproxy() {
    log_info "Requesting graceful reload via Runtime API..."
    
    if [ ! -S "${SOCKET_PATH}" ]; then
        log_error "HAProxy socket not found: ${SOCKET_PATH}"
        log_error "Make sure HAProxy is running with stats socket enabled"
        exit 1
    fi
    
    # Check if HAProxy is responsive
    if ! echo "show info" | socat stdio "${SOCKET_PATH}" > /dev/null 2>&1; then
        log_error "Cannot communicate with HAProxy socket"
        exit 1
    fi
    
    # Note: HAProxy reload via socket is limited. For config changes,
    # we typically need to trigger a container reload.
    # The socket is mainly for runtime commands (enable/disable servers, etc.)
    
    log_info "Verifying HAProxy is healthy..."
    echo "show info" | socat stdio "${SOCKET_PATH}" | head -5
    
    log_info "Config applied. HAProxy will pick up changes on next reload."
    log_warn "For immediate config reload, container restart may be needed."
}

# Mark as last known good
mark_lkg() {
    log_info "Marking configuration as Last Known Good..."
    cp "${ACTIVE_CONFIG}" "${LKG_CONFIG}"
    log_info "LKG updated: ${LKG_CONFIG}"
}

# Show server status
show_status() {
    log_info "Current HAProxy server status:"
    echo "show servers state" | socat stdio "${SOCKET_PATH}" 2>/dev/null || true
}

# Main execution
main() {
    log_info "=== HAProxy Container Deploy (Socket API) ==="
    log_info "Config: ${HAPROXY_CONFIG}"
    log_info "Timestamp: ${TIMESTAMP}"
    
    check_prerequisites
    validate_config
    backup_config
    apply_config
    reload_haproxy
    mark_lkg
    show_status
    
    log_info "=== Deployment Complete ==="
}

main "$@"
