#!/bin/bash

# EC2 Installation Script for FaltuBaat Live Chat Application
# Downloads code from GitHub and installs on EC2
# Supports: Amazon Linux 2023, Amazon Linux 2, Ubuntu 22.04/24.04

set -e

echo "🚀 FaltuBaat - EC2 Installation Script"
echo "======================================="

# ============================================
# CONFIGURATION - Edit these values or use config.env
# ============================================
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEPLOY_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Load configuration
if [ -f "$DEPLOY_ROOT/config.env" ]; then
    source "$DEPLOY_ROOT/config.env"
    echo "✅ Loaded configuration from config.env"
elif [ -f "$SCRIPT_DIR/../../config.env" ]; then
    source "$SCRIPT_DIR/../../config.env"
    echo "✅ Loaded configuration from config.env"
else
    echo "⚠️  No config.env found. Using defaults or command line args."
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
    echo "     sudo ./ec2-install.sh https://github.com/your/repo.git main"
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

# Set app directory
APP_DIR="/opt/faltubaat"
APP_USER="faltubaat"

# Function for Amazon Linux / RHEL
install_amazon_linux() {
    echo "📦 Installing dependencies for Amazon Linux..."
    
    # Update system
    sudo yum update -y
    
    # Install Node.js 20
    curl -fsSL https://rpm.nodesource.com/setup_20.x | sudo bash -
    sudo yum install -y nodejs
    
    # Install build tools for native modules (SQLite)
    sudo yum install -y gcc gcc-c++ make python3 sqlite sqlite-devel
    
    # Install Nginx with RTMP module (compile from source)
    sudo yum install -y pcre-devel openssl-devel zlib-devel git wget
    
    # Download and compile Nginx with RTMP
    cd /tmp
    wget http://nginx.org/download/nginx-1.24.0.tar.gz
    tar -xzf nginx-1.24.0.tar.gz
    git clone https://github.com/arut/nginx-rtmp-module.git
    
    cd nginx-1.24.0
    ./configure --prefix=/etc/nginx \
        --sbin-path=/usr/sbin/nginx \
        --conf-path=/etc/nginx/nginx.conf \
        --error-log-path=/var/log/nginx/error.log \
        --http-log-path=/var/log/nginx/access.log \
        --pid-path=/var/run/nginx.pid \
        --with-http_ssl_module \
        --add-module=../nginx-rtmp-module
    
    make
    sudo make install
    
    # Create nginx user if not exists
    sudo useradd -r nginx 2>/dev/null || true
    
    # Create nginx systemd service for Amazon Linux
    sudo tee /etc/systemd/system/nginx.service > /dev/null <<EOF
[Unit]
Description=The NGINX HTTP and reverse proxy server
After=syslog.target network-online.target remote-fs.target nss-lookup.target
Wants=network-online.target

[Service]
Type=forking
PIDFile=/var/run/nginx.pid
ExecStartPre=/usr/sbin/nginx -t
ExecStart=/usr/sbin/nginx
ExecReload=/bin/kill -s HUP \$MAINPID
ExecStop=/bin/kill -s QUIT \$MAINPID
PrivateTmp=true

[Install]
WantedBy=multi-user.target
EOF
    
    # Set nginx config path (Amazon Linux - module compiled in, no load_module)
    NGINX_CONF_SOURCE="deploy/ec2/nginx-ec2.conf"
    NGINX_NEEDS_MODULE_LOAD=false
}

# Function for Ubuntu/Debian
install_ubuntu() {
    echo "📦 Installing dependencies for Ubuntu..."
    
    # Update system
    sudo apt-get update
    sudo apt-get upgrade -y
    
    # Install Node.js 20
    curl -fsSL https://deb.nodesource.com/setup_20.x | sudo -E bash -
    sudo apt-get install -y nodejs
    
    # Install build tools for native modules (SQLite)
    sudo apt-get install -y build-essential python3 sqlite3 libsqlite3-dev
    
    # Install Nginx with RTMP module
    sudo apt-get install -y nginx libnginx-mod-rtmp openssl
    
    # Set nginx config path (Ubuntu uses load_module)
    NGINX_CONF_SOURCE="nginx.conf"
    NGINX_NEEDS_MODULE_LOAD=true
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

# Default nginx config source if not set
NGINX_CONF_SOURCE="${NGINX_CONF_SOURCE:-deploy/ec2/nginx-ec2.conf}"

# Create app user
echo "👤 Creating application user..."
sudo useradd -r -s /bin/false $APP_USER 2>/dev/null || true

# Create app directory
echo "📁 Setting up application directory..."
sudo mkdir -p $APP_DIR
sudo mkdir -p $APP_DIR/data
sudo mkdir -p /var/www/html/hls
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
sudo chown -R $APP_USER:$APP_USER /var/www/html/hls
sudo chown -R $APP_USER:$APP_USER /var/log/faltubaat

# Copy nginx config from deploy repo if exists
if [ -f "$SCRIPT_DIR/nginx-ec2.conf" ]; then
    sudo mkdir -p $APP_DIR/deploy/ec2
    sudo cp "$SCRIPT_DIR/nginx-ec2.conf" $APP_DIR/deploy/ec2/
fi

# Cleanup temp directory
rm -rf "$TEMP_DIR"

# Setup environment file
echo "📝 Setting up environment configuration..."
if [ ! -f "$APP_DIR/.env" ]; then
    sudo cp $APP_DIR/.env.example $APP_DIR/.env 2>/dev/null || true
    # Generate random JWT secret
    JWT_SECRET=$(openssl rand -hex 32)
    if [ -f "$APP_DIR/.env" ]; then
        sudo sed -i "s/CHANGE_THIS_TO_A_SECURE_RANDOM_STRING_IN_PRODUCTION/$JWT_SECRET/g" $APP_DIR/.env
    else
        echo "JWT_SECRET=$JWT_SECRET" | sudo tee $APP_DIR/.env > /dev/null
        echo "NODE_ENV=production" | sudo tee -a $APP_DIR/.env > /dev/null
        echo "PORT=3000" | sudo tee -a $APP_DIR/.env > /dev/null
        echo "HTTPS_PORT=3443" | sudo tee -a $APP_DIR/.env > /dev/null
        echo "DB_PATH=$APP_DIR/data/faltubaat.db" | sudo tee -a $APP_DIR/.env > /dev/null
    fi
    sudo chown $APP_USER:$APP_USER $APP_DIR/.env
    sudo chmod 600 $APP_DIR/.env
fi

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

# Copy Nginx configuration
echo "⚙️ Configuring Nginx..."
if [ "$NGINX_NEEDS_MODULE_LOAD" = "true" ]; then
    # Ubuntu: Use nginx.conf with load_module directive
    sudo cp $APP_DIR/nginx.conf /etc/nginx/nginx.conf
else
    # Amazon Linux: Use ec2-specific config (module compiled in)
    sudo cp $APP_DIR/deploy/ec2/nginx-ec2.conf /etc/nginx/nginx.conf
fi

# Create mime.types if missing (for compiled nginx)
if [ ! -f /etc/nginx/mime.types ]; then
    sudo cp /etc/nginx/conf/mime.types /etc/nginx/mime.types 2>/dev/null || \
    sudo curl -o /etc/nginx/mime.types https://raw.githubusercontent.com/nginx/nginx/master/conf/mime.types
fi

# Copy systemd service file
echo "🔧 Setting up systemd service..."
sudo cp $APP_DIR/faltubaat.service /etc/systemd/system/faltubaat.service
sudo systemctl daemon-reload

# Enable and start services
echo "🚀 Starting services..."
sudo systemctl enable nginx
sudo systemctl enable faltubaat
sudo systemctl start nginx
sudo systemctl start faltubaat

# Configure firewall (if firewalld is active)
if command -v firewall-cmd &> /dev/null; then
    echo "🔥 Configuring firewall..."
    sudo firewall-cmd --permanent --add-port=3000/tcp
    sudo firewall-cmd --permanent --add-port=3443/tcp
    sudo firewall-cmd --permanent --add-port=1935/tcp
    sudo firewall-cmd --permanent --add-port=8080/tcp
    sudo firewall-cmd --permanent --add-port=80/tcp
    sudo firewall-cmd --permanent --add-port=443/tcp
    sudo firewall-cmd --reload
fi

# Get public IP
PUBLIC_IP=$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4 2>/dev/null || echo "YOUR_EC2_IP")

echo ""
echo "✅ Installation complete!"
echo "======================================="
echo ""
echo "🌐 Access your application:"
echo "   HTTP:  http://$PUBLIC_IP:3000"
echo "   HTTPS: https://$PUBLIC_IP:3443"
echo "   RTMP:  rtmp://$PUBLIC_IP:1935/live"
echo "   HLS:   http://$PUBLIC_IP:8080/hls/"
echo ""
echo "📊 Service Management:"
echo "   Status:  sudo systemctl status faltubaat"
echo "   Logs:    sudo journalctl -u faltubaat -f"
echo "   Restart: sudo systemctl restart faltubaat"
echo "   Stop:    sudo systemctl stop faltubaat"
echo ""
echo "   Nginx Status:  sudo systemctl status nginx"
echo "   Nginx Logs:    sudo tail -f /var/log/nginx/error.log"
echo ""
echo "⚠️  Open these ports in your EC2 Security Group:"
echo "   - 3000  (TCP) - HTTP Chat"
echo "   - 3443  (TCP) - HTTPS Chat"
echo "   - 1935  (TCP) - RTMP Streaming"
echo "   - 8080  (TCP) - HLS Streams"
echo ""
echo "📁 Application Files:"
echo "   App:    $APP_DIR"
echo "   DB:     $APP_DIR/data/faltubaat.db"
echo "   Env:    $APP_DIR/.env"
echo "   HLS:    /var/www/html/hls/"
echo ""
