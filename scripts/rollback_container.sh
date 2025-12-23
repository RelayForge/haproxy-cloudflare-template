#!/usr/bin/env bash
# rollback_container.sh - Rollback HAProxy config using Runtime API
#
# This script rolls back to the Last Known Good (LKG) configuration
# when using the socket-api Docker Compose setup.
#
# Usage:
#   ./scripts/rollback_container.sh

set -euo pipefail

# Configuration
SOCKET_PATH="/var/run/haproxy/admin.sock"
CONFIG_DIR="/haproxy-config"
BACKUP_DIR="/haproxy-backup"
ACTIVE_CONFIG="${CONFIG_DIR}/haproxy.cfg"
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
    log_info "=== HAProxy Rollback (Socket API) ==="
    
    # Check for LKG
    if [ ! -f "${LKG_CONFIG}" ]; then
        log_error "No Last Known Good configuration found!"
        
        # Try to find newest backup
        NEWEST_BACKUP=$(ls -t "${BACKUP_DIR}"/haproxy.cfg.* 2>/dev/null | grep -v LKG | head -1 || true)
        
        if [ -n "${NEWEST_BACKUP}" ]; then
            log_info "Found backup: ${NEWEST_BACKUP}"
            cp "${NEWEST_BACKUP}" "${ACTIVE_CONFIG}"
        else
            log_error "No backups available. Cannot rollback."
            exit 1
        fi
    else
        log_info "Rolling back to LKG configuration..."
        cp "${LKG_CONFIG}" "${ACTIVE_CONFIG}"
    fi
    
    # Verify HAProxy can read the config
    if [ -S "${SOCKET_PATH}" ]; then
        log_info "Verifying HAProxy is responsive..."
        if echo "show info" | socat stdio "${SOCKET_PATH}" > /dev/null 2>&1; then
            log_info "HAProxy is responsive"
        else
            log_warn "Cannot verify HAProxy status via socket"
        fi
    fi
    
    log_info "Config restored. Container restart may be needed for changes to take effect."
    log_info "=== Rollback Complete ==="
}

main "$@"
