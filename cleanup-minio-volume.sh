#!/bin/bash

# Cleanup Old Files from MinIO Volume Directory
# This script must be run with sudo

set -e

VOLUME_PATH="/var/lib/docker/volumes/opera-qc-elastic_minio_data/_data"
DAYS_OLD=${1:-2}

echo "=== MinIO Volume Cleanup Script ==="
echo "Volume path: $VOLUME_PATH"
echo "Deleting files older than: $DAYS_OLD days"
echo ""

# Check if running as root
if [ "$EUID" -ne 0 ]; then 
    echo "This script must be run as root (use sudo)"
    echo "Try: sudo ./cleanup-minio-volume.sh [$DAYS_OLD]"
    exit 1
fi

# Check if directory exists
if [ ! -d "$VOLUME_PATH" ]; then
    echo "ERROR: Volume directory not found: $VOLUME_PATH"
    exit 1
fi

AUDIO_FILES_DIR="$VOLUME_PATH/audio-files"

if [ ! -d "$AUDIO_FILES_DIR" ]; then
    echo "ERROR: audio-files directory not found"
    exit 1
fi

echo "=== Current Status ==="
file_count=$(find "$AUDIO_FILES_DIR" -type f | wc -l)
directory_size=$(du -sh "$AUDIO_FILES_DIR" | awk '{print $1}')
echo "Total files: $file_count"
echo "Directory size: $directory_size"
echo ""

# Check disk space
echo "=== Current Disk Space ==="
df -h | grep -E 'Filesystem|/var/lib/docker'
echo ""

# Find old files
echo "=== Finding Old Files (older than $DAYS_OLD days) ==="
old_files_list=$(find "$AUDIO_FILES_DIR" -type f -mtime +$DAYS_OLD 2>/dev/null)
old_files_count=$(echo "$old_files_list" | wc -l)

if [ $old_files_count -eq 0 ]; then
    echo "No files older than $DAYS_OLD days found"
    exit 0
fi

echo "Found $old_files_count files to delete"
echo ""

# Show sample files
echo "Sample files to be deleted:"
echo "$old_files_list" | head -10
echo ""

# Ask for confirmation
read -p "Do you want to delete these $old_files_count files? (y/N): " -n 1 -r
echo ""

if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Cleanup cancelled"
    exit 0
fi

# Delete files
echo "Starting deletion..."
echo "$old_files_list" | xargs -P 4 rm -f

echo ""
echo "=== Final Status ==="
new_file_count=$(find "$AUDIO_FILES_DIR" -type f | wc -l)
new_directory_size=$(du -sh "$AUDIO_FILES_DIR" | awk '{print $1}')

echo "Files deleted: $((file_count - new_file_count))"
echo "Remaining files: $new_file_count"
echo "New directory size: $new_directory_size"
echo ""

# Check disk space after cleanup
echo "=== Disk Space After Cleanup ==="
df -h | grep -E 'Filesystem|/var/lib/docker'
echo ""

echo "Cleanup completed successfully!"
