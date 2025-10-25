#!/bin/bash

# MinIO Bucket Explorer
# Explores the contents of MinIO buckets on production server
# Usage: ./explore-minio-bucket.sh [bucket-name]

set -e

# MinIO configuration for production server
MINIO_ENDPOINT="http://31.184.134.153:9005"
MINIO_ACCESS_KEY="minioaccesskey"
MINIO_SECRET_KEY="miniosecretkey"
MINIO_BUCKET="${1:-audio-files}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

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
    
    INSTALL_DIR="/tmp/minio-explore-$$"
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
    return 0
}

# Function to explore bucket
explore_bucket() {
    local mc_cmd="$1"
    local alias_name="$2"
    local bucket="$3"
    
    log "Exploring bucket: $bucket"
    
    # Check if bucket exists
    if ! $mc_cmd ls "$alias_name/$bucket" &>/dev/null; then
        log_error "Bucket '$bucket' does not exist or is not accessible"
        return 1
    fi
    
    # Get bucket info
    log "Getting bucket information..."
    local bucket_info=$($mc_cmd ls "$alias_name/$bucket" 2>/dev/null)
    log "Bucket info: $bucket_info"
    
    # List all files recursively
    log "Listing all files in bucket..."
    local all_files=$($mc_cmd ls --recursive "$alias_name/$bucket/" 2>/dev/null || true)
    
    if [ -z "$all_files" ]; then
        log_warning "Bucket '$bucket' is empty"
        return 0
    fi
    
    local total_files=$(echo "$all_files" | wc -l)
    log "Total files in bucket: $total_files"
    
    # Show file breakdown by type
    log "File type breakdown:"
    local wav_files=$(echo "$all_files" | grep -c "\.wav" || echo "0")
    local mp3_files=$(echo "$all_files" | grep -c "\.mp3" || echo "0")
    local m4a_files=$(echo "$all_files" | grep -c "\.m4a" || echo "0")
    local flac_files=$(echo "$all_files" | grep -c "\.flac" || echo "0")
    local other_files=$((total_files - wav_files - mp3_files - m4a_files - flac_files))
    
    log "  WAV files: $wav_files"
    log "  MP3 files: $mp3_files"
    log "  M4A files: $m4a_files"
    log "  FLAC files: $flac_files"
    log "  Other files: $other_files"
    
    # Show recent files (last 10)
    log "Recent files (last 10):"
    echo "$all_files" | tail -10 | while read -r line; do
        if [ -n "$line" ]; then
            local file_date=$(echo "$line" | awk '{print $1}')
            local file_time=$(echo "$line" | awk '{print $2}')
            local file_size=$(echo "$line" | awk '{print $3}')
            local file_name=$(echo "$line" | awk '{print $4}')
            echo "  $file_date $file_time $file_size $file_name"
        fi
    done
    
    # Show oldest files (first 10)
    log "Oldest files (first 10):"
    echo "$all_files" | head -10 | while read -r line; do
        if [ -n "$line" ]; then
            local file_date=$(echo "$line" | awk '{print $1}')
            local file_time=$(echo "$line" | awk '{print $2}')
            local file_size=$(echo "$line" | awk '{print $3}')
            local file_name=$(echo "$line" | awk '{print $4}')
            echo "  $file_date $file_time $file_size $file_name"
        fi
    done
    
    # Calculate total size
    log "Calculating total bucket size..."
    local total_size=$($mc_cmd du "$alias_name/$bucket" 2>/dev/null | tail -1 | awk '{print $1}' || echo "Unknown")
    log "Total bucket size: $total_size"
    
    # Show files by date (last 7 days)
    log "Files from last 7 days:"
    local cutoff_date=$(date -d "7 days ago" '+%Y-%m-%d')
    local recent_count=0
    
    echo "$all_files" | while read -r line; do
        if [ -n "$line" ]; then
            local file_date=$(echo "$line" | awk '{print $1}')
            if [[ "$file_date" > "$cutoff_date" ]]; then
                recent_count=$((recent_count + 1))
                local file_name=$(echo "$line" | awk '{print $4}')
                echo "  $file_date $file_name"
            fi
        fi
    done
    
    if [ $recent_count -eq 0 ]; then
        log "No files from last 7 days found"
    else
        log "Found $recent_count files from last 7 days"
    fi
}

# Main execution
main() {
    log "Starting MinIO bucket exploration"
    log "Configuration:"
    log "  - MinIO endpoint: $MINIO_ENDPOINT"
    log "  - MinIO bucket: $MINIO_BUCKET"
    
    echo ""
    
    # Install MinIO client
    MC_CMD=""
    if command -v mc &> /dev/null; then
        MC_CMD="mc"
        log "Using system MinIO client"
    else
        MC_CMD=$(install_minio_client)
        if [ $? -ne 0 ]; then
            log_error "Failed to install MinIO client"
            exit 1
        fi
    fi
    
    # Configure MinIO client
    local alias_name="explore_minio"
    log "Configuring MinIO client..."
    
    if ! $MC_CMD alias set "$alias_name" "$MINIO_ENDPOINT" "$MINIO_ACCESS_KEY" "$MINIO_SECRET_KEY" &>/dev/null; then
        log_error "Failed to configure MinIO client"
        exit 1
    fi
    
    # Test connection
    if ! $MC_CMD ls "$alias_name" &>/dev/null; then
        log_error "Cannot connect to MinIO"
        exit 1
    fi
    
    log_success "Connected to MinIO successfully"
    echo ""
    
    # List all buckets first
    log "Available buckets:"
    $MC_CMD ls "$alias_name" | while read -r line; do
        if [ -n "$line" ]; then
            echo "  - $line"
        fi
    done
    echo ""
    
    # Explore the specified bucket
    explore_bucket "$MC_CMD" "$alias_name" "$MINIO_BUCKET"
    
    # Cleanup
    if [[ "$MC_CMD" == "/tmp/minio-explore-"* ]]; then
        rm -rf "$(dirname "$MC_CMD")"
    fi
    
    log_success "Bucket exploration completed"
}

# Run main function
main "$@"
