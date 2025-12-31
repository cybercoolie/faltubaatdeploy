#!/bin/bash

# =============================================================================
# S3 Database Sync Script for FaltuBaat
# Downloads DB from S3 on startup, uploads on shutdown
# =============================================================================

S3_DB_BUCKET="${S3_DB_BUCKET:-}"
S3_DB_KEY="${S3_DB_KEY:-faltubaat/database/faltubaat.db}"
S3_SYNC_ENABLED="${S3_SYNC_ENABLED:-false}"
DB_PATH="${DB_PATH:-/app/data/faltubaat.db}"

# Check if S3 sync is enabled
is_s3_enabled() {
    if [ "$S3_SYNC_ENABLED" = "true" ] && [ -n "$S3_DB_BUCKET" ]; then
        return 0
    fi
    return 1
}

# Download database from S3
download_db() {
    if ! is_s3_enabled; then
        echo "[INFO] S3 sync disabled, using local database"
        return 0
    fi

    echo "[INFO] Downloading database from S3..."
    
    # Ensure directory exists
    mkdir -p "$(dirname "$DB_PATH")"
    
    # Try to download from S3
    if aws s3 cp "s3://${S3_DB_BUCKET}/${S3_DB_KEY}" "$DB_PATH" 2>/dev/null; then
        echo "[OK] Database downloaded from S3"
        return 0
    else
        echo "[WARN] No database found in S3, will create new one"
        return 0
    fi
}

# Upload database to S3
upload_db() {
    if ! is_s3_enabled; then
        return 0
    fi

    if [ ! -f "$DB_PATH" ]; then
        echo "[WARN] No local database to upload"
        return 0
    fi

    echo "[INFO] Uploading database to S3..."
    
    if aws s3 cp "$DB_PATH" "s3://${S3_DB_BUCKET}/${S3_DB_KEY}"; then
        echo "[OK] Database uploaded to S3"
        return 0
    else
        echo "[ERROR] Failed to upload database to S3"
        return 1
    fi
}

# Periodic sync (for long-running containers)
periodic_sync() {
    if ! is_s3_enabled; then
        return 0
    fi

    SYNC_INTERVAL="${S3_SYNC_INTERVAL:-300}"  # Default: 5 minutes
    
    echo "[INFO] Starting periodic S3 sync (every ${SYNC_INTERVAL}s)..."
    
    while true; do
        sleep "$SYNC_INTERVAL"
        upload_db
    done
}

# Main entry point based on argument
case "$1" in
    download)
        download_db
        ;;
    upload)
        upload_db
        ;;
    sync)
        periodic_sync &
        ;;
    *)
        echo "Usage: $0 {download|upload|sync}"
        exit 1
        ;;
esac