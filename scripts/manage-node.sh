#!/usr/bin/env bash
#---------------------------------------------------------------------
# Node Management Script
# Assists with adding/removing HAProxy nodes from configuration files
#---------------------------------------------------------------------
# Usage:
#   ./scripts/manage-node.sh list                 - List current nodes
#   ./scripts/manage-node.sh add <node> <ip>      - Add a new node
#   ./scripts/manage-node.sh remove <node>        - Remove a node
#
# Examples:
#   ./scripts/manage-node.sh list
#   ./scripts/manage-node.sh add ha04 192.0.2.14
#   ./scripts/manage-node.sh remove ha03
#
# Note: This script updates YAML config files automatically.
#       HAProxy config (haproxy.cfg) must be updated manually.
#---------------------------------------------------------------------
set -euo pipefail

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
ACTIVE_NODE_FILE="$REPO_ROOT/cloudflare/active-node.yml"
FAILOVER_WORKFLOW="$REPO_ROOT/.github/workflows/cloudflare-failover.yml"
HAPROXY_CONFIG="$REPO_ROOT/haproxy/haproxy.cfg"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

#---------------------------------------------------------------------
# Helper functions
#---------------------------------------------------------------------
log_info() {
    echo -e "${BLUE}ℹ${NC} $1"
}

log_success() {
    echo -e "${GREEN}✓${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}⚠${NC} $1"
}

log_error() {
    echo -e "${RED}✗${NC} $1"
}

check_dependencies() {
    local missing=()
    
    if ! command -v yq &> /dev/null; then
        missing+=("yq")
    fi
    
    if ! command -v sed &> /dev/null; then
        missing+=("sed")
    fi
    
    if [ ${#missing[@]} -gt 0 ]; then
        log_error "Missing required dependencies: ${missing[*]}"
        echo "Install with:"
        echo "  brew install yq     # macOS"
        echo "  apt install yq      # Ubuntu/Debian"
        echo "  snap install yq     # Snap"
        exit 1
    fi
}

validate_node_name() {
    local node="$1"
    if [[ ! "$node" =~ ^ha[0-9]+$ ]]; then
        log_error "Invalid node name: $node"
        echo "Node names must follow pattern: ha01, ha02, ha03, etc."
        exit 1
    fi
}

validate_ip() {
    local ip="$1"
    if [[ ! "$ip" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        log_error "Invalid IP address: $ip"
        exit 1
    fi
}

#---------------------------------------------------------------------
# List nodes
#---------------------------------------------------------------------
cmd_list() {
    log_info "Current nodes in configuration:"
    echo ""
    
    if [ -f "$ACTIVE_NODE_FILE" ]; then
        echo "From cloudflare/active-node.yml:"
        echo "  Active node: $(yq e '.active_node' "$ACTIVE_NODE_FILE")"
        echo "  Configured nodes:"
        yq e '.external_ips | to_entries | .[] | "    " + .key + ": " + .value' "$ACTIVE_NODE_FILE"
    else
        log_warning "active-node.yml not found (using example file?)"
    fi
    
    echo ""
    echo "From .github/workflows/cloudflare-failover.yml:"
    grep -A 20 "target_node:" "$FAILOVER_WORKFLOW" | grep "^\s*- ha" | sed 's/^/  /'
    
    echo ""
    log_info "To add a node:    $0 add <node> <ip>"
    log_info "To remove a node: $0 remove <node>"
}

#---------------------------------------------------------------------
# Add node
#---------------------------------------------------------------------
cmd_add() {
    local node="$1"
    local ip="$2"
    
    validate_node_name "$node"
    validate_ip "$ip"
    
    log_info "Adding node $node with IP $ip..."
    echo ""
    
    # Check if node already exists
    if [ -f "$ACTIVE_NODE_FILE" ]; then
        local existing_ip
        existing_ip=$(yq e ".external_ips.$node // \"\"" "$ACTIVE_NODE_FILE")
        if [ -n "$existing_ip" ] && [ "$existing_ip" != "null" ]; then
            log_error "Node $node already exists with IP $existing_ip"
            exit 1
        fi
    fi
    
    # Update active-node.yml
    if [ -f "$ACTIVE_NODE_FILE" ]; then
        log_info "Updating cloudflare/active-node.yml..."
        yq e ".external_ips.$node = \"$ip\"" -i "$ACTIVE_NODE_FILE"
        log_success "Added $node: $ip to active-node.yml"
    else
        log_warning "active-node.yml not found - skipping"
    fi
    
    # Update cloudflare-failover.yml
    if [ -f "$FAILOVER_WORKFLOW" ]; then
        log_info "Updating cloudflare-failover.yml..."
        
        # Check if node already in options
        if grep -q "^\s*- $node\$" "$FAILOVER_WORKFLOW"; then
            log_warning "Node $node already in failover workflow options"
        else
            # Find the last option and add new node after it
            # This uses sed to add the new option after the last "- ha" line
            local last_node
            last_node=$(grep -o "^\s*- ha[0-9]*" "$FAILOVER_WORKFLOW" | tail -1 | sed 's/.*- //')
            
            if [ -n "$last_node" ]; then
                sed -i "s/^\(\s*- ${last_node}\)$/\1\n          - ${node}/" "$FAILOVER_WORKFLOW"
                log_success "Added $node to failover workflow options"
            else
                log_warning "Could not find existing nodes in workflow - manual edit required"
            fi
        fi
    else
        log_warning "cloudflare-failover.yml not found - skipping"
    fi
    
    echo ""
    log_success "Node $node added to YAML configs!"
    echo ""
    log_warning "MANUAL STEPS REQUIRED:"
    echo ""
    echo "1. Update haproxy/haproxy.cfg - add server lines to each backend:"
    echo ""
    echo "   backend your_backend"
    echo "       ..."
    echo "       server ${node} INTERNAL_IP:PORT check inter 5s fall 3 rise 2"
    echo ""
    echo "2. Set up the new HA node:"
    echo "   - Install HAProxy"
    echo "   - Install GitHub Actions runner with labels: self-hosted, haproxy, $node"
    echo "   - Add runner to 'ha-servers' group"
    echo ""
    echo "3. Commit and push changes:"
    echo "   git add ."
    echo "   git commit -m 'Add node $node'"
    echo "   git push"
    echo ""
    echo "See docs/SCALING.md for detailed instructions."
}

#---------------------------------------------------------------------
# Remove node
#---------------------------------------------------------------------
cmd_remove() {
    local node="$1"
    
    validate_node_name "$node"
    
    log_info "Removing node $node..."
    echo ""
    
    # Safety checks
    if [ -f "$ACTIVE_NODE_FILE" ]; then
        local active_node
        active_node=$(yq e '.active_node' "$ACTIVE_NODE_FILE")
        
        if [ "$active_node" == "$node" ]; then
            log_error "Cannot remove $node - it is the active node!"
            echo "First failover to a different node, then remove."
            exit 1
        fi
        
        local node_count
        node_count=$(yq e '.external_ips | length' "$ACTIVE_NODE_FILE")
        
        if [ "$node_count" -le 2 ]; then
            log_error "Cannot remove $node - minimum 2 nodes required for HA"
            exit 1
        fi
    fi
    
    # Update active-node.yml
    if [ -f "$ACTIVE_NODE_FILE" ]; then
        log_info "Updating cloudflare/active-node.yml..."
        yq e "del(.external_ips.$node)" -i "$ACTIVE_NODE_FILE"
        log_success "Removed $node from active-node.yml"
    else
        log_warning "active-node.yml not found - skipping"
    fi
    
    # Update cloudflare-failover.yml
    if [ -f "$FAILOVER_WORKFLOW" ]; then
        log_info "Updating cloudflare-failover.yml..."
        
        if grep -q "^\s*- $node\$" "$FAILOVER_WORKFLOW"; then
            sed -i "/^\s*- ${node}\$/d" "$FAILOVER_WORKFLOW"
            log_success "Removed $node from failover workflow options"
        else
            log_warning "Node $node not found in failover workflow"
        fi
    else
        log_warning "cloudflare-failover.yml not found - skipping"
    fi
    
    echo ""
    log_success "Node $node removed from YAML configs!"
    echo ""
    log_warning "MANUAL STEPS REQUIRED:"
    echo ""
    echo "1. Update haproxy/haproxy.cfg - remove or disable server lines:"
    echo ""
    echo "   backend your_backend"
    echo "       ..."
    echo "       # Remove this line:"
    echo "       # server ${node} ... check ..."
    echo ""
    echo "2. Decommission the HA node:"
    echo "   - Remove GitHub runner from organization"
    echo "   - Stop HAProxy service"
    echo "   - Update any monitoring/alerting"
    echo ""
    echo "3. Commit and push changes:"
    echo "   git add ."
    echo "   git commit -m 'Remove node $node'"
    echo "   git push"
    echo ""
    echo "See docs/SCALING.md for detailed instructions."
}

#---------------------------------------------------------------------
# Main
#---------------------------------------------------------------------
usage() {
    echo "HAProxy Node Management Script"
    echo ""
    echo "Usage:"
    echo "  $0 list                 List current nodes"
    echo "  $0 add <node> <ip>      Add a new node"
    echo "  $0 remove <node>        Remove a node"
    echo ""
    echo "Examples:"
    echo "  $0 list"
    echo "  $0 add ha04 192.0.2.14"
    echo "  $0 remove ha03"
    echo ""
    echo "Node names must follow pattern: ha01, ha02, ha03, etc."
}

main() {
    check_dependencies
    
    if [ $# -lt 1 ]; then
        usage
        exit 1
    fi
    
    local cmd="$1"
    shift
    
    case "$cmd" in
        list)
            cmd_list
            ;;
        add)
            if [ $# -lt 2 ]; then
                log_error "Usage: $0 add <node> <ip>"
                echo "Example: $0 add ha04 192.0.2.14"
                exit 1
            fi
            cmd_add "$1" "$2"
            ;;
        remove)
            if [ $# -lt 1 ]; then
                log_error "Usage: $0 remove <node>"
                echo "Example: $0 remove ha03"
                exit 1
            fi
            cmd_remove "$1"
            ;;
        -h|--help|help)
            usage
            ;;
        *)
            log_error "Unknown command: $cmd"
            usage
            exit 1
            ;;
    esac
}

main "$@"
