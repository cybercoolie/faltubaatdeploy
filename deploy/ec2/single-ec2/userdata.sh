#!/bin/bash
# =============================================================================
# EC2 User Data Script for FaltuBaat - Single EC2 Deployment
# This script runs automatically when the EC2 instance launches
# =============================================================================

set -e

# Log everything to a file for debugging
exec > >(tee /var/log/faltubaat-userdata.log) 2>&1
echo "Starting FaltuBaat installation at $(date)"

# Update system packages
yum update -y 2>/dev/null || apt-get update -y 2>/dev/null

# Install git if not present
yum install -y git 2>/dev/null || apt-get install -y git 2>/dev/null

# Clone the deployment repository
cd /tmp
rm -rf faltubaatdeploy
git clone https://github.com/cybercoolie/faltubaatdeploy.git

# Navigate to the single-ec2 deploy folder
cd faltubaatdeploy/deploy/ec2/single-ec2

# Make the install script executable
chmod +x ec2-install.sh

# Run the installation script
# Note: User data runs as root, the script handles sudo internally
./ec2-install.sh

echo "FaltuBaat installation completed at $(date)"
