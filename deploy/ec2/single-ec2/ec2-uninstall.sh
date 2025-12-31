#!/bin/bash

# Uninstall Script for FaltuBaat
# Usage: sudo ./ec2-uninstall.sh

set -e

echo "[INFO] FaltuBaat Uninstall Script"
echo "=============================="

read -p "Are you sure you want to uninstall FaltuBaat? (y/N): " confirm
if [ "$confirm" != "y" ] && [ "$confirm" != "Y" ]; then
    echo "Cancelled."
    exit 0
fi

# Stop and disable services
echo "[INFO] Stopping services..."
sudo systemctl stop faltubaat 2>/dev/null || true
sudo systemctl disable faltubaat 2>/dev/null || true

# Remove service file
echo "[INFO] Removing service file..."
sudo rm -f /etc/systemd/system/faltubaat.service
sudo systemctl daemon-reload

# Remove application directory
echo "[INFO] Removing application files..."
sudo rm -rf /opt/faltubaat

# Remove HLS directory
sudo rm -rf /var/www/html/hls

# Remove log directory
sudo rm -rf /var/log/faltubaat

# Remove user
echo "[INFO] Removing application user..."
sudo userdel faltubaat 2>/dev/null || true

echo ""
echo "[OK] Uninstall complete!"
echo "Note: Nginx was not removed. To remove: sudo yum remove nginx (or apt remove nginx)"