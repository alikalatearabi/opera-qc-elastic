#!/bin/bash

# Audio Files Cleanup Script
# Removes audio files older than 2 days from both local filesystem and MinIO storage
# Usage: ./cleanup-old-audio-files.sh [--dry-run] [--days N]

set -e

# Default configuration
DAYS_OLD=2
DRY_RUN=false
LOCAL_AUDIO_DIR="/app/conversations"
MINIO_BUCKET="audio-files"
MINIO_ENDPOINT="http://localhost:9005"
MINIO_ACCESS_KEY="minioaccesskey"
MINIO_SECRET_KEY="miniosecretkey"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --days)
            DAYS_OLD="$2"
            shift 2
            ;;
        --help|-h)
            echo "Usage: $0 [--dry-run] [--days N]"
            echo "  --dry-run    Show what would be deleted without actually deleting"
            echo "  --days N     Number of days old (default: 2)"
            echo "  --help       Show this help message"
            exit 0
            ;;
        *)
            echo "Unknown option $1"
            exit 1
            ;;
    esac
done

# Function to log messages
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

# Function to cleanup local audio files
cleanup_local_files() {
    log "Cleaning up local audio files older than $DAYS_OLD days..."
    
    if [ ! -d "$LOCAL_AUDIO_DIR" ]; then
        log_warning "Local audio directory $LOCAL_AUDIO_DIR does not exist"
        return 0
    fi
    
    # Find files older than specified days
    local files_to_delete=$(find "$LOCAL_AUDIO_DIR" -type f \( -name "*.wav" -o -name "*.mp3" -o -name "*.m4a" -o -name "*.flac" \) -mtime +$DAYS_OLD 2>/dev/null || true)
    
    if [ -z "$files_to_delete" ]; then
        log "No local audio files older than $DAYS_OLD days found"
        return 0
    fi
    
    local count=$(echo "$files_to_delete" | wc -l)
    log "Found $count local audio files older than $DAYS_OLD days"
    
    if [ "$DRY_RUN" = true ]; then
        log_warning "DRY RUN - Would delete the following local files:"
        echo "$files_to_delete" | while read -r file; do
            if [ -n "$file" ]; then
                echo "  - $file"
            fi
        done
    else
        local deleted_count=0
        echo "$files_to_delete" | while read -r file; do
            if [ -n "$file" ] && [ -f "$file" ]; then
                if rm "$file" 2>/dev/null; then
                    echo "Deleted: $file"
                    ((deleted_count++))
                else
                    log_error "Failed to delete: $file"
                fi
            fi
        done
        log_success "Deleted $deleted_count local audio files"
    fi
}

# Function to cleanup MinIO audio files
cleanup_minio_files() {
    log "Cleaning up MinIO audio files older than $DAYS_OLD days..."
    
    # Check if mc (MinIO client) is available
    if ! command -v mc &> /dev/null; then
        log_warning "MinIO client (mc) not found. Installing..."
        
        # Try to install mc
        if command -v wget &> /dev/null; then
            wget https://dl.min.io/client/mc/release/linux-amd64/mc -O /tmp/mc
            chmod +x /tmp/mc
            MC_CMD="/tmp/mc"
        elif command -v curl &> /dev/null; then
            curl https://dl.min.io/client/mc/release/linux-amd64/mc -o /tmp/mc
            chmod +x /tmp/mc
            MC_CMD="/tmp/mc"
        else
            log_error "Neither wget nor curl available. Cannot install MinIO client"
            return 1
        fi
    else
        MC_CMD="mc"
    fi
    
    # Configure MinIO client
    local alias_name="cleanup_minio"
    $MC_CMD alias set "$alias_name" "$MINIO_ENDPOINT" "$MINIO_ACCESS_KEY" "$MINIO_SECRET_KEY" &>/dev/null
    
    if [ $? -ne 0 ]; then
        log_error "Failed to configure MinIO client"
        return 1
    fi
    
    # Calculate cutoff date
    local cutoff_date
    if command -v gdate &> /dev/null; then
        # macOS
        cutoff_date=$(gdate -d "$DAYS_OLD days ago" '+%Y-%m-%d')
    else
        # Linux
        cutoff_date=$(date -d "$DAYS_OLD days ago" '+%Y-%m-%d')
    fi
    
    log "Looking for MinIO files older than $cutoff_date"
    
    # List files in MinIO bucket
    local minio_files=$($MC_CMD ls --recursive "$alias_name/$MINIO_BUCKET/" 2>/dev/null | awk '{print $4 " " $5 " " $6}' || true)
    
    if [ -z "$minio_files" ]; then
        log "No files found in MinIO bucket $MINIO_BUCKET or bucket doesn't exist"
        return 0
    fi
    
    local files_to_delete=""
    local count=0
    
    # Process each file and check date
    while IFS= read -r line; do
        if [ -n "$line" ]; then
            # Extract date and filename from mc ls output
            local file_date=$(echo "$line" | awk '{print $1}')
            local file_name=$(echo "$line" | awk '{print $3}')
            
            # Skip if filename is empty or doesn't look like an audio file
            if [ -z "$file_name" ] || [[ ! "$file_name" =~ \.(wav|mp3|m4a|flac)$ ]]; then
                continue
            fi
            
            # Compare dates (simple string comparison works for YYYY-MM-DD format)
            if [[ "$file_date" < "$cutoff_date" ]]; then
                files_to_delete="$files_to_delete$alias_name/$MINIO_BUCKET/$file_name\n"
                ((count++))
            fi
        fi
    done <<< "$minio_files"
    
    if [ $count -eq 0 ]; then
        log "No MinIO audio files older than $DAYS_OLD days found"
    else
        log "Found $count MinIO audio files older than $DAYS_OLD days"
        
        if [ "$DRY_RUN" = true ]; then
            log_warning "DRY RUN - Would delete the following MinIO files:"
            echo -e "$files_to_delete" | while read -r file; do
                if [ -n "$file" ]; then
                    echo "  - $file"
                fi
            done
        else
            local deleted_count=0
            echo -e "$files_to_delete" | while read -r file; do
                if [ -n "$file" ]; then
                    if $MC_CMD rm "$file" 2>/dev/null; then
                        echo "Deleted: $file"
                        ((deleted_count++))
                    else
                        log_error "Failed to delete: $file"
                    fi
                fi
            done
            log_success "Deleted $deleted_count MinIO audio files"
        fi
    fi
    
    # Cleanup temporary mc if we installed it
    if [ "$MC_CMD" = "/tmp/mc" ]; then
        rm -f /tmp/mc
    fi
}

# Function to cleanup empty directories
cleanup_empty_directories() {
    log "Cleaning up empty directories..."
    
    if [ ! -d "$LOCAL_AUDIO_DIR" ]; then
        return 0
    fi
    
    local empty_dirs=$(find "$LOCAL_AUDIO_DIR" -type d -empty 2>/dev/null || true)
    
    if [ -z "$empty_dirs" ]; then
        log "No empty directories found"
        return 0
    fi
    
    local count=$(echo "$empty_dirs" | wc -l)
    log "Found $count empty directories"
    
    if [ "$DRY_RUN" = true ]; then
        log_warning "DRY RUN - Would remove the following empty directories:"
        echo "$empty_dirs" | while read -r dir; do
            if [ -n "$dir" ]; then
                echo "  - $dir"
            fi
        done
    else
        local deleted_count=0
        echo "$empty_dirs" | while read -r dir; do
            if [ -n "$dir" ] && [ -d "$dir" ]; then
                if rmdir "$dir" 2>/dev/null; then
                    echo "Removed empty directory: $dir"
                    ((deleted_count++))
                fi
            fi
        done
        log_success "Removed $deleted_count empty directories"
    fi
}

# Main execution
main() {
    log "Starting audio files cleanup script"
    log "Configuration:"
    log "  - Days old: $DAYS_OLD"
    log "  - Dry run: $DRY_RUN"
    log "  - Local directory: $LOCAL_AUDIO_DIR"
    log "  - MinIO bucket: $MINIO_BUCKET"
    log "  - MinIO endpoint: $MINIO_ENDPOINT"
    
    echo ""
    
    # Cleanup local files
    cleanup_local_files
    echo ""
    
    # Cleanup MinIO files
    cleanup_minio_files
    echo ""
    
    # Cleanup empty directories
    cleanup_empty_directories
    echo ""
    
    if [ "$DRY_RUN" = true ]; then
        log_warning "DRY RUN completed - no files were actually deleted"
    else
        log_success "Audio files cleanup completed successfully"
    fi
}

# Run main function
main "$@"
