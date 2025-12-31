#!/bin/bash

# FaltuBaat - Docker Multi-Container Build & Run Script
# Downloads code from GitHub and builds/runs containers with Docker Compose

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEPLOY_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

echo "[INFO] FaltuBaat - Docker Multi-Container Deployment"
echo "=================================================="

# Load configuration
if [ -f "$DEPLOY_ROOT/config.env" ]; then
    source "$DEPLOY_ROOT/config.env"
    echo "[OK] Loaded configuration from config.env"
else
    echo "[WARN] No config.env found. Using defaults."
    GITHUB_REPO="https://github.com/YOUR_ORG/faltubaat.git"
    GITHUB_BRANCH="main"
fi

# Allow override via environment variables or command line
GITHUB_REPO="${1:-$GITHUB_REPO}"
GITHUB_BRANCH="${2:-$GITHUB_BRANCH}"

# Validate GitHub repo is configured
if [[ "$GITHUB_REPO" == *"YOUR_ORG"* ]]; then
    echo ""
    echo "[ERROR] GitHub repository not configured!"
    echo ""
    echo "Please either:"
    echo "  1. Edit deploy/config.env and set GITHUB_REPO"
    echo "  2. Pass the repo URL as argument: ./start.sh https://github.com/your/repo.git"
    echo ""
    exit 1
fi

# Create build directory
BUILD_DIR="$SCRIPT_DIR/.build"
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

echo ""
echo "[INFO] Downloading application code..."
echo "   Repository: $GITHUB_REPO"
echo "   Branch: $GITHUB_BRANCH"
echo ""

# Clone the repository
git clone --depth 1 --branch "$GITHUB_BRANCH" "$GITHUB_REPO" "$BUILD_DIR/app"

if [ $? -ne 0 ]; then
    echo "[ERROR] Failed to clone repository"
    rm -rf "$BUILD_DIR"
    exit 1
fi

echo "[OK] Code downloaded successfully"

# Copy Docker files to build directory
echo "[INFO] Preparing Docker build..."
cp "$SCRIPT_DIR/Dockerfile.app" "$BUILD_DIR/"
cp "$SCRIPT_DIR/Dockerfile.nginx-rtmp" "$BUILD_DIR/"
cp "$SCRIPT_DIR/nginx-rtmp.conf" "$BUILD_DIR/"
cp "$SCRIPT_DIR/start-app.sh" "$BUILD_DIR/" 2>/dev/null || true

# Create docker-compose.yml for build
cat > "$BUILD_DIR/docker-compose.yml" <<EOF
version: '3.8'

services:
  chat-app:
    build:
      context: ./app
      dockerfile: ../Dockerfile.app
    container_name: faltubaat-app
    restart: unless-stopped
    ports:
      - "3000:3000"
      - "3443:3443"
    environment:
      - NODE_ENV=production
      - PORT=3000
      - HTTPS_PORT=3443
    volumes:
      - app-data:/app/data
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:3000/"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 10s

  nginx-rtmp:
    build:
      context: .
      dockerfile: Dockerfile.nginx-rtmp
    container_name: faltubaat-nginx-rtmp
    restart: unless-stopped
    ports:
      - "1935:1935"
      - "8080:8080"
    volumes:
      - hls-data:/var/www/html/hls
    depends_on:
      - chat-app
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:8080/health"]
      interval: 30s
      timeout: 10s
      retries: 3

volumes:
  app-data:
  hls-data:
EOF

# Stop existing containers
echo ""
echo "[INFO] Stopping existing containers (if any)..."
cd "$BUILD_DIR"
docker compose down 2>/dev/null || true

# Build and start
echo ""
echo "[INFO] Building and starting containers..."
docker compose up -d --build

if [ $? -ne 0 ]; then
    echo "[ERROR] Docker Compose failed"
    exit 1
fi

echo ""
echo "[OK] FaltuBaat Multi-Container is running!"
echo ""
echo "[INFO] Access points:"
echo "   HTTP:  http://localhost:3000"
echo "   HTTPS: https://localhost:3443"
echo "   RTMP:  rtmp://localhost:1935/live"
echo "   HLS:   http://localhost:8080/hls/"
echo ""
echo "[INFO] Containers:"
echo "   faltubaat-app        -> Node.js Chat Application"
echo "   faltubaat-nginx-rtmp -> Nginx RTMP/HLS Streaming"
echo ""
echo "[INFO] Commands:"
echo "   View logs:      cd $BUILD_DIR && docker compose logs -f"
echo "   Stop:           cd $BUILD_DIR && docker compose down"
echo "   Restart:        cd $BUILD_DIR && docker compose restart"
echo ""