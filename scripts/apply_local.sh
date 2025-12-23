#!/usr/bin/env bash
#---------------------------------------------------------------------
# HAProxy Configuration Apply Script
# Applies new configuration with validation and automatic backup
#
# This script:
# 1. Creates timestamped backup of current config
# 2. Copies new config to HAProxy directory
# 3. Validates the new configuration
# 4. Gracefully reloads HAProxy
# 5. Marks the deployment as Last Known Good (LKG)
#
# Usage: ./scripts/apply_local.sh
#---------------------------------------------------------------------
set -euo pipefail

# Configuration
HAPROXY_CFG="/etc/haproxy/haproxy.cfg"
BACKUP_DIR="/etc/haproxy/backup"
REPO_CFG="$(dirname "$0")/../haproxy/haproxy.cfg"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)

echo "🚀 Starting HAProxy configuration deployment..."

# Ensure backup directory exists
sudo mkdir -p "$BACKUP_DIR"

# Step 1: Backup current configuration
if [ -f "$HAPROXY_CFG" ]; then
    echo "📦 Backing up current configuration..."
    sudo cp "$HAPROXY_CFG" "$BACKUP_DIR/haproxy.cfg.$TIMESTAMP"
    echo "   Backup saved to: $BACKUP_DIR/haproxy.cfg.$TIMESTAMP"
fi

# Step 2: Copy new configuration
echo "📋 Copying new configuration..."
sudo cp "$REPO_CFG" "$HAPROXY_CFG"

# Step 3: Validate new configuration
echo "🔍 Validating new configuration..."
if ! sudo /usr/sbin/haproxy -c -f "$HAPROXY_CFG"; then
    echo "❌ Configuration validation failed!"
    echo "🔄 Rolling back to previous configuration..."
    if [ -f "$BACKUP_DIR/haproxy.cfg.$TIMESTAMP" ]; then
        sudo cp "$BACKUP_DIR/haproxy.cfg.$TIMESTAMP" "$HAPROXY_CFG"
    fi
    exit 1
fi
echo "✅ Configuration is valid"

# Step 4: Reload HAProxy gracefully
echo "🔄 Reloading HAProxy..."
if ! sudo systemctl reload haproxy; then
    echo "❌ HAProxy reload failed!"
    echo "🔄 Rolling back to previous configuration..."
    if [ -f "$BACKUP_DIR/haproxy.cfg.$TIMESTAMP" ]; then
        sudo cp "$BACKUP_DIR/haproxy.cfg.$TIMESTAMP" "$HAPROXY_CFG"
        sudo systemctl reload haproxy || sudo systemctl restart haproxy
    fi
    exit 1
fi
echo "✅ HAProxy reloaded successfully"

# Step 5: Mark as Last Known Good
echo "📝 Marking deployment as Last Known Good..."
sudo cp "$HAPROXY_CFG" "$BACKUP_DIR/haproxy.cfg.LKG"

echo ""
echo "✅ Deployment completed successfully!"
echo "   Backup: $BACKUP_DIR/haproxy.cfg.$TIMESTAMP"
echo "   LKG:    $BACKUP_DIR/haproxy.cfg.LKG"
