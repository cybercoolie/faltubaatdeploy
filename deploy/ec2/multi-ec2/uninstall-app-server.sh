#!/bin/bash

# =============================================================================
# Uninstall Script for FaltuBaat - APP SERVER ONLY
# Usage: sudo ./uninstall-app-server.sh
# =============================================================================

set -e

echo "[INFO] FaltuBaat App Server Uninstall Script"
echo "============================================="

read -p "Are you sure you want to uninstall FaltuBaat App Server? (y/N): " confirm
if [ "$confirm" != "y" ] && [ "$confirm" != "Y" ]; then
    echo "Cancelled."
    exit 0
fi

# Stop and disable services
echo "[INFO] Stopping faltubaat service..."
sudo systemctl stop faltubaat 2>/dev/null || true
sudo systemctl disable faltubaat 2>/dev/null || true

# Remove service file
echo "[INFO] Removing service file..."
sudo rm -f /etc/systemd/system/faltubaat.service
sudo systemctl daemon-reload

# Remove application directory
echo "[INFO] Removing application files..."
sudo rm -rf /opt/faltubaat

# Remove log directory
echo "[INFO] Removing log directory..."
sudo rm -rf /var/log/faltubaat

# Remove user and home directory
echo "[INFO] Removing application user..."
sudo userdel -r faltubaat 2>/dev/null || true

echo ""
echo "[OK] App Server uninstall complete!"
echo ""
echo "Note: Node.js was not removed. To remove:"
echo "  Amazon Linux: sudo yum remove nodejs"
echo "  Ubuntu: sudo apt remove nodejs"
