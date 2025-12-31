#!/bin/bash

echo "ðŸ³ Building and running FaltuBaat Single-Container..."

# Navigate to project root
cd "$(dirname "$0")/../../.."

# Stop and remove existing container
docker stop faltubaat-single 2>/dev/null || true
docker rm faltubaat-single 2>/dev/null || true

# Build the image using the Dockerfile in this directory
echo "Building Docker image..."
docker build -t faltubaat-single -f deploy/docker/single-container/Dockerfile .

# Run the container with volume for database persistence
echo "Starting container..."
docker run -d \
  --name faltubaat-single \
  -p 3000:3000 \
  -p 3443:3443 \
  -p 1935:1935 \
  -p 8080:8080 \
  -v faltubaat-db:/app/data \
  -v faltubaat-hls:/var/www/html/hls \
  --restart unless-stopped \
  faltubaat-single

echo "âœ… Single-container application started successfully!"
echo ""
echo "ðŸŒ Access your application:"
echo "  Chat App (HTTP):  http://localhost:3000"
echo "  Chat App (HTTPS): https://localhost:3443"
echo "  RTMP Server:      rtmp://localhost:1935/live"
echo "  HLS Streams:      http://localhost:8080/hls/"
echo ""
echo "ðŸ³ Container: faltubaat-single (Node.js + Nginx/RTMP)"
echo ""
echo "ðŸ“Š Management:"
echo "  View logs:  docker logs -f faltubaat-single"
echo "  Stop app:   docker stop faltubaat-single"
echo "  Remove app: docker rm faltubaat-single"
echo "  Shell:      docker exec -it faltubaat-single bash"
