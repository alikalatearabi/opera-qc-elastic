#!/bin/bash

# Local Audio Files Cleanup Script for Production Server
# Removes audio files older than specified days from local conversations directory
# Usage: ./cleanup-local-audio.sh [--dry-run] [--days N]

set -e

# Default configuration
DAYS_OLD=2
DRY_RUN=false
LOCAL_AUDIO_DIR="./conversations"  # Relative to script location

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
    
    # Convert relative path to absolute
    if [[ "$LOCAL_AUDIO_DIR" == ./* ]]; then
        LOCAL_AUDIO_DIR="$(pwd)/${LOCAL_AUDIO_DIR#./}"
    fi
    
    log "Checking directory: $LOCAL_AUDIO_DIR"
    
    if [ ! -d "$LOCAL_AUDIO_DIR" ]; then
        log_warning "Local audio directory $LOCAL_AUDIO_DIR does not exist"
        log "Creating directory..."
        mkdir -p "$LOCAL_AUDIO_DIR"
        log_success "Created directory: $LOCAL_AUDIO_DIR"
        return 0
    fi
    
    # Show directory statistics
    local total_files=$(find "$LOCAL_AUDIO_DIR" -type f \( -name "*.wav" -o -name "*.mp3" -o -name "*.m4a" -o -name "*.flac" \) 2>/dev/null | wc -l)
    local total_size=$(du -sh "$LOCAL_AUDIO_DIR" 2>/dev/null | cut -f1 || echo "Unknown")
    
    log "Directory Statistics:"
    log "  Total audio files: $total_files"
    log "  Total size: $total_size"
    
    # Find files older than specified days
    local files_to_delete=$(find "$LOCAL_AUDIO_DIR" -type f \( -name "*.wav" -o -name "*.mp3" -o -name "*.m4a" -o -name "*.flac" \) -mtime +$DAYS_OLD 2>/dev/null || true)
    
    if [ -z "$files_to_delete" ]; then
        log "No local audio files older than $DAYS_OLD days found"
        return 0
    fi
    
    local count=$(echo "$files_to_delete" | wc -l)
    log "Found $count local audio files older than $DAYS_OLD days"
    
    # Calculate size of files to be deleted
    local size_to_delete=0
    if [ "$count" -gt 0 ]; then
        size_to_delete=$(echo "$files_to_delete" | xargs -r du -ch 2>/dev/null | tail -1 | cut -f1 || echo "Unknown")
    fi
    
    log "Size of files to be deleted: $size_to_delete"
    
    if [ "$DRY_RUN" = true ]; then
        log_warning "DRY RUN - Would delete the following local files:"
        echo "$files_to_delete" | while read -r file; do
            if [ -n "$file" ]; then
                local file_size=$(du -h "$file" 2>/dev/null | cut -f1 || echo "Unknown")
                local file_date=$(stat -c %y "$file" 2>/dev/null | cut -d' ' -f1 || echo "Unknown")
                echo "  - $file ($file_size, modified: $file_date)"
            fi
        done
    else
        log "Starting deletion process..."
        local deleted_count=0
        local failed_count=0
        local deleted_size=0
        
        echo "$files_to_delete" | while read -r file; do
            if [ -n "$file" ] && [ -f "$file" ]; then
                local file_size=$(du -b "$file" 2>/dev/null | cut -f1 || echo "0")
                if rm "$file" 2>/dev/null; then
                    echo "Deleted: $file"
                    deleted_count=$((deleted_count + 1))
                    deleted_size=$((deleted_size + file_size))
                else
                    log_error "Failed to delete: $file"
                    failed_count=$((failed_count + 1))
                fi
            fi
        done
        
        # Convert bytes to human readable
        local deleted_size_human=""
        if [ $deleted_size -gt 0 ]; then
            if [ $deleted_size -gt 1073741824 ]; then
                deleted_size_human=$(echo "scale=2; $deleted_size / 1073741824" | bc -l 2>/dev/null || echo "Unknown")
                deleted_size_human="${deleted_size_human}GB"
            elif [ $deleted_size -gt 1048576 ]; then
                deleted_size_human=$(echo "scale=2; $deleted_size / 1048576" | bc -l 2>/dev/null || echo "Unknown")
                deleted_size_human="${deleted_size_human}MB"
            elif [ $deleted_size -gt 1024 ]; then
                deleted_size_human=$(echo "scale=2; $deleted_size / 1024" | bc -l 2>/dev/null || echo "Unknown")
                deleted_size_human="${deleted_size_human}KB"
            else
                deleted_size_human="${deleted_size}B"
            fi
        fi
        
        log_success "Deleted $deleted_count local audio files (freed $deleted_size_human)"
        if [ $failed_count -gt 0 ]; then
            log_warning "Failed to delete $failed_count files"
        fi
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
                    deleted_count=$((deleted_count + 1))
                fi
            fi
        done
        log_success "Removed $deleted_count empty directories"
    fi
}

# Main execution
main() {
    log "Starting local audio files cleanup script"
    log "Configuration:"
    log "  - Days old: $DAYS_OLD"
    log "  - Dry run: $DRY_RUN"
    log "  - Local directory: $LOCAL_AUDIO_DIR"
    
    echo ""
    
    # Cleanup local files
    cleanup_local_files
    echo ""
    
    # Cleanup empty directories
    cleanup_empty_directories
    echo ""
    
    if [ "$DRY_RUN" = true ]; then
        log_warning "DRY RUN completed - no files were actually deleted"
    else
        log_success "Local audio files cleanup completed successfully"
    fi
}

# Run main function
main "$@"
