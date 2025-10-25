#!/bin/bash

# Inspect MinIO Volume Directory
# This script must be run with sudo to access Docker volume data

set -e

VOLUME_PATH="/var/lib/docker/volumes/opera-qc-elastic_minio_data/_data"

echo "=== Inspecting MinIO Volume Directory ==="
echo "Volume path: $VOLUME_PATH"
echo ""

# Check if running as root
if [ "$EUID" -ne 0 ]; then 
    echo "This script must be run as root (use sudo)"
    echo "Try: sudo ./inspect-minio-volume.sh"
    exit 1
fi

# Check if directory exists
if [ ! -d "$VOLUME_PATH" ]; then
    echo "ERROR: Volume directory not found: $VOLUME_PATH"
    exit 1
fi

echo "=== Directory Listing ==="
ls -lh "$VOLUME_PATH"
echo ""

# Check audio-files directory specifically
AUDIO_FILES_DIR="$VOLUME_PATH/audio-files"

if [ -d "$AUDIO_FILES_DIR" ]; then
    echo "=== audio-files Directory ==="
    
    # Count files
    echo "Counting files in audio-files directory..."
    file_count=$(find "$AUDIO_FILES_DIR" -type f | wc -l)
    echo "Total files: $file_count"
    echo ""
    
    # Check size
    echo "=== Directory Size ==="
    du -sh "$AUDIO_FILES_DIR"
    echo ""
    
    # Show directory structure
    echo "=== Directory Structure (first 20 items) ==="
    ls -lh "$AUDIO_FILES_DIR" | head -20
    echo ""
    
    # Show sample files
    echo "=== Sample Files (first 10) ==="
    find "$AUDIO_FILES_DIR" -type f | head -10
    echo ""
    
    # Check old files (older than 2 days)
    echo "=== Finding Old Files (older than 2 days) ==="
    old_files=$(find "$AUDIO_FILES_DIR" -type f -mtime +2 2>/dev/null | wc -l)
    echo "Files older than 2 days: $old_files"
    
    if [ $old_files -gt 0 ]; then
        echo "Sample old files:"
        find "$AUDIO_FILES_DIR" -type f -mtime +2 2>/dev/null | head -10
    fi
    echo ""
    
    # Disk space analysis
    echo "=== Disk Space Analysis ==="
    df -h "$AUDIO_FILES_DIR"
    echo ""
    
else
    echo "audio-files directory not found"
fi

echo "Done"
