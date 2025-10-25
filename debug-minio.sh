#!/bin/bash

# MinIO Debug Script
# Simple script to debug MinIO connection issues

set -e

# MinIO configuration
MINIO_ENDPOINT="http://31.184.134.153:9005"
MINIO_ACCESS_KEY="minioaccesskey"
MINIO_SECRET_KEY="miniosecretkey"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log() {
    echo -e "${BLUE}[$(date '+%Y-%m-%d %H:%M:%S')]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Install mc if needed
install_mc() {
    if command -v mc &> /dev/null; then
        echo "mc"
        return 0
    fi
    
    log "Installing MinIO client..."
    INSTALL_DIR="/tmp/minio-debug-$$"
    mkdir -p "$INSTALL_DIR"
    
    if command -v wget &> /dev/null; then
        wget -q https://dl.min.io/client/mc/release/linux-amd64/mc -O "$INSTALL_DIR/mc"
    elif command -v curl &> /dev/null; then
        curl -s https://dl.min.io/client/mc/release/linux-amd64/mc -o "$INSTALL_DIR/mc"
    else
        log_error "Cannot install MinIO client"
        return 1
    fi
    
    chmod +x "$INSTALL_DIR/mc"
    echo "$INSTALL_DIR/mc"
}

main() {
    log "Debugging MinIO connection..."
    
    # Install mc
    MC_CMD=$(install_mc)
    if [ $? -ne 0 ]; then
        exit 1
    fi
    
    log "Using MinIO client: $MC_CMD"
    
    # Test basic connection
    log "Testing basic connection to $MINIO_ENDPOINT..."
    if curl -s --connect-timeout 5 "$MINIO_ENDPOINT" &>/dev/null; then
        log_success "Endpoint is accessible"
    else
        log_error "Endpoint is not accessible"
        exit 1
    fi
    
    # Try to configure mc
    log "Configuring MinIO client..."
    local alias_name="debug_minio"
    
    # Try with verbose output
    log "Attempting to set alias..."
    if $MC_CMD alias set "$alias_name" "$MINIO_ENDPOINT" "$MINIO_ACCESS_KEY" "$MINIO_SECRET_KEY" 2>&1; then
        log_success "Alias set successfully"
    else
        log_error "Failed to set alias"
        exit 1
    fi
    
    # Try to list
    log "Attempting to list buckets..."
    if $MC_CMD ls "$alias_name" 2>&1; then
        log_success "Successfully listed buckets"
    else
        log_error "Failed to list buckets"
        exit 1
    fi
    
    # Try different bucket names
    log "Testing different bucket names..."
    for bucket in "audio-files" "audio" "files" "conversations" "recordings"; do
        log "Testing bucket: $bucket"
        if $MC_CMD ls "$alias_name/$bucket" 2>/dev/null; then
            log_success "Bucket '$bucket' exists and is accessible"
            
            # List contents
            log "Contents of bucket '$bucket':"
            $MC_CMD ls --recursive "$alias_name/$bucket/" 2>/dev/null | head -10 || true
        else
            log "Bucket '$bucket' does not exist or is not accessible"
        fi
    done
    
    # Cleanup
    if [[ "$MC_CMD" == "/tmp/minio-debug-"* ]]; then
        rm -rf "$(dirname "$MC_CMD")"
    fi
}

main "$@"
