#!/usr/bin/env bash
#---------------------------------------------------------------------
# HAProxy Configuration Rollback Script
# Automatically rolls back to Last Known Good (LKG) configuration
#
# This script:
# 1. Attempts to restore LKG configuration
# 2. If no LKG exists, finds the most recent valid backup
# 3. Validates the restored configuration
# 4. Reloads HAProxy
#
# Usage: ./scripts/rollback_local.sh
#---------------------------------------------------------------------
set -euo pipefail

# Configuration
HAPROXY_CFG="/etc/haproxy/haproxy.cfg"
BACKUP_DIR="/etc/haproxy/backup"
LKG_FILE="$BACKUP_DIR/haproxy.cfg.LKG"

echo "🔄 Starting HAProxy rollback..."

# Function to validate and apply config
validate_and_apply() {
    local config_file="$1"
    local source_name="$2"

    echo "🔍 Validating $source_name..."
    if sudo /usr/sbin/haproxy -c -f "$config_file"; then
        echo "✅ Configuration is valid"
        echo "📋 Applying configuration..."
        sudo cp "$config_file" "$HAPROXY_CFG"
        echo "🔄 Reloading HAProxy..."
        if sudo systemctl reload haproxy; then
            echo "✅ Rollback successful using $source_name"
            return 0
        else
            echo "⚠️ Reload failed, trying restart..."
            if sudo systemctl restart haproxy; then
                echo "✅ Rollback successful using $source_name (restart)"
                return 0
            fi
        fi
    fi
    return 1
}

# Step 1: Try LKG configuration
if [ -f "$LKG_FILE" ]; then
    echo "📁 Found Last Known Good configuration"
    if validate_and_apply "$LKG_FILE" "LKG"; then
        exit 0
    fi
    echo "⚠️ LKG configuration is not valid, searching for backups..."
fi

# Step 2: Find and try backups (newest first)
echo "📁 Searching for valid backups..."
BACKUPS=$(find "$BACKUP_DIR" -name "haproxy.cfg.[0-9]*" -type f 2>/dev/null | sort -r)

if [ -z "$BACKUPS" ]; then
    echo "❌ No backup configurations found!"
    echo "   Manual intervention required."
    exit 1
fi

for backup in $BACKUPS; do
    echo "🔄 Trying backup: $(basename "$backup")"
    if validate_and_apply "$backup" "$(basename "$backup")"; then
        # Mark this as new LKG
        sudo cp "$backup" "$LKG_FILE"
        exit 0
    fi
done

# Step 3: All backups failed
echo ""
echo "❌ Rollback failed - no valid configuration found!"
echo "   Manual intervention required."
echo ""
echo "   Available backups:"
ls -la "$BACKUP_DIR"/ 2>/dev/null || echo "   (no backups found)"
exit 1
