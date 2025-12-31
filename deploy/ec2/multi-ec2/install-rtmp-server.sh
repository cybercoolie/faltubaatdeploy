#!/bin/bash

# =============================================================================
# EC2 Installation Script for FaltuBaat - RTMP SERVER ONLY
# Installs Nginx with RTMP module (no Node.js app)
# =============================================================================

set -e

echo "[INFO] FaltuBaat - RTMP Server Installation"
echo "========================================"

# Detect OS
if [ -f /etc/os-release ]; then
    . /etc/os-release
    OS=$ID
    VERSION=$VERSION_ID
else
    echo "[ERROR] Cannot detect OS. Exiting."
    exit 1
fi

echo "[INFO] Detected OS: $OS $VERSION"

# Get App server IP from user
read -p "Enter App Server PRIVATE IP address (for stream callbacks): " APP_SERVER_IP
if [ -z "$APP_SERVER_IP" ]; then
    echo "[ERROR] App server IP is required for stream callbacks."
    exit 1
fi

# Validate IP format
if ! [[ $APP_SERVER_IP =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "[ERROR] Invalid IP address format: $APP_SERVER_IP"
    exit 1
fi

echo "[INFO] App Server IP: $APP_SERVER_IP"

# Function for Amazon Linux / RHEL
install_amazon_linux() {
    echo "[INFO] Installing dependencies for Amazon Linux..."
    
    sudo yum update -y
    
    # Install build tools
    sudo yum install -y pcre-devel openssl-devel zlib-devel git wget gcc make
    
    # Download and compile Nginx with RTMP
    cd /tmp
    
    # Clean up previous nginx downloads if they exist
    echo "[INFO] Cleaning up previous nginx downloads..."
    rm -rf /tmp/nginx-1.24.0*
    rm -rf /tmp/nginx-rtmp-module
    
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
    
    # Create nginx user
    sudo useradd -r nginx 2>/dev/null || true
    
    # Create nginx systemd service
    sudo tee /etc/systemd/system/nginx.service > /dev/null <<EOF
[Unit]
Description=NGINX RTMP Server
After=network.target

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
}

# Function for Ubuntu/Debian
install_ubuntu() {
    echo "[INFO] Installing dependencies for Ubuntu..."
    
    sudo apt-get update
    sudo apt-get upgrade -y
    
    # Install Nginx with RTMP module
    sudo apt-get install -y nginx libnginx-mod-rtmp
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
        echo "[ERROR] Unsupported OS: $OS"
        exit 1
        ;;
esac

# Create HLS directory
echo "[INFO] Setting up directories..."
sudo mkdir -p /var/www/html/hls
sudo chown -R nginx:nginx /var/www/html/hls 2>/dev/null || \
sudo chown -R www-data:www-data /var/www/html/hls 2>/dev/null || true
sudo chmod 755 /var/www/html/hls

# Create nginx configuration
echo "[INFO] Configuring Nginx RTMP..."

# Check if Ubuntu (needs load_module)
if [ "$OS" = "ubuntu" ] || [ "$OS" = "debian" ]; then
    LOAD_MODULE="load_module modules/ngx_rtmp_module.so;"
else
    LOAD_MODULE="# Module compiled in - no load_module needed"
fi

sudo tee /etc/nginx/nginx.conf > /dev/null <<EOF
# Nginx RTMP Configuration for FaltuBaat
# App Server: $APP_SERVER_IP

$LOAD_MODULE

worker_processes auto;
rtmp_auto_push on;
pid /var/run/nginx.pid;
error_log /var/log/nginx/error.log;

events {
    worker_connections 1024;
}

rtmp {
    server {
        listen 1935;

        application live {
            live on;
            record off;
            
            # HLS settings
            hls on;
            hls_path /var/www/html/hls;
            hls_fragment 3;
            hls_playlist_length 60;
            
            allow publish all;
            allow play all;
            
            # Notify App Server when stream starts/stops
            on_publish http://$APP_SERVER_IP:3000/stream/start;
            on_publish_done http://$APP_SERVER_IP:3000/stream/stop;
        }
    }
}

http {
    include       /etc/nginx/mime.types;
    default_type  application/octet-stream;
    
    access_log /var/log/nginx/access.log;
    
    sendfile off;
    tcp_nopush on;
    directio 512;
    keepalive_timeout 65;
    
    server {
        listen 8080;
        server_name _;
        
        location /hls {
            types {
                application/vnd.apple.mpegurl m3u8;
                video/mp2t ts;
            }
            root /var/www/html;
            
            # CORS headers
            add_header Cache-Control no-cache;
            add_header Access-Control-Allow-Origin *;
            add_header Access-Control-Allow-Methods 'GET, OPTIONS';
            add_header Access-Control-Allow-Headers 'Origin, Content-Type, Accept';
        }
        
        # Health check
        location /health {
            return 200 'OK';
            add_header Content-Type text/plain;
        }
        
        location / {
            root /var/www/html;
            index index.html;
        }
    }
}
EOF

# Test nginx configuration
echo "[INFO] Testing Nginx configuration..."
sudo nginx -t

# Enable and start nginx
echo "[INFO] Starting Nginx RTMP server..."
sudo systemctl daemon-reload
sudo systemctl enable nginx
sudo systemctl start nginx

# Configure firewall (if firewalld is active)
if command -v firewall-cmd &> /dev/null; then
    echo "[INFO] Configuring firewall..."
    sudo firewall-cmd --permanent --add-port=1935/tcp
    sudo firewall-cmd --permanent --add-port=8080/tcp
    sudo firewall-cmd --reload
fi

# Get public IP
PUBLIC_IP=$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4 2>/dev/null || echo "YOUR_EC2_IP")

echo ""
echo "[OK] RTMP Server Installation complete!"
echo "======================================="
echo ""
echo "[INFO] Stream endpoints:"
echo "   RTMP:  rtmp://$PUBLIC_IP:1935/live/STREAM_KEY"
echo "   HLS:   http://$PUBLIC_IP:8080/hls/STREAM_KEY.m3u8"
echo ""
echo "[INFO] Connected to App Server: $APP_SERVER_IP:3000"
echo ""
echo "[INFO] Service Management:"
echo "   Status:  sudo systemctl status nginx"
echo "   Logs:    sudo tail -f /var/log/nginx/error.log"
echo "   Restart: sudo systemctl restart nginx"
echo ""
echo "[WARN] Open these ports in your EC2 Security Group:"
echo "   - 1935  (TCP) - RTMP Streaming"
echo "   - 8080  (TCP) - HLS Streams"
echo ""
echo "[INFO] To change App Server IP later, edit:"
echo "   /etc/nginx/nginx.conf"
echo "   Then: sudo systemctl restart nginx"
echo ""
