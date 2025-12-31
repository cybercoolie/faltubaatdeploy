#!/bin/bash

echo "ðŸš€ Starting FaltuBaat Single-Container (Node.js + Nginx/RTMP)..."

# Generate JWT_SECRET if not set
if [ -z "$JWT_SECRET" ] || [ "$JWT_SECRET" = "CHANGE_THIS_IN_PRODUCTION" ]; then
    export JWT_SECRET=$(openssl rand -hex 32)
    echo "ðŸ” Generated random JWT_SECRET"
fi

# =============================================================================
# S3 Database Sync (Optional - for testing without EFS)
# =============================================================================
if [ "$S3_SYNC_ENABLED" = "true" ] && [ -n "$S3_DB_BUCKET" ]; then
    echo "ðŸ“¦ S3 database sync enabled"
    
    # Download database from S3 on startup
    /app/s3-db-sync.sh download
    
    # Start periodic sync in background
    /app/s3-db-sync.sh sync &
    
    # Trap signals to upload on shutdown
    trap '/app/s3-db-sync.sh upload; exit 0' SIGTERM SIGINT
else
    echo "ðŸ“¦ Using local/EFS storage for database"
fi

# Ensure HLS directory exists and has correct permissions
mkdir -p /var/www/html/hls
chmod 755 /var/www/html/hls

# Kill any existing nginx processes
killall nginx 2>/dev/null || true
sleep 1

# Start Nginx in background
echo "Starting Nginx RTMP server..."
nginx

# Wait a moment for Nginx to start
sleep 2

# Check if Nginx started successfully
if pgrep nginx > /dev/null; then
    echo "âœ… Nginx RTMP server started on ports 1935 (RTMP) and 8080 (HLS)"
else
    echo "âŒ Nginx failed to start!"
    cat /var/log/nginx/error.log 2>/dev/null || true
    echo "âš ï¸  Continuing with Node.js only..."
fi

# Start Node.js application (foreground - keeps container alive)
echo "Starting Chat Application on ports 3000 (HTTP) and 3443 (HTTPS)..."
cd /app
exec node server-https.js
