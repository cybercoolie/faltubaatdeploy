#!/bin/bash
# =============================================================================
# EC2 User Data Script for FaltuBaat - RTMP Server (Multi-EC2 Deployment)
# This script runs automatically when the EC2 instance launches
# =============================================================================

set -e

# Log everything to a file for debugging
exec > >(tee /var/log/faltubaat-userdata.log) 2>&1
echo "Starting FaltuBaat RTMP Server installation at $(date)"

# ============================================
# CONFIGURATION - Set App server IP here
# ============================================
APP_SERVER_IP="${APP_SERVER_IP:-localhost}"

# Update system packages
yum update -y 2>/dev/null || apt-get update -y 2>/dev/null

# Install git if not present
yum install -y git 2>/dev/null || apt-get install -y git 2>/dev/null

# Clone the deployment repository
cd /tmp
rm -rf faltubaatdeploy
git clone https://github.com/cybercoolie/faltubaatdeploy.git

# Navigate to the multi-ec2 deploy folder
cd faltubaatdeploy/deploy/ec2/multi-ec2

# Make the install script executable
chmod +x install-rtmp-server.sh

# Run the installation script with App server IP
# The script expects APP_SERVER_IP as input, we'll provide it via stdin
echo "$APP_SERVER_IP" | ./install-rtmp-server.sh

echo "FaltuBaat RTMP Server installation completed at $(date)"
