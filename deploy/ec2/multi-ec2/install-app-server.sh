#!/bin/bash

# =============================================================================
# EC2 Installation Script for FaltuBaat - APP SERVER ONLY
# Downloads code from GitHub and installs Node.js chat application (no Nginx/RTMP)
# =============================================================================

set -e

echo "🚀 FaltuBaat - App Server Installation"
echo "======================================="

# ============================================
# CONFIGURATION
# ============================================
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEPLOY_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Load configuration
if [ -f "$DEPLOY_ROOT/config.env" ]; then
    source "$DEPLOY_ROOT/config.env"
    echo "✅ Loaded configuration from config.env"
else
    GITHUB_REPO="${GITHUB_REPO:-https://github.com/YOUR_ORG/faltubaat.git}"
    GITHUB_BRANCH="${GITHUB_BRANCH:-main}"
fi

# Allow override via command line
GITHUB_REPO="${1:-$GITHUB_REPO}"
GITHUB_BRANCH="${2:-$GITHUB_BRANCH}"

# Validate GitHub repo is configured
if [[ "$GITHUB_REPO" == *"YOUR_ORG"* ]]; then
    echo ""
    echo "❌ ERROR: GitHub repository not configured!"
    echo ""
    echo "Please either:"
    echo "  1. Edit deploy/config.env and set GITHUB_REPO"
    echo "  2. Pass the repo URL as argument:"
    echo "     sudo ./install-app-server.sh https://github.com/your/repo.git main"
    echo ""
    exit 1
fi

echo ""
echo "📥 Will download code from:"
echo "   Repository: $GITHUB_REPO"
echo "   Branch: $GITHUB_BRANCH"
echo ""

# Detect OS
if [ -f /etc/os-release ]; then
    . /etc/os-release
    OS=$ID
    VERSION=$VERSION_ID
else
    echo "❌ Cannot detect OS. Exiting."
    exit 1
fi

echo "📦 Detected OS: $OS $VERSION"

# Configuration
APP_DIR="/opt/faltubaat"
APP_USER="faltubaat"

# Get RTMP server IP from user
read -p "Enter RTMP Server IP address (for stream callbacks): " RTMP_SERVER_IP
if [ -z "$RTMP_SERVER_IP" ]; then
    echo "⚠️  No RTMP server IP provided. Streams won't work until configured."
    RTMP_SERVER_IP="localhost"
fi

# Function for Amazon Linux / RHEL
install_amazon_linux() {
    echo "📦 Installing dependencies for Amazon Linux..."
    
    sudo yum update -y
    
    # Install Node.js 20
    curl -fsSL https://rpm.nodesource.com/setup_20.x | sudo bash -
    sudo yum install -y nodejs
    
    # Install build tools for native modules (SQLite)
    sudo yum install -y gcc gcc-c++ make python3 sqlite sqlite-devel openssl
}

# Function for Ubuntu/Debian
install_ubuntu() {
    echo "📦 Installing dependencies for Ubuntu..."
    
    sudo apt-get update
    sudo apt-get upgrade -y
    
    # Install Node.js 20
    curl -fsSL https://deb.nodesource.com/setup_20.x | sudo -E bash -
    sudo apt-get install -y nodejs
    
    # Install build tools for native modules (SQLite)
    sudo apt-get install -y build-essential python3 sqlite3 libsqlite3-dev openssl
}

# Install based on OS
case $OS in
    "amzn"|"rhel"|"centos")
        install_amazon_linux
        ;;
    "ubuntu"|"debian")
        install_ubuntu
        ;;
    *)
        echo "❌ Unsupported OS: $OS"
        exit 1
        ;;
esac

# Create app user
echo "👤 Creating application user..."
sudo useradd -r -s /bin/false $APP_USER 2>/dev/null || true

# Create app directory
echo "📁 Setting up application directory..."
sudo mkdir -p $APP_DIR
sudo mkdir -p $APP_DIR/data
sudo mkdir -p /var/log/faltubaat

# Download application code from GitHub
echo "📥 Downloading application code from GitHub..."
TEMP_DIR=$(mktemp -d)
git clone --depth 1 --branch "$GITHUB_BRANCH" "$GITHUB_REPO" "$TEMP_DIR/app"

if [ $? -ne 0 ]; then
    echo "❌ Failed to clone repository"
    rm -rf "$TEMP_DIR"
    exit 1
fi

echo "✅ Code downloaded successfully"

# Copy application files
echo "📋 Copying application files..."
sudo cp -r $TEMP_DIR/app/* $APP_DIR/
sudo chown -R $APP_USER:$APP_USER $APP_DIR
sudo chown -R $APP_USER:$APP_USER /var/log/faltubaat

# Cleanup temp directory
rm -rf "$TEMP_DIR"

# Setup environment file
echo "📝 Setting up environment configuration..."
JWT_SECRET=$(openssl rand -hex 32)
cat << EOF | sudo tee $APP_DIR/.env > /dev/null
NODE_ENV=production
PORT=3000
HTTPS_PORT=3443
JWT_SECRET=$JWT_SECRET
DB_PATH=$APP_DIR/data/faltubaat.db
RTMP_SERVER=$RTMP_SERVER_IP
EOF
sudo chown $APP_USER:$APP_USER $APP_DIR/.env
sudo chmod 600 $APP_DIR/.env

# Install Node.js dependencies
echo "📦 Installing Node.js dependencies..."
cd $APP_DIR
sudo -u $APP_USER npm install --production

# Initialize database
echo "🗄️ Initializing database..."
cd $APP_DIR
sudo -u $APP_USER npm run init-db

# Generate SSL certificates
echo "🔐 Generating SSL certificates..."
sudo openssl req -x509 -newkey rsa:4096 \
    -keyout $APP_DIR/key.pem \
    -out $APP_DIR/cert.pem \
    -days 365 -nodes \
    -subj "/C=US/ST=State/L=City/O=FaltuBaat/CN=localhost"
sudo chown $APP_USER:$APP_USER $APP_DIR/key.pem $APP_DIR/cert.pem

# Copy systemd service file
echo "🔧 Setting up systemd service..."
sudo cp $APP_DIR/faltubaat.service /etc/systemd/system/faltubaat.service
sudo systemctl daemon-reload

# Enable and start service
echo "🚀 Starting application..."
sudo systemctl enable faltubaat
sudo systemctl start faltubaat

# Configure firewall (if firewalld is active)
if command -v firewall-cmd &> /dev/null; then
    echo "🔥 Configuring firewall..."
    sudo firewall-cmd --permanent --add-port=3000/tcp
    sudo firewall-cmd --permanent --add-port=3443/tcp
    sudo firewall-cmd --reload
fi

# Get public IP
PUBLIC_IP=$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4 2>/dev/null || echo "YOUR_EC2_IP")
PRIVATE_IP=$(curl -s http://169.254.169.254/latest/meta-data/local-ipv4 2>/dev/null || echo "YOUR_PRIVATE_IP")

echo ""
echo "✅ App Server Installation complete!"
echo "======================================="
echo ""
echo "🌐 Access your application:"
echo "   HTTP:  http://$PUBLIC_IP:3000"
echo "   HTTPS: https://$PUBLIC_IP:3443"
echo ""
echo "📋 IMPORTANT - Configure RTMP Server:"
echo "   On your RTMP server, set the callback URL to:"
echo "   on_publish http://$PRIVATE_IP:3000/stream/start"
echo "   on_publish_done http://$PRIVATE_IP:3000/stream/stop"
echo ""
echo "📊 Service Management:"
echo "   Status:  sudo systemctl status faltubaat"
echo "   Logs:    sudo journalctl -u faltubaat -f"
echo "   Restart: sudo systemctl restart faltubaat"
echo ""
echo "⚠️  Open these ports in your EC2 Security Group:"
echo "   - 3000  (TCP) - HTTP Chat"
echo "   - 3443  (TCP) - HTTPS Chat"
echo ""
