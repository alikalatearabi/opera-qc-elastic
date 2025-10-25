#!/bin/bash

# Direct MinIO Cleanup Script
# Connects directly to MinIO on production server 31.184.134.153
# Usage: ./cleanup-minio-direct.sh [--dry-run] [--days N]

set -e

# MinIO configuration for production server
MINIO_ENDPOINT="http://31.184.134.153:9005"  # MinIO port on production server
MINIO_ACCESS_KEY="minioaccesskey"
MINIO_SECRET_KEY="miniosecretkey"
MINIO_BUCKET="audio-files"

# Default configuration
DAYS_OLD=2
DRY_RUN=false

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
            echo ""
            echo "MinIO Configuration:"
            echo "  Endpoint: $MINIO_ENDPOINT"
            echo "  Bucket: $MINIO_BUCKET"
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

# Function to install MinIO client
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

# Function to test MinIO connection
test_minio_connection() {
    log "Testing connection to MinIO at $MINIO_ENDPOINT..."
    
    # Check if mc is available
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
    local alias_name="production_minio"
    log "Configuring MinIO client..."
    
    if ! $MC_CMD alias set "$alias_name" "$MINIO_ENDPOINT" "$MINIO_ACCESS_KEY" "$MINIO_SECRET_KEY" &>/dev/null; then
        log_error "Failed to configure MinIO client"
        log "Endpoint: $MINIO_ENDPOINT"
        log "Access Key: $MINIO_ACCESS_KEY"
        return 1
    fi
    
    # Test connection
    if ! $MC_CMD ls "$alias_name" &>/dev/null; then
        log_error "Cannot connect to MinIO. Check:"
        log "  1. MinIO is running on $MINIO_ENDPOINT"
        log "  2. Network connectivity to the server"
        log "  3. MinIO credentials are correct"
        log "  4. Firewall allows connection to port 9005"
        return 1
    fi
    
    log_success "Connected to MinIO successfully"
    echo "$MC_CMD|$alias_name"
    return 0
}

# Function to show MinIO bucket statistics
show_bucket_stats() {
    local mc_cmd="$1"
    local alias_name="$2"
    
    log "Getting MinIO bucket statistics..."
    
    # Check if bucket exists
    if ! $mc_cmd ls "$alias_name/$MINIO_BUCKET" &>/dev/null; then
        log_warning "Bucket '$MINIO_BUCKET' does not exist or is not accessible"
        return 1
    fi
    
    # Get bucket info
    local total_files=$($mc_cmd ls --recursive "$alias_name/$MINIO_BUCKET/" 2>/dev/null | wc -l)
    local total_size=$($mc_cmd du "$alias_name/$MINIO_BUCKET" 2>/dev/null | tail -1 | awk '{print $1}' || echo "Unknown")
    
    log "Bucket Statistics:"
    log "  Bucket: $MINIO_BUCKET"
    log "  Total files: $total_files"
    log "  Total size: $total_size"
    
    # Show file type breakdown
    log "File type breakdown:"
    local wav_files=$($mc_cmd ls --recursive "$alias_name/$MINIO_BUCKET/" 2>/dev/null | grep -c "\.wav" || echo "0")
    local mp3_files=$($mc_cmd ls --recursive "$alias_name/$MINIO_BUCKET/" 2>/dev/null | grep -c "\.mp3" || echo "0")
    local other_files=$((total_files - wav_files - mp3_files))
    
    log "  WAV files: $wav_files"
    log "  MP3 files: $mp3_files"
    log "  Other files: $other_files"
}

# Function to cleanup MinIO audio files
cleanup_minio_files() {
    local mc_cmd="$1"
    local alias_name="$2"
    
    log "Cleaning up MinIO audio files older than $DAYS_OLD days..."
    
    # Calculate cutoff date
    local cutoff_date=$(date -d "$DAYS_OLD days ago" '+%Y-%m-%d')
    log "Looking for MinIO files older than $cutoff_date"
    
    # List files in MinIO bucket with detailed info
    log "Scanning MinIO bucket for old files..."
    local minio_files=$($mc_cmd ls --recursive "$alias_name/$MINIO_BUCKET/" 2>/dev/null || true)
    
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
            local file_size=$(echo "$line" | awk '{print $3}')
            
            # Skip if filename is empty or doesn't look like an audio file
            if [ -z "$file_name" ] || [[ ! "$file_name" =~ \.(wav|mp3|m4a|flac)$ ]]; then
                continue
            fi
            
            # Compare dates (simple string comparison works for YYYY-MM-DD format)
            if [[ "$file_date" < "$cutoff_date" ]]; then
                files_to_delete="$files_to_delete$alias_name/$MINIO_BUCKET/$file_name|$file_size\n"
                count=$((count + 1))
            fi
        fi
    done <<< "$minio_files"
    
    log "Scanned $total_files files in MinIO bucket"
    
    if [ $count -eq 0 ]; then
        log "No MinIO audio files older than $DAYS_OLD days found"
    else
        log "Found $count MinIO audio files older than $DAYS_OLD days"
        
        # Calculate total size to be deleted
        local total_size_to_delete=0
        echo -e "$files_to_delete" | while IFS='|' read -r file size; do
            if [ -n "$file" ]; then
                # Convert size to bytes (mc shows sizes in human readable format)
                local size_bytes=0
                if [[ "$size" =~ ^[0-9]+$ ]]; then
                    size_bytes=$size
                elif [[ "$size" =~ ^([0-9]+)K$ ]]; then
                    size_bytes=$((${BASH_REMATCH[1]} * 1024))
                elif [[ "$size" =~ ^([0-9]+)M$ ]]; then
                    size_bytes=$((${BASH_REMATCH[1]} * 1024 * 1024))
                elif [[ "$size" =~ ^([0-9]+)G$ ]]; then
                    size_bytes=$((${BASH_REMATCH[1]} * 1024 * 1024 * 1024))
                fi
                total_size_to_delete=$((total_size_to_delete + size_bytes))
            fi
        done
        
        # Convert total size to human readable
        local size_human=""
        if [ $total_size_to_delete -gt 1073741824 ]; then
            size_human=$(echo "scale=2; $total_size_to_delete / 1073741824" | bc -l 2>/dev/null || echo "Unknown")
            size_human="${size_human}GB"
        elif [ $total_size_to_delete -gt 1048576 ]; then
            size_human=$(echo "scale=2; $total_size_to_delete / 1048576" | bc -l 2>/dev/null || echo "Unknown")
            size_human="${size_human}MB"
        elif [ $total_size_to_delete -gt 1024 ]; then
            size_human=$(echo "scale=2; $total_size_to_delete / 1024" | bc -l 2>/dev/null || echo "Unknown")
            size_human="${size_human}KB"
        else
            size_human="${total_size_to_delete}B"
        fi
        
        log "Total size to be deleted: $size_human"
        
        if [ "$DRY_RUN" = true ]; then
            log_warning "DRY RUN - Would delete the following MinIO files:"
            echo -e "$files_to_delete" | while IFS='|' read -r file size; do
                if [ -n "$file" ]; then
                    echo "  - $file ($size)"
                fi
            done
        else
            log "Starting deletion process..."
            local deleted_count=0
            local failed_count=0
            local deleted_size=0
            
            echo -e "$files_to_delete" | while IFS='|' read -r file size; do
                if [ -n "$file" ]; then
                    if $mc_cmd rm "$file" 2>/dev/null; then
                        echo "Deleted: $file ($size)"
                        deleted_count=$((deleted_count + 1))
                        # Add size to deleted_size (simplified)
                        deleted_size=$((deleted_size + 1))
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
}

# Function to cleanup temporary files
cleanup_temp_files() {
    local mc_cmd="$1"
    
    # Cleanup temporary mc if we installed it
    if [[ "$mc_cmd" == "/tmp/minio-cleanup-"* ]]; then
        rm -rf "$(dirname "$mc_cmd")"
        log "Cleaned up temporary MinIO client"
    fi
}

# Main execution
main() {
    log "Starting direct MinIO cleanup script"
    log "Configuration:"
    log "  - MinIO endpoint: $MINIO_ENDPOINT"
    log "  - MinIO bucket: $MINIO_BUCKET"
    log "  - Days old: $DAYS_OLD"
    log "  - Dry run: $DRY_RUN"
    
    echo ""
    
    # Test MinIO connection
    local connection_result=$(test_minio_connection)
    if [ $? -ne 0 ]; then
        exit 1
    fi
    
    local mc_cmd=$(echo "$connection_result" | cut -d'|' -f1)
    local alias_name=$(echo "$connection_result" | cut -d'|' -f2)
    
    echo ""
    
    # Show bucket statistics
    show_bucket_stats "$mc_cmd" "$alias_name"
    echo ""
    
    # Cleanup MinIO files
    cleanup_minio_files "$mc_cmd" "$alias_name"
    echo ""
    
    # Show final statistics
    if [ "$DRY_RUN" = false ]; then
        log "Final bucket statistics:"
        show_bucket_stats "$mc_cmd" "$alias_name"
    fi
    
    # Cleanup temporary files
    cleanup_temp_files "$mc_cmd"
    
    if [ "$DRY_RUN" = true ]; then
        log_warning "DRY RUN completed - no files were actually deleted"
    else
        log_success "Direct MinIO cleanup completed successfully"
    fi
}

# Run main function
main "$@"
