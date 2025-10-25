#!/bin/bash

# Quick MinIO Cleanup Script
# Deletes files older than specified days from MinIO bucket

set -e

# Configuration
MC_CMD="/tmp/minio-cleanup-58848/mc"
ALIAS_NAME="test_minio"
BUCKET="audio-files"
DAYS_OLD=${1:-2}

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

main() {
    log "Starting quick MinIO cleanup"
    log "Deleting files older than $DAYS_OLD days"
    
    # Calculate cutoff date
    local cutoff_date=$(date -d "$DAYS_OLD days ago" '+%Y-%m-%d')
    log "Cutoff date: $cutoff_date"
    
    # Get list of files older than cutoff date
    log "Finding files to delete..."
    local files_to_delete=$($MC_CMD ls --recursive "$ALIAS_NAME/$BUCKET/" 2>/dev/null | awk -v cutoff="$cutoff_date" '$1 < cutoff {print $4}' | head -1000)
    
    if [ -z "$files_to_delete" ]; then
        log "No files older than $DAYS_OLD days found"
        exit 0
    fi
    
    local count=$(echo "$files_to_delete" | wc -l)
    log "Found $count files to delete (showing first 1000)"
    
    # Show some examples
    log "Example files to be deleted:"
    echo "$files_to_delete" | head -5 | while read -r file; do
        echo "  - $file"
    done
    
    # Ask for confirmation
    echo ""
    read -p "Do you want to delete these files? (y/N): " -n 1 -r
    echo ""
    
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log "Cleanup cancelled"
        exit 0
    fi
    
    # Delete files
    log "Starting deletion..."
    local deleted=0
    local failed=0
    
    echo "$files_to_delete" | while read -r file; do
        if [ -n "$file" ]; then
            if $MC_CMD rm "$ALIAS_NAME/$BUCKET/$file" 2>/dev/null; then
                echo "Deleted: $file"
                deleted=$((deleted + 1))
            else
                log_error "Failed to delete: $file"
                failed=$((failed + 1))
            fi
        fi
    done
    
    log_success "Cleanup completed"
    log "Deleted: $deleted files"
    if [ $failed -gt 0 ]; then
        log_warning "Failed: $failed files"
    fi
    
    # Show new bucket size
    log "New bucket size:"
    $MC_CMD du "$ALIAS_NAME/$BUCKET"
}

main "$@"
