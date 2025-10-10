#!/bin/bash

# MinIO Voice Files Cleanup Script
# Removes voice files older than specified days from MinIO storage

set -e

# Configuration
DAYS_OLD=${1:-2}  # Default: 2 days old
DRY_RUN=${2:-false}  # Default: actually delete
MINIO_ENDPOINT="http://31.184.134.153:9005"
MINIO_ACCESS_KEY="minioaccesskey"
MINIO_SECRET_KEY="miniosecretkey"
MINIO_BUCKET="audio-files"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

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
    if ! command -v mc &> /dev/null; then
        log "Installing MinIO client..."
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
            exit 1
        fi
    else
        MC_CMD="mc"
    fi
}

# Configure MinIO client
configure_mc() {
    local alias_name="voice_cleanup"
    $MC_CMD alias set "$alias_name" "$MINIO_ENDPOINT" "$MINIO_ACCESS_KEY" "$MINIO_SECRET_KEY" &>/dev/null
    
    if [ $? -ne 0 ]; then
        log_error "Failed to configure MinIO client"
        exit 1
    fi
    
    echo "$alias_name"
}

# Get cutoff date
get_cutoff_date() {
    if command -v gdate &> /dev/null; then
        # macOS
        gdate -d "$DAYS_OLD days ago" '+%Y-%m-%d'
    else
        # Linux
        date -d "$DAYS_OLD days ago" '+%Y-%m-%d'
    fi
}

# Clean up voice files
cleanup_voice_files() {
    local alias_name="$1"
    local cutoff_date="$2"
    
    log "Looking for voice files older than $cutoff_date (${DAYS_OLD} days ago)"
    
    # List files in MinIO bucket
    local minio_files=$($MC_CMD ls --recursive "$alias_name/$MINIO_BUCKET/" 2>/dev/null || true)
    
    if [ -z "$minio_files" ]; then
        log "No files found in MinIO bucket $MINIO_BUCKET or bucket doesn't exist"
        return 0
    fi
    
    local files_to_delete=""
    local count=0
    local total_size=0
    
    # Process each file and check date
    while IFS= read -r line; do
        if [ -n "$line" ]; then
            # Extract date, size, and filename from mc ls output
            local file_date=$(echo "$line" | awk '{print $1}')
            local file_time=$(echo "$line" | awk '{print $2}')
            local file_size_raw=$(echo "$line" | awk '{print $3}')
            local file_name=$(echo "$line" | awk '{print $4}')
            
            # Skip if filename is empty or doesn't look like a voice file
            if [ -z "$file_name" ] || [[ ! "$file_name" =~ \.(wav|mp3|m4a|flac|aac|ogg)$ ]]; then
                continue
            fi
            
            # Convert size to bytes for calculation
            local file_size_bytes=0
            if [[ "$file_size_raw" =~ ([0-9.]+)([KMGT]?i?B?) ]]; then
                local size_num="${BASH_REMATCH[1]}"
                local size_unit="${BASH_REMATCH[2]}"
                
                case "$size_unit" in
                    "B"|"") file_size_bytes=$(echo "$size_num" | cut -d. -f1) ;;
                    "KiB"|"KB") file_size_bytes=$(echo "$size_num * 1024" | bc 2>/dev/null || echo "1024") ;;
                    "MiB"|"MB") file_size_bytes=$(echo "$size_num * 1024 * 1024" | bc 2>/dev/null || echo "1048576") ;;
                    "GiB"|"GB") file_size_bytes=$(echo "$size_num * 1024 * 1024 * 1024" | bc 2>/dev/null || echo "1073741824") ;;
                esac
            fi
            
            # Compare dates (simple string comparison works for YYYY-MM-DD format)
            if [[ "$file_date" < "$cutoff_date" ]]; then
                files_to_delete="$files_to_delete$alias_name/$MINIO_BUCKET/$file_name\n"
                ((count++))
                total_size=$((total_size + file_size_bytes))
            fi
        fi
    done <<< "$minio_files"
    
    if [ $count -eq 0 ]; then
        log "No voice files older than $DAYS_OLD days found"
        return 0
    fi
    
    # Calculate total size in human readable format
    local total_size_mb=$((total_size / 1024 / 1024))
    local total_size_gb=$((total_size_mb / 1024))
    
    if [ $total_size_gb -gt 0 ]; then
        log "Found $count voice files older than $DAYS_OLD days (Total: ${total_size_gb}GB)"
    else
        log "Found $count voice files older than $DAYS_OLD days (Total: ${total_size_mb}MB)"
    fi
    
    if [ "$DRY_RUN" = "true" ]; then
        log_warning "DRY RUN - Would delete the following voice files:"
        echo -e "$files_to_delete" | head -10 | while read -r file; do
            if [ -n "$file" ]; then
                echo "  - $file"
            fi
        done
        if [ $count -gt 10 ]; then
            echo "  ... and $((count - 10)) more files"
        fi
    else
        log "Deleting $count voice files..."
        local deleted_count=0
        local failed_count=0
        
        echo -e "$files_to_delete" | while read -r file; do
            if [ -n "$file" ]; then
                if $MC_CMD rm "$file" 2>/dev/null; then
                    echo "Deleted: $(basename "$file")"
                    ((deleted_count++))
                else
                    log_error "Failed to delete: $(basename "$file")"
                    ((failed_count++))
                fi
            fi
        done
        
        if [ $total_size_gb -gt 0 ]; then
            log_success "Cleanup completed: $deleted_count files deleted, ${total_size_gb}GB freed"
        else
            log_success "Cleanup completed: $deleted_count files deleted, ${total_size_mb}MB freed"
        fi
        
        if [ $failed_count -gt 0 ]; then
            log_warning "$failed_count files could not be deleted"
        fi
    fi
}

# Main execution
main() {
    log "Starting MinIO voice files cleanup"
    log "Configuration:"
    log "  - Days old: $DAYS_OLD"
    log "  - Dry run: $DRY_RUN"
    log "  - MinIO endpoint: $MINIO_ENDPOINT"
    log "  - MinIO bucket: $MINIO_BUCKET"
    
    # Install and configure MinIO client
    install_mc
    local alias_name=$(configure_mc)
    
    # Get cutoff date
    local cutoff_date=$(get_cutoff_date)
    
    # Clean up voice files
    cleanup_voice_files "$alias_name" "$cutoff_date"
    
    # Cleanup temporary mc if we installed it
    if [ "$MC_CMD" = "/tmp/mc" ]; then
        rm -f /tmp/mc
    fi
    
    log "Voice files cleanup completed"
}

# Show usage
if [ "$1" = "--help" ] || [ "$1" = "-h" ]; then
    echo "Usage: $0 [DAYS_OLD] [DRY_RUN]"
    echo "  DAYS_OLD: Number of days old (default: 2)"
    echo "  DRY_RUN: true/false (default: false)"
    echo ""
    echo "Examples:"
    echo "  $0                    # Delete files older than 2 days"
    echo "  $0 7                  # Delete files older than 7 days"
    echo "  $0 1 true            # Dry run: show files older than 1 day"
    exit 0
fi

# Run main function
main "$@"
