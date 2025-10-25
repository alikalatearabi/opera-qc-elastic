#!/bin/bash

# Server MinIO Cleanup Script
# Works on the production server to clean up old audio files
# Usage: ./server-minio-cleanup.sh [days]

set -e

# Configuration
MINIO_ENDPOINT="http://31.184.134.153:9005"
MINIO_ACCESS_KEY="minioaccesskey"
MINIO_SECRET_KEY="miniosecretkey"
MINIO_BUCKET="audio-files"
DAYS_OLD=${1:-7}

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

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Install MinIO client if not available
install_mc() {
    local mc_cmd="$1"
    
    log "Installing MinIO client..."
    local install_dir="/tmp/minio-setup-$$"
    mkdir -p "$install_dir"
    
    if wget -q https://dl.min.io/client/mc/release/linux-amd64/mc -O "$install_dir/mc" 2>/dev/null; then
        chmod +x "$install_dir/mc"
        echo "$install_dir/mc"
    elif curl -s https://dl.min.io/client/mc/release/linux-amd64/mc -o "$install_dir/mc" 2>/dev/null; then
        chmod +x "$install_dir/mc"
        echo "$install_dir/mc"
    else
        log_error "Failed to download MinIO client"
        return 1
    fi
}

# Find or install mc
find_mc() {
    # Check if mc is in PATH
    if command -v mc &> /dev/null; then
        echo "mc"
        return 0
    fi
    
    # Check if we have a temp installation
    local temp_mc="/tmp/minio-cleanup-*/mc"
    if ls $temp_mc &> /dev/null; then
        echo "$(ls $temp_mc | head -1)"
        return 0
    fi
    
    # Install new mc
    install_mc
}

main() {
    log "Starting MinIO cleanup on production server"
    log "Configuration:"
    log "  Endpoint: $MINIO_ENDPOINT"
    log "  Bucket: $MINIO_BUCKET"
    log "  Days old: $DAYS_OLD"
    echo ""
    
    # Find or install mc
    local mc_cmd=$(find_mc)
    if [ -z "$mc_cmd" ]; then
        log_error "Failed to find or install MinIO client"
        exit 1
    fi
    
    log "Using MinIO client: $mc_cmd"
    
    # Configure alias
    local alias_name="prod_minio_$$"
    log "Configuring MinIO connection..."
    
    if ! $mc_cmd alias set "$alias_name" "$MINIO_ENDPOINT" "$MINIO_ACCESS_KEY" "$MINIO_SECRET_KEY" 2>/dev/null; then
        log_error "Failed to configure MinIO"
        exit 1
    fi
    
    # Check bucket exists
    if ! $mc_cmd ls "$alias_name/$MINIO_BUCKET" &>/dev/null; then
        log_error "Bucket '$MINIO_BUCKET' not found or not accessible"
        $mc_cmd ls "$alias_name/"
        exit 1
    fi
    
    log_success "Connected to MinIO successfully"
    
    # Get current bucket stats
    log "Current bucket statistics:"
    $mc_cmd du "$alias_name/$MINIO_BUCKET"
    local total_files=$($mc_cmd ls --recursive "$alias_name/$MINIO_BUCKET/" 2>/dev/null | wc -l)
    log "Total files: $total_files"
    echo ""
    
    # Calculate cutoff date (files older than X days)
    local cutoff_timestamp=$(date -d "$DAYS_OLD days ago" +%s)
    log "Looking for files older than $(date -d "@$cutoff_timestamp" '+%Y-%m-%d %H:%M:%S')"
    echo ""
    
    # Get files list with timestamps
    log "Scanning for old files..."
    local old_files=""
    local count=0
    local total_size=0
    
    # Get all files and check their dates
    $mc_cmd ls --recursive "$alias_name/$MINIO_BUCKET/" 2>/dev/null | while read -r line; do
        # Extract date and filename
        # Format: [2025-10-09 18:25:29 +0330] 12345 filename.wav
        local file_date=$(echo "$line" | awk '{print $1" "$2" "$3}')
        local file_name=$(echo "$line" | awk '{print $5}')
        local file_size=$(echo "$line" | awk '{print $4}')
        
        if [ -z "$file_name" ]; then
            continue
        fi
        
        # Convert MinIO date to timestamp for comparison
        # Handle both +0330 and UTC formats
        local file_timestamp=$(date -d "$file_date" +%s 2>/dev/null || echo "0")
        
        if [ $file_timestamp -gt 0 ] && [ $file_timestamp -lt $cutoff_timestamp ]; then
            # This file is old, add to list
            count=$((count + 1))
            echo "$file_name"
            
            if [ $count -le 10 ]; then
                echo "  #$count: $file_name (size: $file_size, date: $file_date)"
            fi
        fi
    done > /tmp/minio_files_to_delete.txt
    
    # Count total files to delete
    local delete_count=$(wc -l < /tmp/minio_files_to_delete.txt)
    
    if [ $delete_count -eq 0 ]; then
        log "No files older than $DAYS_OLD days found"
        rm -f /tmp/minio_files_to_delete.txt
        exit 0
    fi
    
    log "Found $delete_count files to delete"
    echo ""
    
    # Show first 10 files
    if [ $delete_count -gt 0 ]; then
        log "First 10 files to be deleted:"
        head -10 /tmp/minio_files_to_delete.txt
    fi
    echo ""
    
    # Ask for confirmation
    read -p "Do you want to delete these $delete_count files? (y/N): " -n 1 -r
    echo ""
    
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log "Cleanup cancelled"
        rm -f /tmp/minio_files_to_delete.txt
        exit 0
    fi
    
    # Delete files
    log "Starting deletion..."
    local deleted=0
    local failed=0
    
    while read -r file; do
        if [ -n "$file" ]; then
            if $mc_cmd rm "$alias_name/$MINIO_BUCKET/$file" 2>/dev/null; then
                deleted=$((deleted + 1))
                if [ $((deleted % 100)) -eq 0 ]; then
                    echo "Progress: Deleted $deleted files..."
                fi
            else
                failed=$((failed + 1))
            fi
        fi
    done < /tmp/minio_files_to_delete.txt
    
    echo ""
    log_success "Cleanup completed!"
    log "Deleted: $deleted files"
    if [ $failed -gt 0 ]; then
        log_warning "Failed: $failed files"
    fi
    
    # Show new bucket stats
    echo ""
    log "Updated bucket statistics:"
    $mc_cmd du "$alias_name/$MINIO_BUCKET"
    local remaining_files=$($mc_cmd ls --recursive "$alias_name/$MINIO_BUCKET/" 2>/dev/null | wc -l)
    log "Remaining files: $remaining_files"
    
    # Cleanup
    rm -f /tmp/minio_files_to_delete.txt
    $mc_cmd alias remove "$alias_name" 2>/dev/null || true
    
    log_success "MinIO cleanup completed successfully"
}

main "$@"
