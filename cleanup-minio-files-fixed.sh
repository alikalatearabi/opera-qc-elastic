#!/bin/bash

# Fixed Audio Files Cleanup Script for Production Server
# Removes audio files older than specified days from MinIO storage
# Usage: ./cleanup-minio-files-fixed.sh [--dry-run] [--days N]

set -e

# Default configuration
DAYS_OLD=2
DRY_RUN=false
MINIO_BUCKET="audio-files"
MINIO_ENDPOINT="http://localhost:9005"  # Will be updated based on container
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

# Function to detect MinIO container and get correct endpoint
detect_minio_endpoint() {
    log "Detecting MinIO container and endpoint..."
    
    # Check if MinIO container is running
    MINIO_CONTAINER=$(docker ps --format "table {{.Names}}" | grep -i minio | head -1)
    
    if [ -z "$MINIO_CONTAINER" ]; then
        log_error "MinIO container not found. Available containers:"
        docker ps --format "table {{.Names}}\t{{.Status}}"
        return 1
    fi
    
    log "Found MinIO container: $MINIO_CONTAINER"
    
    # Get MinIO port mapping
    MINIO_PORT=$(docker port $MINIO_CONTAINER 9000 2>/dev/null | cut -d':' -f2 | head -1)
    
    if [ -z "$MINIO_PORT" ]; then
        log_warning "Could not determine MinIO port, using default 9005"
        MINIO_PORT="9005"
    fi
    
    MINIO_ENDPOINT="http://localhost:$MINIO_PORT"
    log "Using MinIO endpoint: $MINIO_ENDPOINT"
    
    return 0
}

# Function to install MinIO client with proper permissions
install_minio_client() {
    log "Installing MinIO client..."
    
    # Create a writable directory
    INSTALL_DIR="/tmp/minio-cleanup-$$"
    mkdir -p "$INSTALL_DIR"
    
    # Download MinIO client
    if command -v wget &> /dev/null; then
        wget -q https://dl.min.io/client/mc/release/linux-amd64/mc -O "$INSTALL_DIR/mc"
    elif command -v curl &> /dev/null; then
        curl -s https://dl.min.io/client/mc/release/linux-amd64/mc -o "$INSTALL_DIR/mc"
    else
        log_error "Neither wget nor curl available. Cannot install MinIO client"
        return 1
    fi
    
    # Make it executable
    chmod +x "$INSTALL_DIR/mc"
    
    # Test if it works
    if "$INSTALL_DIR/mc" --version &>/dev/null; then
        log_success "MinIO client installed successfully"
        echo "$INSTALL_DIR/mc"
        return 0
    else
        log_error "Failed to install MinIO client"
        rm -rf "$INSTALL_DIR"
        return 1
    fi
}

# Function to cleanup MinIO audio files
cleanup_minio_files() {
    log "Cleaning up MinIO audio files older than $DAYS_OLD days..."
    
    # Detect MinIO endpoint
    if ! detect_minio_endpoint; then
        return 1
    fi
    
    # Check if mc (MinIO client) is available
    MC_CMD=""
    if command -v mc &> /dev/null; then
        MC_CMD="mc"
        log "Using system MinIO client"
    else
        log_warning "MinIO client (mc) not found. Installing..."
        MC_CMD=$(install_minio_client)
        if [ $? -ne 0 ]; then
            log_error "Failed to install MinIO client"
            return 1
        fi
    fi
    
    # Configure MinIO client
    local alias_name="cleanup_minio"
    log "Configuring MinIO client..."
    
    if ! $MC_CMD alias set "$alias_name" "$MINIO_ENDPOINT" "$MINIO_ACCESS_KEY" "$MINIO_SECRET_KEY" &>/dev/null; then
        log_error "Failed to configure MinIO client. Check endpoint and credentials."
        log "Endpoint: $MINIO_ENDPOINT"
        log "Access Key: $MINIO_ACCESS_KEY"
        return 1
    fi
    
    log_success "MinIO client configured successfully"
    
    # Test connection
    if ! $MC_CMD ls "$alias_name" &>/dev/null; then
        log_error "Cannot connect to MinIO. Check if container is running and accessible."
        return 1
    fi
    
    # Check if bucket exists
    if ! $MC_CMD ls "$alias_name/$MINIO_BUCKET" &>/dev/null; then
        log_warning "Bucket '$MINIO_BUCKET' does not exist or is not accessible"
        return 0
    fi
    
    # Calculate cutoff date
    local cutoff_date=$(date -d "$DAYS_OLD days ago" '+%Y-%m-%d')
    log "Looking for MinIO files older than $cutoff_date"
    
    # List files in MinIO bucket with detailed info
    log "Scanning MinIO bucket for old files..."
    local minio_files=$($MC_CMD ls --recursive "$alias_name/$MINIO_BUCKET/" 2>/dev/null || true)
    
    if [ -z "$minio_files" ]; then
        log "No files found in MinIO bucket $MINIO_BUCKET"
        return 0
    fi
    
    local files_to_delete=""
    local count=0
    local total_files=0
    
    # Process each file and check date
    while IFS= read -r line; do
        if [ -n "$line" ]; then
            total_files=$((total_files + 1))
            
            # Extract date and filename from mc ls output
            # Format: [DATE] [TIME] [SIZE] [FILENAME]
            local file_date=$(echo "$line" | awk '{print $1}')
            local file_name=$(echo "$line" | awk '{print $4}')
            
            # Skip if filename is empty or doesn't look like an audio file
            if [ -z "$file_name" ] || [[ ! "$file_name" =~ \.(wav|mp3|m4a|flac)$ ]]; then
                continue
            fi
            
            # Compare dates (simple string comparison works for YYYY-MM-DD format)
            if [[ "$file_date" < "$cutoff_date" ]]; then
                files_to_delete="$files_to_delete$alias_name/$MINIO_BUCKET/$file_name\n"
                count=$((count + 1))
            fi
        fi
    done <<< "$minio_files"
    
    log "Scanned $total_files files in MinIO bucket"
    
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
            log "Starting deletion process..."
            local deleted_count=0
            local failed_count=0
            
            echo -e "$files_to_delete" | while read -r file; do
                if [ -n "$file" ]; then
                    if $MC_CMD rm "$file" 2>/dev/null; then
                        echo "Deleted: $file"
                        deleted_count=$((deleted_count + 1))
                    else
                        log_error "Failed to delete: $file"
                        failed_count=$((failed_count + 1))
                    fi
                fi
            done
            
            log_success "Deleted $deleted_count MinIO audio files"
            if [ $failed_count -gt 0 ]; then
                log_warning "Failed to delete $failed_count files"
            fi
        fi
    fi
    
    # Cleanup temporary mc if we installed it
    if [[ "$MC_CMD" == "/tmp/minio-cleanup-"* ]]; then
        rm -rf "$(dirname "$MC_CMD")"
    fi
}

# Function to show MinIO bucket statistics
show_bucket_stats() {
    log "Getting MinIO bucket statistics..."
    
    # Detect MinIO endpoint
    if ! detect_minio_endpoint; then
        return 1
    fi
    
    # Install client if needed
    MC_CMD=""
    if command -v mc &> /dev/null; then
        MC_CMD="mc"
    else
        MC_CMD=$(install_minio_client)
        if [ $? -ne 0 ]; then
            return 1
        fi
    fi
    
    # Configure MinIO client
    local alias_name="cleanup_minio"
    $MC_CMD alias set "$alias_name" "$MINIO_ENDPOINT" "$MINIO_ACCESS_KEY" "$MINIO_SECRET_KEY" &>/dev/null
    
    # Get bucket info
    if $MC_CMD ls "$alias_name/$MINIO_BUCKET" &>/dev/null; then
        local total_files=$($MC_CMD ls --recursive "$alias_name/$MINIO_BUCKET/" 2>/dev/null | wc -l)
        local total_size=$($MC_CMD du "$alias_name/$MINIO_BUCKET" 2>/dev/null | tail -1 | awk '{print $1}' || echo "Unknown")
        
        log "Bucket Statistics:"
        log "  Total files: $total_files"
        log "  Total size: $total_size"
    else
        log_warning "Cannot access bucket $MINIO_BUCKET"
    fi
    
    # Cleanup temporary mc if we installed it
    if [[ "$MC_CMD" == "/tmp/minio-cleanup-"* ]]; then
        rm -rf "$(dirname "$MC_CMD")"
    fi
}

# Main execution
main() {
    log "Starting MinIO audio files cleanup script"
    log "Configuration:"
    log "  - Days old: $DAYS_OLD"
    log "  - Dry run: $DRY_RUN"
    log "  - MinIO bucket: $MINIO_BUCKET"
    log "  - MinIO endpoint: $MINIO_ENDPOINT (will be auto-detected)"
    
    echo ""
    
    # Show current bucket stats
    show_bucket_stats
    echo ""
    
    # Cleanup MinIO files
    cleanup_minio_files
    echo ""
    
    if [ "$DRY_RUN" = true ]; then
        log_warning "DRY RUN completed - no files were actually deleted"
    else
        log_success "MinIO audio files cleanup completed successfully"
    fi
}

# Run main function
main "$@"
