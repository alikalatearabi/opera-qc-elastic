#!/bin/bash

# Debug MinIO Connection on Server
# Run this to troubleshoot why files are not showing up

set -e

MINIO_ENDPOINT="http://31.184.134.153:9005"
MINIO_ACCESS_KEY="minioaccesskey"
MINIO_SECRET_KEY="miniosecretkey"
MINIO_BUCKET="audio-files"

echo "=== MinIO Debug Script ==="
echo ""
echo "Configuration:"
echo "  Endpoint: $MINIO_ENDPOINT"
echo "  Bucket: $MINIO_BUCKET"
echo ""

# Check if mc is available
if ! command -v mc &> /dev/null; then
    echo "ERROR: MinIO client (mc) not found in PATH"
    exit 1
fi

echo "Using MinIO client: $(which mc)"
echo ""

# Show existing aliases
echo "=== Existing Aliases ==="
mc alias list
echo ""

# Try to list buckets at the root
echo "=== Available Buckets ==="
mc ls "$MINIO_ENDPOINT" 2>&1 || echo "Cannot list buckets. Trying with credentials..."
echo ""

# Create a fresh alias for testing
TEST_ALIAS="debug_minio_$$"
echo "Creating test alias: $TEST_ALIAS"
if mc alias set "$TEST_ALIAS" "$MINIO_ENDPOINT" "$MINIO_ACCESS_KEY" "$MINIO_SECRET_KEY" 2>&1; then
    echo "Alias created successfully"
else
    echo "ERROR: Failed to create alias"
    exit 1
fi
echo ""

# List buckets using the alias
echo "=== Listing Buckets ==="
mc ls "$TEST_ALIAS/" 2>&1 || true
echo ""

# Check if audio-files bucket exists
echo "=== Checking audio-files Bucket ==="
if mc ls "$TEST_ALIAS/$MINIO_BUCKET" 2>&1; then
    echo ""
    echo "Bucket exists!"
    echo ""
    
    # Count files
    echo "=== Counting Files ==="
    local count=$(mc ls --recursive "$TEST_ALIAS/$MINIO_BUCKET/" 2>/dev/null | wc -l)
    echo "Total files: $count"
    echo ""
    
    # Show bucket size
    echo "=== Bucket Size ==="
    mc du "$TEST_ALIAS/$MINIO_BUCKET"
    echo ""
    
    # Show some sample files
    echo "=== Sample Files (first 10) ==="
    mc ls "$TEST_ALIAS/$MINIO_BUCKET/" 2>/dev/null | head -10
    echo ""
    
    # Show files in subdirectories
    echo "=== Checking for Subdirectories ==="
    mc ls --recursive "$TEST_ALIAS/$MINIO_BUCKET/" 2>/dev/null | head -10
else
    echo "ERROR: Cannot access bucket '$MINIO_BUCKET'"
    echo ""
    echo "Available buckets:"
    mc ls "$TEST_ALIAS/" 2>&1 || true
fi

# Cleanup
echo "=== Cleanup ==="
mc alias remove "$TEST_ALIAS" 2>/dev/null || true
echo "Done"
