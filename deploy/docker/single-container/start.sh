#!/bin/bash

# FaltuBaat - Docker Single Container Build & Run Script
# Downloads code from GitHub and builds/runs the container

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEPLOY_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

echo "ðŸš€ FaltuBaat - Docker Single Container Deployment"
echo "=================================================="

# Load configuration
if [ -f "$DEPLOY_ROOT/config.env" ]; then
    source "$DEPLOY_ROOT/config.env"
    echo "âœ… Loaded configuration from config.env"
else
    echo "âš ï¸  No config.env found. Using defaults."
    GITHUB_REPO="https://github.com/YOUR_ORG/faltubaat.git"
    GITHUB_BRANCH="main"
fi

# Allow override via environment variables or command line
GITHUB_REPO="${1:-$GITHUB_REPO}"
GITHUB_BRANCH="${2:-$GITHUB_BRANCH}"

# Validate GitHub repo is configured
if [[ "$GITHUB_REPO" == *"YOUR_ORG"* ]]; then
    echo ""
    echo "âŒ ERROR: GitHub repository not configured!"
    echo ""
    echo "Please either:"
    echo "  1. Edit deploy/config.env and set GITHUB_REPO"
    echo "  2. Pass the repo URL as argument: ./start.sh https://github.com/your/repo.git"
    echo ""
    exit 1
fi

# Create temporary directory for code
TEMP_DIR=$(mktemp -d)
BUILD_DIR="$TEMP_DIR/faltubaat"

echo ""
echo "ðŸ“¥ Downloading application code..."
echo "   Repository: $GITHUB_REPO"
echo "   Branch: $GITHUB_BRANCH"
echo ""

# Clone the repository
git clone --depth 1 --branch "$GITHUB_BRANCH" "$GITHUB_REPO" "$BUILD_DIR"

if [ $? -ne 0 ]; then
    echo "âŒ Failed to clone repository"
    rm -rf "$TEMP_DIR"
    exit 1
fi

echo "âœ… Code downloaded successfully"

# Copy Dockerfile to build directory
echo "ðŸ“‹ Preparing Docker build..."
cp "$SCRIPT_DIR/Dockerfile" "$BUILD_DIR/"

# Build the Docker image
echo ""
echo "ðŸ”¨ Building Docker image..."
cd "$BUILD_DIR"

DOCKER_IMAGE="${DOCKER_REGISTRY:+$DOCKER_REGISTRY/}${DOCKER_IMAGE_NAME:-faltubaat}:${DOCKER_IMAGE_TAG:-latest}"

docker build -t "$DOCKER_IMAGE" -f Dockerfile .

if [ $? -ne 0 ]; then
    echo "âŒ Docker build failed"
    rm -rf "$TEMP_DIR"
    exit 1
fi

echo "âœ… Docker image built: $DOCKER_IMAGE"

# Cleanup temp directory
rm -rf "$TEMP_DIR"

# Create data volume if not exists
docker volume create faltubaat-data 2>/dev/null || true

# Stop existing container if running
echo ""
echo "ðŸ”„ Stopping existing container (if any)..."
docker stop faltubaat-single 2>/dev/null || true
docker rm faltubaat-single 2>/dev/null || true

# Run the container
echo ""
echo "ðŸš€ Starting container..."
docker run -d \
    --name faltubaat-single \
    --restart unless-stopped \
    -p 3000:3000 \
    -p 3443:3443 \
    -p 1935:1935 \
    -p 8080:8080 \
    -v faltubaat-data:/app/data \
    -e NODE_ENV=production \
    "$DOCKER_IMAGE"

if [ $? -ne 0 ]; then
    echo "âŒ Failed to start container"
    exit 1
fi

echo ""
echo "âœ… FaltuBaat is running!"
echo ""
echo "ðŸ“ Access points:"
echo "   HTTP:  http://localhost:3000"
echo "   HTTPS: https://localhost:3443"
echo "   RTMP:  rtmp://localhost:1935/live"
echo "   HLS:   http://localhost:8080/hls/"
echo ""
echo "ðŸ“‹ Container commands:"
echo "   View logs:  docker logs -f faltubaat-single"
echo "   Stop:       docker stop faltubaat-single"
echo "   Restart:    docker restart faltubaat-single"
echo ""
