#!/usr/bin/env bash
#---------------------------------------------------------------------
# CloudFlare DNS Sync Script
# Synchronizes DNS records from YAML configuration to CloudFlare
#
# Prerequisites:
#   - CLOUDFLARE_API_TOKEN environment variable
#   - CLOUDFLARE_ZONE_ID environment variable
#   - jq and yq installed
#
# Environment Variables:
#   CLOUDFLARE_API_TOKEN  - CloudFlare API token with Zone:DNS:Edit
#   CLOUDFLARE_ZONE_ID    - CloudFlare Zone ID
#   DNS_RECORDS_FILE      - Path to DNS records YAML (optional)
#   DNS_FILTER            - Only process records matching this name
#   FORCE_OVERWRITE       - Delete records with conflicting types
#
# Usage:
#   ./scripts/cloudflare_sync.sh --check   # Validate config and API
#   ./scripts/cloudflare_sync.sh --plan    # Dry-run, show changes
#   ./scripts/cloudflare_sync.sh --apply   # Apply changes
#---------------------------------------------------------------------
set -euo pipefail

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"

# Configuration
CONFIG_FILE="${DNS_RECORDS_FILE:-$REPO_ROOT/cloudflare/dns-records.yml}"
ACTIVE_NODE_FILE="$REPO_ROOT/cloudflare/active-node.yml"
CF_API="https://api.cloudflare.com/client/v4"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

#---------------------------------------------------------------------
# Helper Functions
#---------------------------------------------------------------------
log_info() {
    echo -e "${GREEN}✓${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}⚠${NC} $1"
}

log_error() {
    echo -e "${RED}✗${NC} $1"
}

#---------------------------------------------------------------------
# Validate Prerequisites
#---------------------------------------------------------------------
validate_prerequisites() {
    local errors=0

    # Check required tools
    for tool in jq yq curl; do
        if ! command -v "$tool" &> /dev/null; then
            log_error "Required tool not found: $tool"
            ((errors++))
        fi
    done

    # Check environment variables
    if [ -z "${CLOUDFLARE_API_TOKEN:-}" ]; then
        log_error "CLOUDFLARE_API_TOKEN environment variable is not set"
        ((errors++))
    fi

    if [ -z "${CLOUDFLARE_ZONE_ID:-}" ]; then
        log_error "CLOUDFLARE_ZONE_ID environment variable is not set"
        ((errors++))
    fi

    # Check config files
    if [ ! -f "$CONFIG_FILE" ]; then
        log_error "DNS records config not found: $CONFIG_FILE"
        ((errors++))
    fi

    if [ ! -f "$ACTIVE_NODE_FILE" ]; then
        log_error "Active node config not found: $ACTIVE_NODE_FILE"
        ((errors++))
    fi

    if [ $errors -gt 0 ]; then
        exit 1
    fi

    log_info "Prerequisites validated"
}

#---------------------------------------------------------------------
# Get Active Node IP
#---------------------------------------------------------------------
get_active_node_ip() {
    local active_node
    active_node=$(yq e '.active_node' "$ACTIVE_NODE_FILE")
    local ip
    ip=$(yq e ".external_ips.${active_node}" "$ACTIVE_NODE_FILE")
    
    if [ -z "$ip" ] || [ "$ip" == "null" ]; then
        log_error "Could not determine active node IP for: $active_node"
        exit 1
    fi
    
    echo "$ip"
}

#---------------------------------------------------------------------
# Validate CloudFlare API Connection
#---------------------------------------------------------------------
validate_api() {
    echo "Validating CloudFlare API connection..."
    
    local response
    response=$(curl -s -X GET "$CF_API/zones/$CLOUDFLARE_ZONE_ID" \
        -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" \
        -H "Content-Type: application/json")
    
    local success
    success=$(echo "$response" | jq -r '.success')
    
    if [ "$success" != "true" ]; then
        log_error "CloudFlare API validation failed"
        echo "$response" | jq .
        exit 1
    fi
    
    local zone_name
    zone_name=$(echo "$response" | jq -r '.result.name')
    log_info "Connected to zone: $zone_name"
}

#---------------------------------------------------------------------
# Get Existing DNS Records
#---------------------------------------------------------------------
get_existing_records() {
    local response
    response=$(curl -s -X GET "$CF_API/zones/$CLOUDFLARE_ZONE_ID/dns_records?per_page=1000" \
        -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" \
        -H "Content-Type: application/json")
    
    echo "$response" | jq '.result'
}

#---------------------------------------------------------------------
# Process DNS Records
#---------------------------------------------------------------------
process_records() {
    local mode="$1"
    local active_ip
    active_ip=$(get_active_node_ip)
    echo "Active node IP: $active_ip"
    
    local existing_records
    existing_records=$(get_existing_records)
    
    local zone_name
    zone_name=$(yq e '.zones[0].zone' "$CONFIG_FILE")
    
    local records_count
    records_count=$(yq e '.zones[0].records | length' "$CONFIG_FILE")
    
    echo ""
    echo "Processing $records_count records for $zone_name..."
    echo ""
    
    for i in $(seq 0 $((records_count - 1))); do
        local name type content proxied ttl comment
        name=$(yq e ".zones[0].records[$i].name" "$CONFIG_FILE")
        type=$(yq e ".zones[0].records[$i].type" "$CONFIG_FILE")
        content=$(yq e ".zones[0].records[$i].content" "$CONFIG_FILE")
        proxied=$(yq e ".zones[0].records[$i].proxied // true" "$CONFIG_FILE")
        ttl=$(yq e ".zones[0].records[$i].ttl // 1" "$CONFIG_FILE")
        comment=$(yq e ".zones[0].records[$i].comment // \"\"" "$CONFIG_FILE")
        
        # Apply filter if set
        if [ -n "${DNS_FILTER:-}" ] && [[ "$name" != *"$DNS_FILTER"* ]]; then
            continue
        fi
        
        # Replace template variable
        content="${content//\{\{active_node_ip\}\}/$active_ip}"
        
        # Build FQDN
        local fqdn
        if [ "$name" == "@" ]; then
            fqdn="$zone_name"
        else
            fqdn="${name}.${zone_name}"
        fi
        
        # Find existing record
        local existing_id existing_type
        existing_id=$(echo "$existing_records" | jq -r ".[] | select(.name == \"$fqdn\") | .id" | head -1)
        existing_type=$(echo "$existing_records" | jq -r ".[] | select(.name == \"$fqdn\") | .type" | head -1)
        
        # Handle type conflicts
        if [ -n "$existing_id" ] && [ "$existing_type" != "$type" ]; then
            if [ "${FORCE_OVERWRITE:-false}" == "true" ]; then
                log_warn "$fqdn: Type conflict ($existing_type → $type), will delete and recreate"
                if [ "$mode" == "apply" ]; then
                    curl -s -X DELETE "$CF_API/zones/$CLOUDFLARE_ZONE_ID/dns_records/$existing_id" \
                        -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" \
                        -H "Content-Type: application/json" > /dev/null
                    existing_id=""
                fi
            else
                log_error "$fqdn: Type conflict ($existing_type → $type), skipping. Use FORCE_OVERWRITE=true to override."
                continue
            fi
        fi
        
        # Create or update record
        if [ -z "$existing_id" ]; then
            echo "CREATE: $fqdn ($type) → $content"
            
            if [ "$mode" == "apply" ]; then
                local result
                result=$(curl -s -X POST "$CF_API/zones/$CLOUDFLARE_ZONE_ID/dns_records" \
                    -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" \
                    -H "Content-Type: application/json" \
                    --data "{
                        \"type\": \"$type\",
                        \"name\": \"$name\",
                        \"content\": \"$content\",
                        \"proxied\": $proxied,
                        \"ttl\": $ttl,
                        \"comment\": \"$comment\"
                    }")
                
                if [ "$(echo "$result" | jq -r '.success')" != "true" ]; then
                    log_error "Failed to create $fqdn"
                    echo "$result" | jq .
                else
                    log_info "Created: $fqdn"
                fi
            fi
        else
            echo "UPDATE: $fqdn ($type) → $content"
            
            if [ "$mode" == "apply" ]; then
                local result
                result=$(curl -s -X PUT "$CF_API/zones/$CLOUDFLARE_ZONE_ID/dns_records/$existing_id" \
                    -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" \
                    -H "Content-Type: application/json" \
                    --data "{
                        \"type\": \"$type\",
                        \"name\": \"$name\",
                        \"content\": \"$content\",
                        \"proxied\": $proxied,
                        \"ttl\": $ttl,
                        \"comment\": \"$comment\"
                    }")
                
                if [ "$(echo "$result" | jq -r '.success')" != "true" ]; then
                    log_error "Failed to update $fqdn"
                    echo "$result" | jq .
                else
                    log_info "Updated: $fqdn"
                fi
            fi
        fi
    done
}

#---------------------------------------------------------------------
# Main
#---------------------------------------------------------------------
main() {
    local mode="check"
    
    # Parse arguments
    case "${1:-}" in
        --check)
            mode="check"
            ;;
        --plan)
            mode="plan"
            ;;
        --apply)
            mode="apply"
            ;;
        *)
            echo "Usage: $0 [--check|--plan|--apply]"
            echo ""
            echo "Modes:"
            echo "  --check   Validate config and API connection"
            echo "  --plan    Dry-run, show what would be changed"
            echo "  --apply   Create/update DNS records"
            exit 1
            ;;
    esac
    
    echo "=========================================="
    echo "CloudFlare DNS Sync - Mode: $mode"
    echo "=========================================="
    echo ""
    
    validate_prerequisites
    validate_api
    
    if [ "$mode" != "check" ]; then
        process_records "$mode"
    fi
    
    echo ""
    echo "=========================================="
    if [ "$mode" == "apply" ]; then
        log_info "DNS sync completed"
    else
        log_info "Validation completed"
    fi
    echo "=========================================="
}

main "$@"
