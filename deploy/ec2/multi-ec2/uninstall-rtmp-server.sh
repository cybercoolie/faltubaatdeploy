#!/bin/bash

# =============================================================================
# Uninstall Script for FaltuBaat - RTMP SERVER ONLY
# Usage: sudo ./uninstall-rtmp-server.sh
# =============================================================================

set -e

echo "[INFO] FaltuBaat RTMP Server Uninstall Script"
echo "=============================================="

read -p "Are you sure you want to uninstall FaltuBaat RTMP Server? (y/N): " confirm
if [ "$confirm" != "y" ] && [ "$confirm" != "Y" ]; then
    echo "Cancelled."
    exit 0
fi

# Stop and disable nginx
echo "[INFO] Stopping nginx service..."
sudo systemctl stop nginx 2>/dev/null || true
sudo systemctl disable nginx 2>/dev/null || true

# Remove nginx service file (if custom)
echo "[INFO] Removing nginx service file..."
sudo rm -f /etc/systemd/system/nginx.service
sudo systemctl daemon-reload

# Remove nginx binary and config
echo "[INFO] Removing nginx installation..."
sudo rm -rf /etc/nginx
sudo rm -f /usr/sbin/nginx

# Remove HLS directory
echo "[INFO] Removing HLS directory..."
sudo rm -rf /var/www/html/hls

# Remove nginx logs
echo "[INFO] Removing nginx logs..."
sudo rm -rf /var/log/nginx

# Remove nginx user
echo "[INFO] Removing nginx user..."
sudo userdel nginx 2>/dev/null || true

# Remove compiled nginx source files
echo "[INFO] Cleaning up build files..."
sudo rm -rf /tmp/nginx-1.24.0*
sudo rm -rf /tmp/nginx-rtmp-module

echo ""
echo "[OK] RTMP Server uninstall complete!"
echo ""
echo "Note: Build dependencies were not removed. To remove:"
echo "  Amazon Linux: sudo yum remove pcre-devel openssl-devel zlib-devel"
echo "  Ubuntu: sudo apt remove nginx libnginx-mod-rtmp"
