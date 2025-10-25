#!/bin/bash

# Complete Remote Server Cleanup Script
# Uploads cleanup scripts to server and runs them remotely
# Usage: ./cleanup-server-remote.sh [--dry-run] [--days N] [--upload-only]

set -e

# Server configuration
SERVER_HOST="31.184.134.153"
SERVER_USER="rahpoo"  # Change this to your server username
SERVER_PROJECT_DIR="~/opera-qc-elastic"

# Default configuration
DAYS_OLD=2
DRY_RUN=false
UPLOAD_ONLY=false

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
        --upload-only)
            UPLOAD_ONLY=true
            shift
            ;;
        --help|-h)
            echo "Usage: $0 [--dry-run] [--days N] [--upload-only]"
            echo "  --dry-run      Show what would be deleted without actually deleting"
            echo "  --days N       Number of days old (default: 2)"
            echo "  --upload-only  Only upload scripts, don't run cleanup"
            echo "  --help         Show this help message"
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

# Function to execute command on remote server
remote_exec() {
    local command="$1"
    ssh "$SERVER_USER@$SERVER_HOST" "$command"
}

# Function to check server connection
check_server_connection() {
    log "Checking connection to server $SERVER_HOST..."
    
    if ! ssh -o ConnectTimeout=10 -o BatchMode=yes "$SERVER_USER@$SERVER_HOST" "echo 'Connection successful'" &>/dev/null; then
        log_error "Cannot connect to server $SERVER_HOST as user $SERVER_USER"
        log "Please ensure:"
        log "  1. SSH key is set up for passwordless access"
        log "  2. Server is accessible from this machine"
        log "  3. Username '$SERVER_USER' is correct"
        exit 1
    fi
    
    log_success "Connected to server successfully"
}

# Function to upload cleanup scripts to server
upload_scripts() {
    log "Uploading cleanup scripts to server..."
    
    # Check if local scripts exist
    local scripts=("cleanup-minio-files-fixed.sh" "cleanup-local-audio.sh")
    
    for script in "${scripts[@]}"; do
        if [ ! -f "$script" ]; then
            log_error "Local script $script not found"
            exit 1
        fi
    done
    
    # Upload scripts using scp
    log "Uploading scripts to $SERVER_USER@$SERVER_HOST:$SERVER_PROJECT_DIR/"
    
    for script in "${scripts[@]}"; do
        log "Uploading $script..."
        if scp "$script" "$SERVER_USER@$SERVER_HOST:$SERVER_PROJECT_DIR/"; then
            log_success "Uploaded $script"
        else
            log_error "Failed to upload $script"
            exit 1
        fi
    done
    
    # Make scripts executable on server
    log "Making scripts executable on server..."
    remote_exec "cd $SERVER_PROJECT_DIR && chmod +x cleanup-minio-files-fixed.sh cleanup-local-audio.sh"
    log_success "Scripts are now executable on server"
}

# Function to show server status
show_server_status() {
    log "Checking server status..."
    
    echo ""
    log "=== SERVER DISK USAGE ==="
    remote_exec "df -h /"
    
    echo ""
    log "=== CONVERSATIONS DIRECTORY SIZE ==="
    remote_exec "cd $SERVER_PROJECT_DIR && du -sh conversations/ 2>/dev/null || echo 'conversations directory not found or empty'"
    
    echo ""
    log "=== DOCKER CONTAINER STATUS ==="
    remote_exec "docker ps --format 'table {{.Names}}\\t{{.Status}}\\t{{.Ports}}'"
    
    echo ""
    log "=== MINIO BUCKET INFO ==="
    remote_exec "cd $SERVER_PROJECT_DIR && docker exec \$(docker ps --format '{{.Names}}' | grep minio | head -1) mc ls / 2>/dev/null || echo 'MinIO not accessible'"
}

# Function to run MinIO cleanup
run_minio_cleanup() {
    log "Running MinIO cleanup on server..."
    
    local dry_run_flag=""
    if [ "$DRY_RUN" = true ]; then
        dry_run_flag="--dry-run"
    fi
    
    log "Command: cd $SERVER_PROJECT_DIR && ./cleanup-minio-files-fixed.sh $dry_run_flag --days $DAYS_OLD"
    
    echo ""
    log "=== MINIO CLEANUP OUTPUT ==="
    remote_exec "cd $SERVER_PROJECT_DIR && ./cleanup-minio-files-fixed.sh $dry_run_flag --days $DAYS_OLD"
}

# Function to run local audio cleanup
run_local_cleanup() {
    log "Running local audio cleanup on server..."
    
    local dry_run_flag=""
    if [ "$DRY_RUN" = true ]; then
        dry_run_flag="--dry-run"
    fi
    
    log "Command: cd $SERVER_PROJECT_DIR && ./cleanup-local-audio.sh $dry_run_flag --days $DAYS_OLD"
    
    echo ""
    log "=== LOCAL AUDIO CLEANUP OUTPUT ==="
    remote_exec "cd $SERVER_PROJECT_DIR && ./cleanup-local-audio.sh $dry_run_flag --days $DAYS_OLD"
}

# Function to show final status
show_final_status() {
    log "Final server status after cleanup..."
    show_server_status
}

# Main execution
main() {
    log "Starting complete remote server cleanup"
    log "Target server: $SERVER_HOST"
    log "Server user: $SERVER_USER"
    log "Project directory: $SERVER_PROJECT_DIR"
    log "Configuration:"
    log "  - Days old: $DAYS_OLD"
    log "  - Dry run: $DRY_RUN"
    log "  - Upload only: $UPLOAD_ONLY"
    
    echo ""
    
    # Check server connection
    check_server_connection
    echo ""
    
    # Show initial server status
    show_server_status
    echo ""
    
    # Upload scripts
    upload_scripts
    echo ""
    
    if [ "$UPLOAD_ONLY" = true ]; then
        log_success "Scripts uploaded successfully. Use --upload-only=false to run cleanup."
        exit 0
    fi
    
    # Run MinIO cleanup
    run_minio_cleanup
    echo ""
    
    # Run local audio cleanup
    run_local_cleanup
    echo ""
    
    # Show final status
    show_final_status
    echo ""
    
    if [ "$DRY_RUN" = true ]; then
        log_warning "DRY RUN completed - no files were actually deleted"
    else
        log_success "Complete remote server cleanup completed successfully"
    fi
}

# Run main function
main "$@"
