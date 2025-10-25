#!/bin/bash

# Remote MinIO Cleanup Script
# Runs cleanup on production server 31.184.134.153 from local machine
# Usage: ./cleanup-remote-minio.sh [--dry-run] [--days N]

set -e

# Server configuration
SERVER_HOST="31.184.134.153"
SERVER_USER="rahpoo"  # Change this to your server username
SERVER_PROJECT_DIR="~/opera-qc-elastic"

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

# Function to check if cleanup script exists on server
check_cleanup_script() {
    log "Checking if cleanup script exists on server..."
    
    if ! remote_exec "test -f $SERVER_PROJECT_DIR/cleanup-minio-files-fixed.sh"; then
        log_error "Cleanup script not found on server at $SERVER_PROJECT_DIR/cleanup-minio-files-fixed.sh"
        log "Please ensure the script is uploaded to the server first"
        exit 1
    fi
    
    log_success "Cleanup script found on server"
}

# Function to make script executable on server
make_script_executable() {
    log "Making cleanup script executable on server..."
    remote_exec "chmod +x $SERVER_PROJECT_DIR/cleanup-minio-files-fixed.sh"
    log_success "Script is now executable"
}

# Function to run cleanup on server
run_cleanup() {
    log "Running MinIO cleanup on server..."
    
    local dry_run_flag=""
    if [ "$DRY_RUN" = true ]; then
        dry_run_flag="--dry-run"
    fi
    
    log "Command: cd $SERVER_PROJECT_DIR && ./cleanup-minio-files-fixed.sh $dry_run_flag --days $DAYS_OLD"
    
    # Run the cleanup script on the server and capture output
    remote_exec "cd $SERVER_PROJECT_DIR && ./cleanup-minio-files-fixed.sh $dry_run_flag --days $DAYS_OLD"
}

# Function to show server disk usage
show_server_disk_usage() {
    log "Checking server disk usage..."
    remote_exec "df -h /"
    echo ""
}

# Function to show Docker container status
show_docker_status() {
    log "Checking Docker container status on server..."
    remote_exec "docker ps --format 'table {{.Names}}\\t{{.Status}}\\t{{.Ports}}'"
    echo ""
}

# Main execution
main() {
    log "Starting remote MinIO cleanup script"
    log "Target server: $SERVER_HOST"
    log "Server user: $SERVER_USER"
    log "Project directory: $SERVER_PROJECT_DIR"
    log "Configuration:"
    log "  - Days old: $DAYS_OLD"
    log "  - Dry run: $DRY_RUN"
    
    echo ""
    
    # Check server connection
    check_server_connection
    echo ""
    
    # Show server status
    show_server_disk_usage
    show_docker_status
    
    # Check if cleanup script exists
    check_cleanup_script
    echo ""
    
    # Make script executable
    make_script_executable
    echo ""
    
    # Run cleanup
    run_cleanup
    echo ""
    
    if [ "$DRY_RUN" = true ]; then
        log_warning "DRY RUN completed - no files were actually deleted"
    else
        log_success "Remote MinIO cleanup completed successfully"
    fi
    
    # Show final disk usage
    log "Final server disk usage:"
    show_server_disk_usage
}

# Run main function
main "$@"
