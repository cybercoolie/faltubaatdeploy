#!/bin/bash

echo "ðŸš€ Starting FaltuBaat Chat Application..."

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

# Start Node.js application
cd /app
exec node server-https.js
