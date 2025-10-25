#!/bin/bash

# Check Docker MinIO container and volume data
# This will help us find where the 187,840 files are stored

echo "=== Checking Docker MinIO Container ==="
echo ""

# Check if docker is available
if ! command -v docker &> /dev/null; then
    echo "ERROR: Docker is not installed or not in PATH"
    exit 1
fi

echo "=== MinIO Container Status ==="
docker ps -a | grep -i minio
echo ""

# Check MinIO container status
MINIO_CONTAINER=$(docker ps --format "{{.Names}}" | grep -i minio | head -1)

if [ -z "$MINIO_CONTAINER" ]; then
    echo "ERROR: No running MinIO container found"
    echo ""
    echo "Checking all containers (including stopped):"
    docker ps -a
    exit 1
fi

echo "Found MinIO container: $MINIO_CONTAINER"
echo ""

# Check MinIO logs
echo "=== Recent MinIO Container Logs ==="
docker logs --tail 20 $MINIO_CONTAINER
echo ""

# Check MinIO volume mounts
echo "=== MinIO Container Mounts ==="
docker inspect $MINIO_CONTAINER | grep -A 10 "Mounts"
echo ""

# Find the volume directory
MINIO_VOLUME=$(docker inspect $MINIO_CONTAINER | grep -A 5 'Mounts' | grep 'Source' | awk '{print $2}' | tr -d '",')
echo "MinIO data directory: $MINIO_VOLUME"
echo ""

# Check if volume directory exists
if [ -d "$MINIO_VOLUME" ]; then
    echo "=== MinIO Volume Directory Contents ==="
    ls -lh "$MINIO_VOLUME" | head -20
    echo ""
    
    # Count files in volume
    echo "=== Counting Files in Volume ==="
    file_count=$(find "$MINIO_VOLUME" -type f 2>/dev/null | wc -l)
    echo "Total files in volume: $file_count"
    echo ""
    
    # Check volume size
    echo "=== Volume Size ==="
    du -sh "$MINIO_VOLUME" 2>/dev/null || echo "Cannot determine size"
    echo ""
    
    # Find bucket directories
    echo "=== Bucket Directories ==="
    find "$MINIO_VOLUME" -type d -name "audio-files" 2>/dev/null || echo "No audio-files directory found"
    echo ""
else
    echo "WARNING: Volume directory not found at expected location"
fi

# Check MinIO environment variables
echo "=== MinIO Environment Variables ==="
docker inspect $MINIO_CONTAINER | grep -A 5 "Env"
echo ""

# Try to access MinIO from inside the container
echo "=== Testing MinIO from Inside Container ==="
docker exec $MINIO_CONTAINER ls -l /data 2>&1 || echo "Cannot access container"
echo ""

# Check MinIO port binding
echo "=== MinIO Port Bindings ==="
docker port $MINIO_CONTAINER
echo ""

echo "Done checking MinIO container"
